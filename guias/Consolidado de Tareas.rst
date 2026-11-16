=============================================================================
Listado Cronológico y Consolidado de Tareas, Configuraciones y Diagnósticos
=============================================================================

Listado cronológico y consolidado de todas las tareas, configuraciones y
diagnósticos que hemos ejecutado a lo largo de todo este laboratorio, desde la
preparación base hasta la automatización y diagnóstico de OpenShift y GitLab.

1. Preparación Base, Repositorios y GitLab
==========================================

- Creación del proyecto ``my-app-simple`` en GitLab y configuración de
  repositorio local en la rama ``develop``.
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

- Creación de la página web estática (``index.html``) y definición de la
  imagen base de contenedor (``Dockerfile`` con ``nginx:alpine``).
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

- Configuración de autenticación en GitLab mediante Personal Access Token
  (PAT) para operaciones ``git push`` sobre HTTP.
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

- Configuración de permisos en el servidor GitLab (``srvgitlab``) añadiendo
  al usuario ``gitlab-runner`` al grupo ``docker`` y reiniciando los
  servicios.
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

2. Configuración de Seguridad, Permisos y Registry en OpenShift
===============================================================

- Creación del namespace de despliegue (``demo-app``) y configuración inicial
  de registro inseguro en el clúster OpenShift Local / CRC mediante
  ``oc patch image.config.openshift.io/cluster``.
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

- Creación de la cuenta de servicio global (``global-gitlab-deployer``) en el
  namespace ``openshift-image-registry``.

- Asignación de roles administrativos y de registro (``cluster-admin``,
  ``system:image-builder``, ``system:image-puller`` y ``admin``) mediante
  ``oc adm policy`` y ``oc policy``.

- Generación de tokens de autenticación (tanto efímeros de larga duración con
  ``oc create token --duration=8760h`` / ``720h`` como pruebas de Secret de
  tipo ``kubernetes.io/service-account-token``).

- Registro del token JWT como variable enmascarada (``OPENSHIFT_TOKEN``)
  dentro de GitLab CI/CD.

- Configuración del demonio Docker en ``srvgitlab``
  (``/etc/docker/daemon.json``) declarando
  ``default-route-openshift-image-registry.apps-crc.testing`` como
  ``insecure-registries``.

3. Desarrollo y Estabilización del Pipeline CI/CD (.gitlab-ci.yml)
==================================================================

- Estructuración del pipeline en tres etapas: ``build``, ``registerDev`` y
  ``deployDev``.
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

- Implementación de login automatizado y seguro hacia el registry interno de
  OpenShift utilizando ``docker login --password-stdin``.

- Compilación y subida automática de imágenes etiquetadas con
  ``$CI_PIPELINE_ID`` directamente al registro interno de OpenShift.

- Generación dinámica y despliegue automatizado de manifiestos de OpenShift
  (Namespace, ImageStream, ConfigMap de Nginx en puerto 8080, Deployment
  adaptado a restricciones de seguridad ``runAsNonRoot`` y Service tipo
  NodePort en puerto 30080) vía ``scp`` y ``ssh`` hacia ``srvopenshift``.
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

- Verificación de despliegue automático mediante ``oc rollout status`` y
  validación externa con ``curl`` hacia el puerto 30080.
  *(Ref: CD-CI en GitLab con Nginx y Registry Privado.rst)*

4. Operación, Mantenimiento y Diagnóstico en OpenShift
======================================================

- Inspección de estado de pods y etiquetas de flujo de imágenes mediante
  ``oc get pods,istag -n demo-app``.

- Limpieza y eliminación de etiquetas obsoletas de ImageStreamTag con
  ``oc delete istag/<nombre>:<tag> -n demo-app``.

- Corrección de sintaxis para inspección detallada de eventos y errores en
  pods mediante ``oc describe pod <nombre-pod>``.

- Homologación del flujo de diagnóstico tradicional de Kubernetes
  (``crictl images`` / ``crictl pull``) hacia el entorno CRI-O y
  ``oc debug node/`` en OpenShift para aislar fallos de red, certificados TLS
  o permisos RBAC.

- Estructuración y depuración de toda la documentación técnica del proyecto en
  formato reStructuredText (``.rst``).
