=============================================================================
Listado Cronológico y Consolidado Global de Tareas, Configuraciones y
Diagnósticos
=============================================================================

1. Preparación de Entornos de Homelab y Servidores Base
=======================================================

- **Aprovisionamiento del Equipo Local (Homelab):** Configuración inicial del
  mini PC GMKtec M6 Ultra (AMD Ryzen 5 7640HS, 32 GB RAM, 1 TB SSD) ejecutando
  Rocky Linux 9.8.

- **Despliegue de OpenShift Local (CRC):** Instalación, inicialización y
  configuración de clústeres locales para pruebas de desarrollo e
  infraestructura orientadas al entorno corporativo.

- **Infraestructura de Red y Acceso:** Configuración de conectividad, reglas
  de reenvío de puertos, y direccionamiento IP para el acceso remoto y local a
  los nodos del clúster.

2. Administración de Servicios de Red, Seguridad y Enrutamiento (iptables / Linux)
=================================================================================

- **Diagnóstico de Red en Servidores:** Identificación y resolución de
  problemas de redirección de tráfico externo utilizando tablas NAT en Linux.

- **Configuración de Puertos y Bucles Locales:**

  - Habilitación del parámetro del kernel
    ``net.ipv4.conf.all.route_localnet=1`` para permitir el reenvío de tráfico
    hacia direcciones de loopback (``127.0.0.1``).

  - Aplicación y depuración de reglas en las cadenas ``PREROUTING``,
    ``OUTPUT`` y ``POSTROUTING`` (``MASQUERADE``) para mapear puertos expuestos
    (como el ``30080`` de los NodePort en OpenShift) hacia servicios locales.

3. Integración de GitLab, CI/CD y Automatización de Pipelines
=============================================================

- **Estructuración de Proyectos:** Creación y configuración de repositorios
  Git (ej. ``my-app-simple``) orientados a la gestión de aplicaciones estáticas
  y contenedores Nginx.

- **Configuración del Servidor GitLab (``srvgitlab``):**

  - Integración del usuario ``gitlab-runner`` al grupo ``docker`` y reinicio
    de servicios asociados.

  - Configuración del demonio Docker (``/etc/docker/daemon.json``) declarando
    los registros internos de OpenShift
    (``default-route-openshift-image-registry.apps-crc.testing``) dentro de los
    ``insecure-registries``.

- **Desarrollo del Archivo ``.gitlab-ci.yml``:**

  - Diseño de pipelines en múltiples etapas (``build``, ``registerDev``,
    ``deployDev``).

  - Automatización de la compilación de imágenes de contenedores mediante
    ``docker build``.

  - Autenticación segura y robusta hacia el registro de OpenShift utilizando
    tuberías estándar (``docker login --password-stdin``).

  - Generación y despliegue automatizado de manifiestos YAML (Namespace,
    ImageStream, ConfigMap, Deployment y Service tipo NodePort) ejecutados
    remotamente vía ``scp`` y ``ssh``.

4. Gestión de Identidades, Permisos y Tokens en OpenShift
=========================================================

- **Creación de Cuentas de Servicio (ServiceAccounts):** Creación de cuentas
  dedicadas (ej. ``global-gitlab-deployer``) en el namespace
  ``openshift-image-registry``.

- **Asignación de Roles RBAC:**

  - Asignación de privilegios administrativos y de gestión de imágenes
    (``cluster-admin``, ``system:image-builder``, ``system:image-puller``,
    ``admin``) mediante ``oc policy`` y ``oc adm policy``.

- **Estrategia de Autenticación Permanente:**

  - Evaluación de tokens efímeros y creación de recursos de tipo Secret
    (``kubernetes.io/service-account-token``) para generar tokens de larga
    duración / perpetuos sin fecha de caducidad.

  - Configuración y enmascaramiento de las credenciales JWT
    (``OPENSHIFT_TOKEN``) en las variables globales de GitLab CI/CD.

5. Operación, Monitoreo y Diagnóstico en OpenShift
==================================================

- **Inspección de Recursos del Clúster:**

  - Monitoreo del estado de los Pods y despliegues (``oc get pods``,
    ``oc rollout status``).

  - Consulta, filtrado y eliminación de etiquetas de imágenes obsoletas
    mediante ``oc get istag`` y ``oc delete istag``.

- **Diagnóstico Avanzado:**

  - Corrección de sintaxis en comandos de inspección detallada
    (``oc describe pod <nombre>``).

  - Utilización de herramientas del ecosistema subyacente
    (``crictl images``, ``crictl pull``, contenedores de debug con
    ``oc debug node/``) para aislar fallos de red, almacenamiento NFS,
    volúmenes persistentes (PVCs) o certificados TLS en CRI-O.

6. Documentación Técnica Normalizada
====================================

- **Generación de Manuales:** Estructuración y refinamiento de guías
  operativas completas y procedimientos definitivos utilizando sintaxis
  reStructuredText (``.rst``), optimizados para la lectura técnica y el
  mantenimiento de la infraestructura.
