========================================================================
Escalado de Réplicas en OpenShift manteniendo el NodePort Externo
========================================================================

Este procedimiento detalla cómo escalar horizontalmente una aplicación (Deployment) 
a múltiples réplicas en OpenShift Local (CRC), manteniendo intacta la exposición 
externa a través del puerto ``30021`` y las reglas de ``iptables`` previamente configuradas.


1. Escalar el Deployment
=========================

Para aumentar el número de contenedores en ejecución de su aplicación de prueba a dos réplicas, ejecute:

.. code-block:: bash

   oc scale deployment mi-web-demo --replicas=2

*Verificación:* Compruebe mediante ``oc get pods`` que ahora se muestran múltiples 
instancias del pod en estado ``Running (1/1)``.


2. Validar los Endpoints del Servicio
=====================================

OpenShift actualiza automáticamente el balanceo de carga interno sin alterar el puerto ``NodePort``. 
Verifique que los puntos finales (*endpoints*) apunten a los nuevos pods:

.. code-block:: bash

   oc get endpoints mi-web-demo

*Verificación:* El listado mostrará las IPs internas de todos los pods activos escuchando en el puerto ``8080``.

.. code-block:: bash
                                  
    oc get all
    Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable no sooner than v6.0+
    NAME                               READY   STATUS    RESTARTS   AGE
    pod/mi-web-demo-74d8df798c-r8hd8   1/1     Running   0          12m
    pod/mi-web-demo-74d8df798c-zqqx4   1/1     Running   0          3m49s
    
    NAME                  TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)          AGE
    service/mi-web-demo   NodePort   10.217.5.95   <none>        8080:30021/TCP   26m
    
    NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
    deployment.apps/mi-web-demo   2/2     2            2           30m
    
    NAME                                     DESIRED   CURRENT   READY   AGE
    replicaset.apps/mi-web-demo-74d8df798c   2         2         2       30m
    [cgomeznt@srvopenshift ~]$ oc describe pod/mi-web-demo-74d8df798c-zqqx4 | grep "IP:"
    IP:               10.217.0.46
      IP:           10.217.0.46

.. code-block:: bash
                                  
    oc describe pod/mi-web-demo-74d8df798c-r8hd8 | grep "IP:"
    IP:               10.217.0.33
      IP:           10.217.0.33
    
.. code-block:: bash
                                  
    oc get endpoints mi-web-demo
    Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
    NAME          ENDPOINTS                           AGE
    mi-web-demo   10.217.0.33:8080,10.217.0.46:8080   26m



3. Validación del Acceso Externo
================================

Pruebe la conectividad desde la red utilizando la misma IP física y puerto estático:

.. code-block:: bash

   curl http://192.168.123.40:30021

*Resultado esperado:* El servicio responderá con éxito, distribuyendo las peticiones 
de forma transparente entre las réplicas activas del clúster.
