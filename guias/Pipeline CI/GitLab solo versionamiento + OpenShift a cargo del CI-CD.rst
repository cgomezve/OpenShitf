=========================================================
GitLab solo versionamiento + OpenShift a cargo del CI/CD
=========================================================

:Autor: Carlos
:Entorno: GitLab (local) + OpenShift Local (CRC) + OpenShift Pipelines (PaC)
:Objetivo: GitLab solo almacena código; OpenShift ejecuta CI/CD y usa su registry interno
:Fecha: 2026-11-17

.. contents::
   :depth: 2
   :local:

Introducción
============

Este documento describe cómo configurar GitLab como **mero repositorio de
código** y trasladar la totalidad del CI/CD a OpenShift. El mecanismo
central es **Pipelines as Code (PaC)** de OpenShift Pipelines: tras un
``git push`` a GitLab, GitLab dispara un Webhook hacia el controlador de
PaC en OpenShift; PaC lee el archivo ``.tekton/pipelinerun.yaml`` del
repositorio y crea un ``PipelineRun`` que compila, hace push al registry
interno de OpenShift y despliega.

Al finalizar, GitLab Runner puede detenerse o eliminarse. GitLab no
ejecuta ningún pipeline propio.

Paso 1: Desactivar el CI/CD de GitLab
=====================================

Para evitar conflictos con el CI/CD externo, se recomienda desactivar
GitLab CI/CD en el proyecto. Al desactivarlo, desaparecen las páginas
``/pipelines`` y ``/jobs`` del menú lateral; los jobs históricos no se
borran, solo se ocultan [citation:3].

1. En GitLab, ve al proyecto.
2. Menú lateral: **Settings → General**.
3. Expande **Visibility, project features, permissions**.
4. En la sección **Repository**, desactiva el toggle **CI/CD**.
5. Pulsa **Save changes**.

.. note::

   Aunque no desactives GitLab CI/CD, mientras no exista un GitLab
   Runner activo y no se suba un ``.gitlab-ci.yml``, GitLab no ejecutará
   nada. La desactivación explícita es una medida de higiene para evitar
   confusiones.

Paso 2: Verificar que Pipelines as Code está instalado en OpenShift
==================================================================

PaC se instala junto con el Operator de Red Hat OpenShift Pipelines. En
la mayoría de instalaciones de CRC ya está presente. Verifica:

.. code-block:: bash

    oc get pods -n openshift-pipelines | grep pipelines-as-code

Debe aparecer un Pod ``pipelines-as-code-controller-xxxx`` en estado
``Running``. Si no existe, instala o habilita el Operator de OpenShift
Pipelines y asegúrate de que PaC esté habilitado en ``TektonConfig``
[citation:2].

Paso 3: Obtener la URL pública del controlador de PaC
=====================================================

Esta URL es la que se configurará como Webhook en GitLab:

.. code-block:: bash

    echo https://$(oc get route -n openshift-pipelines pipelines-as-code-controller -o jsonpath='{.spec.host}')

Anota el resultado, por ejemplo:
``https://pipelines-as-code-controller-openshift-pipelines.apps-crc.testing``
[citation:8].

Paso 4: Crear un Personal Access Token en GitLab
================================================

PaC necesita un token para leer el repositorio y escribir los estados de
vuelta en GitLab.

1. En GitLab: **User Settings → Access Tokens**.
2. Crea un token con los scopes:

   - ``api`` (obligatorio)
   - ``admin:repo_hook`` (necesario si vas a usar ``tkn pac create repo``
     para configurar el Webhook automáticamente) [citation:8]

3. Copia y guarda el token.

Paso 5: Configurar Webhook y Repository CR (vía tkn pac)
========================================================

La forma más rápida es usar la CLI ``tkn pac``. Ejecuta en el directorio
raíz de tu repositorio local:

.. code-block:: bash

    tkn pac create repo

El asistente te pedirá:

1. URL del repositorio de GitLab.
2. Namespace de OpenShift donde se ejecutará el pipeline.
3. **Project ID de GitLab** (visible en la página principal del proyecto,
   es un número).
4. Detectar la URL del controlador de PaC; confirma.
5. Secret del Webhook (puedes aceptar el valor aleatorio por defecto).
6. Pegar el Personal Access Token de GitLab.

Al finalizar, ``tkn pac`` habrá:

- Creado el recurso ``Repository`` en OpenShift.
- Creado el ``Secret`` con el token y el secreto del Webhook.
- Configurado el Webhook en GitLab automáticamente.
- Generado un archivo de plantilla ``.tekton/pipelinerun.yaml`` en tu
  repositorio [citation:1][citation:8].

.. note::

   Si tu GitLab es una instancia privada (no gitlab.com), en el
   ``Repository`` CR generado debes descomentar y ajustar el campo
   ``git_provider.url`` con la URL de tu GitLab (por ejemplo,
   ``https://tu-gitlab.local/``) [citation:8].

Paso 6: Editar el PipelineRun para compilar, hacer push al registry interno y desplegar
======================================================================================

La plantilla generada es solo un esqueleto. Debes reemplazarla con tu
lógica real. El punto clave para que la imagen vaya al **registry interno
de OpenShift** es usar la dirección interna del registry
(``image-registry.openshift-image-registry.svc:5000``) en la tarea de
build/push. Esta dirección es accesible desde dentro del clúster sin
necesidad de rutas externas ni secrets de pull adicionales [citation:9].

Ejemplo de ``.tekton/pipelinerun.yaml``:

.. code-block:: yaml

    apiVersion: tekton.dev/v1beta1
    kind: PipelineRun
    metadata:
      name: "mi-app-run"
      annotations:
        pipelinesascode.tekton.dev/on-event: "[push]"
        pipelinesascode.tekton.dev/on-target-branch: "[main]"
    spec:
      pipelineSpec:
        workspaces:
          - name: source
        tasks:
          - name: clone-and-build
            taskSpec:
              workspaces:
                - name: source
              steps:
                - name: clone
                  image: alpine/git:latest
                  script: |
                    git clone $(params.repo-url) $(workspaces.source.path)
                - name: build-and-push
                  image: quay.io/buildah/stable:latest
                  workingDir: $(workspaces.source.path)
                  script: |
                    buildah bud -t image-registry.openshift-image-registry.svc:5000/my-app-dev/my-app:$COMMIT_SHA .
                    buildah push image-registry.openshift-image-registry.svc:5000/my-app-dev/my-app:$COMMIT_SHA
              params:
                - name: repo-url
                  value: "https://tu-gitlab.local/tu-usuario/tu-repo.git"
          - name: deploy
            runAfter: [clone-and-build]
            taskSpec:
              steps:
                - name: deploy
                  image: quay.io/openshift/origin-cli:latest
                  script: |
                    oc login --token=$OPENSHIFT_TOKEN --server=$OPENSHIFT_SERVER --insecure-skip-tls-verify
                    oc set image deployment/my-app my-app=image-registry.openshift-image-registry.svc:5000/my-app-dev/my-app:$COMMIT_SHA
                    oc rollout status deployment/my-app --timeout=300s

.. warning::

   El valor de ``$COMMIT_SHA`` debe obtenerse del contexto de PaC. En la
   práctica, PaC inyecta variables como ``{{ revision }}`` o parámetros
   del evento. Consulta la documentación de PaC para el nombre exacto de
   la variable según tu versión.

Paso 7: Verificar que el Webhook está configurado en GitLab
===========================================================

Si usaste ``tkn pac create repo``, el Webhook ya debería estar creado.
Verifica en GitLab: **Settings → Webhooks**. Debe existir una URL
apuntando al controlador de PaC con los eventos:

- Push events
- Merge request events
- Comments

Si necesitas configurarlo manualmente, la URL es la del Paso 3, y el
secret se genera con ``openssl rand -hex 20`` [citation:8].

Paso 8: Hacer push y verificar la ejecución
===========================================

Haz un ``git push`` a la rama ``main`` de tu repositorio. Luego, en
OpenShift:

.. code-block:: bash

    tkn pipelinerun list -n my-app-dev

Deberías ver un PipelineRun nuevo. Para ver logs:

.. code-block:: bash

    tkn pipelinerun logs -n my-app-dev --last

Si el PipelineRun falla, revisa:

- Que el Webhook en GitLab tenga la URL correcta y el secret coincida.
- Que el ``Repository`` CR en OpenShift tenga el token correcto.
- Que el archivo ``.tekton/pipelinerun.yaml`` exista en la rama que
  disparó el evento.

Paso 9: Detener/eliminar GitLab Runner
======================================

Una vez confirmado que PaC ejecuta correctamente los pipelines, el GitLab
Runner ya no es necesario. Puedes:

- Detener el servicio del runner.
- Eliminar el contenedor o proceso del runner.
- Opcionalmente, eliminar el registro del runner en GitLab (Settings →
  CI/CD → Runners).

GitLab seguirá funcionando como repositorio y emisor de Webhooks.

Resumen: quién activa qué
=========================

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Componente
     - Rol
   * - Tú
     - ``git push`` a GitLab
   * - GitLab
     - Almacena código; al recibir push, envía Webhook a PaC
   * - Controlador PaC (OpenShift)
     - Recibe Webhook, lee ``.tekton/`` del repo, crea PipelineRun
   * - Tekton (OpenShift)
     - Ejecuta build, push al registry interno y deploy
   * - Registry interno OpenShift
     - Almacena la imagen construida
   * - GitLab Runner
     - **Ya no participa**

Checklist de verificación
=========================

.. list-table::
   :header-rows: 1
   :widths: 60 20 20

   * - Requisito
     - Estado
     - Nota
   * - CI/CD de GitLab desactivado
     - ☐
     - Settings → General → Repository
   * - PaC controller Running
     - ☐
     - ``oc get pods -n openshift-pipelines``
   * - Webhook en GitLab apunta a PaC
     - ☐
     - Settings → Webhooks
   * - Repository CR existe en OpenShift
     - ☐
     - ``oc get repository -n my-app-dev``
   * - ``.tekton/pipelinerun.yaml`` existe en repo
     - ☐
     - Rama main
   * - PipelineRun usa registry interno
     - ☐
     - ``image-registry.openshift-image-registry.svc:5000/...``
   * - GitLab Runner detenido/eliminado
     - ☐
     - Después de validar
