=============================================================================
Migración de Imágenes hacia el Registro Interno de OpenShift y ImageStreams
=============================================================================

:Autor: Carlos Gómez
:Infraestructura: OpenShift Local / CRC (``192.168.123.40``) | Registry Externo (``192.168.123.150:4443``)
:Namespace: ``demo-app``
:Fecha: Noviembre 2026

.. contents:: Tabla de Contenidos
   :depth: 2

1. Objetivo y Alcance
=====================

Documentar el procedimiento técnico paso a paso para migrar una imagen de contenedor alojada en un registro externo hacia el **Registry Interno de OpenShift**, validando su disponibilidad mediante objetos nativos ``ImageStream`` e ``ImageStreamTag`` sin depender de servidores externos tras un reinicio del clúster.

2. Diagnóstico Inicial del Nodo y Clúster
=========================================

Antes de transferir la imagen, se valida el estado del motor de contenedores local (``podman``) y la existencia de etiquetas de imagen en el namespace objetivo:

.. code-block:: bash

   # Verificar imágenes almacenadas localmente en el nodo
   podman images

   # Verificar etiquetas de ImageStream registradas en el namespace
   oc get istag -n demo-app

**Resultado observado:** Ambas consultas retornaron vacías (``No resources found``), confirmando la causa del estado ``RegistryUnavailable`` en los Pods tras apagar el registro externo.

3. Obtención de Ruta y Autenticación en el Registry Interno
===========================================================

Para interactuar con el registro interno de OpenShift desde fuera del plano de control, se obtiene su ruta expuesta y se inicia sesión utilizando un token de sesión activo de ``oc``:

3.1. Consultar la ruta externa del registro
-------------------------------------------

.. code-block:: bash

   oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}'

**Salida:**

.. code-block:: text

   default-route-openshift-image-registry.apps-crc.testing

3.2. Autenticar Podman contra el registro interno
-------------------------------------------------

Dado que el clúster utiliza certificados autofirmados de laboratorio, se omite la verificación TLS con ``--tls-verify=false``:

.. code-block:: bash

   podman login --tls-verify=false -u kubeadmin -p $(oc whoami -t) default-route-openshift-image-registry.apps-crc.testing

**Salida:**

.. code-block:: text

   Login Succeeded!

4. Transferencia y Etiquetado de la Imagen
==========================================

Una vez autenticados, se descarga la imagen desde el origen externo, se reetiqueta apuntando al namespace destino en OpenShift y se sube al registro interno.

4.1. Descargar la imagen origen (Pull)
--------------------------------------

.. code-block:: bash

   podman pull 192.168.123.150:4443/my-app-simple:9 --tls-verify=false

4.2. Reetiquetar para el registro interno (Tag)
-----------------------------------------------

La estructura de destino debe seguir el formato ``<ruta-registry>/<namespace>/<nombre-imagen>:<tag>``:

.. code-block:: bash

   podman tag 192.168.123.150:4443/my-app-simple:9 default-route-openshift-image-registry.apps-crc.testing/demo-app/my-app-simple:9

4.3. Subir la imagen a OpenShift (Push)
---------------------------------------

.. code-block:: bash

   podman push default-route-openshift-image-registry.apps-crc.testing/demo-app/my-app-simple:9 --tls-verify=false

5. Verificación y Evidencia de Operatividad
===========================================

5.1. Comprobación en el motor local (Podman)
--------------------------------------------

.. code-block:: bash

   podman images

**Salida obtenida:**

.. code-block:: text

   REPOSITORY                                                                     TAG   IMAGE ID      CREATED         SIZE
   default-route-openshift-image-registry.apps-crc.testing/demo-app/my-app-simple 9     dc3406fdc7d6  15 minutes ago  64.4 MB
   192.168.123.150:4443/my-app-simple                                             9     dc3406fdc7d6  15 minutes ago  64.4 MB

5.2. Comprobación nativa en OpenShift (ImageStreamTag)
------------------------------------------------------

Al recibir el ``push``, OpenShift crea y vincula automáticamente el objeto ``ImageStream`` e ``ImageStreamTag`` dentro del proyecto:

.. code-block:: bash

   oc get istag -n demo-app

**Salida obtenida:**

.. code-block:: text

   NAME              IMAGE REFERENCE                                                                                                                         UPDATED
   my-app-simple:9   image-registry.openshift-image-registry.svc:5000/demo-app/my-app-simple@sha256:4fa89ba99798443497df962c973f21683d67505e5b1817dbd8daf11af517c82b   17 seconds ago

5.3. Actualizar la imagen en el Deployment

Como en el manifiesto aun apunta al registro interno. Ejecuta el siguiente comando para forzar al deployment a usar la ruta interna del registry de OpenShift:

.. code-block:: text

   oc set image deployment/my-app-simple-dev *=image-registry.openshift-image-registry.svc:5000/demo-app/my-app-simple:9 -n demo-app

Eliminar el pod bloqueado

.. code-block:: text

   oc delete pod -l app=my-app-simple -n demo-app

6. Próximos Pasos en el Despliegue
==================================

* Actualizar el parámetro ``image:`` en el manifiesto del ``Deployment`` para apuntar a la referencia interna: ``image-registry.openshift-image-registry.svc:5000/demo-app/my-app-simple:9``.
* Ejecutar el laboratorio pendiente de almacenamiento persistente mediante servidor **NFS externo** montado en ``/nfs-apps``.
