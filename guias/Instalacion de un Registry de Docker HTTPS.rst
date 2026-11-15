=========================================================
Manual Técnico: Despliegue de Docker Registry Seguro con TLS
=========================================================


Este manual detalla los pasos operativos para realizar una instalación limpia del motor Docker, desplegar un **Docker Registry privado** con cifrado HTTPS en un puerto personalizado (`4443`), configurar certificados autofirmados con soporte nativo de **IP SAN**, y automatizar la confianza de certificados en servidores clientes mediante herramientas de red (`openssl`).

---

1. Instalación Limpia de Docker Engine (Rocky Linux 9)
======================================================

Si el nodo destino posee instalaciones previas o paquetes obsoletos, ejecute la limpieza y el despliegue del motor oficial de Docker mediante los siguientes comandos:

.. code-block:: bash

   # 1. Remover versiones previas (si aplican)
   sudo dnf remove -y docker docker-client docker-client-latest docker-common \
                      docker-latest docker-latest-logrotate docker-logrotate docker-engine

   # 2. Configurar el repositorio oficial de Docker CE
   sudo dnf install -y dnf-plugins-core
   sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

   # 3. Instalar Docker Engine y plugins de contenedores
   sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

   # 4. Habilitar e iniciar el servicio systemd
   sudo systemctl enable --now docker

   # 5. Validar la instalación con un contenedor de prueba
   sudo docker run hello-world

---

2. Generación de Certificados TLS con Soporte IP SAN (Servidor Registry)
=====================================================================

Para evitar errores de validación por parte del demonio de Docker al utilizar direcciones IP directas (ej. ``x509: cannot validate certificate for IP because it doesn't contain any IP SANs``), es obligatorio generar el certificado incorporando bloques de nombres alternativos de sujeto (SAN).

Ejecute los siguientes pasos en el servidor de registros (ej. `192.168.123.150`):

.. code-block:: bash

   # 1. Crear entorno temporal de trabajo
   mkdir -p ~/certs-gen && cd ~/certs-gen

   # 2. Crear configuración de OpenSSL con extensiones IP y DNS SAN
   cat <<EOF > openssl.cnf
   [req]
   default_bits       = 2048
   prompt             = no
   default_md         = sha256
   distinguished_name = dn
   req_extensions     = req_ext

   [dn]
   CN = 192.168.123.150

   [req_ext]
   subjectAltName = @alt_names

   [alt_names]
   IP.1  = 192.168.123.150
   DNS.1 = srv-registry
   DNS.2 = localhost
   EOF

   # 3. Generar llave privada y certificado autofirmado (validez: 365 días)
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout domain.key \
     -out domain.crt \
     -config openssl.cnf \
     -extensions req_ext

   # 4. Crear la estructura de directorios requerida por Docker para puertos personalizados
   sudo mkdir -p /etc/docker/certs.d/192.168.123.150:4443

   # 5. Copiar los certificados oficiales a la ruta del sistema
   sudo cp domain.crt /etc/docker/certs.d/192.168.123.150:4443/domain.crt
   sudo cp domain.key /etc/docker/certs.d/192.168.123.150:4443/domain.key
   sudo cp domain.crt /etc/docker/certs.d/192.168.123.150:4443/ca.crt

---

3. Despliegue del Contenedor Registry
====================================

Despliegue el contenedor oficial de Docker Registry mapeando el puerto externo `4443` hacia el puerto interno `5000` y utilizando la opción `--mount` para asegurar compatibilidad con rutas que contienen dos puntos en el host:

.. code-block:: bash

   # Limpiar contenedores previos si existiesen
   sudo docker rm -f registry 2>/dev/null || true

   # Ejecutar el contenedor con políticas de reinicio automático
   sudo docker run -d \
     --restart=always \
     --name registry \
     -v /var/lib/registry:/var/lib/registry \
     --mount type=bind,source=/etc/docker/certs.d/192.168.123.150:4443,target=/certs \
     -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
     -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
     -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
     -p 4443:5000 \
     registry:2

   # Reiniciar demonio Docker local para aplicar cambios de confianza
   sudo systemctl restart docker

---

4. Configuración Remota de Clientes (Ej. Servidor GitLab)
==========================================================

Para que servidores satélites o de integración continua (como el nodo GitLab) confíen automáticamente en el certificado autofirmado del Registry sin necesidad de transferencias manuales por SCP, utilice OpenSSL a través de la red para extraer y cargar el certificado directamente:

.. code-block:: bash

   # Ejecutar en el servidor cliente (ej. srvgitlab)
   sudo mkdir -p /etc/docker/certs.d/192.168.123.150:4443 && \
   echo | openssl s_client -connect 192.168.123.150:4443 -servername 192.168.123.150 2>/dev/null | \
   openssl x509 > /etc/docker/certs.d/192.168.123.150:4443/ca.crt

   # Reiniciar el servicio Docker en el cliente para cargar la nueva CA
   sudo systemctl restart docker

---

5. Verificación Operativa (Push y Pull)
======================================

Valide el funcionamiento completo del flujo de imágenes ejecutando las siguientes operaciones desde el nodo cliente:

.. code-block:: bash

   # 1. Descargar imagen pública de referencia
   sudo docker pull alpine:latest

   # 2. Etiquetar la imagen apuntando al Registry privado y puerto 4443
   sudo docker tag alpine:latest 192.168.123.150:4443/alpine:latest

   # 3. Subir la imagen al repositorio privado (Push)
   sudo docker push 192.168.123.150:4443/alpine:latest

   # 4. Prueba opcional de descarga (Pull) limpiando caché local previa
   sudo docker rmi 192.168.123.150:4443/alpine:latest
   sudo docker pull 192.168.123.150:4443/alpine:latest

6. Consulta de Catálogo y Etiquetas (API v2)
============================================

Para verificar de forma remota las imágenes y etiquetas (*tags*) almacenadas en el Docker Registry mediante peticiones HTTPS hacia su API v2, ejecute los siguientes comandos:

.. code-block:: bash

   # 1. Listar todos los repositorios disponibles en el Registry
   curl --cacert /etc/docker/certs.d/192.168.123.150:4443/ca.crt \
     -X GET https://192.168.123.150:4443/v2/_catalog

   # Salida esperada:
   # {"repositories":["alpine"]}

   # 2. Listar las etiquetas (tags) de un repositorio específico (ej. alpine)
   curl --cacert /etc/docker/certs.d/192.168.123.150:4443/ca.crt \
     -X GET https://192.168.123.150:4443/v2/alpine/tags/list

   # Salida esperada:
   # {"name":"alpine","tags":["latest"]}

.. note::

   Si realiza la consulta desde una estación de trabajo donde aún no se ha instalado el certificado ``ca.crt``, puede sustituir el parámetro ``--cacert /ruta/al/ca.crt`` por la bandera ``-k`` para omitir temporalmente la validación estricta del certificado TLS.
