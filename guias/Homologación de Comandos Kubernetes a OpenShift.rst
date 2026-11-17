==========================================
Homologación de Comandos Kubernetes a OpenShift
==========================================

:Autor: Guía de aprendizaje basada en el runbook de Credicard
:Fecha: 2026-11-17
:Propósito: Aprender OpenShift homologando los comandos de Kubernetes usados en el entorno de Credicard

.. contents::
   :depth: 3
   :local:

Introducción
============

Este documento homologa los comandos del runbook original de Kubernetes (``kubectl``) al entorno de OpenShift (``oc``). La buena noticia es que **casi todo es compatible**, ya que OpenShift internamente sigue usando Kubernetes. La diferencia principal es el uso de la CLI ``oc`` y la adopción de objetos nativos de OpenShift como ``Route``, ``DeploymentConfig`` y ``SecurityContextConstraints`` (SCC).

.. note::

   Aunque ``kubectl`` suele seguir funcionando en OpenShift, se recomienda usar ``oc`` porque incluye comandos específicos como ``oc new-app``, ``oc expose``, ``oc status`` y ``oc debug``.

1. Eliminación de Instana
=========================

En OpenShift, además de eliminar DaemonSets y Deployments, es crucial limpiar los **Routes** y **Namespaces** para no dejar basura.

Comando original (Kubernetes)
----------------------------

.. code-block:: bash

   kubectl delete daemonset -n instana-agent --all
   kubectl scale deployment -n instana-agent --replicas=0 --all
   kubectl scale deployment -n instana-autotrace-webhook --replicas=0 --all

Homologación a OpenShift
------------------------

.. code-block:: bash

   oc delete daemonset -n instana-agent --all
   oc scale deployment -n instana-agent --replicas=0 --all
   oc scale deployment -n instana-autotrace-webhook --replicas=0 --all

Recomendaciones
---------------

* Si Instana se instaló vía **Operator**, lo correcto es borrar el ``CustomResource`` (CR) y el Namespace.
* Si hay rutas expuestas, bórralas primero:

.. code-block:: bash

   oc get routes -n instana-agent
   oc delete route <nombre> -n instana-agent

* Para una eliminación completa y limpia:

.. code-block:: bash

   oc delete deployment -n instana-agent --all

2. Obtención de Métricas y Tiempos de Respuesta (Logs)
======================================================

Los comandos de ``grep`` sobre logs son perfectamente válidos en OpenShift. Solo cambia ``kubectl`` por ``oc``.

Logs de un pod específico (contenedor anterior)
-----------------------------------------------

.. code-block:: bash

   # Original
   kubectl logs scoring-backend17528-df54f7d95-pp56x --previous

   # OpenShift
   oc logs scoring-backend17528-df54f7d95-pp56x --previous

Logs de todos los pods de una aplicación
----------------------------------------

.. code-block:: bash

   # Original
   sudo kubectl logs -l app=integracion-bdv-access --tail=700 --follow --max-log-requests=9

   # OpenShift
   oc logs -l app=integracion-bdv-access --tail=700 --follow --max-log-requests=9

.. note::

   En OpenShift, el usuario ``sudo`` no suele ser necesario si tienes el rol ``cluster-admin`` o ``edit`` en el proyecto. Usa ``oc`` directamente.

Métricas de tiempo de respuesta (parseo de logs)
------------------------------------------------

.. code-block:: bash

   # Tiempo total (alarma si > 5500 ms o si es 0)
   oc logs -l app=integracion-bdv-access --tail=700 --max-log-requests=9 | grep "TIEMPO TOTAL: " | tail -n1 | awk '{print $8}' | tr -d 'ms'

   # Cambio de pin (alarma si > 2500 ms o si es 0)
   oc logs -l app=integracion-bdv-access --tail=700 --max-log-requests=9 | grep "activate] changePin=" | tail -n1 | awk -F'=' '{print $2}' | tr -d 'ms'

.. recommendation::

   En lugar de parsear logs con ``awk``, OpenShift tiene **Prometheus** integrado. Podrías crear una alerta real basada en métricas si la aplicación expone un endpoint de métricas. Sin embargo, para un chequeo rápido vía CLI, el comando es válido.

3. Escalado y HPA (Horizontal Pod Autoscaler)
==============================================

Los comandos de ``patch hpa`` son válidos. OpenShift maneja ``DeploymentConfig`` (legacy) y ``Deployment`` (moderno).

Comando original (Kubernetes)
----------------------------

.. code-block:: bash

   kubectl patch hpa integracion-bdv-access -p '{"spec":{"minReplicas":3,"maxReplicas":24}}'
   kubectl patch hpa access-iseries-service -p '{"spec":{"minReplicas":3,"maxReplicas":24}}'

Homologación a OpenShift
------------------------

.. code-block:: bash

   oc patch hpa integracion-bdv-access -p '{"spec":{"minReplicas":3,"maxReplicas":24}}'
   oc patch hpa access-iseries-service -p '{"spec":{"minReplicas":3,"maxReplicas":24}}'

Recomendaciones
---------------

* Si usas ``DeploymentConfig`` (común en OpenShift antiguos), el comando es:

.. code-block:: bash

   oc scale dc/integracion-bdv-access --replicas=3

* Para HPA, el objeto es el mismo que en Kubernetes.

4. Reinicio Controlado de Pods
==============================

El runbook original menciona que ``scale`` a 0 es una mala práctica y que ``rollout restart`` es mejor. En OpenShift, ``rollout`` es el estándar.

Comando original (Kubernetes)
-----------------------------

.. code-block:: bash

   kubectl rollout restart deployment/[deployment_name]

Homologación a OpenShift
------------------------

.. code-block:: bash

   oc rollout restart deployment/[deployment_name]

.. important::

   **Usa siempre** ``oc rollout restart``. OpenShift gestiona el ciclo de vida de los Pods de forma nativa (usa ReplicaSets), por lo que el reinicio es controlado y no tumba el servicio si tienes más de 1 réplica.

5. Verificación de Nodos, Servicios y Pods
===========================================

.. code-block:: bash

   oc get nodes                  # Verifica estado "Ready"
   oc get pods                   # Verifica estado "Running"
   oc get svc                    # Verifica "NodePort" o "ClusterIP"
   oc describe pod <nombre>      # Para troubleshooting
   oc get deployments.apps       # Verifica réplicas y disponibilidad

.. recommendation::

   En lugar de verificar manualmente ``NodePort`` en las IPs de los Masters/Workers (como en el documento original con ``https://10.133.0.248:31200``), OpenShift usa **Routes**. Deberías verificar el acceso a través de:

.. code-block:: bash

   oc get routes -n <namespace>

Y usar el hostname que te arroje (ej: ``https://ccr-pic-frontend2024-namespace.apps.cluster...``). Esto es mucho más seguro y es la forma nativa de exponer servicios en OpenShift.

6. Eventos y Logs del Sistema
=============================

.. code-block:: bash

   # Original
   kubectl get events -A --sort-by=.metadata.creationTimestamp

   # OpenShift
   oc get events -A --sort-by=.metadata.creationTimestamp

   # Filtrar errores
   oc get events -A | grep -Ei "warning|error"

.. recommendation::

   OpenShift tiene un visor de eventos y logs integrado en la consola web (**Observe -> Events/Logs**). Para CLI, el comando es correcto.

7. Recomendaciones Adicionales para OpenShift
=============================================

1. **Usa ``oc`` en lugar de ``kubectl``**
   Aunque ``kubectl`` funciona, ``oc`` tiene comandos específicos como ``oc new-app``, ``oc expose``, ``oc status`` (dashboard rápido de tu proyecto) y ``oc debug`` (para lanzar un pod de debug con el mismo entorno).

2. **Seguridad (SCC - SecurityContextConstraints)**
   En OpenShift, los contenedores no corren como ``root`` por defecto. Si tus pods de Node.js o Tomcat fallan al iniciar, revisa los ``SecurityContextConstraints`` (SCC). El runbook menciona ``sudo`` para logs; en OpenShift el usuario de cluster ``system:admin`` o roles como ``cluster-admin`` son los que dan permisos.

3. **Métricas sin parsear logs**
   El método actual (``grep`` + ``awk``) es frágil. Para producción en OpenShift, revisa la pestaña **Observe -> Metrics** en la consola web. Puedes crear alertas nativas (Alertmanager) si la aplicación expone métricas en formato Prometheus. Si no, el método de logs sigue siendo válido como "quick check".

4. **Registry**
   El runbook menciona ``gitlab-runner`` y el registry en ``10.133.0.236``. OpenShift tiene su propio **Image Registry** interno. Asegúrate de que los nodos Masters/Workers puedan resolver el DNS de ese registry externo o, mejor aún, migrar las imágenes al registry interno de OpenShift para evitar dependencias de red externas.

8. Tabla Resumen de Homologación
===============================

.. list-table:: Comparativa kubectl vs oc
   :header-rows: 1
   :widths: 40 40 20

   * - Acción
     - Kubernetes (kubectl)
     - OpenShift (oc)
   * - Ver nodos
     - ``kubectl get nodes``
     - ``oc get nodes``
   * - Ver pods
     - ``kubectl get pods``
     - ``oc get pods``
   * - Ver servicios
     - ``kubectl get services``
     - ``oc get svc``
   * - Ver deployments
     - ``kubectl get deploy``
     - ``oc get deploy``
   * - Describir pod
     - ``kubectl describe pod <nombre>``
     - ``oc describe pod <nombre>``
   * - Logs de pod
     - ``kubectl logs <pod>``
     - ``oc logs <pod>``
   * - Logs en vivo
     - ``kubectl logs -f <pod>``
     - ``oc logs -f <pod>``
   * - Reinicio controlado
     - ``kubectl rollout restart deployment/<nombre>``
     - ``oc rollout restart deployment/<nombre>``
   * - Escalar deployment
     - ``kubectl scale deployment <nombre> --replicas=N``
     - ``oc scale deployment <nombre> --replicas=N``
   * - Patch HPA
     - ``kubectl patch hpa <nombre> -p '{...}'``
     - ``oc patch hpa <nombre> -p '{...}'``
   * - Ver eventos
     - ``kubectl get events -A``
     - ``oc get events -A``
   * - Exponer servicio
     - ``kubectl expose ...``
     - ``oc expose svc/<nombre>`` (crea Route)
   * - Dashboard rápido
     - (no nativo)
     - ``oc status``

9. Notas Finales
================

* Todos los comandos de ``grep``, ``awk``, ``tail`` y ``tr`` sobre logs son **idénticos** en OpenShift.
* La principal diferencia conceptual es el uso de **Routes** en lugar de **NodePort** para exponer servicios al exterior.
* OpenShift integra **Prometheus**, **Alertmanager** y **Grafana** de forma nativa, lo que permite migrar los chequeos manuales de logs a alertas reales.
* Para el troubleshooting de LDAP (mencionado en el runbook original), los comandos ``ldapsearch`` y ``systemctl status slapd`` se ejecutan **dentro del pod** o en el nodo, no cambian en OpenShift.

.. seealso::

   * Documentación oficial de OpenShift CLI: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html
   * Guía de Routes en OpenShift: https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html
   * SecurityContextConstraints: https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html
