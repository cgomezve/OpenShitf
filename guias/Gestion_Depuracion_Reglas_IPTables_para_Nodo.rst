=========================================================
Gestión y Depuración de Reglas de IPTables para el Nodo
=========================================================

Este procedimiento detalla cómo consultar las reglas de traducción de red (NAT) 
activas en el servidor y cómo eliminarlas de forma precisa o total en caso de requerir 
una limpieza del entorno.


1. Consultar las Reglas Activas
==============================

Para verificar el estado actual de las reglas configuradas en la tabla NAT (tanto para 
el tráfico entrante como para el tráfico generado localmente), ejecute el siguiente comando:

.. code-block:: bash

   sudo iptables -t nat -L -n -v

*Explicación de parámetros:*
* ``-t nat``: Selecciona la tabla de traducción de direcciones de red.
* ``-L``: Lista las reglas existentes.
* ``-n``: Muestra las direcciones IP y puertos en formato numérico (omite la resolución DNS para mayor velocidad).
* ``-v``: Muestra información detallada de paquetes y bytes que han hecho coincidencia.

*Verificación:* Deberá observar listadas las reglas de reenvío asociadas a la IP ``192.168.123.40`` y el puerto ``30021``.


2. Borrar Reglas Específicas o Limpiar el Entorno
===============================================

Si necesita modificar o eliminar las reglas aplicadas, puede hacerlo mediante dos métodos:


Método A: Borrado preciso por número de línea (Recomendado)
-----------------------------------------------------------

1. Liste las reglas mostrando su número de línea correspondiente para cada cadena:

   .. code-block:: bash

      sudo iptables -t nat -L PREROUTING -n --line-numbers
      sudo iptables -t nat -L OUTPUT -n --line-numbers

2. Identifique el número de línea de la regla que desea retirar y ejecute el comando de borrado (``-D``):

   * Para eliminar una regla en la cadena ``PREROUTING`` (ejemplo, línea 1):

     .. code-block:: bash

        sudo iptables -t nat -D PREROUTING 1

   * Para eliminar una regla en la cadena ``OUTPUT`` (ejemplo, línea 1):

     .. code-block:: bash

        sudo iptables -t nat -D OUTPUT 1


Método B: Limpieza total de la tabla NAT
----------------------------------------

Si prefiere vaciar por completo todas las reglas de traducción de red de un solo golpe:

.. code-block:: bash

   sudo iptables -t nat -F

*Verificación:* Al ejecutar nuevamente ``sudo iptables -t nat -L -n -v``, la tabla aparecerá completamente limpia.
