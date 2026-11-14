Fragmento de código


========================================================================
Despliegue de Nginx en OpenShift Local (CRC) y Exposición por NodePort 30021
========================================================================

Este documento detalla el procedimiento completo y validado para desplegar Nginx 
de forma segura (non-root) en OpenShift Local (CRC) sobre RHEL 9.9, exponerlo mediante 
un servicio ``NodePort`` en el puerto estático ``30021``, y configurar el enrutamiento 
del kernel para permitir el acceso desde la IP física de la red (ej. ``192.168.123.40``).

Prerrequisitos
=============

* Entorno RHEL 9.9 con OpenShift Local (CRC) instalado y en ejecución.
* Acceso a la terminal con privilegios de administrador (``sudo``) y herramientas de OpenShift (``oc``).
* IP física de la interfaz de red del host (en este laboratorio: ``192.168.123.40``).


Paso 1: Crear el proyecto limpio
===============================

Cree y seleccione un nuevo namespace para aislar completamente la aplicación de prueba:

.. code-block:: bash

   oc delete project demo-app --ignore-not-found=true
   oc new-project demo-app

*Verificación:* El sistema confirmará que se encuentra posicionado en el proyecto ``demo-app``.


Paso 2: Configurar Nginx para ejecución Non-Root
================================================

Cree un ``ConfigMap`` que reconfigure Nginx para escuchar en el puerto no privilegiado ``8080``:

.. code-block:: bash

   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nginx-config
     namespace: demo-app
   data:
     default.conf: |
       server {
           listen 8080;
           server_name localhost;
           location / {
               root /usr/share/nginx/html;
               index index.html index.htm;
           }
       }
   EOF

*Verificación:* Deberá retornar ``configmap/nginx-config created``.


Paso 3: Desplegar el Pod de Nginx
================================

Aplique el manifiesto del Deployment incluyendo los volúmenes temporales (``emptyDir``) 
para cumplir con las políticas de seguridad estrictas de OpenShift:

.. code-block:: bash

   cat <<EOF | oc apply -f -
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: mi-web-demo
     namespace: demo-app
     labels:
       app: mi-web-demo
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: mi-web-demo
     template:
       metadata:
         labels:
           app: mi-web-demo
       spec:
         containers:
         - name: nginx
           image: docker.io/library/nginx:alpine
           ports:
           - containerPort: 8080
           securityContext:
             allowPrivilegeEscalation: false
             runAsNonRoot: true
           volumeMounts:
           - name: nginx-conf
             mountPath: /etc/nginx/conf.d
           - name: nginx-cache
             mountPath: /var/cache/nginx
           - name: nginx-run
             mountPath: /var/run
         volumes:
         - name: nginx-conf
           configMap:
             name: nginx-config
         - name: nginx-cache
           emptyDir: {}
         - name: nginx-run
           emptyDir: {}
   EOF

*Verificación:* Deberá retornar ``deployment.apps/mi-web-demo created``.


Paso 4: Exponer el servicio mediante NodePort estático
=====================================================

Cree el servicio de tipo ``NodePort`` asignando explícitamente el puerto ``30021``:

.. code-block:: bash

   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: Service
   metadata:
     name: mi-web-demo
     namespace: demo-app
   spec:
     type: NodePort
     selector:
       app: mi-web-demo
     ports:
     - port: 8080
       targetPort: 8080
       nodePort: 30021
       protocol: TCP
   EOF

*Verificación:* Deberá retornar ``service/mi-web-demo created``. 
Compruebe que el pod se encuentra en estado ``Running (1/1)`` ejecutando:

.. code-block:: bash

   oc get pods -n demo-app


Paso 5: Configurar el enrutamiento de red en el Host RHEL
========================================================

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

3. Verifica, esto es Importante

   .. code-block:: bash

   sudo iptables -t nat -L -n -v
   Chain PREROUTING (policy ACCEPT 11 packets, 1002 bytes)
    pkts bytes target     prot opt in     out     source               destination         
       0     0 DNAT       tcp  --  *      *       0.0.0.0/0            192.168.123.40       tcp dpt:30021 to:127.0.0.1:30021

   Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts bytes target     prot opt in     out     source               destination         

   Chain OUTPUT (policy ACCEPT 122 packets, 10745 bytes)
    pkts bytes target     prot opt in     out     source               destination         
       1    60 DNAT       tcp  --  *      *       0.0.0.0/0            192.168.123.40       tcp dpt:30021 to:127.0.0.1:30021

   Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
    pkts bytes target     prot opt in     out     source               destination   

Paso 6: Validación Final
========================

Desde cualquier equipo de la red (incluyendo su laptop Debian o el propio servidor RHEL), 
ejecute la prueba de conexión:

.. code-block:: bash

   curl http://192.168.123.40:30021

*Resultado esperado:* El comando devolverá de inmediato el documento HTML con el mensaje 
``Welcome to nginx!``.
