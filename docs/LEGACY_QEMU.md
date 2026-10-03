# Compatibilidad heredada: imagen Debian/QEMU

Esta documentación aplica solo a la ruta anterior de MiniOS. **No es la instalación ni el producto principal de MiniAriño**, y no interviene en Termux nativo/XFCE. Se conservan fuentes, listas de paquetes, scripts de imagen y CI manual para revisión/compatibilidad; no se eliminan.

## Alcance

El constructor genera una imagen raw Debian 13 `trixie` amd64 con GRUB BIOS/MBR, raíz ext4, XFCE/LightDM y herramientas Debian. Se ejecuta en QEMU, no como filesystem nativo Android. En Android ARM, x86-64 corre por emulación; el rendimiento gráfico/CPU es limitado. No se promete compatibilidad general con todos los programas Linux ni con aplicaciones Windows/macOS.

`packages/base.txt`, `desktop.txt`, `development.txt` y `network.txt` son listas del rootfs Debian antiguo; **no son paquetes que se instalen dentro del camino nativo Termux**.

## Comandos explícitos

El `make` sin argumentos no crea imágenes. Solo para trabajar deliberadamente en la compatibilidad heredada:

```sh
make legacy-image
make legacy-verify
make legacy-run
make legacy-debug
make test-qemu-runner
```

También se conservan alias viejos `make image`, `verify`, `run` y `debug`; son comandos de la ruta heredada, no defaults. El workflow `.github/workflows/build-image.yml` se ejecuta únicamente con `workflow_dispatch` manual y descarga dependencias de build en Ubuntu. No se ejecuta en PR/CI nativa. El workflow bare-metal está igualmente limitado a ejecución manual.

La compilación requiere un host Linux amd64 con privilegios para construir filesystem, montar/chroot, GRUB, `debootstrap`, `sfdisk`, `losetup`, `mkfs.ext4` y red. No usar esos pasos como solución a la instalación nativa Termux.

La salida por defecto histórica es `build/os.img` (16 GiB lógicos; `MINIARINO_IMAGE_GIB` permite el tamaño del workflow). El constructor archiva una imagen previa encontrada antes de reemplazarla y el script `clean` conserva `build/os.img`. No subir imágenes privadas/grandes a Git. La salida del constructor no se considera verificada solo por estar presente.

## Pruebas y seguridad

- `make legacy-verify`: comprueba geometría de imagen, MBR/ext4, GRUB, kernel/initramfs y los componentes Debian esperados.
- `scripts/smoke-qemu.sh`: prueba de arranque BIOS headless/serial.
- `scripts/desktop-smoke-qemu.sh`: captura la GUI de esa imagen dentro de QEMU automatizado; no prueba Termux/XFCE nativo ni la interacción de Android.
- `make test-qemu-runner`: prueba mocks de selección de pantalla/input; no reemplaza ejecución real.
- `docs/PRUEBAS_ACEPTACION.md`: plan manual del camino antiguo.

Una build o screenshot QEMU no certifica el teléfono Android. No expongas esta VM a redes públicas ni uses su credencial de prueba para información real; si generas una imagen de laboratorio, cambia credenciales antes de usarla. VNC/RDP/servicios no forman parte de la nueva ruta nativa.
