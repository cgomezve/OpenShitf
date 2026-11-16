=============================================================================
Configuración de Permisos y Registro en OpenShift Local (CRC)
=============================================================================

Cuando los pipelines de GitLab CI/CD o los despliegues interactúan con registros de contenedores (ya sea el registro interno de OpenShift o un registro privado externo con certificados autofirmados), es indispensable configurar tanto los **permisos RBAC de la cuenta de servicio** como la **confianza en el registro** para evitar errores de autenticación (``unauthorized``) o bloqueos de descarga (``ImagePullBackOff``).

1. Asignación de Permisos sobre el Registry Interno de OpenShift
----------------------------------------------------------------

Para que la cuenta de servicio global utilizada por GitLab (``global-gitlab-deployer``) pueda subir (push) y descargar (pull) imágenes en el registro interno del clúster, se deben vincular los roles ``system:image-puller`` y ``system:image-builder`` en el namespace ``openshift-image-registry``:

.. code-block:: bash

   oc policy add-role-to-user system:image-puller system:serviceaccount:openshift-image-registry:global-gitlab-deployer -n openshift-image-registry
   oc policy add-role-to-user system:image-builder system:serviceaccount:openshift-image-registry:global-gitlab-deployer -n openshift-image-registry

*Verificación:* Comprobar que los enlaces de roles (*RoleBindings*) quedaron asociados a la cuenta de servicio:

.. code-block:: bash

   oc get rolebindings -n openshift-image-registry | grep global-gitlab-deployer

*Resultado esperado:* Deben listarse los bindings correspondientes a ``system:image-puller`` y ``system:image-builder``.

2. Registrar Origen Inseguro en el Clúster (Registros Externos)
---------------------------------------------------------------

*(Aplica únicamente si se consumen imágenes desde un registro privado externo por HTTP plano o con certificados autofirmados, como ``192.168.123.150:4443``).*

Para habilitar el acceso hacia un registro privado externo sin que el clúster bloquee la descarga generando el estado ``ImagePullBackOff``, ejecutar el siguiente parche con un usuario administrador (``kubeadmin``):

.. code-block:: bash

   oc patch image.config.openshift.io/cluster --type=merge -p '{"spec":{"registrySources":{"insecureRegistries":["192.168.123.150:4443"]}}}'

*Verificación:* Comprobar que la dirección del registro quedó registrada en la especificación global del clúster:

.. code-block:: bash

   oc get image.config.openshift.io/cluster -o jsonpath='{.spec.registrySources.insecureRegistries}'

*Resultado esperado:* Devolverá la lista incluyendo ``192.168.123.150:4443``.

3. Reiniciar el Despliegue para Forzar la Descarga de la Imagen
----------------------------------------------------------------

Una vez aplicadas las políticas de permisos o de runtime en el clúster, reiniciar el deployment para que OpenShift vuelva a intentar descargar la imagen:

.. code-block:: bash

   oc rollout restart deployment/my-app-simple-dev -n demo-app

*Verificación:* Monitorear el estado del pod hasta que alcance el estado ``Running (1/1)``:

.. code-block:: bash

   oc get pods -n demo-app -w

4. Validación de Conectividad Externa
-------------------------------------

Confirmar que la aplicación responde correctamente a través del puerto ``NodePort`` expuesto (``30080``):

.. code-block:: bash

   curl http://192.168.123.40:30080

*Resultado esperado:* Retornará el código HTML de bienvenida de ``my-app-simple``.
