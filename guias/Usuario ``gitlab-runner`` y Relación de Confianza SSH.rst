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

3. Habilitación de Cliente OpenShift (``oc``) para ``gitlab-runner``
====================================================================

Una vez establecida la sesión en el nodo master (``192.168.123.40``) bajo el usuario ``gitlab-runner``, verificar el acceso al binario ``oc`` y la sesión activa contra el clúster CRC.

3.1. Verificar disponibilidad del binario ``oc`` en el PATH
-----------------------------------------------------------
.. code-block:: bash

   which oc
   oc version

*Nota:* Si el comando ``oc`` no se encuentra en el PATH del usuario ``gitlab-runner``, copiar o enlazar el binario desde la ruta de instalación de CRC (habitualmente ``~/.crc/bin/oc/oc`` del usuario que instaló CRC hacia ``/usr/local/bin/oc``) usando ``root``:

.. code-block:: bash

   sudo cp /ruta/hacia/oc /usr/local/bin/oc
   sudo chmod +x /usr/local/bin/oc

3.2. Iniciar sesión en el clúster OpenShift Local
-------------------------------------------------
Como usuario ``gitlab-runner`` en el nodo ``192.168.123.40``, comprobar la sesión actual:

.. code-block:: bash

   oc whoami

Si retorna error de sesión no iniciada, autenticarse contra la API local de OpenShift (CRC) para guardar el contexto en ``~/.kube/config``:

.. code-block:: bash

   oc login -u kubeadmin -p <PASSWORD_KUBEADMIN> https://api.crc.testing:6443 --insecure-skip-tls-verify=true

*Verificación:* Ejecutar ``oc get projects`` para confirmar que el usuario ``gitlab-runner`` tiene visibilidad y permisos de administración sobre los proyectos y namespaces del clúster.

4. Resumen de Validación Pre-Pipeline
=====================================

Antes de relanzar el pipeline en GitLab, verificar los siguientes tres puntos desde el servidor ``192.168.123.121`` como usuario ``gitlab-runner``:

1. ``ssh gitlab-runner@192.168.123.40 "oc whoami"`` devuelve ``kubeadmin`` (o el usuario administrador configurado) sin pedir contraseña.
2. El usuario ``gitlab-runner`` en ``192.168.123.121`` pertenece al grupo ``docker`` (``groups gitlab-runner``).
3. El enrutamiento ``iptables`` hacia ``127.0.0.1:30080`` se encuentra activo en ``192.168.123.40`` para exponer el servicio NodePort.
