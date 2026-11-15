=============================================================================
Creación de Token Global de Servicio en OpenShift para Pipelines de GitLab
=============================================================================

:Autor: Carlos Gómez
:Infraestructura: OpenShift Local / CRC (``192.168.123.40``) | GitLab (``srvgitlab``)
:Namespace: ``openshift-image-registry``
:Fecha: Noviembre 2026

.. contents:: Tabla de Contenidos
   :depth: 2

1. Objetivo y Alcance
=====================

Documentar el procedimiento para crear una cuenta de servicio (``ServiceAccount``) con permisos globales en el clúster de OpenShift y generar un token estático de larga duración. Esto permite que los pipelines de GitLab se autentiquen contra el **Registry Interno de OpenShift** y gestionen recursos en múltiples proyectos o namespaces sin depender de la herramienta ``oc`` en el servidor de compilación.

2. Configuración en el Clúster OpenShift
========================================

Los siguientes comandos se ejecutan directamente en el nodo de administración de OpenShift (``srvopenshift``) con una sesión activa de administrador.

2.1. Crear la Cuenta de Servicio (ServiceAccount)
-------------------------------------------------

Se crea la cuenta ``global-gitlab-deployer`` dentro del namespace de infraestructura ``openshift-image-registry`` para centralizar el acceso:

.. code-block:: bash

   oc create sa global-gitlab-deployer -n openshift-image-registry

2.2. Asignar Permisos Globales de Clúster
-----------------------------------------

Se vincula el rol ``cluster-admin`` a la cuenta de servicio creada para permitirle empujar imágenes y desplegar recursos en cualquier namespace actual o futuro:

.. code-block:: bash

   oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:openshift-image-registry:global-gitlab-deployer

2.3. Generar Token Estático de Larga Duración
---------------------------------------------

Se emite un token de autenticación con vigencia de un año (``8760h``):

.. code-block:: bash

   oc create token global-gitlab-deployer -n openshift-image-registry --duration=8760h

**Salida esperada:** Una cadena alfanumérica codificada en formato JWT (comienza por ``eyJ...``). Copiar la cadena completa para su registro en GitLab.

3. Configuración de Credenciales en GitLab
==========================================

Para resguardar el token y evitar su exposición en el código fuente o registros de ejecución:

1. Acceder al proyecto correspondiente en la interfaz web de GitLab.
2. Navegar a **Settings** > **CI/CD** > **Variables** y seleccionar **Add variable**.
3. Completar los parámetros de la variable:

   * **Key:** ``OPENSHIFT_TOKEN``
   * **Value:** *(Pegar el token generado en el paso 2.3)*
   * **Protect variable:** Activado (opcional, según políticas de ramas protegidas)
   * **Mask variable:** Activado (obligatorio para ocultar el valor en los logs del runner)

4. Guardar la configuración haciendo clic en **Add variable**.

4. Integración en el Pipeline (``.gitlab-ci.yml``)
==================================================

Con la variable ``OPENSHIFT_TOKEN`` configurada, la etapa de registro de imagen (``registerDev``) se autentica directamente contra el registro interno de OpenShift utilizando la entrada estándar (``--password-stdin``):

.. code-block:: yaml

   docker-build-dev:
     stage: registerDev
     script:
       - echo "Autenticando contra el registro interno de OpenShift usando token estático..."
       - echo "${OPENSHIFT_TOKEN}" | docker login default-route-openshift-image-registry.apps-crc.testing -u global-gitlab-deployer --password-stdin --tls-verify=false
       - echo "Construyendo y subiendo imagen directamente al registry interno..."
       - docker build -t ${REPO_DEV}/${CI_PROJECT_NAME}:${CI_PIPELINE_ID} .
       - docker push ${REPO_DEV}/${CI_PROJECT_NAME}:${CI_PIPELINE_ID} --tls-verify=false
     tags:
       - shell
     only:
       - develop
