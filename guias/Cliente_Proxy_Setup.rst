=========================================================
Configuración del Cliente Debian (Túnel SSH y Navegador)
=========================================================

Este documento detalla los pasos necesarios en su laptop Debian para establecer un túnel
SSH dinámico (SOCKS5) hacia el servidor OpenShift (``192.168.123.40``), configurar la resolución
de nombres locales y ajustar el navegador para acceder al clúster de forma transparente.


1. Establecer el Túnel SSH Dinámico
==================================

Ejecute el siguiente comando en la terminal de su laptop Debian para levantar un túnel SOCKS
en segundo plano en el puerto ``8080``:

.. code-block:: bash

   ssh -D 8080 -N -f cgomeznt@192.168.123.40

*Verificación:* Compruebe que el puerto local se encuentra escuchando correctamente ejecutando:

.. code-block:: bash

   ss -tulpn | grep 8080


2. Configurar la Resolución de Dominios en el Archivo Hosts
==========================================================

Edite el archivo ``/etc/hosts`` en su equipo Debian para asociar los dominios internos
de OpenShift Local (CRC) al loopback local:

.. code-block:: bash

   sudo nano /etc/hosts

Asegúrese de que el archivo contenga las siguientes líneas de mapeo:

.. code-block:: text

   127.0.0.1   localhost
   127.0.1.1   debian-home
   # The following lines are desirable for IPv6 capable hosts
   ::1         localhost ip6-localhost ip6-loopback
   ff02::1     ip6-allnodes
   ff02::2     ip6-allrouters
   127.0.0.1   api.crc.testing console-openshift-console.apps-crc.testing oauth-openshift.apps-crc.testing


3. Configurar el Proxy SOCKSv5 en Firefox o su Navegador
=======================================================

Para permitir que el navegador resuelva los dominios ``.testing`` a través del túnel SSH,
configure las preferencias de red de la siguiente manera:

1. Ingrese a la configuración de red o de proxy de su navegador en Debian.
2. Seleccione la opción de **Configuración manual de proxy**.
3. En el campo **SOCKS Host**, escriba ``127.0.0.1`` y en el campo **Puerto**, escriba ``8080`` (seleccione **SOCKSv5**).
4. **Muy importante:** Asegúrese de marcar la casilla **"Proxy DNS a través de SOCKS v5"** 
   *(esto permite que su laptop resuelva los dominios ``.testing`` internos).*
```eof
