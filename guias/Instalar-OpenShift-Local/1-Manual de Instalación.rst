=============================================================================
Manual de Instalación: Rocky Linux 9 / RHEL 9 y OpenShift Local (CRC)
=============================================================================

:Equipo Objetivo: GMKtec M6 Ultra (AMD Ryzen 5 7640HS, 32 GB RAM DDR5, 1 TB NVMe)
:Sistema Operativo: Rocky Linux 9 / Red Hat Enterprise Linux 9
:Componente Principal: Red Hat OpenShift Local (CRC)

.. contents:: Contenido del Manual
   :depth: 3
   :local:

-----------------------------------------------------------------------------
1. Fallas Conocidas y Medidas Preventivas
-----------------------------------------------------------------------------

Antes de iniciar el despliegue, es fundamental aplicar estas cuatro medidas preventivas para evitar errores documentados en entornos reales con este hardware y sistema operativo:

1. **Controladores Wi-Fi (MediaTek RZ616 / MT7922):**
   Las imágenes ISO *Minimal* pueden carecer de ``NetworkManager-wifi`` o del firmware actualizado. Utilice siempre la **ISO DVD completa** (aprox. 10 GB) de Rocky Linux 9 o RHEL 9 para garantizar soporte inalámbrico nativo durante la instalación.

2. **Sobrescritura de DNS al ejecutar ``crc setup`` (Issue #3840):**
   ``crc setup`` configura ``dnsmasq`` dentro de ``NetworkManager`` para resolver ``*.apps-crc.testing`` y ``api.crc.testing`` hacia ``127.0.0.1``. Si el adaptador Wi-Fi tiene DNS estáticos manuales, ``crc setup`` puede romper la resolución externa. Configure siempre la conexión inalámbrica por **DHCP automático** antes de preparar CRC.

3. **Prohibición de ejecución como usuario ``root``:**
   Ejecutar ``sudo crc setup`` o ``crc start`` como ``root`` provocará un fallo intencional de seguridad. Toda la gestión de CRC debe ejecutarse desde un **usuario estándar** con privilegios ``sudo`` y pertenencia al grupo ``libvirt``.

4. **Particionado del disco de 1 TB (``/home`` vs ``/``):**
   El esquema LVM automático de RHEL/Rocky asigna alrededor de 70 GB a ``/`` y destina el resto del almacenamiento a ``/home``. Mantenga este esquema por defecto, ya que CRC almacena su máquina virtual y discos virtuales (entre 35 GB y 100 GB) dentro de ``$HOME/.crc``.

-----------------------------------------------------------------------------
2. Preparación del BIOS e Instalación del Sistema Operativo
-----------------------------------------------------------------------------

2.1. Habilitar Virtualización por Hardware (AMD-V / SVM)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Encienda el **GMKtec M6 Ultra** y presione repetidamente ``Delete`` (``Supr``) o ``Esc`` para ingresar al BIOS.
2. Navegue hacia **Advanced** -> **CPU Configuration** (o **AMD CBS** -> **CPU Common Options**).
3. Verifique que las siguientes opciones estén habilitadas:
   - ``SVM Mode``: **Enabled**
   - ``IOMMU``: **Enabled** *(opcional recomendado)*
4. Presione ``F10`` para guardar los cambios y reiniciar.

2.2. Instalación de Rocky Linux 9 / RHEL 9
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Arranque desde el medio USB con la **DVD ISO** de Rocky Linux 9 o RHEL 9.
2. En **Selección de Software** (*Software Selection*), elija **Server** o **Minimal Install** para evitar sobrecarga gráfica y reservar toda la RAM para el laboratorio.
3. En **Destino de la Instalación** (*Installation Destination*), seleccione el SSD NVMe de 1 TB y deje el particionado automático.
4. Cree su usuario administrativo estándar (ejemplo: ``carlos``) marcando la casilla **Hacer a este usuario administrador** (*Make this user administrator*).
5. Finalice la instalación y reinicie el equipo.

-----------------------------------------------------------------------------
3. Configuración de Red Wi-Fi por Terminal (``nmcli``)
-----------------------------------------------------------------------------

Inicie sesión en la consola con su usuario normal y ejecute los siguientes pasos para conectar el equipo a la red inalámbrica mediante DHCP:

1. **Verificar la interfaz inalámbrica detectada:**

   .. code-block:: bash

      nmcli device

   .. note::
      Si la interfaz (``wlp...`` o ``wlan0``) aparece como ``unavailable``, active la radio inalámbrica con ``sudo nmcli radio wifi on`` y verifique que estén instalados los paquetes ``NetworkManager-wifi`` y ``linux-firmware``.

2. **Escanear las redes Wi-Fi disponibles:**

   .. code-block:: bash

      sudo nmcli device wifi rescan
      nmcli device wifi list

3. **Conectar a la red Wi-Fi:**

   .. code-block:: bash

      sudo nmcli device wifi connect "NOMBRE_DE_TU_WIFI" password "TU_CONTRASEÑA"

4. **Comprobar asignación IP y salida a Internet:**

   .. code-block:: bash

      ip -brief addr
      ping -c 3 8.8.8.8
      ping -c 3 redhat.com

.. tip::
   Anote la dirección IP asignada por su router (ejemplo: ``192.168.1.50``) para conectarse cómodamente vía SSH desde su estación de trabajo (``ssh carlos@192.168.1.50``).

-----------------------------------------------------------------------------
4. Preparación del Hipervisor KVM y Dependencias
-----------------------------------------------------------------------------

.. important::
   Si instaló **RHEL 9**, registre el sistema con su cuenta gratuita de Red Hat Developer antes de instalar paquetes:

   .. code-block:: bash

      sudo subscription-manager register --username TU_USUARIO_REDHAT --password TU_CLAVE
      sudo subscription-manager attach --auto

   Si instaló **Rocky Linux 9**, omita el bloque anterior y continúe directamente con el paso 1.

1. **Actualizar el sistema e instalar KVM, libvirt y utilidades:**

   .. code-block:: bash

      sudo dnf update -y
      sudo dnf install -y qemu-kvm libvirt libvirt-client virt-install NetworkManager dnsmasq tar xz policycoreutils-python-utils

2. **Habilitar e iniciar los servicios de virtualización y red:**

   .. code-block:: bash

      sudo systemctl enable --now libvirtd
      sudo systemctl enable --now NetworkManager

3. **Agregar su usuario al grupo ``libvirt`` y validar soporte de virtualización:**

   .. code-block:: bash

      sudo usermod -aG libvirt $USER
      newgrp libvirt
      egrep -c '(vmx|svm)' /proc/cpuinfo

   El último comando debe devolver ``12`` (correspondiente a los 12 hilos del Ryzen 5 7640HS).

-----------------------------------------------------------------------------
5. Instalación y Arranque de OpenShift Local (CRC)
-----------------------------------------------------------------------------

5.1. Transferencia de Archivos Oficiales
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Desde su equipo donde descargó los instaladores (``crc-linux-amd64.tar.xz`` y ``pull-secret.txt``), transfiéralos al directorio personal del mini PC:

.. code-block:: bash

   scp crc-linux-amd64.tar.xz pull-secret.txt carlos@IP_DEL_MINIPC:~/

5.2. Instalación del Binario ``crc``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En la terminal del mini PC, con su **usuario estándar** (nunca como ``root``):

.. code-block:: bash

   cd ~
   tar -xvf crc-linux-amd64.tar.xz
   sudo install -m 0755 crc-linux-*/crc /usr/local/bin/crc
   crc version

5.3. Ajuste de Recursos del Clúster (Recomendado)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Para aprovechar los 32 GB de RAM DDR5 y el SSD NVMe de 1 TB del GMKtec M6 Ultra sin sufrir errores *OOMKilled*:

.. code-block:: bash

   crc config set memory 14336
   crc config set cpus 6
   crc config set disk-size 80

5.4. Configuración del Entorno (``crc setup``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Ejecute la preparación del hipervisor, red puente y descarga del bundle base (~3.5 GB):

.. code-block:: bash

   crc setup

.. warning::
   Al finalizar ``crc setup``, valide que la resolución DNS externa sigue funcionando correctamente ejecutando ``ping -c 2 redhat.com``.

5.5. Inicio del Clúster (``crc start``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Inicie el nodo único de OpenShift suministrando el archivo de credenciales:

.. code-block:: bash

   crc start -p ~/pull-secret.txt

El despliegue inicial tardará entre 5 y 12 minutos. Al concluir, el terminal mostrará la URL de la consola web (``https://console-openshift-console.apps-crc.testing``) y las contraseñas generadas para los usuarios ``kubeadmin`` y ``developer``.

5.6. Habilitación de la Herramienta CLI ``oc``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Para interactuar con el clúster desde la línea de comandos bash:

.. code-block:: bash

   eval $(crc oc-env)
   oc whoami
