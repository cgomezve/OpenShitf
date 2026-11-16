=================================================================
Despliegue seguro en OpenShift desde GitLab Runner sin SSH al Bastion
=================================================================

:Autor: Equipo de Plataforma
:Versión: 1.1
:Fecha: |today|
:Estado: Documento técnico / Runbook

.. contents:: Contenido
   :depth: 3
   :local:

Introducción
============

En entornos de producción, evitar que el **GitLab Runner** use SSH hacia el
**Bastion** reduce la superficie de ataque. Con este enfoque:

* No necesitas llaves privadas SSH almacenadas en GitLab.
* No necesitas abrir puertos administrativos entre segmentos de red.

En su lugar, el Runner se comporta como un **cliente API directo** contra el
puerto ``6443`` (API Server de OpenShift).

A continuación se describe la implementación paso a paso para lograr esta
arquitectura limpia y nativa.

.. note::

   Todos los comandos asumen que el clúster es OpenShift 4.x y que el
   binario ``oc`` está disponible en el entorno donde se ejecutan.

1. Habilitar el binario ``oc`` en el GitLab Runner
==================================================

Existen dos formas de proporcionar el comando ``oc`` a tu pipeline,
dependiendo de cómo esté configurado el GitLab Runner.

Opción A: Runner tipo shell
---------------------------

Runner instalado en el sistema operativo (como en el laboratorio). Descarga
el cliente oficial de OpenShift directamente en el servidor donde corre el
GitLab Runner y muévelo a ``/usr/local/bin/``:

.. code-block:: bash

   curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
   tar -xzf openshift-client-linux.tar.gz oc kubectl
   sudo mv oc kubectl /usr/local/bin/

**Verificación:** ejecuta ``oc version --client`` en el servidor del Runner;
debe mostrar la versión del cliente instalada.

Opción B: Runner tipo docker o kubernetes (recomendado)
-------------------------------------------------------

No se instala nada en el servidor. Simplemente se le indica al job ``deploy``
en el ``.gitlab-ci.yml`` que utilice una imagen oficial de Red Hat que ya
trae ``oc`` preinstalado, por ejemplo:

* ``registry.redhat.io/openshift4/ose-cli:latest``
* Una copia alojada en tu registry corporativo.

2. Preparar la ServiceAccount y permisos RBAC (desde el Bastion)
================================================================

Desde el servidor Bastion (donde ya tienes sesión como administrador del
clúster), crea la cuenta de servicio acotada estrictamente al namespace de la
aplicación (ejemplo: ``app-produccion``) para cumplir con el principio de
**menor privilegio**.

2.1 Crear el namespace y la ServiceAccount
------------------------------------------

.. code-block:: bash

   oc new-project app-produccion
   oc create sa gitlab-deployer -n app-produccion

2.2 Asignar el rol ``edit``
----------------------------

El rol ``edit`` permite crear/actualizar ``Deployments``, ``Services``,
``Routes`` y ``ConfigMaps``, pero no otorga control sobre todo el clúster.

.. code-block:: bash

   oc policy add-role-to-user edit \
     system:serviceaccount:app-produccion:gitlab-deployer \
     -n app-produccion

2.3 Permisos sobre el Registry interno (opcional)
-------------------------------------------------

Si el pipeline también va a subir imágenes al Registry interno de OpenShift,
otorga permisos de construcción sobre ese mismo namespace:

.. code-block:: bash

   oc policy add-role-to-user system:image-builder \
     system:serviceaccount:app-produccion:gitlab-deployer \
     -n app-produccion

2.4 Crear el Secret para obtener el token permanente
----------------------------------------------------

.. code-block:: bash

   cat << 'EOF' | oc apply -f -
   apiVersion: v1
   kind: Secret
   metadata:
     name: gitlab-deployer-token
     namespace: app-produccion
     annotations:
       kubernetes.io/service-account.name: gitlab-deployer
   type: kubernetes.io/service-account-token
   EOF

.. warning::

   Este tipo de Secret genera un token **sin fecha de expiración**. Úsalo
   solo cuando el flujo de CI/CD lo requiera y protégelo como credencial
   sensible. En clústeres modernos se recomienda evaluar ``TokenRequest``
   con tokens de corta duración.

2.5 Extraer el token y la URL de la API
---------------------------------------

.. code-block:: bash

   # Obtener el token JWT
   oc get secret gitlab-deployer-token -n app-produccion \
     -o jsonpath='{.data.token}' | base64 -d; echo ""

   # Obtener la URL de la API (ej. https://api.ocp.empresa.com:6443)
   oc whoami --show-server

**Verificación:** ambos comandos deben imprimir una cadena JWT larga y la URL
HTTPS del puerto ``6443`` de los Masters.

3. Configurar las variables y certificados en GitLab
====================================================

3.1 Variables CI/CD
-------------------

Ve a tu proyecto en GitLab → **Settings → CI/CD → Variables** y registra:

.. list-table::
   :header-rows: 1
   :widths: 25 45 30

   * - Variable
     - Valor
     - Atributos
   * - ``OPENSHIFT_SERVER``
     - ``https://api.ocp.empresa.com:6443``
     - —
   * - ``OPENSHIFT_TOKEN``
     - Token JWT extraído
     - Masked y Protected
   * - ``OPENSHIFT_NAMESPACE``
     - ``app-produccion``
     - —

.. note::

   Marca ``OPENSHIFT_TOKEN`` como **Masked** y **Protected** si solo
   despliegas desde ramas protegidas.

3.2 Manejo del certificado TLS de la API
----------------------------------------

Los Masters de OpenShift usan un certificado autofirmado o firmado por la CA
interna de tu empresa.

**Modo rápido (para pruebas iniciales):**
Usar ``--insecure-skip-tls-verify=true`` en el comando ``oc login``.

**Modo producción (recomendado):**

1. Extrae el certificado raíz de la API desde el Bastion:

   .. code-block:: bash

      oc get configmap kube-root-ca.crt \
        -o jsonpath='{.data.ca\.crt}' > ocp-ca.crt

2. Guárdalo como variable de tipo **File** en GitLab llamada
   ``OPENSHIFT_CA_CERT``.
3. Pásalo con ``--certificate-authority=$OPENSHIFT_CA_CERT``.

4. Validar conectividad de red (firewall)
=========================================

Antes de lanzar el pipeline, asegúrate de que exista una regla de firewall
abierta desde la IP del GitLab Runner hacia la VIP (IP virtual del
balanceador) de los Masters de OpenShift en el puerto ``6443/TCP``.

**Verificación:** desde el servidor del GitLab Runner, ejecuta:

.. code-block:: bash

   curl -vk https://api.ocp.empresa.com:6443/healthz

Debe responder ``ok`` (código HTTP 200). Si se queda colgado
(``Connection timed out``), el firewall está bloqueando el puerto ``6443``
entre el Runner y los Masters.

5. Estructura del job ``deploy`` en ``.gitlab-ci.yml``
=====================================================

Así queda el stage de despliegue eliminando por completo ``scp``, ``ssh`` y
archivos temporales en el Bastion:

.. code-block:: yaml

   deploy_prod:
     stage: deploy
     # Si usas Docker Runner, descomenta la siguiente línea con tu imagen de cli:
     # image: registry.redhat.io/openshift4/ose-cli:latest
     script:
       - echo "Autenticando directamente contra la API de OpenShift..."
       - oc login --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_SERVER}" --insecure-skip-tls-verify=true
       - oc project "${OPENSHIFT_NAMESPACE}"

       - echo "Aplicando manifiestos de despliegue..."
       - oc apply -f k8s/deployment.yaml
       - oc apply -f k8s/service.yaml
       - oc apply -f k8s/route.yaml

       - echo "Verificando estado del despliegue..."
       - oc rollout status deployment/mi-aplicacion --timeout=120s
     after_script:
       - oc logout || true

.. tip::

   En producción, reemplaza ``--insecure-skip-tls-verify=true`` por
   ``--certificate-authority=$OPENSHIFT_CA_CERT``.

6. Escalabilidad: arquitectura para más de 120 aplicaciones
===========================================================

Cuando el número de aplicaciones crece por encima del centenar, el modelo de
"una ServiceAccount y un namespace por aplicación" deja de ser sostenible
operativamente. Esta sección describe cómo adaptar el flujo anterior sin
sacrificar aislamiento ni seguridad.

6.1 Por qué NO colocar 120 aplicaciones en un único namespace
-------------------------------------------------------------

Colocar las 120 aplicaciones dentro de un único namespace en producción es un
**antipatrón grave** en OpenShift/Kubernetes y genera problemas operativos
críticos a corto plazo:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Problema
     - Impacto
   * - **Colisión de nombres de recursos**
     - En un mismo namespace no pueden existir dos objetos ``ConfigMap``,
       ``Secret``, ``Service`` o ``Route`` con el mismo nombre. Si dos equipos
       llaman a su configuración ``app-config`` o ``redis-secret``, el
       segundo pipeline sobrescribirá al primero.
   * - **Radio de explosión (Blast Radius) y RBAC**
     - Si todas comparten namespace, cualquier token o desarrollador con
       acceso de lectura/escritura ve las variables de entorno, contraseñas y
       certificados (``Secrets``) de las 120 aplicaciones.
   * - **Agotamiento de recursos y cuotas**
     - En OpenShift se aplican ``ResourceQuotas`` y ``LimitRanges`` por
       namespace para evitar que una aplicación con fuga de memoria tumbe los
       Workers. Si todas están juntas, una sola aplicación descontrolada puede
       consumir toda la cuota e impedir que las demás escalen.
   * - **Ruido operativo en diagnóstico**
     - Hacer ``oc get pods`` o buscar eventos en un namespace con 300+ pods y
       cientos de ``ReplicaSets`` vuelve lenta y propensa a errores cualquier
       intervención de guardia.

6.2 Arquitectura recomendada: 120 aplicaciones sin perder el control en CI/CD
----------------------------------------------------------------------------

Para no administrar 120 tokens distintos ni 120 ServiceAccounts manuales,
combina estas tres mejores prácticas empresariales.

Segmentación por dominio de negocio o tribu
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En lugar de un megacontenedor o 120 namespaces atomizados, agrupa las
aplicaciones por unidad funcional o célula de negocio. Por ejemplo:

* ``pagos-prod``
* ``canales-digitales-prod``
* ``core-bancario-prod``
* ``integracion-wso2-prod``

Así reduces la gestión a unos **10 a 15 namespaces lógicos**, manteniendo
aislados los ``Secrets``, cuotas de CPU/RAM y políticas de red
(``NetworkPolicy``).

Una sola ServiceAccount central de CI/CD con un ClusterRole acotado
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Para evitar crear decenas de tokens, crea una única identidad para tu
plataforma GitLab en un namespace administrativo (por ejemplo,
``cicd-tools``). En lugar de darle ``cluster-admin`` (que le permitiría
borrar nodos o modificar el clúster), créale un ``ClusterRole``
personalizado que solo le permita gestionar recursos de aplicación
(``Deployments``, ``Services``, ``Routes``, ``ConfigMaps``,
``ImageStreams``), bloqueando recursos críticos de infraestructura
(``Nodes``, ``ClusterOperators``, ``PVs``, ``Roles``).

.. code-block:: yaml

   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: gitlab-cicd-deployer-role
   rules:
     - apiGroups: ["", "apps", "route.openshift.io", "image.openshift.io"]
       resources: ["deployments", "replicasets", "pods", "services", "routes", "configmaps", "secrets", "imagestreams", "imagestreamtags"]
       verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

Luego vincula este rol global a tu única cuenta ``gitlab-deployer``:

.. code-block:: bash

   oc adm policy add-cluster-role-to-user gitlab-cicd-deployer-role \
     system:serviceaccount:cicd-tools:gitlab-deployer

Variables a nivel de grupo en GitLab + plantilla única (``include``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Para no configurar tokens ni mantener 120 archivos ``.gitlab-ci.yml``
distintos:

**Variables heredadas (Group Level):** En GitLab, mete los 120 repositorios
dentro de un Grupo o Subgrupos (por ejemplo,
``empresa/microservicios/...``). Configura ``OPENSHIFT_SERVER`` y
``OPENSHIFT_TOKEN`` una sola vez a nivel del Grupo raíz. Todos los 120
proyectos heredarán automáticamente esas credenciales; cuando rotes el token,
lo cambias en un solo sitio y se actualiza para las 120 apps.

**Namespace dinámico por proyecto:** Cada repositorio define únicamente su
variable local ``OPENSHIFT_NAMESPACE`` (por ejemplo, ``pagos-prod``).

**Pipeline centralizado (template):** Crea un repositorio central
``ci-templates`` con un único archivo ``openshift-deploy.yml`` estandarizado.
Los 120 proyectos solo tendrán un ``.gitlab-ci.yml`` de 4 líneas llamando a
esa plantilla:

.. code-block:: yaml

   include:
     - project: 'devops/ci-templates'
       file: '/templates/openshift-deploy.yml'

   variables:
     OPENSHIFT_NAMESPACE: "pagos-prod"
     APP_NAME: "servicio-autorizaciones"

6.3 Comparativa de estrategias para 120 aplicaciones
----------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 25 25 25 25

   * - Criterio
     - 1 Namespace único
     - 120 Namespaces (1 token c/u)
     - Arquitectura híbrida (recomendada)
   * - Aislamiento de Secrets/Red
     - Nulo (riesgo de seguridad)
     - Máximo
     - Alto (por dominio de negocio)
   * - Gestión de tokens en GitLab
     - 1 token
     - 120 tokens (inmanejable)
     - 1 token a nivel de Grupo GitLab
   * - Privilegios en OpenShift
     - Riesgo de colisión de nombres
     - Muy granular
     - ClusterRole limitado solo a apps
   * - Mantenimiento de pipelines
     - 120 archivos YAML
     - 120 archivos YAML
     - 1 plantilla central (``include``)

Con este modelo tienes un solo punto de control para el token de GitLab y la
lógica de despliegue, pero mantienes aislamiento real en OpenShift para evitar
que una falla o colisión de nombres afecte a las otras 119 aplicaciones.

Ventajas clave de este flujo
============================

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Ventaja
     - Descripción
   * - **Trazabilidad**
     - En los logs de auditoría de OpenShift (``oc adm node-logs``), todas
       las acciones quedan registradas exactamente bajo el usuario
       ``system:serviceaccount:app-produccion:gitlab-deployer`` (o
       ``system:serviceaccount:cicd-tools:gitlab-deployer`` en el modelo
       escalado), sabiendo qué proyecto ejecutó cada cambio.
   * - **Cero mantenimiento en el Bastion**
     - No acumulas carpetas ni manifiestos residuales en el servidor
       Bastion.
   * - **Limpieza de sesión**
     - El bloque ``after_script`` ejecuta ``oc logout`` automáticamente al
       terminar (falle o tenga éxito el job), borrando el archivo
       ``~/.kube/config`` temporal del Runner.

Referencias
===========

* Documentación oficial de OpenShift: *OpenShift CLI (oc)*.
* Documentación oficial de Kubernetes: *Service Accounts* y *RBAC
  Authorization*.
* Documentación oficial de GitLab: *CI/CD Variables* y *Group-level
  variables*.
