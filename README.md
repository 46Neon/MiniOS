# MiniAriño — escritorio Linux para QEMU/Termux

MiniAriño cambia de estrategia: **Debian 13 amd64 + kernel Linux + XFCE**, con arranque BIOS/SeaBIOS, GRUB y disco IDE en QEMU. Ya no se ampliará el kernel bare-metal de ensamblador para simular Linux. Los fuentes anteriores se archivan bajo `legacy/baremetal/` y no participan en la nueva construcción.

## Estado honesto

Esta rama contiene el constructor reproducible, la configuración prevista de Debian/XFCE/GRUB y las pruebas estructurales y de arranque. **La imagen no se considera terminada ni verificada hasta que el workflow la construya, pase sus comprobaciones y se pruebe la interfaz en QEMU/Termux.** El entorno de esta sesión no cuenta con `debootstrap`, dispositivos loop ni QEMU para fabricar y arrancar la imagen aquí.

El repositorio MiniOS auditado no incluía la `os.img` que Lennd había probado anteriormente. Por eso el constructor conserva una imagen previa si encuentra `build/os.img`, archivándola bajo `reference/images/` antes de sustituirla, pero no puede preservar la copia local que no se entregó.

## Qué integra

- Debian 13 `trixie`, amd64, kernel Linux, GRUB para BIOS/MBR y raíz ext4 dentro de una imagen raw dispersa de 16 GiB.
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

La salida es `build/os.img` (16 GiB lógicos, archivo raw disperso). El workflow comprime la imagen después de las verificaciones para descargarla como artefacto y entrega sumas SHA-256.

## Prueba en Termux/QEMU

Una vez descargados el artefacto `.img.gz` y este repositorio en Termux:

```sh
chmod +x run-termux.sh
./run-termux.sh /ruta/al/artefacto/os.img.gz
```

El script descomprime conservando bloques cero cuando `dd conv=sparse` está disponible y ejecuta QEMU con TCG, 2 vCPU, 2 GiB, VGA estándar, disco IDE y red user-mode con e1000. En ARM, x86-64 se emula por software y la interfaz —especialmente Firefox— puede ser lenta. Ajusta `RAM`, `SMP` o `QEMU_DISPLAY` según el teléfono y el backend gráfico instalado. Si SDL falla, prueba `QEMU_DISPLAY=gtk` o configura VNC manualmente. La disponibilidad exacta de QEMU y Termux:X11 depende de los repositorios y versión instalados en el dispositivo; el script comprueba que encuentre un binario QEMU x86-64.

**Cuenta de la imagen de prueba:** usuario `miniarino`, clave inicial `miniarino`; cámbiala inmediatamente con `passwd`. La imagen es para pruebas en VM, no un servidor público. Mantén la red en user-mode y no expongas servicios ni uses credenciales reales.

## Alcance de compatibilidad

MiniAriño ejecuta aplicaciones Linux amd64 empaquetadas para Debian. Puede soportar aplicaciones ELF32 Linux seleccionadas mediante multiarch y dependencias compatibles; eso se validará aparte. **No promete ejecutar aplicaciones nativas de Windows o macOS**, ni todos los binarios Linux de cualquier distribución. Para instalar software, prefiere repositorios Debian/`apt` o paquetes `.deb` de amd64 con firmas verificadas. `nmap` sirve para laboratorios y redes que tengas autorización de auditar; la red NAT de QEMU limita algunos escaneos de la LAN del teléfono.

## Verificación

- `make verify`: MBR de 16 GiB, tabla MBR, firma `55 AA`, una partición ext4 Linux, GRUB BIOS, kernel, initramfs, paquetes/binarios XFCE, LightDM/autologin, sesión, servicios, wallpaper y launchers dentro del rootfs.
- `make selftest`, Ctrl+Alt+M o el acceso «Diagnóstico MiniAriño»: ejecutar **dentro de XFCE** como usuario `miniarino`, nunca como root. Comprueba en vivo sesión, D-Bus/X11, procesos, EWMH, servicios, Xfconf temporal, launchers y operaciones de archivo; guarda el informe en `~/.cache/miniarino-selftest/last.log` y el código de salida en `last.exitcode`. No instala ni ejecuta las pruebas internas upstream de Xfce.
- `scripts/smoke-qemu.sh`: arranque headless por BIOS y comprobación del saludo en consola serial. No sustituye una prueba visual de XFCE/teclado/ratón.
- `docs/PRUEBAS_ACEPTACION.md`: pruebas manuales en Termux/QEMU y las limitaciones actuales.
- `docs/INTEGRACION_50.md`: correspondencia de los 50 hitos con componentes Linux reutilizados.

No marcar como listo un release hasta pasar el workflow y la prueba manual visual en el dispositivo Termux/QEMU.
