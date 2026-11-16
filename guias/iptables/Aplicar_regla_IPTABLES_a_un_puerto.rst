Para permitir que el puerto ``30021`` (enlazado por el hipervisor al bucle local) 
responda a través de la IP física de la tarjeta de red (``192.168.123.40``), 
habilite el reenvío del kernel y las reglas de NAT:

1. Habilite el parámetro ``route_localnet`` en el kernel:

   .. code-block:: bash

      sudo sysctl -w net.ipv4.conf.all.route_localnet=1

2. Aplique las reglas de ``iptables`` para redirigir tanto el tráfico entrante de la red 
   como las peticiones locales hacia el ``127.0.0.1:30021`` del clúster:

   .. code-block:: bash

      sudo iptables -t nat -A PREROUTING -p tcp -d 192.168.123.40 --dport 30021 -j DNAT --to-destination 127.0.0.1:30021
      sudo iptables -t nat -A OUTPUT -p tcp -d 192.168.123.40 --dport 30021 -j DNAT --to-destination 127.0.0.1:30021

      sudo iptables -t nat -A POSTROUTING -p tcp -d 127.0.0.1 --dport 30080 -j MASQUERADE

3. Si quieres borrar todo

   .. code-block:: bash

      sudo iptables -t nat -F PREROUTING
      sudo iptables -t nat -F OUTPUT
