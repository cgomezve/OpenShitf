===============================================================================
Manual de Configuración: Usuario ``gitlab-runner`` y Relación de Confianza SSH
===============================================================================

:Autor: Carlos Gómez
:Servidor Origen (GitLab / Runner): 192.168.123.121
:Servidor Destino (Nodo Master OpenShift Local): 192.168.123.40
:Sistema Operativo: RHEL / Rocky Linux 9

.. contents:: Contenido
   :depth: 2

1. Creación del Usuario ``gitlab-runner``
=========================================

Este procedimiento debe ejecutarse tanto en el servidor donde corre el GitLab Runner (``192.168.123.121``) como en el nodo destino OpenShift Local (``192.168.123.40``), si aún no existe el usuario en alguno de ellos.

1.1. Crear usuario de sistema y directorio home
------------------------------------------------
Ejecutar con privilegios de administrador (``sudo`` o ``root``):

.. code-block:: bash

   sudo useradd --system --home-dir /home/gitlab-runner --create-home --shell /bin/bash gitlab-runner

*Verificación:* Comprobar que el usuario fue creado correctamente y validar su identificador (UID/GID):

.. code-block:: bash

   id gitlab-runner

1.2. Asignar contraseña temporal (Requerido para ``ssh-copy-id``)
-----------------------------------------------------------------
En el servidor destino (``192.168.123.40``), asignar una contraseña al usuario ``gitlab-runner`` para permitir el intercambio inicial de la llave pública:

.. code-block:: bash

   sudo passwd gitlab-runner

1.3. Agregar ``gitlab-runner`` al grupo ``docker`` (Servidor GitLab)
--------------------------------------------------------------------
En el servidor donde corre el GitLab Runner (``192.168.123.121``), otorgar permisos de acceso al socket de Docker (``/var/run/docker.sock``) para evitar errores de permisos durante la etapa ``registerDev``:

.. code-block:: bash

   sudo usermod -aG docker gitlab-runner

Reiniciar el servicio de Docker y el GitLab Runner para que el cambio de grupo surta efecto:

.. code-block:: bash

   sudo systemctl restart docker
   sudo systemctl restart gitlab-runner

*Verificación:* Confirmar que ``docker`` aparezca en la lista de grupos asignados al usuario:

.. code-block:: bash

   groups gitlab-runner

2. Configuración de Relación de Confianza (SSH sin contraseña)
==============================================================

Para que la etapa ``deploy-dev`` del pipeline transfiera manifiestos mediante ``scp`` y ejecute comandos remotos por ``ssh`` de forma automatizada, es indispensable configurar autenticación por llave pública.

2.1. Generar par de llaves RSA en el servidor GitLab
----------------------------------------------------
En el servidor GitLab (``192.168.123.121``), cambiar a la sesión del usuario ``gitlab-runner``:

.. code-block:: bash

   su - gitlab-runner

Verificar si ya existe una llave pública:

.. code-block:: bash

   ls -la ~/.ssh/id_rsa.pub

Si el archivo no existe, generar un par de llaves RSA de 4096 bits sin frase de paso (*passphrase* vacía):

.. code-block:: bash

   ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

*Verificación:* Confirmar que se crearon los archivos ``~/.ssh/id_rsa`` (llave privada) y ``~/.ssh/id_rsa.pub`` (llave pública).

2.2. Copiar la llave pública al nodo OpenShift Local
----------------------------------------------------
Desde la misma sesión de ``gitlab-runner`` en ``192.168.123.121``, transferir la llave pública al servidor ``192.168.123.40``:

.. code-block:: bash

   ssh-copy-id gitlab-runner@192.168.123.40

*(Ingresar la contraseña asignada en el paso 1.2 cuando el sistema la solicite).*

2.3. Validar conexión automática
--------------------------------
Ejecutar un comando de prueba remoto para verificar que el acceso se realiza sin solicitar contraseña ni interacción manual:

.. code-block:: bash

   ssh gitlab-runner@192.168.123.40 "hostname && whoami"

*Resultado esperado:* Debe devolver el nombre del host destino y ``gitlab-runner`` inmediatamente.

3. Habilitación de Cliente OpenShift (``oc``) y Credenciales para ``gitlab-runner``
===================================================================================

En el nodo master de OpenShift Local (``192.168.123.40``), es necesario exponer el binario ``oc`` de forma global en el sistema y transferir el archivo de configuración de sesión (``kubeconfig``) hacia el directorio personal de ``gitlab-runner``.

3.1. Crear enlace simbólico global del binario ``oc``
-----------------------------------------------------
Con un usuario con privilegios de administrador (ej. ``cgomeznt``), ubicar el binario ``oc`` en la caché de CRC y enlazarlo hacia ``/usr/local/bin/oc`` para que esté disponible en el ``PATH`` de todos los usuarios:

.. code-block:: bash

   sudo ln -s /home/cgomeznt/.crc/cache/crc_libvirt_4.22.14_amd64/oc /usr/local/bin/oc

*Verificación:* Comprobar que el binario es accesible desde cualquier ruta ejecutando ``which oc``.

3.2. Transferir configuración del clúster (``kubeconfig``)
----------------------------------------------------------
Copiar el archivo ``config`` de la sesión activa hacia el directorio ``~/.kube/`` del usuario ``gitlab-runner`` y asignar la propiedad correspondiente:

.. code-block:: bash

   sudo mkdir -p /home/gitlab-runner/.kube
   sudo cp /home/cgomeznt/.kube/config /home/gitlab-runner/.kube/config
   sudo chown -R gitlab-runner:gitlab-runner /home/gitlab-runner/.kube

3.3. Validar acceso y contexto de OpenShift
-------------------------------------------
Cambiar al usuario ``gitlab-runner`` y verificar la autenticación contra el clúster CRC:

.. code-block:: bash

   sudo su - gitlab-runner
   oc whoami
   oc get projects

*Resultado esperado:* ``oc whoami`` debe devolver ``kubeadmin`` (o el usuario administrador activo) y ``oc get projects`` debe listar los namespaces disponibles sin errores de configuración.

4. Resumen de Validación Pre-Pipeline
=====================================

Antes de relanzar el pipeline en GitLab, verificar los siguientes tres puntos desde el servidor ``192.168.123.121`` como usuario ``gitlab-runner``:

1. ``ssh gitlab-runner@192.168.123.40 "oc whoami"`` devuelve ``kubeadmin`` sin pedir contraseña.
2. El usuario ``gitlab-runner`` en ``192.168.123.121`` pertenece al grupo ``docker`` (``groups gitlab-runner``).
3. El enrutamiento ``iptables`` hacia ``127.0.0.1:30080`` se encuentra activo en ``192.168.123.40`` para exponer el servicio NodePort.
