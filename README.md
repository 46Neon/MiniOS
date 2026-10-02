# MiniAriño — escritorio Linux para QEMU/Termux

MiniAriño cambia de estrategia: **Debian 13 amd64 + kernel Linux + XFCE**, con arranque BIOS/SeaBIOS, GRUB y disco IDE en QEMU. Ya no se ampliará el kernel bare-metal de ensamblador para simular Linux. Los fuentes anteriores se archivan bajo `legacy/baremetal/` y no participan en la nueva construcción.

## Estado honesto

Esta rama contiene el constructor reproducible, la configuración prevista de Debian/XFCE/GRUB y las pruebas estructurales y de arranque. **La imagen no se considera terminada ni verificada hasta que el workflow la construya, pase sus comprobaciones y se pruebe la interfaz en QEMU/Termux.** El entorno de esta sesión no cuenta con `debootstrap`, dispositivos loop ni QEMU para fabricar y arrancar la imagen aquí.

El repositorio MiniOS auditado no incluía la `os.img` que Lennd había probado anteriormente. Por eso el constructor conserva una imagen previa si encuentra `build/os.img`, archivándola bajo `reference/images/` antes de sustituirla, pero no puede preservar la copia local que no se entregó.

## Qué integra

- Debian 13 `trixie`, amd64, kernel Linux, GRUB para BIOS/MBR y raíz ext4 dentro de una imagen raw dispersa (16 GiB por defecto, tamaño ajustable).
- Escritorio XFCE/LightDM, Thunar, terminal Bash, Firefox ESR, Synaptic/GDebi, herramientas de desarrollo y `nmap`.
- Usuario normal `miniarino`, acceso automático al escritorio para la VM de pruebas y saludo de arranque **“MiniAriño bienvenido”**.
- GRUB con tres opciones: Iniciar MiniAriño, Reiniciar y Apagar.
- QEMU con disco IDE y tarjeta de red e1000 emulada; la pila de Linux proporciona procesos, memoria virtual, filesystem, sockets, TCP/TLS y compatibilidad ELF de Linux.

## Construcción

La construcción requiere un host Linux amd64 con acceso root, `debootstrap`, el paquete `debian-archive-keyring`, `sfdisk`, `losetup`, `mkfs.ext4`, `mount`, `chroot` y red. **Termux en Android ARM se usa para ejecutar la VM, no para construir su filesystem**: el workflow de GitHub Actions es la vía recomendada.

```sh
make clean && make
make verify
```

`make` reconstruye la imagen cada vez. `make clean` elimina solo temporales: no borra `build/os.img`. Si ya existía una imagen con ese nombre, el constructor la conserva con su hash en `reference/images/` antes de reemplazarla, pero solo después de que la nueva imagen pase su verificación. No subas imágenes privadas o de gran tamaño al historial de Git; usa artefactos/releases.

La salida predeterminada es `build/os.img` (16 GiB lógicos, archivo raw disperso). Puedes elegir otro tamaño entero, entre 1 y 2048 GiB, con `MINIARINO_IMAGE_GIB=24 make`; usa la misma variable en `make verify`. El límite superior corresponde al direccionamiento MBR de 512 bytes y no se ha probado cada tamaño. Para un build de GitHub Actions, ejecuta manualmente el workflow y elige 8, 16, 24 o 32 GiB. El tamaño del archivo comprimido depende de los datos usados; no equivale al tamaño lógico de la imagen.

## Prueba en Termux/QEMU

Una vez descargados el artefacto `.img.gz` y este repositorio en Termux, abre Termux:X11 y gira el teléfono a horizontal antes de iniciar QEMU:

```sh
chmod +x run-termux.sh
termux-x11 :0 &
export DISPLAY=:0
./run-termux.sh /ruta/al/artefacto/os.img.gz
```

El lanzador usa TCG, 2 vCPU, 2 GiB, VGA estándar, disco IDE, red user-mode con e1000 y agrega tableta absoluta/teclado USB si la build de QEMU los admite. En Termux solicita pantalla completa a la app Termux:X11 y QEMU; con GTK activa `zoom-to-fit` y muestra el cursor. Rota el teléfono a horizontal: XFCE selecciona el modo panorámico más amplio que QEMU anuncie y cae a uno compatible si no existe. Para volver a ventana usa `QEMU_FULLSCREEN=off`; QEMU también permite alternar pantalla completa con Ctrl+Alt+F. `QEMU_DISPLAY=auto` elige SDL/GTK cuando hay un display exportado y esos backends existen; si no, abre VNC en `127.0.0.1:5901`. Para elegirlo explícitamente, usa `QEMU_DISPLAY=sdl`, `QEMU_DISPLAY=gtk` o `QEMU_DISPLAY=vnc`. Puedes desactivar periféricos USB con `QEMU_USB_INPUT=off`, o ajustar `RAM` y `SMP` según el teléfono.

Al expandir `.img.gz`, el script comprueba que `dd` admita `conv=sparse` y se detiene con un aviso si no; así evita reservar todo el tamaño lógico configurado cuando la imagen tiene bloques vacíos. En ARM, x86-64 se emula por software y la interfaz —especialmente Firefox— puede ser lenta; fullscreen y mayor resolución no aceleran el CPU emulado. La disponibilidad exacta de QEMU y Termux:X11 depende de los repositorios y la versión instalados en el dispositivo; esta comprobación local no sustituye la prueba en un teléfono real.

**Cuenta de la imagen de prueba:** usuario `miniarino`, clave inicial `miniarino`; cámbiala inmediatamente con `passwd`. La imagen es para pruebas en VM, no un servidor público. Mantén la red en user-mode y no expongas servicios ni uses credenciales reales.

## Alcance de compatibilidad

MiniAriño ejecuta aplicaciones Linux amd64 empaquetadas para Debian. Puede soportar aplicaciones ELF32 Linux seleccionadas mediante multiarch y dependencias compatibles; eso se validará aparte. **No promete ejecutar aplicaciones nativas de Windows o macOS**, ni todos los binarios Linux de cualquier distribución. Para instalar software, prefiere repositorios Debian/`apt` o paquetes `.deb` de amd64 con firmas verificadas. `nmap` sirve para laboratorios y redes que tengas autorización de auditar; la red NAT de QEMU limita algunos escaneos de la LAN del teléfono.

## Verificación

- `make verify`: tamaño configurado (16 GiB por defecto), tabla MBR y geometría de partición, firma `55 AA`, una partición ext4 Linux, GRUB BIOS, kernel, initramfs, paquetes/binarios XFCE, LightDM/autologin, sesión, servicios, wallpaper y launchers dentro del rootfs.
- `make selftest`, Ctrl+Alt+M o el acceso «Diagnóstico MiniAriño»: ejecutar **dentro de XFCE** como usuario `miniarino`, nunca como root. Comprueba en vivo sesión, D-Bus/X11, procesos, EWMH, servicios, Xfconf temporal, launchers y operaciones de archivo; guarda el informe en `~/.cache/miniarino-selftest/last.log` y el código de salida en `last.exitcode`. No instala ni ejecuta las pruebas internas upstream de Xfce.
- `scripts/smoke-qemu.sh`: arranque headless por BIOS y comprobación del saludo en consola serial. No sustituye una prueba visual de XFCE/teclado/ratón.
- `make test-qemu-runner`: prueba la selección SDL/GTK/VNC y los periféricos con un QEMU simulado; no sustituye la ejecución real en Android.
- `docs/PRUEBAS_ACEPTACION.md`: pruebas manuales en Termux/QEMU y las limitaciones actuales.
- `docs/INTEGRACION_50.md`: correspondencia de los 50 hitos con componentes Linux reutilizados.

No marcar como listo un release hasta pasar el workflow y la prueba manual visual en el dispositivo Termux/QEMU.
