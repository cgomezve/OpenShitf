=============================================================================
Procedimiento Definitivo: Autenticación Permanente en Registry de OpenShift 
y Automatización CI/CD con GitLab
=============================================================================

:Autor: Carlos Gómez
:Proyecto: my-app-simple
:Infraestructura: OpenShift Local / CRC (``192.168.123.40``) | GitLab (``srvgitlab``)
:Registro Interno OpenShift: ``default-route-openshift-image-registry.apps-crc.testing``
:Namespace de Despliegue: ``demo-app``

.. contents:: Tabla de Contenidos
   :depth: 2

1. Introducción y Arquitectura de la Solución
============================================

Este documento consolida el procedimiento definitivo para configurar un pipeline de **GitLab CI/CD** robusto y permanente. Se elimina el problema de expiración de tokens mediante el uso de un secreto basado en tokens de larga duración, permitiendo a los pipelines compilar, autenticarse y subir imágenes directamente al **Registry Interno de OpenShift** sin intervención manual.

2. Creación de Cuenta de Servicio y Token Permanente
=====================================================

Para evitar la caducidad anual de los tokens de servicio estándar, se genera un recurso de tipo token de larga duración asociado a la cuenta de servicio global del registro.

2.1. Crear la Cuenta de Servicio Global
---------------------------------------

Ejecutar en el nodo de OpenShift (``srvopenshift``) con privilegios de administrador:

.. code-block:: bash

   oc create sa global-gitlab-deployer -n openshift-image-registry

2.2. Asignar Permisos de Administrador y Constructor
-----------------------------------------------------

Otorgar los roles necesarios para la gestión del clúster y construcción de imágenes:

.. code-block:: bash

   oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:openshift-image-registry:global-gitlab-deployer
   oc policy add-role-to-user system:image-builder system:serviceaccount:openshift-image-registry:global-gitlab-deployer -n openshift-image-registry
   oc policy add-role-to-user admin system:serviceaccount:openshift-image-registry:global-gitlab-deployer -n openshift-image-registry

2.3. Crear el Secreto Permanente y Extraer el Token
---------------------------------------------------

Generar un secreto de tipo token de servicio que no expira y extraer su valor codificado:

.. code-block:: bash

   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: Secret
   metadata:
     name: global-gitlab-deployer-token
     namespace: openshift-image-registry
     annotations:
       kubernetes.io/service-account.name: global-gitlab-deployer
   type: kubernetes.io/service-account-token
   EOF

   # Extraer y decodificar el JWT definitivo
   oc get secret global-gitlab-deployer-token -n openshift-image-registry -o jsonpath='{.data.token}' | base64 --decode

*Nota:* Copiar esta cadena completa que inicia con ``eyJ...`` para configurarla de forma permanente en GitLab.

3. Configuración del Servidor GitLab y Demonio Docker
======================================================

Para que el servidor GitLab (``srvgitlab``) confíe en el registro interno expuesto por HTTPS con certificado autofirmado:

3.1. Configurar Registros Inseguros
-----------------------------------

Editar o crear el archivo ``/etc/docker/daemon.json``:

.. code-block:: json

   {
     "insecure-registries": [
       "default-route-openshift-image-registry.apps-crc.testing"
     ]
   }

3.2. Reiniciar el Servicio Docker
----------------------------------

.. code-block:: bash

   systemctl restart docker

4. Configuración de Variables en GitLab
=======================================

1. Ingresar a la interfaz web de GitLab en el proyecto correspondiente.
2. Navegar a **Settings** > **CI/CD** > **Variables** y hacer clic en **Add variable**.
3. Registrar los siguientes parámetros:
   * **Key:** ``OPENSHIFT_TOKEN``
   * **Value:** *(Pegar el token permanente obtenido en el paso 2.3)*
   * **Mask variable:** Activado (para proteger la credencial en los logs).
   * **Protect variable:** Opcional (según si la rama `develop` es protegida).

5. Definición del Pipeline (``.gitlab-ci.yml``)
================================================

El siguiente archivo automatiza las etapas de compilación, autenticación segura mediante entrada estándar (``--password-stdin``), subida al registro y aplicación de manifiestos:

.. code-block:: yaml

   stages:
     - build
     - registerDev
     - deployDev

   variables:
     REPO_DEV: "default-route-openshift-image-registry.apps-crc.testing/demo-app"
     HOSTMASTER: "192.168.123.40"
     PORT_OPENSHIFT: "30080"
     USER: "gitlab-runner"

   nginx-build:
     stage: build
     script:
       - echo "Preparando archivos estáticos para Nginx..."
       - ls -la
     tags:
       - shell
     artifacts:
       paths:
         - index.html
         - Dockerfile
     only:
       - develop

   docker-build-dev:
     stage: registerDev
     script:
       - echo "Autenticando contra el registro interno de OpenShift con token global..."
       - echo "${OPENSHIFT_TOKEN}" | docker login default-route-openshift-image-registry.apps-crc.testing -u global-gitlab-deployer --password-stdin
       
       - echo "Construyendo y subiendo imagen directamente al registry interno..."
       - docker build -t ${REPO_DEV}/${CI_PROJECT_NAME}:${CI_PIPELINE_ID} .
       - docker push ${REPO_DEV}/${CI_PROJECT_NAME}:${CI_PIPELINE_ID}
     tags:
       - shell
     only:
       - develop

   deploy-dev:
     stage: deployDev
     script:
       - |
         APP_NAME="${CI_PROJECT_NAME}"
         DEPLOYMENT_NAME="${CI_PROJECT_NAME}-dev"
         IMAGE_NAME="image-registry.openshift-image-registry.svc:5000/demo-app/${CI_PROJECT_NAME}:${CI_PIPELINE_ID}"
         
         cat << END_YAML > openshift-manifests.yaml
         apiVersion: v1
         kind: Namespace
         metadata:
           name: demo-app
         ---
         apiVersion: image.openshift.io/v1
         kind: ImageStream
         metadata:
           name: ${APP_NAME}
           namespace: demo-app
         ---
         apiVersion: v1
         kind: ConfigMap
         metadata:
           name: nginx-config-dev
           namespace: demo-app
         data:
           default.conf: |
             server {
                 listen 8080;
                 server_name localhost;
                 location / {
                     root /usr/share/nginx/html;
                     index index.html index.htm;
                 }
             }
         ---
         apiVersion: apps/v1
         kind: Deployment
         metadata:
           name: ${DEPLOYMENT_NAME}
           namespace: demo-app
           labels:
             app: ${APP_NAME}
         spec:
           replicas: 1
           selector:
             matchLabels:
               app: ${APP_NAME}
           template:
             metadata:
               labels:
                 app: ${APP_NAME}
             spec:
               containers:
               - name: ${APP_NAME}
                 image: ${IMAGE_NAME}
                 imagePullPolicy: Always
                 ports:
                 - containerPort: 8080
                   name: http
                 securityContext:
                   allowPrivilegeEscalation: false
                   runAsNonRoot: true
                 volumeMounts:
                 - name: nginx-conf
                   mountPath: /etc/nginx/conf.d
                 - name: nginx-cache
                   mountPath: /var/cache/nginx
                 - name: nginx-run
                   mountPath: /var/run
               volumes:
               - name: nginx-conf
                 configMap:
                   name: nginx-config-dev
               - name: nginx-cache
                 emptyDir: {}
               - name: nginx-run
                 emptyDir: {}
         ---
         apiVersion: v1
         kind: Service
         metadata:
           name: ${APP_NAME}-service
           namespace: demo-app
         spec:
           type: NodePort
           selector:
             app: ${APP_NAME}
           ports:
           - port: 8080
             targetPort: 8080
             nodePort: ${PORT_OPENSHIFT}
             protocol: TCP
         END_YAML
         
         echo "Copiando manifiestos de OpenShift al nodo master ${HOSTMASTER}..."
         scp openshift-manifests.yaml ${USER}@${HOSTMASTER}:/tmp/
         
         echo "Aplicando configuración en OpenShift Local..."
         ssh -t -t ${USER}@${HOSTMASTER} "oc apply -f /tmp/openshift-manifests.yaml"
         ssh -t -t ${USER}@${HOSTMASTER} "oc rollout status deployment/${DEPLOYMENT_NAME} -n demo-app"
         ssh -t -t ${USER}@${HOSTMASTER} "oc get pods,istag -n demo-app"
     tags:
       - shell
     only:
       - develop

6. Verificación de Funcionamiento y Diagnóstico
===============================================

Para validar el estado de los componentes desplegados en el clúster:

.. code-block:: bash

   oc get pods,istag -n demo-app

**Resultado Esperado:**
Los Pods se encuentran en estado ``Running`` y las etiquetas de imagen (**ImageStreamTags**, o ``istag``) reflejan de manera precisa la versión desplegada en el registro interno.

Para eliminar etiquetas obsoletas de ImageStream que ya no se utilicen:

.. code-block:: bash

   oc delete istag/<nombre-imagen>:<tag-obsoleto> -n demo-app
