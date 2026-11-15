=========================================================================
Guía Paso a Paso: Pipeline CI/CD en GitLab con Nginx y Registry Privado
=========================================================================

:Autor: Carlos Gómez
:Proyecto: my-app-simple
:Servidor GitLab: http://192.168.123.121/
:Registry Privado: 192.168.123.150:4443
:Nodo Master Kubernetes: 192.168.123.40

.. contents:: Contenido
   :depth: 2

1. Creación del Proyecto y Repositorio Local
=============================================

1.1. Crear el proyecto en la interfaz web de GitLab
---------------------------------------------------
1. Ingresar a ``http://192.168.123.121/``.
2. Hacer clic en **New project** > **Create blank project**.
3. Asignar el nombre ``my-app-simple``.
4. Seleccionar visibilidad *Private* o *Internal* y confirmar en **Create project**.

1.2. Inicializar el proyecto y crear ``index.html``
---------------------------------------------------
En el servidor de GitLab, crear el directorio del proyecto y la página web base:

.. code-block:: bash

   cd /root/gitlab/
   mkdir my-app-simple
   cd my-app-simple

   cat << 'EOF' > index.html
   <!DOCTYPE html>
   <html lang="es">
   <head>
       <meta charset="UTF-8">
       <title>Mi App Simple - Laboratorio</title>
   </head>
   <body style="font-family: Arial; text-align: center; margin-top: 50px;">
       <h1>¡Hola desde Nginx en GitLab CI/CD!</h1>
       <p>Proyecto desplegado exitosamente con my-app-simple.</p>
   </body>
   </html>
   EOF

   git init
   git checkout -b develop
   git remote add origin http://192.168.123.121/soporte-web/my-app-simple.git
   git add index.html
   git commit -m "Commit inicial con index.html"

2. Construcción de la Imagen Docker (Dockerfile)
================================================

Crear el archivo ``Dockerfile`` en la raíz del proyecto para empaquetar el contenido estático sobre ``nginx:alpine``:

.. code-block:: dockerfile

   FROM nginx:alpine
   COPY index.html /usr/share/nginx/html/index.html
   EXPOSE 80

3. Configuración del Pipeline (``.gitlab-ci.yml``)
==================================================

El pipeline replica una estructura de producción con tres etapas (``build``, ``registerDev``, ``deployDev``), enviando la imagen directamente a la raíz del registry privado (``192.168.123.150:4443``) etiquetada únicamente con ``$CI_PIPELINE_ID``:

.. code-block:: yaml

    stages:
     - build
     - registerDev
     - deployDev
   
   variables:
     REPO_DEV: "192.168.123.150:4443"
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
       - echo "Construyendo y subiendo imagen a la raíz del registry..."
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
         IMAGE_NAME="${REPO_DEV}/${CI_PROJECT_NAME}:${CI_PIPELINE_ID}"
         
         cat << END_YAML > openshift-manifests.yaml
         apiVersion: v1
         kind: Namespace
         metadata:
           name: demo-app
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
                 imagePullPolicy: IfNotPresent
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
         
         echo "Copiando manifiestos de OpenShift al nodo master ${HOSTMASTER} como ${USER}..."
         scp openshift-manifests.yaml ${USER}@${HOSTMASTER}:/tmp/
         
         echo "Aplicando configuración en OpenShift Local..."
         ssh -t -t ${USER}@${HOSTMASTER} "oc apply -f /tmp/openshift-manifests.yaml"
         ssh -t -t ${USER}@${HOSTMASTER} "oc rollout status deployment/${DEPLOYMENT_NAME} -n demo-app"
         ssh -t -t ${USER}@${HOSTMASTER} "oc get pods -n demo-app -l app=${APP_NAME}"
     tags:
       - shell
     only:
       - develop

4. Resolución de Permisos y Autenticación
=========================================

4.1. Personal Access Token (PAT) para Git Push
----------------------------------------------
Dado que GitLab exige autenticación mediante token sobre HTTP:

1. Ir a **Preferences** > **Access Tokens** en la interfaz web.
2. Crear un token con alcance ``api`` y ``write_repository``.
3. Configurar la URL remota con el token y realizar el push:

.. code-block:: bash

   git remote set-url origin http://root:TU_TOKEN_PERSONAL@192.168.123.121/soporte-web/my-app-simple.git
   git add .
   git commit -m "Configuración completa de pipeline CI/CD, Dockerfile e index.html"
   git push -u origin develop

4.2. Permisos de Docker para ``gitlab-runner``
----------------------------------------------
Para evitar el error ``permission denied while trying to connect to the docker API at unix:///var/run/docker.sock``:

.. code-block:: bash

   sudo usermod -aG docker gitlab-runner
   sudo systemctl restart docker
   sudo systemctl restart gitlab-runner

4.3. Configuración de Registro Privado Inseguro en OpenShift Local (CRC)
----------------------------------------------

Cuando OpenShift intenta descargar una imagen desde un registro privado que utiliza HTTP plano o certificados autofirmados (como ``192.168.123.150:4443``), el clúster bloquea la descarga por defecto generando el estado ``ImagePullBackOff`` en el pod.

Para habilitar el acceso hacia este registro, es necesario declararlo como registro inseguro en la configuración global del clúster.

4.4. Registrar el origen inseguro en el clúster
---------------------------------------------
Ejecutar el siguiente parche con un usuario administrador del clúster (``kubeadmin``):

.. code-block:: bash

   oc patch image.config.openshift.io/cluster --type=merge -p '{"spec":{"registrySources":{"insecureRegistries":["192.168.123.150:4443"]}}}'

*Verificación:* Comprobar que la dirección del registro quedó registrada en la especificación del clúster:

.. code-block:: bash

   oc get image.config.openshift.io/cluster -o jsonpath='{.spec.registrySources.insecureRegistries}'

*Resultado esperado:* Devolverá la lista incluyendo ``192.168.123.150:4443``.

5. Estado Actual del Laboratorio
================================

* **nginx-build**: Completado exitosamente (validador de artefactos estáticos).
* **docker-build-dev**: Completado exitosamente (imagen construida y subida a ``192.168.123.150:4443/my-app-simple``).
* **deploy-dev**: integración con clúster OpenShift 100% completado.
