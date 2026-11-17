=========================================================
CI/CD GitLab → OpenShift Local (CRC): Guía Unificada
=========================================================

:Autor: Carlos
:Entorno: GitLab local + OpenShift Local (CRC) + Registry interno de OpenShift
:Versión: 1.0
:Fecha: 2026-11-17

.. contents::
   :depth: 2
   :local:

Introducción
============

Este documento describe el procedimiento completo para que un pipeline de
GitLab CI/CD construya una imagen, la publique en el registry interno de
OpenShift Local (CRC) y desplace automáticamente la aplicación en el
clúster, usando autenticación basada en ``ServiceAccount`` con token de
larga duración y verificación estricta post-despliegue.

El objetivo es lograr una integración **segura** (sin ``cluster-admin``),
**mantenible** (sin valores hardcodeados innecesarios) y **verificable**
(el pipeline falla si la imagen activa no coincide con el commit).

Paso 1: Configurar el ServiceAccount y Permisos en OpenShift
============================================================

Para que GitLab pueda desplegar en tu proyecto sin comprometer la
seguridad del clúster, se crea una cuenta de servicio dedicada con
permisos de edición acotados al namespace destino.

1. Iniciar sesión en OpenShift Local (CRC)::

    oc login -u developer -p developer https://api.crc.testing:6443

2. Seleccionar el proyecto donde se desplegará la aplicación::

    oc project my-app-dev

3. Crear el ServiceAccount dedicado para GitLab::

    oc create sa gitlab-deployer-sa

4. Asignar exclusivamente el rol ``edit`` en el namespace (principio de
   mínimo privilegio, sin ``cluster-admin``)::

    oc policy add-role-to-user edit -z gitlab-deployer-sa -n my-app-dev

5. Generar un token de larga duración (por ejemplo, 1 año / 8760 horas)
   para evitar expiraciones que rompan los deploys futuros::

    oc create token gitlab-deployer-sa --duration=8760h

   Copiar la cadena resultante. Este valor será ``OPENSHIFT_TOKEN``.

6. Obtener la URL del servidor API (si no se tiene a mano)::

    oc whoami --show-server

   Normalmente será ``https://api.crc.testing:6443``. Este valor será
   ``OPENSHIFT_SERVER``.

Paso 2: Configurar las Variables de CI/CD en GitLab
===================================================

Para mantener las credenciales fuera del código fuente y protegerlas
frente a exposiciones accidentales:

1. Entrar al proyecto en GitLab.
2. Ir a **Settings → CI/CD → Variables** y hacer clic en **Add variable**.
3. Añadir las siguientes tres variables:

   .. list-table::
      :header-rows: 1
      :widths: 25 45 30

      * - Variable
        - Valor
        - Notas
      * - ``OPENSHIFT_SERVER``
        - ``https://api.crc.testing:6443``
        - URL del API de CRC
      * - ``OPENSHIFT_TOKEN``
        - Token generado en el Paso 1
        - Marcar como **Masked** si cumple los requisitos de longitud
      * - ``OPENSHIFT_NAMESPACE``
        - Nombre del proyecto (ej. ``my-app-dev``)
        - Namespace destino

Paso 3: Archivo ``.gitlab-ci.yml`` Definitivo y Blindado
========================================================

Reemplazar el contenido del archivo ``.gitlab-ci.yml`` del repositorio
con la siguiente estructura. Esta versión separa explícitamente el nombre
del Deployment y del Container (para evitar fallos de mapeo) e incluye
una verificación post-deploy estricta que rompe el pipeline si la imagen
activa no coincide con el commit actual.

.. code-block:: yaml

    stages:
      - build
      - push
      - deploy

    variables:
      DEPLOYMENT_NAME: "my-app-simple-dev"
      CONTAINER_NAME: "my-app-simple-dev"  # Ajustar si el contenedor interno tiene otro nombre
      IMAGE_TAG: "$CI_COMMIT_SHA"
      REGISTRY_URL: "default-route-openshift-image-registry.apps-crc.testing"

    # --- ETAPA 1: BUILD ---
    build_job:
      stage: build
      script:
        - echo "Compilando la aplicación..."
        # Comandos de compilación actuales

    # --- ETAPA 2: PUSH ---
    push_job:
      stage: push
      script:
        - echo "Construyendo y subiendo la imagen al Registry..."
        # Comandos funcionales de Podman/Docker previamente validados:
        # podman tag $DEPLOYMENT_NAME:$IMAGE_TAG $REGISTRY_URL/$OPENSHIFT_NAMESPACE/$DEPLOYMENT_NAME:$IMAGE_TAG
        # podman push $REGISTRY_URL/$OPENSHIFT_NAMESPACE/$DEPLOYMENT_NAME:$IMAGE_TAG

    # --- ETAPA 3: DESPLIEGUE AUTOMÁTICO EN OPENSHIFT ---
    deploy_to_openshift:
      stage: deploy
      image:
        name: quay.io/openshift/origin-cli:latest
        entrypoint: [""]
      script:
        - echo "Iniciando despliegue seguro en OpenShift Local..."

        # 1. Autenticación con el token de larga duración
        - oc login $OPENSHIFT_SERVER --token=$OPENSHIFT_TOKEN --namespace=$OPENSHIFT_NAMESPACE --insecure-skip-tls-verify=true

        # 2. Actualización explícita separando Deployment y Container
        - oc set image deployment/$DEPLOYMENT_NAME $CONTAINER_NAME=$REGISTRY_URL/$OPENSHIFT_NAMESPACE/$DEPLOYMENT_NAME:$IMAGE_TAG

        # 3. Monitorear el rollout con timeout de seguridad
        - oc rollout status deployment/$DEPLOYMENT_NAME --timeout=300s

        # 4. Verificación post-deploy estricta
        - echo "Verificando integridad de la imagen desplegada..."
        - ACTIVE_IMAGE=$(oc get deployment $DEPLOYMENT_NAME -o jsonpath='{.spec.template.spec.containers[0].image}')
        - echo "Imagen activa en clúster -> $ACTIVE_IMAGE"
        - |
          if [[ "$ACTIVE_IMAGE" != *"$IMAGE_TAG"* ]]; then
            echo "¡Error crítico! La imagen activa no coincide con el commit actual ($IMAGE_TAG)."
            exit 1
          fi
        - echo "¡Despliegue verificado y exitoso!"

      rules:
        - if: '$CI_COMMIT_BRANCH == "main"'

Observaciones técnicas y recomendaciones de arquitectura
========================================================

Aunque esta versión es funcional para un laboratorio local, conviene
tener presentes las siguientes observaciones para llevarla a un entorno
más robusto.

Dirección del registry hardcodeada
----------------------------------

La variable ``REGISTRY_URL`` está fijada a
``default-route-openshift-image-registry.apps-crc.testing``. Esto
funciona en CRC, pero es frágil: la dirección puede cambiar al
reinstalar el clúster o al mover el pipeline a otro entorno. Se
recomienda obtenerla dinámicamente en la etapa de despliegue::

    - INTERNAL_REGISTRY=$(oc registry info)
    - oc set image deployment/$DEPLOYMENT_NAME $CONTAINER_NAME=$INTERNAL_REGISTRY/$OPENSHIFT_NAMESPACE/$DEPLOYMENT_NAME:$IMAGE_TAG

Duración y rotación del token
-----------------------------

``--duration=8760h`` reduce el riesgo frente al valor por defecto de 1
hora, pero el token sigue expirando. Se recomienda documentar una
política de rotación periódica del ``ServiceAccount`` y del token, o
bien evaluar el uso de ``oc apply -f`` con manifiestos versionados en
Git como estrategia de despliegue declarativa a futuro.

Contenido de ``push_job``
-------------------------

El bloque ``push_job`` actualmente contiene solo comentarios. Para que
el pipeline sea ejecutable de principio a fin, es necesario incluir los
comandos reales de ``podman``/``docker`` (login, tag, push) y, si el
runner de GitLab no resuelve ``apps-crc.testing`` o no confía en el
certificado autofirmado de CRC, ajustar la configuración de red y TLS
del runner.

Verificación TLS
----------------

El flag ``--insecure-skip-tls-verify=true`` es aceptable en CRC por el
uso de certificados autofirmados, pero **no debe llevarse a un clúster
de producción**. En entornos estándar, eliminar ese flag y confiar en la
CA del clúster.

Resumen de cumplimiento
-----------------------

.. list-table::
   :header-rows: 1
   :widths: 45 20 35

   * - Requisito
     - Estado
     - Comentario
   * - Sin ``cluster-admin``
     - Cumple
     - Se usa rol ``edit`` acotado al namespace
   * - Token de larga duración
     - Cumple
     - ``--duration=8760h``
   * - Sin ``|| true``
     - Cumple
     - Los errores hacen fallar el pipeline
   * - ``rollout status`` con timeout
     - Cumple
     - ``--timeout=300s``
   * - Verificación post-deploy estricta
     - Cumple
     - ``if`` + ``exit 1``
   * - Registry dinámico
     - Pendiente
     - Reemplazar por ``oc registry info``
   * - ``push_job`` ejecutable
     - Pendiente
     - Añadir comandos reales de push
