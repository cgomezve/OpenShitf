=============================================================================
Guía Completa: Pipeline CI/CD en GitLab con Registry Interno de OpenShift
=============================================================================

:Autor: Carlos Gómez
:Proyecto: my-app-simple
:Infraestructura: OpenShift Local / CRC (``192.168.123.40``) | GitLab (``srvgitlab``)
:Registro Interno OpenShift: ``default-route-openshift-image-registry.apps-crc.testing``
:Namespace de Despliegue: ``demo-app``

.. contents:: Tabla de Contenidos
   :depth: 2

1. Introducción y Arquitectura del Flujo
========================================

Este documento detalla el procedimiento completo y optimizado para configurar un pipeline en **GitLab CI/CD** capaz de compilar aplicaciones, autenticarse de forma segura mediante un token global de larga duración contra el **Registry Interno de OpenShift** (vía ruta predeterminada), y desplegar nativamente utilizando manifiestos e ``ImageStreams`` en el namespace ``demo-app``.

2. Configuración de Credenciales y Permisos en OpenShift
========================================================

Para permitir que los pipelines de GitLab interactúen con el registro interno de OpenShift y desplieguen recursos sin restricciones, se requiere crear una cuenta de servicio global (``ServiceAccount``) y otorgarle privilegios administrativos en el clúster.

2.1. Crear la Cuenta de Servicio Global
---------------------------------------

Ejecutar los siguientes comandos en el nodo de OpenShift (``srvopenshift``) con una sesión administrativa activa:

.. code-block:: bash

   oc create sa global-gitlab-deployer -n openshift-image-registry

2.2. Asignar Permisos de Administrador y Constructor
-----------------------------------------------------

Se vinculan los roles necesarios para permitir la gestión de recursos de clúster y la construcción de imágenes:

.. code-block:: bash

   oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:openshift-image-registry:global-gitlab-deployer
   oc policy add-role-to-user system:image-builder system:serviceaccount:openshift-image-registry:global-gitlab-deployer -n openshift-image-registry
   oc policy add-role-to-user admin system:serviceaccount:openshift-image-registry:global-gitlab-deployer -n openshift-image-registry

2.3. Generar el Token Estático de Larga Duración
------------------------------------------------

Emitir un token JWT con vigencia de un año (``8760h``):

.. code-block:: bash

   oc create token global-gitlab-deployer -n openshift-image-registry --duration=8760h

*Nota:* Copiar la cadena generada (que comienza por ``eyJ...``) para registrarla posteriormente en GitLab.

3. Configuración del Servidor GitLab y Demonio Docker
======================================================

Debido a que el registro interno de OpenShift expone un servicio HTTPS protegido por un certificado autofirmado, el servidor GitLab (``srvgitlab``) debe configurar su motor Docker para confiar en el dominio.

3.1. Declarar Registro Inseguro en Docker
------------------------------------------

Editar o crear el archivo de configuración del demonio Docker en ``/etc/docker/daemon.json``:

.. code-block:: json

   {
     "insecure-registries": [
       "default-route-openshift-image-registry.apps-crc.testing"
     ]
   }

3.2. Reiniciar el Servicio Docker
----------------------------------

Aplicar los cambios reiniciando el demonio:

.. code-block:: bash

   systemctl restart docker

4. Configuración de Variables en GitLab
=======================================

Para proteger las credenciales de acceso:

1. Ingresar al proyecto en la interfaz web de GitLab.
2. Navegar a **Settings** > **CI/CD** > **Variables** y hacer clic en **Add variable**.
3. Configurar los parámetros:
   * **Key:** ``OPENSHIFT_TOKEN``
   * **Value:** *(Pegar el token JWT generado en el paso 2.3)*
   * **Mask variable:** Activado (para ocultar el valor en los logs).
   * **Protect variable:** Opcional (desmarcar si la rama `develop` no está marcada como protegida).

5. Definición del Pipeline (``.gitlab-ci.yml``)
================================================

El archivo ``.gitlab-ci.yml`` automatiza la preparación de artefactos estáticos de Nginx, la autenticación mediante el token global con entrada estándar (``--password-stdin``), el envío directo al registro interno, y la aplicación de manifiestos en OpenShift:

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

6. Verificación y Resultados Exitosos
======================================

Al realizar un cambio y subirlo a la rama `develop`, las etapas del pipeline concluyen de forma exitosa y la aplicación se despliega de manera nativa.

Validación en el clúster OpenShift:

.. code-block:: bash

   oc get pods,istag -n demo-app

**Resultado esperado:**
El Pod se encuentra en estado ``Running`` y el ImageStream refleja la versión sincronizada lista para producción o desarrollo.
```eof
