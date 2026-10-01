# Pruebas de aceptación MiniAriño

Este plan distingue controles automatizados de validación visual e interacción manual. Un artefacto no se considera terminado hasta que se construye desde cero, sus comprobaciones y las capturas de escritorio en QEMU pasan para el mismo commit; la interacción real en Termux sigue siendo una prueba separada. No se afirma que la interacción en el teléfono haya ocurrido solo porque compile o arranque el sistema.

## Automatizadas — Linux amd64 / GitHub Actions

Ejecutar desde la raíz:

```sh
make clean && make
make verify
scripts/smoke-qemu.sh
scripts/desktop-smoke-qemu.sh
```

La imagen de CI debe superar, en ese orden:

1. Construcción reproducible con Debian 13 `trixie` amd64, filesystem raíz ext4 y GRUB BIOS en MBR.
2. Verificación de tamaño raw lógico de 16 GiB, firma MBR `55 AA`, una partición Linux que empieza en LBA 2048, estructura del filesystem, módulos GRUB BIOS, kernel, initramfs, paquetes/binarios XFCE, LightDM/autologin/sesión, enlaces de servicios, wallpaper/configuración, directorios personales, launchers y comandos instalados, configuración del saludo y exactamente tres entradas de menú.
3. Inicio en QEMU `pc`/SeaBIOS con el disco como IDE, aceleración TCG y VGA estándar; la consola serial debe recibir `MiniAriño bienvenido` dentro del límite de tiempo.
4. Inicio de un segundo QEMU con VGA/VNC y captura de XFCE. El runner añade temporalmente a la imagen un XDG autostart que ejecuta el diagnóstico en una terminal dentro de la sesión gráfica del usuario normal; después apaga limpiamente, extrae el log y exige `0 FAIL`. La entrada temporal se quita antes de publicar la imagen. Esto no valida el atajo Ctrl+Alt+M ni la interacción de teclado/ratón.
5. Solo después de los anteriores, compresión `.img.gz`, generación de SHA-256 y subida del artefacto de imagen. Cualquier fallo impide publicar ese artefacto.

Los logs del autodiagnóstico, las capturas de antes y durante la prueba, la consola serial y el SHA del commit probado deben guardarse junto al resultado de CI. Esto verifica X11, D-Bus, procesos XFCE, EWMH, Xfconf y comandos desde la sesión gráfica; todavía no prueba ratón, navegación real, instalación de paquetes ni uso en Termux.

## Manual — escritorio QEMU

En un QEMU gráfico de x86-64, adjuntar la imagen raw como IDE y arrancar en BIOS/SeaBIOS:

- [ ] Aparece el menú GRUB con «Iniciar MiniAriño», «Reiniciar» y «Apagar»; seleccionar la primera opción e indicar Enter inicia Linux.
- [ ] Aparece «MiniAriño bienvenido» durante el arranque.
- [ ] Se inicia LightDM/XFCE sin pedir una cuenta, a 640×480 si el adaptador anuncia ese modo; si no, el escritorio permanece utilizable con el modo anunciado por QEMU.
- [ ] Se ve el fondo y los accesos directos de Archivos, Terminal, Navegador web, Instalar programas y Diagnóstico MiniAriño.
- [ ] Ejecutar «Diagnóstico MiniAriño» en la sesión como usuario normal; el atajo Ctrl+Alt+M también está configurado, pero no se da por validado automáticamente. Revisar el resumen PASS/FAIL/WARN y el log `~/.cache/miniarino-selftest/last.log`. El canal/archivos de prueba temporales deben limpiarse. Esta prueba de sistema se inspira en categorías upstream, pero no ejecuta los binarios internos de Xfce.
- [ ] Teclado y ratón funcionan; abrir Thunar y navegar por las carpetas personales.
- [ ] Abrir XFCE Terminal y ejecutar comandos locales; abrir Firefox ESR y cargar un sitio usando la red emulada.
- [ ] Abrir Synaptic/GDebi y confirmar que el gestor puede consultar repositorios e instalar un paquete Debian de prueba.
- [ ] Conectar a la red user-mode y verificar `git --version` y `nmap --version`; usar `nmap` solo en destinos autorizados.
- [ ] Reiniciar y apagar desde el menú GRUB.

## Manual — dispositivo Android / Termux

1. Instalar una build de QEMU de Termux con soporte `qemu-system-x86_64` y reservar almacenamiento para la imagen raw lógica de 16 GiB.
2. Descargar el artefacto `.img.gz` y el SHA-256 del mismo run de Actions; verificarlo antes de expandirlo.
3. Para Termux:X11, iniciar `termux-x11 :0` y exportar `DISPLAY=:0`; luego ejecutar `./run-termux.sh /ruta/al/os.img.gz`. `QEMU_DISPLAY=auto` prefiere SDL/GTK si hay display y hace fallback a VNC local en `127.0.0.1:5901`. El script exige soporte de `dd conv=sparse` para evitar una expansión completa inesperada.
4. Completar en el teléfono la lista visual de GRUB, saludo, XFCE, teclado/ratón, red y aplicaciones. Registrar si la tableta USB fue reconocida o si se usó la entrada PS/2.
5. Guardar modelo y arquitectura del dispositivo, versiones de Android/Termux/QEMU/backend gráfico, RAM asignada, SHA del artefacto y evidencia de pantalla/logs.

La emulación amd64 por TCG en un teléfono ARM puede ser lenta, y ciertos binarios QEMU/paquetes de Termux pueden no soportar la combinación requerida. No se promete rendimiento nativo ni se debe marcar esta prueba como pasada sin ejecución real en un dispositivo.

## Límites conocidos y estado

- La cobertura de tests upstream está inventariada en `docs/PRUEBAS_XFCE_UPSTREAM.md`. La imagen instala paquetes binarios Debian, por lo que los tests C/Rust asociados a builds de código fuente de Xfce no están incluidos ni se consideran ejecutados. Los tests interactivos del diagnóstico tampoco sustituyen la prueba manual de teclado/ratón, navegación/red, instalación de paquetes ni uso en Termux.

- En este cambio aún no se incorpora ni verifica la `os.img` que el usuario dice haber probado anteriormente; esa copia no estaba en el repositorio ni en los archivos recibidos. Si existe localmente como `build/os.img`, el constructor la conserva con su SHA bajo `reference/images/` al reemplazarla tras validar la nueva.
- No se certifica el uso de hardware físico ni aceleración KVM. La meta inmediata es QEMU/SeaBIOS con IDE y TCG.
- Aplicaciones Linux amd64 para Debian son el objetivo. No se promete compatibilidad Windows/macOS ni todos los binarios de cualquier distribución Linux.
- Un build exitoso, una verificación estática y el smoke headless no certifican todos los periféricos, actualizaciones, suspensión, codecs, impresión ni la usabilidad del navegador en ARM.
- La cuenta inicial de pruebas es `miniarino` con contraseña `miniarino` y autologin de LightDM. Es una credencial pública de laboratorio: cámbiala inmediatamente; no reutilices contraseñas ni expongas servicios. No uses esta imagen tal cual como sistema multiusuario o servidor público.
