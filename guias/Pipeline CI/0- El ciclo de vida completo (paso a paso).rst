Para entender cómo funciona todo este sistema sin perderte en tecnicismos, imagina una cadena de montaje automática en el namespace ``my-app-dev``: tú escribes el código y subes un cambio a GitLab, y OpenShift se encarga por su cuenta de empaquetarlo, guardarlo y encenderlo en el puerto del nodo (como el ``30012``).

1. El ciclo de vida completo (paso a paso)
==========================================

- **Disparo desde GitLab (``git push``):** Haces ``git push origin develop``. GitLab envía una notificación automática (Webhook) a Pipelines as Code (PaC) en OpenShift, y GitLab no compila nada por su cuenta porque su CI/CD nativo está apagado.
- **Creación del PipelineRun:** PaC lee el archivo ``.tekton/pipeline.yaml`` dentro de tu repo y crea una ejecución (``PipelineRun``) en ``my-app-dev`` con el hash exacto de tu commit (``$(params.revision)``).
- **Descarga del código (``git-clone``):** Un pod temporal clona tu repositorio en un espacio compartido en memoria (``emptyDir``), para que todos los pasos siguientes trabajen sobre los mismos archivos sin problemas de permisos de disco.
- **Construcción de la imagen y subida al Registry (``build-image``):** El paso de compilación toma el ``Dockerfile`` y los archivos de tu proyecto, arma la imagen del contenedor y la sube al registro interno de OpenShift (``image-registry.openshift-image-registry.svc:5000/my-app-dev/my-app-simple:<hash-del-commit>``). Queda registrada como un ``ImageStream``.
- **Despliegue y reemplazo del Pod (``deploy-app``):** Se aplica ``kubernetes/deployment.yaml`` con ``oc apply``, se actualiza el ``Deployment`` ``my-app-simple`` para que use la imagen nueva con el hash del commit y se ejecuta ``oc rollout status``. OpenShift levanta el pod nuevo, verifica que arranque bien y apaga el pod viejo (``RollingUpdate``). El ``Service`` tipo ``NodePort`` mantiene tu puerto de nodo (ej. ``30012``) apuntando al puerto interno del servicio (``80``) y este al del contenedor (``8080``).

.. note::
   **Verificación:** Si al terminar el ``PipelineRun`` ves el pod de la aplicación en ``Running (1/1)`` y ``curl http://127.0.0.1:30012`` responde con tu cambio, todo el ciclo se completó bien.

2. Qué archivos se requieren y para qué sirve cada uno
====================================================

.. list-table::
   :header-rows: 1
   :widths: 25 45 30

   * - Archivo / Carpeta
     - ¿Para qué sirve?
     - ¿Qué pasa si falta o está mal configurado?
   * - ``.tekton/pipeline.yaml``
     - Es la receta del pipeline para Tekton y Pipelines as Code: define qué evento lo dispara (``push`` a ``develop``), cómo clona el código, cómo construye/sube la imagen y cómo despliega en OpenShift.
     - OpenShift no sabrá qué ejecutar automáticamente al recibir el webhook de GitLab.
   * - ``Dockerfile``
     - Indica cómo armar la imagen del contenedor: qué imagen base usar, qué archivos copiar adentro y qué puerto expone la aplicación (ej. ``8080``).
     - No se puede construir la imagen del contenedor.
   * - ``nginx.conf`` (en apps Nginx)
     - Configura Nginx para correr sin privilegios de root en OpenShift: usa rutas temporales en ``/tmp`` y escucha en un puerto alto (``8080``) en vez del ``80``.
     - Nginx falla al arrancar con errores de permiso de escritura o ``Permission denied`` en puerto privilegiado.
   * - ``kubernetes/deployment.yaml``
     - Define dos recursos clave: el ``Deployment`` (cómo corre el pod, su imagen y su puerto de contenedor) y el ``Service`` (cómo se expone la red, por ejemplo ``NodePort`` en ``30012`` hacia ``port: 80`` y ``targetPort: 8080``).
     - El pod no se crea/actualiza o el tráfico no llega al contenedor (o falla por ``NodePort`` ya ocupado).
   * - Archivos de la app (``index.html``, ``contador.txt``, código fuente, etc.)
     - Son el contenido o la lógica real de tu aplicación que se copia dentro de la imagen durante el build.
     - La imagen se construye vacía o sin tus cambios recientes.
   * - ``.gitignore`` / ``.dockerignore``
     - Evitan subir o empaquetar archivos innecesarios o pesados (temporales, carpetas locales, etc.).
     - Repositorio e imágenes más pesadas y sucias con archivos locales.

3. Regla práctica para reutilizarlo en otros proyectos
====================================================

Si otro desarrollador toma esta plantilla para otro lenguaje (Node.js, Python, Java, etc.), el ciclo de vida es idéntico: solo adapta el ``Dockerfile`` a su runtime, usa un puerto no privilegiado (``8080``, ``3000``, ``8000``, etc.) y hace que ``containerPort`` en el ``Deployment`` y ``targetPort`` en el ``Service`` coincidan con ese puerto.
