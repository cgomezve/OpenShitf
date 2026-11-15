========================================================================
Persistencia del Parámetro `route_localnet` en el Kernel de RHEL
========================================================================

El comando ``sysctl -w`` aplica cambios de forma volátil que se pierden al reiniciar 
el servidor. Este procedimiento detalla cómo consultar el estado del parámetro 
y cómo configurarlo de manera permanente para que sobreviva a los reinicios.


1. Consultar el Estado Actual del Parámetro
=========================================

Para verificar si el reenvío de IPs locales está activo en el kernel actual, 
puede utilizar cualquiera de los siguientes comandos:

.. code-block:: bash

   cat /proc/sys/net/ipv4/conf/all/route_localnet

O bien mediante la utilidad ``sysctl``:

.. code-block:: bash

   sudo sysctl net.ipv4.conf.all.route_localnet

*Resultado esperado:* El valor retornado debe ser ``1`` (activo).


2. Configurar la Persistencia Permanente
======================================

Para asegurar que el parámetro se aplique automáticamente cada vez que inicie el sistema operativo:

1. Cree un archivo de configuración personalizado dentro del directorio de políticas del kernel:

   .. code-block:: bash

      echo "net.ipv4.conf.all.route_localnet = 1" | sudo tee /etc/sysctl.d/99-route_localnet.conf

2. Recargue todas las configuraciones del sistema para aplicarlas de inmediato:

   .. code-block:: bash

      sudo sysctl --system

*Verificación:* En el listado que genera el comando ``sysctl --system``, compruebe que se cargó 
correctamente el archivo ``/etc/sysctl.d/99-route_localnet.conf`` sin errores.
