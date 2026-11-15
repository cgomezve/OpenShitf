Configuración de Registro Privado Inseguro en OpenShift Local (CRC)
==================================================================

Cuando OpenShift intenta descargar una imagen desde un registro privado que utiliza HTTP plano o certificados autofirmados (como ``192.168.123.150:4443``), el clúster bloquea la descarga por defecto generando el estado ``ImagePullBackOff`` en el pod.

Para habilitar el acceso hacia este registro, es necesario declararlo como registro inseguro en la configuración global del clúster.

1. Registrar el origen inseguro en el clúster
---------------------------------------------
Ejecutar el siguiente parche con un usuario administrador del clúster (``kubeadmin``):

.. code-block:: bash

   oc patch image.config.openshift.io/cluster --type=merge -p '{"spec":{"registrySources":{"insecureRegistries":["192.168.123.150:4443"]}}}'

*Verificación:* Comprobar que la dirección del registro quedó registrada en la especificación del clúster:

.. code-block:: bash

   oc get image.config.openshift.io/cluster -o jsonpath='{.spec.registrySources.insecureRegistries}'

*Resultado esperado:* Devolverá la lista incluyendo ``192.168.123.150:4443``.

2. Reiniciar el despliegue para forzar la descarga de la imagen
----------------------------------------------------------------
Una vez aplicada la política en el runtime del clúster, reiniciar el deployment para que OpenShift vuelva a intentar descargar la imagen:

.. code-block:: bash

   oc rollout restart deployment/my-app-simple-dev -n demo-app

*Verificación:* Monitorear el estado del pod hasta que alcance el estado ``Running (1/1)``:

.. code-block:: bash

   oc get pods -n demo-app -w

3. Validación de conectividad externa
-------------------------------------
Confirmar que la aplicación responde correctamente a través del puerto ``NodePort`` expuesto (``30080``):

.. code-block:: bash

   curl http://192.168.123.40:30080

*Resultado esperado:* Retornará el código HTML de bienvenida de ``my-app-simple``.
