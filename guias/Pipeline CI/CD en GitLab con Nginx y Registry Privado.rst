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
     PORT_KUBERNETES: "30080"
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
         DEPLOYMENT_NAME="${CI_PROJECT_NAME}-${CI_PIPELINE_ID}"
         IMAGE_NAME="${REPO_DEV}/${CI_PROJECT_NAME}:${CI_PIPELINE_ID}"
         
         cat << 'END_YAML' > deployment.yaml
         apiVersion: apps/v1
         kind: Deployment
         metadata:
           name: ${DEPLOYMENT_NAME}
           namespace: default
           labels:
             app: ${CI_PROJECT_NAME}
             version: ${CI_PIPELINE_ID}
         spec:
           replicas: 1
           selector:
             matchLabels:
               app: ${CI_PROJECT_NAME}
           template:
             metadata:
               labels:
                 app: ${CI_PROJECT_NAME}
                 version: ${CI_PIPELINE_ID}
             spec:
               containers:
               - name: ${CI_PROJECT_NAME}
                 image: ${IMAGE_NAME}
                 imagePullPolicy: Always
                 ports:
                 - containerPort: 80
                   name: http
         END_YAML
         
         echo "Copiando deployment.yaml al nodo master ${HOSTMASTER} como ${USER}..."
         scp deployment.yaml ${USER}@${HOSTMASTER}:/tmp/
         
         echo "Ejecutando kubectl en el nodo master..."
         ssh -t -t ${USER}@${HOSTMASTER} "sudo kubectl apply -f /tmp/deployment.yaml"
         ssh -t -t ${USER}@${HOSTMASTER} "sudo kubectl delete service ${CI_PROJECT_NAME}-service --ignore-not-found=true"
         ssh -t -t ${USER}@${HOSTMASTER} "sudo kubectl create service nodeport ${CI_PROJECT_NAME}-service --tcp=80:80 --node-port=${PORT_KUBERNETES}"
         ssh -t -t ${USER}@${HOSTMASTER} "sudo kubectl rollout status deployment/${DEPLOYMENT_NAME}"
         ssh -t -t ${USER}@${HOSTMASTER} "sudo kubectl get pods -l app=${CI_PROJECT_NAME}"
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

5. Estado Actual del Laboratorio
================================

* **nginx-build**: Completado exitosamente (validador de artefactos estáticos).
* **docker-build-dev**: Completado exitosamente (imagen construida y subida a ``192.168.123.150:4443/my-app-simple``).
* **deploy-dev**: Pendiente de integración con clúster Kubernetes e intercambio de llaves SSH en ``192.168.123.40``.
