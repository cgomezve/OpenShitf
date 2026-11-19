# Manual Definitivo y Consolidado: Pipeline CI/CD con OpenShift Local (CRC), Pipelines as Code (PaC) y GitLab Local

* **Autor:** Carlos Gómez
* **Entorno:** GitLab CE local (HTTP, sin SSL) + OpenShift Local (CRC) + OpenShift Pipelines (Tekton & PaC)
* **Objetivo:** Configurar GitLab exclusivamente como repositorio de código y delegar la totalidad del ciclo CI/CD a OpenShift mediante Pipelines as Code, resolviendo progresivamente los permisos de seguridad (SCC), volúmenes efímeros, restricciones de usuario no-privilegiado (rootless) en Nginx y el enrutamiento de puertos.
* **Fecha:** 2026-11-18

---

## Introducción

Este manual recopila de principio a fin todo el diseño arquitectónico, los requisitos previos de red, la configuración del operador de Pipelines as Code (PaC), la resolución de bloqueos de seguridad (SCC), los ajustes de almacenamiento en volúmenes efímeros, la adaptación de Nginx para contenedores rootless (puerto 8080 y rutas temporales en `/tmp`) y la estabilización completa del pipeline de compilación con `buildah` y despliegue continuo en OpenShift.

---

## Paso 0: Habilitar Webhooks locales en GitLab (Requisito crítico)

Por defecto, GitLab bloquea las peticiones de Webhooks hacia direcciones IP privadas o dominios locales (como `apps-crc.testing`) por políticas de seguridad (SSRF).

1. Inicia sesión en GitLab con una cuenta de Administrador.
2. Ve a **Admin Area** (icono de llave inglesa) -> **Settings** -> **Network**.
3. Expande la sección **Outbound requests**.
4. Marca la casilla **Allow requests to the local network from webhooks and integrations**.
5. Haz clic en **Save changes**.

---

## Paso 1: Desactivar el CI/CD nativo de GitLab

Para evitar ejecuciones duplicadas o conflictos de compilación en el servidor de GitLab:

1. Entra a tu proyecto en GitLab.
2. En el menú lateral ve a **Settings** -> **General**.
3. Expande **Visibility, project features, permissions**.
4. En la sección **Repository**, desactiva el interruptor **CI/CD**.
5. Haz clic en **Save changes**.

---

## Paso 2: Instalar y habilitar OpenShift Pipelines (Tekton) y PaC

Como administrador del clúster (`kubeadmin`), instala el operador oficial y habilita Pipelines as Code:

1. Crear la suscripción para el operador:

```bash
cat <<EOF ## (SCC) (`api` (namespace): ) - --- --type="merge" -f -n -o -p="{" -z 1. 2. 3. 3: 4: 5: Asegurar Automatic CR Code Configurar Constraints Context Crea Crear EOF GitLab HTTP Namespace Obtener Obtén OpenShift OpenShift: Otorgar PaC Para Paso Permisos Pipelines Repository SCC Security ServiceAccount ServiceAccounts Subscription URL Verificar Webhook `Repository` `TektonConfig`: ``` ```bash `admin:repo_hook`). `anyuid` `oc` `pipeline`: `privileged` a acceso activación add-role-to-user add-scc-to-user adecuados adm al anyuid apiVersion: apply apuntando as channel: componentes con config configura configurar controlador correctamente: de del donde echo edit ejecuten el en enviará get hacia https://$(oc installPlanApproval: instancia jsonpath="{.spec.host}" kind: la las latest levanten los metadata: my-app-dev name: namespace: new-project oc openshift-marketplace openshift-operators openshift-pipelines openshift-pipelines-operator-rh operaciones [operators.coreos.com/v1alpha1](https://operators.coreos.com/v1alpha1) patch permitir personal pipeline pipelines-as-code-controller pods policy privileged privilegios project proyecto pública que recurso redhat-operators route ruta se secreto source: sourceNamespace: spec":{"platforms":{"openshift":{"pipelinesAsCode":{"enable":true}}}}}" spec: system:serviceaccount:my-app-dev:pipeline tareas tektonconfig token tu webhooks: y |> **Nota:** Asegúrate de configurar el Webhook en GitLab apuntando a la ruta del controlador de PaC y desmarcar la verificación SSL si utilizas certificados autofirmados en CRC.

---

## Paso 6: Estructura del Repositorio Local (`~/my-app-simple`)

El proyecto mantiene la siguiente distribución de archivos optimizada para entornos rootless:

```text
my-app-simple/
├── .tekton/
│   └── pipeline.yaml         # Definición del PipelineRun con PaC
├── kubernetes/
│   └── deployment.yaml       # Manifiestos de Deployment y Service para my-app-dev
├── Dockerfile                # Receta para Nginx rootless (/tmp y puerto 8080)
├── nginx.conf                # Configuración optimizada de Nginx para OpenShift
├── index.html                # Página web de prueba
└── contador.txt              # Archivo de control para pruebas de commits
