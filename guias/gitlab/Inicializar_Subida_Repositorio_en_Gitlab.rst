=====================================================================
Inicialización y Subida de Repositorios a GitLab
=====================================================================


Este procedimiento documenta los pasos necesarios para inicializar un proyecto local existente como un repositorio de Git, vincularlo a un proyecto creado en el servidor interno de GitLab (``192.168.123.121``), resolver conflictos de historiales iniciales divergentes y realizar la subida definitiva del código fuente.

---

1. Preparación e Inicialización del Repositorio Local
====================================================

Acceda al directorio raíz del proyecto local que desea importar y configure la identidad global de Git junto con la rama principal estándar (``main``):

.. code-block:: bash

   # 1. Acceder al directorio del proyecto
   cd /root/gitlab/my-app-demo

   # 2. Configurar identidad global de Git (si aún no está definida)
   git config --global user.email "cgomeznt@gmail.com"
   git config --global user.name "Carlos Gomez"

   # 3. Inicializar el repositorio y establecer 'main' como rama principal
   git init
   git branch -M main

---

2. Registro de Archivos y Commit Inicial
========================================

Agregue la totalidad de los archivos del directorio de trabajo al área de preparación (*staging*) y genere el primer punto de control (*commit*):

.. code-block:: bash

   # 1. Agregar todos los archivos del proyecto
   git add .

   # 2. Confirmar los cambios localmente
   git commit -m "Commit inicial: importando proyecto desde trabajo"

---

3. Vinculación Remota y Resolución de Historiales Divergentes
=============================================================

Asocie el repositorio local con la URL HTTP del proyecto en GitLab. Si el proyecto en la interfaz web fue inicializado con archivos previos (como ``README.md``), deberá fusionar ambos historiales independientes antes de subir sus cambios:

.. code-block:: bash

   # 1. Vincular el repositorio remoto
   git remote add origin http://192.168.123.121/soporte-web/my-app-demo.git

   # 2. Definir la estrategia de fusión por defecto (merge)
   git config pull.rebase false

   # 3. Descargar y fusionar el historial remoto permitiendo historias inconexas
   git pull origin main --allow-unrelated-histories

.. note::

   Durante la ejecución del comando ``git pull``, es posible que se abra el editor de texto predeterminado (``nano``) solicitando confirmar el mensaje de fusión (*Merge*). Para guardar y continuar, presione ``Ctrl + O``, luego ``Enter``, y finalmente ``Ctrl + X`` para salir.

---

4. Subida Definitiva al Servidor (Push)
=======================================

Una vez conciliadas las ramas, envíe el código integrado al repositorio remoto en GitLab y establezca el seguimiento (*upstream*) de la rama ``main``:

.. code-block:: bash

   # Subir los cambios a GitLab (solicitará usuario y contraseña)
   git push -u origin main
