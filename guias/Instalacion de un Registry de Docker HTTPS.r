========================================================================
Guía de Instalación de un Registry de Docker Privado con HTTPS (TLS)
========================================================================

Este documento detalla el procedimiento para desplegar un **Docker Registry** 
privado ejecutándose como un contenedor, asegurado mediante certificados 
HTTPS (SSL/TLS autofirmados o firmados por una CA local), ideal para almacenar 
las imágenes de contenedores destinadas a los despliegues en OpenShift.


1. Generación de Certificados SSL/TLS
====================================

Para que Docker permita el acceso seguro mediante HTTPS, el registry requiere 
un certificado y una llave privada. 

1. Cree un directorio para almacenar los certificados en su servidor:

   .. code-block:: bash

      sudo mkdir -p /etc/docker/certs.d/192.168.123.121:4443

2. Genere un certificado autofirmado (reemplace la IP o dominio según corresponda):

   .. code-block:: bash

      sudo openssl req -newkey rsa:4096 -nodes -sha256 -keyout /etc/docker/certs.d/192.168.123.121:4443/domain.key -x509 -days 365 -out /etc/docker/certs.d/192.168.123.121:4443/domain.crt -subj "/CN=10.134.0.89"

*Verificación:* Compruebe que los archivos ``domain.key`` y ``domain.crt`` existan dentro de la ruta creada.


2. Despliegue del Contenedor Registry
====================================

Utilice la imagen oficial de Docker Registry para levantar el servicio 
montando el volumen de certificados y configurando un directorio de almacenamiento persistente.

1. Ejecute el contenedor mapeando el puerto ``5000`` y apuntando a los certificados:

   .. code-block:: bash

      sudo docker run -d \
        --restart=always \
        --name registry \
        -v /var/lib/registry:/var/lib/registry \
        -v /etc/docker/certs.d/192.168.123.121:4443:/certs \
        -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
        -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
        -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
        -p 5000:5000 \
        registry:2

*Verificación:* Ejecute ``sudo docker ps`` y confirme que el contenedor ``registry`` se encuentra en estado ``Up``.


3. Configuración del Cliente Docker para Confiar en el Certificado
==================================================================

Para que cualquier nodo o servidor que interactúe con el registry confíe en el certificado autofirmado:

1. Copie el certificado al directorio de confianza del sistema de certificados raíz de Docker (o del sistema operativo):

   .. code-block:: bash

      sudo cp /etc/docker/certs.d/192.168.123.121:4443/domain.crt /etc/pki/ca-trust/source/anchors/registry-domain.crt
      sudo update-ca-trust

2. Reinicie el servicio de Docker para aplicar los cambios:

   .. code-block:: bash

      sudo systemctl restart docker

*Verificación:* Pruebe la conectividad segura ejecutando una petición ``curl`` hacia el registry:

.. code-block:: bash

   curl -k https://192.168.123.121:4443/v2/_catalog

*Resultado esperado:* El servidor responderá con un JSON vacío ``{"repositories":[]}`` indicando que la capa HTTPS opera correctamente.
