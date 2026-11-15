================================================================================
Guía de Configuración de Servidor y Cliente NFS en Rocky Linux 9.8
================================================================================

Esta guía detalla los pasos necesarios para instalar y configurar un servidor NFS (Network File System) en Rocky Linux 9.8, así como la configuración correspondiente en los equipos clientes para montar directorios compartidos de forma persistente y segura.

.. contents:: Tabla de Contenidos
   :depth: 2
   :local:

--------------------------------------------------------------------------------
1. Configuración del Servidor NFS
--------------------------------------------------------------------------------

Paso 1.1: Instalación de Paquetes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En el nodo que funcionará como servidor NFS, instale el paquete del servidor mediante ``dnf``:

.. code-block:: bash

   sudo dnf install nfs-utils -y

Paso 1.2: Creación y Preparación del Directorio Compartido
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Cree el directorio que desea exportar y establezca los permisos adecuados:

.. code-block:: bash

   sudo mkdir -p /srv/nfs/compartido
   sudo chown -R nfsnobody:nfsnobody /srv/nfs/compartido
   sudo chmod 755 /srv/nfs/compartido

Paso 1.3: Configuración de Exportaciones (exports)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Edite el archivo de configuración de exportaciones con su editor preferido:

.. code-block:: bash

   sudo nano /etc/exports

Añada la siguiente línea para compartir el directorio con una red específica (por ejemplo, ``192.168.1.0/24``):

.. code-block:: text

   /srv/nfs/compartido  192.168.1.0/24(rw,sync,no_root_squash,no_subtree_check)

*Opciones comunes:*
- ``rw``: Permite lectura y escritura.
- ``sync``: Escribe los cambios en el disco antes de responder (mayor seguridad).
- ``no_root_squash``: Mantiene los privilegios de root del cliente sobre el recurso compartido (úsese con precaución).

Paso 1.4: Configuración del Firewall y SELinux
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Abra los puertos necesarios en el servicio de firewall de Rocky Linux:

.. code-block:: bash

   sudo firewall-cmd --permanent --add-service={nfs,mountd,rpc-bind}
   sudo firewall-cmd --reload

Si SELinux está activo en modo ``enforcing``, configure los booleanos necesarios si planea lectura/escritura genérica:

.. code-block:: bash

   sudo setsebool -P nfs_export_all_rw 1
   sudo setsebool -P nfs_export_all_ro 1

Paso 1.5: Habilitación y Arranque del Servicio
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Inicie y habilite el servicio NFS para que persista tras reinicios:

.. code-block:: bash

   sudo systemctl enable --now nfs-server

Verifique el estado del servidor:

.. code-block:: bash

   sudo systemctl status nfs-server
   sudo exportfs -av

--------------------------------------------------------------------------------
2. Configuración del Cliente NFS
--------------------------------------------------------------------------------

Paso 2.1: Instalación de Utilidades NFS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En cada máquina cliente, instale las utilidades de cliente NFS necesarias para realizar los montajes:

.. code-block:: bash

   sudo dnf install nfs-utils -y

Paso 2.2: Creación del Punto de Montaje Local
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Cree el directorio local en el cual se montará el recurso compartido:

.. code-block:: bash

   sudo mkdir -p /mnt/nfs_compartido

Paso 2.3: Montaje Manual de Prueba
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Verifique que puede montar el recurso temporalmente desde el servidor (reemplace ``192.168.1.100`` por la IP de su servidor NFS):

.. code-block:: bash

   sudo mount -t nfs 192.168.1.100:/srv/nfs/compartido /mnt/nfs_compartido

Compruebe que el montaje fue exitoso ejecutando:

.. code-block:: bash

   df -h | grep nfs

Paso 2.4: Configuración del Montaje Persistente (/etc/fstab)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Para asegurar que el recurso se monte automáticamente al arrancar el sistema, edite el archivo ``/etc/fstab``:

.. code-block:: bash

   sudo nano /etc/fstab

Añada la siguiente línea al final del archivo:

.. code-block:: text

   192.168.1.100:/srv/nfs/compartido  /mnt/nfs_compartido  nfs  defaults,_netdev  0  0

.. note::
   El parámetro ``_netdev`` es crucial en entornos de red para asegurar que el sistema intente montar la partición únicamente después de que las interfaces de red estén completamente levantadas.

Paso 2.5: Verificación Final del Fstab
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Pruebe la configuración recargando las unidades de montaje sin necesidad de reiniciar:

.. code-block:: bash

   sudo umount /mnt/nfs_compartido
   sudo mount -a

Si no se generan errores y el comando ``df -h`` muestra nuevamente la unidad montada, la configuración de cliente habrá finalizado con éxito.
