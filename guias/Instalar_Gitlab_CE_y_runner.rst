========================================================================
Guía de Instalación de GitLab CE y GitLab Runner en Rocky Linux
========================================================================

Este documento detalla el procedimiento completo para desplegar **GitLab Community Edition (CE)** 
y el agente **GitLab Runner** en una máquina virtual con Rocky Linux (ejecutándose sobre VMware Workstation), 
configurando una dirección IP estática para garantizar la estabilidad de los pipelines de CI/CD hacia OpenShift.


1. Configuración de Red Estática en Rocky Linux
===============================================

Para asegurar que la máquina virtual mantenga una IP fija (por ejemplo, ``192.168.123.121``) 
a través de reinicios, configure el perfil de red de la interfaz (por ejemplo, ``ens160``) mediante ``nmcli``:

1. Modifique la conexión para establecer el método manual, la dirección IP, la puerta de enlace y los servidores DNS en un solo bloque:

   .. code-block:: bash

      sudo nmcli connection modify "ens160" ipv4.addresses "192.168.123.121/24" ipv4.gateway "192.168.123.1" ipv4.dns "8.8.8.8,192.168.123.1" ipv4.method manual

2. Reinicie el perfil de red para aplicar los cambios de inmediato:

   .. code-block:: bash

      sudo nmcli connection up "ens160"

*Verificación:* Compruebe que la IP esté asignada correctamente ejecutando ``ip a show ens160``.


2. Instalación de Dependencias Previas en Rocky Linux
=====================================================

Antes de instalar GitLab, asegúrese de que el sistema tenga habilitados los repositorios necesarios 
y las herramientas básicas para el manejo de certificados y servicios de correo local (Postfix):

1. Actualice el sistema operativo:

   .. code-block:: bash

      sudo dnf upgrade -y

2. Instale los paquetes requeridos (curl, policycoreutils, postfix):

   .. code-block:: bash

      sudo dnf install -y curl policycoreutils openssh-server postfix

3. Habilite e inicie el servicio de correo Postfix:

   .. code-block:: bash

      sudo systemctl enable --now postfix

*Verificación:* Confirme que Postfix y SSH estén activos en el sistema.


3. Instalación de GitLab Community Edition (CE)
==============================================

1. Agregue el repositorio oficial de GitLab ejecutando su script de configuración para sistemas RPM (RHEL/Rocky):

   .. code-block:: bash

      curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | sudo bash

2. Instale el paquete de GitLab CE configurando su URL externa definitiva:

   .. code-block:: bash

      sudo EXTERNAL_URL="http://192.168.123.121" dnf install -y gitlab-ce

3. Obtenga la contraseña temporal generada automáticamente para el usuario administrador ``root``:

   .. code-block:: bash

      sudo cat /etc/gitlab/initial_root_password

*Verificación:* Acceda desde su navegador web a ``http://192.168.123.121`` e inicie sesión con el usuario ``root`` y la contraseña obtenida.


4. Instalación y Registro de GitLab Runner
==========================================

Para ejecutar los trabajos de CI/CD automatizados:

1. Agregue el repositorio oficial de GitLab Runner para Rocky Linux e instálelo:

   .. code-block:: bash

      curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | sudo bash
      sudo dnf install -y gitlab-runner

2. Registre el Runner utilizando el token de su proyecto (obtenido en la sección *Settings > CI/CD > Runners* de su instancia de GitLab):

   .. code-block:: bash

      sudo gitlab-runner register --url "http://192.168.123.121/" --registration-token "TU_TOKEN_DE_REGISTRO"

3. Inicie y verifique el servicio del agente:

   .. code-block:: bash

      sudo systemctl enable --now gitlab-runner

*Verificación:* Confirme que el servicio se encuentra activo ejecutando ``sudo gitlab-runner status`` y verifique su estado en el panel web de GitLab.
