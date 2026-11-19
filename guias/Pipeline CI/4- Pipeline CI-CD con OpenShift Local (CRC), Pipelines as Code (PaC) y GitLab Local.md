  ----------------------------------------------------------------------------
  Manual Definitivo y Consolidado: Pipeline CI/CD con OpenShift Local (CRC),
  Pipelines as Code (PaC) y GitLab Local
  ----------------------------------------------------------------------------

Autor

:   Carlos Gómez

Entorno

:   GitLab CE local (HTTP, sin SSL) + OpenShift Local (CRC) + OpenShift
    Pipelines (Tekton & PaC)

Objetivo

:   Configurar GitLab exclusivamente como repositorio de código y
    delegar la totalidad del ciclo CI/CD a OpenShift mediante Pipelines
    as Code, resolviendo progresivamente los permisos de seguridad
    (SCC), volúmenes efímeros, restricciones de usuario no-privilegiado
    (rootless) en Nginx y el enrutamiento de puertos.

Fecha

:   2026-11-18

::: {.contents depth="2" local=""}
Contenido
:::

# Introducción

Este manual recopila de principio a fin todo el diseño arquitectónico,
los requisitos previos de red, la configuración del operador de
Pipelines as Code (PaC), la resolución de bloqueos de seguridad (SCC),
los ajustes de almacenamiento en volúmenes efímeros, la adaptación de
Nginx para contenedores rootless (puerto 8080 y rutas temporales en
`/tmp`) y la estabilización completa del pipeline de compilación con
`buildah` y despliegue continuo en OpenShift.

# Paso 0: Habilitar Webhooks locales en GitLab (Requisito crítico)

Por defecto, GitLab bloquea las peticiones de Webhooks hacia direcciones
IP privadas o dominios locales (como `apps-crc.testing`) por políticas
de seguridad (SSRF).

1.  Inicia sesión en GitLab con una cuenta de Administrador.
2.  Ve a **Admin Area** (icono de llave inglesa) -\> **Settings** -\>
    **Network**.
3.  Expande la sección **Outbound requests**.
4.  Marca la casilla **Allow requests to the local network from webhooks
    and integrations**.
5.  Haz clic en **Save changes**.

# Paso 1: Desactivar el CI/CD nativo de GitLab

Para evitar ejecuciones duplicadas o conflictos de compilación en el
servidor de GitLab:

1.  Entra a tu proyecto en GitLab.
2.  En el menú lateral ve a **Settings** -\> **General**.
3.  Expande **Visibility, project features, permissions**.
4.  En la sección **Repository**, desactiva el interruptor **CI/CD**.
5.  Haz clic en **Save changes**.

# Paso 2: Instalar y habilitar OpenShift Pipelines (Tekton) y PaC

Como administrador del clúster (`kubeadmin`), instala el operador
oficial y habilita Pipelines as Code:

1.  Crear la suscripción para el operador:

    ``` bash
    cat <<EOF | oc apply -f -
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: openshift-pipelines-operator-rh
      namespace: openshift-operators
    spec:
      channel: latest
      installPlanApproval: Automatic
      name: openshift-pipelines-operator-rh
      source: redhat-operators
      sourceNamespace: openshift-marketplace
    EOF
    ```

2.  Asegurar la activación del controlador Pipelines as Code en
    `TektonConfig`:

    ``` bash
    oc patch tektonconfig config --type=merge -p='{"spec":{"platforms":{"openshift":{"pipelinesAsCode":{"enable":true}}}}}'
    ```

3.  Verificar que los componentes levanten correctamente:

    ``` bash
    oc get pods -n openshift-pipelines
    ```

Paso 3: Crear el Namespace y configurar ServiceAccounts y Permisos SCC
====================================================================

Para permitir que las tareas del pipeline y las operaciones `oc` se
ejecuten con los privilegios adecuados en OpenShift:

1.  Crear el proyecto (namespace):

    ``` bash
    oc new-project my-app-dev
    oc project my-app-dev
    ```

2.  Otorgar los privilegios de Security Context Constraints (SCC)
    `privileged` y `anyuid` al ServiceAccount `pipeline`:

    ``` bash
    oc adm policy add-scc-to-user privileged system:serviceaccount:my-app-dev:pipeline
    oc adm policy add-scc-to-user anyuid system:serviceaccount:my-app-dev:pipeline
    oc policy add-role-to-user edit -z pipeline -n my-app-dev
    ```

# Paso 4: Obtener la URL del controlador de PaC

Obtén la ruta pública de OpenShift hacia donde GitLab enviará los
webhooks:

``` bash
echo https://$(oc get route -n openshift-pipelines pipelines-as-code-controller -o jsonpath='{.spec.host}')
```

# Paso 5: Configurar el Repository CR en OpenShift y Webhook en GitLab

Crea el recurso `Repository` apuntando a tu instancia HTTP de GitLab y
configura el secreto con el token de acceso personal (`api` y
`admin:repo_hook`).

*Asegúrate de configurar el Webhook en GitLab apuntando a la ruta del
controlador de PaC y desmarcar la verificación SSL si utilizas
certificados autofirmados en CRC.*

# Paso 6: Estructura del Repositorio Local (`~/my-app-simple`)

El proyecto mantiene la siguiente distribución de archivos optimizada
para entornos rootless:

``` text
my-app-simple/
├── .tekton/
│   └── pipeline.yaml         # Definición del PipelineRun con PaC
├── kubernetes/
│   └── deployment.yaml       # Manifiestos de Deployment y Service para my-app-dev
├── Dockerfile                # Receta para Nginx rootless (/tmp y puerto 8080)
├── nginx.conf                # Configuración optimizada de Nginx para OpenShift
├── index.html                # Página web de prueba
└── contador.txt              # Archivo de control para pruebas de commits
```

# Paso 7: Archivos de Configuración del Contenedor y Despliegue

## A. Configuración de Nginx (`nginx.conf`)

Para cumplir estrictamente con las políticas de seguridad de OpenShift
(prohibido escribir en `/var/cache/nginx` y prohibido usar puertos
menores a 1024 como el 80), reubicamos los temporales a `/tmp` y
escuchamos en el puerto **8080**:

``` nginx
pid /tmp/nginx.pid;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    client_body_temp_path /tmp/client_temp;
    proxy_temp_path /tmp/proxy_temp;
    fastcgi_temp_path /tmp/fastcgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    scgi_temp_path /tmp/scgi_temp;

    sendfile on;
    keepalive_timeout 65;

    server {
        listen 8080;
        server_name localhost;

        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }
    }
}
```

## B. Receta de Contenedor (`Dockerfile`)

``` dockerfile
FROM nginx:alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080
```

## C. Manifiesto de Despliegue y Red (`kubernetes/deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-simple
  namespace: my-app-dev
  labels:
    app: my-app-simple
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app-simple
  template:
    metadata:
      labels:
        app: my-app-simple
    spec:
      containers:
        - name: my-app-simple
          image: image-registry.openshift-image-registry.svc:5000/my-app-dev/my-app-simple:latest
          ports:
            - containerPort: 8080
          resources:
            limits:
              cpu: "200m"
              memory: "256Mi"
            requests:
              cpu: "50m"
              memory: "64Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: my-app-simple-svc
  namespace: my-app-dev
  labels:
    app: my-app-simple
spec:
  type: NodePort
  selector:
    app: my-app-simple
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8080
      nodePort: 30012

## Paso 8: Manifiesto Consolidado Final `.tekton/pipeline.yaml`

Este manifiesto integra todas las tareas validadas:

-   Uso de workspace efímero (`emptyDir: {}`).
-   Clonado con `git-clone` y compilación con `buildah`.
-   Despliegue automático y validación de rollout en el namespace
    `my-app-dev`.

``` yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: my-app-simple-full-pipeline
  annotations:
    pipelinesascode.tekton.dev/on-event: "[push]"
    pipelinesascode.tekton.dev/on-target-branch: "[develop]"
    pipelinesascode.tekton.dev/max-keep-runs: "3"
    pipelinesascode.tekton.dev/task: "[git-clone, buildah]"
spec:
  params:
    - name: repo_url
      value: "{{ repo_url }}"
    - name: revision
      value: "{{ revision }}"
  workspaces:
    - name: shared-workspace
      emptyDir: {}
    - name: basic-auth
      secret:
        secretName: "{{ git_auth_secret }}"
  pipelineSpec:
    params:
      - name: repo_url
      - name: revision
    workspaces:
      - name: shared-workspace
      - name: basic-auth
    tasks:
      - name: git-clone
        taskRef:
          name: git-clone
        params:
          - name: url
            value: "$(params.repo_url)"
          - name: revision
            value: "$(params.revision)"
          - name: sslVerify
            value: "false"
          - name: subdirectory
            value: ""
        workspaces:
          - name: output
            workspace: shared-workspace
          - name: basic-auth
            workspace: basic-auth

      - name: build-image
        taskRef:
          name: buildah
        runAfter:
          - git-clone
        params:
          - name: IMAGE
            value: "image-registry.openshift-image-registry.svc:5000/my-app-dev/my-app-simple:$(params.revision)"
          - name: STORAGE_DRIVER
            value: "vfs"
          - name: TLSVERIFY
            value: "false"
          - name: CONTEXT
            value: "."
          - name: DOCKERFILE
            value: "Dockerfile"
        workspaces:
          - name: source
            workspace: shared-workspace

      - name: deploy-app
        runAfter:
          - build-image
        workspaces:
          - name: source
            workspace: shared-workspace
        taskSpec:
          workspaces:
            - name: source
          steps:
            - name: apply-and-verify
              image: quay.io/openshift/origin-cli:latest
              script: |
                #!/usr/bin/env bash
                set -e
                cd $(workspaces.source.path)
                oc apply -f kubernetes/deployment.yaml -n my-app-dev
                oc set image deployment/my-app-simple my-app-simple=image-registry.openshift-image-registry.svc:5000/my-app-dev/my-app-simple:$(params.revision) -n my-app-dev
                oc rollout status deployment/my-app-simple -n my-app-dev --timeout=300s
```

Paso 9: Operación, Monitoreo y Comandos Útiles
=============================================

-   **Sincronización y Envío a GitLab:**

    ``` bash
    cd ~/my-app-simple
    git add .
    git commit -m "feat: complete pipeline setup and configuration"
    git push origin develop
    ```

-   **Monitoreo de PipelineRuns en OpenShift:**

    ``` bash
    oc get pipelineruns -n my-app-dev --sort-by='{.metadata.creationTimestamp}' -w
    ```

-   **Seguimiento del ciclo de vida de los Pods en vivo:**

    ``` bash
    oc get pods -n my-app-dev --sort-by='.metadata.creationTimestamp' -w
    ```

-   **Inspección de logs ante incidencias:**

    ``` bash
    oc logs -n my-app-dev <nombre-del-pod> --tail=100
    ```

-   **Cancelar un PipelineRun colgado o atascado:**

    ``` bash
    oc patch pipelinerun <nombre-del-pipelinerun> -n my-app-dev --type=merge -p '{"spec":{"status":"Cancelled"}}'
    ```
