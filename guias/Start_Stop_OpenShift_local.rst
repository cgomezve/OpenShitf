
.. code-block:: bash

    cgomeznt@srvopenshift ~]$ crc stop
    INFO Stopping the instance, this may take a few minutes... 
    Stopped the instance

.. code-block:: bash

  [cgomeznt@srvopenshift ~]$ sudo netstat -natp | grep -i listen
  tcp        0      0 127.0.0.1:631           0.0.0.0:*               LISTEN      1217/cupsd          
  tcp        0      0 0.0.0.0:111             0.0.0.0:*               LISTEN      1/systemd           
  tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      1222/sshd: /usr/sbi 
  tcp6       0      0 ::1:631                 :::*                    LISTEN      1217/cupsd          
  tcp6       0      0 :::111                  :::*                    LISTEN      1/systemd           
  tcp6       0      0 :::22                   :::*                    LISTEN      1222/sshd: /usr/sbi 

.. code-block:: bash

  [cgomeznt@srvopenshift ~]$ crc start
  WARN A new version (2.65.0) has been published on https://developers.redhat.com/content-gateway/file/pub/cgw/crc/2.65.0/crc-linux-amd64.tar.xz 
  INFO Using bundle path /home/cgomeznt/.crc/cache/crc_libvirt_4.22.14_amd64.crcbundle 
  INFO Checking if running as non-root              
  INFO Checking if running inside WSL2              
  INFO Checking if crc-admin-helper executable is cached 
  INFO Checking if running on a supported CPU architecture 
  INFO Checking if crc executable symlink exists    
  INFO Checking minimum RAM requirements            
  INFO Checking if Virtualization is enabled        
  INFO Checking if KVM is enabled                   
  INFO Checking if libvirt is installed             
  INFO Checking if user is part of libvirt group    
  INFO Checking if active user/process is currently part of the libvirt group 
  INFO Checking if libvirt daemon is running        
  INFO Checking if a supported libvirt version is installed 
  INFO Checking if crc-driver-libvirt is installed  
  INFO Checking REST API token                      
  INFO Checking crc daemon systemd socket units     
  INFO Checking if vsock is correctly configured    
  INFO Loading bundle: crc_libvirt_4.22.14_amd64... 
  INFO Starting CRC VM for openshift 4.22.14...     
  INFO CRC instance is running with IP 127.0.0.1    
  INFO CRC VM is running                            
  INFO Updating authorized keys...                  
  INFO Configuring shared directories               
  INFO Check internal and public DNS query...       
  INFO Check DNS query from host...                 
  INFO Verifying validity of the kubelet certificates... 
  INFO Starting kubelet service                     
  INFO Waiting for kube-apiserver availability... [takes around 2min] 
  INFO Overriding password for developer user       
  INFO Starting openshift instance... [waiting for the cluster to stabilize] 
  INFO 2 operators are progressing: openshift-controller-manager, operator-lifecycle-manager-packageserver 
  INFO Operator image-registry is not yet available 
  INFO All operators are available. Ensuring stability... 
  INFO Operators are stable (2/3)...                
  INFO Operators are stable (3/3)...                
  INFO Waiting until the user's pull secret is written to the instance disk... 
  INFO Adding crc-admin and crc-developer contexts to kubeconfig... 
  Started the OpenShift cluster.
  
  The server is accessible via web console at:
    https://console-openshift-console.apps-crc.testing
  
  Log in as administrator:
    Username: kubeadmin
    Password: FzHSI-CRU7Z-IygCt-jRRUg
  
  Log in as user:
    Username: developer
    Password: developer

Use the 'oc' command line interface:
  $ eval $(crc oc-env)
  $ oc login -u developer https://api.crc.testing:6443
[cgomeznt@srvopenshift ~]$ eval $(crc oc-env)
[cgomeznt@srvopenshift ~]$ 
