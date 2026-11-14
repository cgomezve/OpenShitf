========================================================================
Guía de Instalación de GitLab CE y GitLab Runner en Debian
========================================================================

Este documento detalla el procedimiento completo para instalar **GitLab Community Edition (CE)** 
y el agente **GitLab Runner** en un servidor con Debian, configurando una dirección IP estática 
para garantizar la estabilidad del servicio y su integración con entornos de contenedores e infraestructura.


1. Configuración de Red Estática en Debian
==========================================

Para asegurar que el servidor mantenga una IP fija (por ejemplo, ``192.168.123.41``) 
a través de reinicios, configure el perfil de red mediante ``nmcli``:

1. Modifique la conexión para establecer el método manual, la dirección IP, la puerta de enlace y los servidores DNS en un solo bloque:

   .. code-block:: bash

      sudo nmcli connection modify "ens160" ipv4.addresses "192.168.123.41/24" ipv4.gateway "192.168.123.1" ipv4.dns "8.8.8.8,192.168.123.1" ipv4.method manual

2. Reinicie el perfil de red para aplicar los cambios de inmediato:

   .. code-block:: bash

      sudo nmcli connection up "ens160"

*Verificación:* Compruebe que la IP esté asignada correctamente ejecutando ``ip a show ens160``.


2. Instalación de GitLab Community Edition (CE)
==============================================

1. Actualice el sistema e instale los paquetes de dependencia necesarios:

   .. code-block:: bash

      sudo apt update && sudo apt upgrade -y
      sudo apt install -y curl openssh-server ca-certificates tzdata perl

2. Agregue el repositorio oficial de GitLab e instale el paquete ejecutando:

   .. code-block:: bash

      curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash
      sudo EXTERNAL_URL="http://192.168.123.41" apt install -y gitlab-ce

3. Obtenga la contraseña temporal generada automáticamente para el usuario administrador ``root``:

   .. code-block:: bash

      sudo cat /etc/gitlab/initial_root_password

*Verificación:* Acceda desde su navegador web a ``http://192.168.123.41`` e inicie sesión con el usuario ``root`` y la contraseña obtenida.


3. Instalación y Registro de GitLab Runner
==========================================

Para ejecutar pipelines de CI/CD, instale el binario del agente en el servidor:

1. Descargue e instale el servicio del Runner:

   .. code-block:: bash

      curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/v17.5.0/binaries/gitlab-runner-linux-amd64
      sudo chmod +x /usr/local/bin/gitlab-runner
      sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
      sudo gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
      sudo gitlab-runner start

2. Registre el Runner utilizando el token de su proyecto (obtenido en la sección *Settings > CI/CD > Runners* de su instancia de GitLab):

   .. code-block:: bash

      sudo gitlab-runner register --url "http://192.168.123.41/" --registration-token "TU_TOKEN_DE_REGISTRO"

*Verificación:* Confirme que el servicio se encuentra activo ejecutando ``sudo gitlab-runner status`` y verifique su estado en el panel web de GitLab.
