# Manual Definitivo y Consolidado: Pipeline CI/CD con OpenShift Local (CRC), Pipelines as Code (PaC) y GitLab Local

* **Autor:** Carlos Gómez
* **Entorno:** GitLab CE local (HTTP, sin SSL) + OpenShift Local (CRC) + OpenShift Pipelines (Tekton & PaC)
* **Objetivo:** Configurar GitLab exclusivamente como repositorio de código y delegar la totalidad del ciclo CI/CD a OpenShift mediante Pipelines as Code, resolviendo progresivamente los permisos de seguridad (SCC), volúmenes efímeros, restricciones de usuario no-privilegiado (rootless) en Nginx y el enrutamiento de puertos.
* **Fecha:** 2026-11-18

---

## Contenido

1. [Introducción](#introducción)
2. [Paso 0: Habilitar Webhooks locales en GitLab (Requisito crítico)](#paso-0-habilitar-webhooks-locales-en-gitlab-requisito-crítico)
3. [Paso 1: Desactivar el CI/CD nativo de GitLab](#paso-1-desactivar-el-cicd-nativo-de-gitlab)
4. [Paso 2: Instalar y habilitar OpenShift Pipelines (Tekton) y PaC](#paso-2-instalar-y-habilitar-openshift-pipelines-tekton-y-pac)
5. [Paso 3: Crear el Namespace y configurar ServiceAccounts y Permisos SCC](#paso-3-crear-el-namespace-y-configurar-serviceaccounts-y-permisos-scc)
6. [Paso 4: Obtener la URL del controlador de PaC](#paso-4-obtener-la-url-del-controlador-de-pac)
7. [Paso 5: Configurar el Repository CR en OpenShift y Webhook en GitLab](#paso-5-configurar-el-repository-cr-en-openshift-y-webhook-en-gitlab)
8. [Paso 6: Estructura del Repositorio Local (`~/my-app-simple`)](#paso-6-estructura-del-repositorio-local-my-app-simple)
9. [Paso 7: Archivos de Configuración del Contenedor y Despliegue](#paso-7-archivos-de-configuración-del-contenedor-y-despliegue)
10. [Paso 8: Manifiesto Consolidado Final `.tekton/pipeline.yaml`](#paso-8-manifiesto-consolidado-final-tektonpipelineyaml)
11. [Paso 9: Operación, Monitoreo y Comandos Útiles](#paso-9-operación-monitoreo-y-comandos-útiles)

---

## Introducción

Este manual recopila de principio a fin todo el diseño arquitectónico, los requisitos previos de red, la configuración del operador de Pipelines as Code (PaC), la resolución de bloqueos de seguridad (SCC), los ajustes de almacenamiento en volúmenes efímeros, la adaptación de Nginx para contenedores rootless (puerto 8080 y rutas temporales en `/tmp`) y la estabilización completa del pipeline de compilación con `buildah` y despliegue continuo en OpenShift.

## Paso 0: Habilitar Webhooks locales en GitLab (Requisito crítico)

Por defecto, GitLab bloquea las peticiones de Webhooks hacia direcciones IP privadas o dominios locales (como `apps-crc.testing`) por políticas de seguridad (SSRF).

1. Inicia sesión en GitLab con una cuenta de Administrador.
2. Ve a **Admin Area** (icono de llave inglesa) -> **Settings** -> **Network**.
3. Expande la sección **Outbound requests**.
4. Marca la casilla **Allow requests to the local network from webhooks and integrations**.
5. Haz clic en **Save changes**.

## Paso 1: Desactivar el CI/CD nativo de GitLab

Para evitar ejecuciones duplicadas o conflictos de compilación en el servidor de GitLab:

1. Entra a tu proyecto en GitLab.
2. En el menú lateral ve a **Settings** -> **General**.
3. Expande **Visibility, project features, permissions**.
4. En la sección **Repository**, desactiva el interruptor **CI/CD**.
5. Haz clic en **Save changes**.

## Paso 2: Instalar y habilitar OpenShift Pipelines (Tekton) y PaC

Como administrador del clúster (`kubeadmin`), instala el operador oficial y habilita Pipelines as Code:

1. Crear la suscripción para el operador:

   ```bash
   cat <<EOF | oc apply -f -
   apiVersion: [operators.coreos.com/v1alpha1](https://operators.coreos.com/v1alpha1)
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
