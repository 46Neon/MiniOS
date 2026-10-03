# MiniAriño nativo en Termux: migración local y pruebas en teléfono

## Objetivo y estado

La dirección actual de producto es XFCE nativo en Termux + Termux:X11 en el mismo dispositivo Android. No se usa QEMU, PRoot ni una distribución Linux en la ruta principal. No se crea APK independiente, backend o servicio de red. Los archivos Debian/QEMU y bare-metal permanecen en el árbol como material heredado/manual; no se borran ni se construyen por defecto.

Esta propuesta local está basada en el snapshot público `46Neon/MiniOS` commit `4044fd0aa7836e4806e930cd6fac684c7fe46cb3`. El usuario verificó en un Android ARM64 con Termux 0.118.3 que XFCE nativo inicia y que Chromium puede abrir dentro de Termux:X11. Esto no sustituye completar la aceptación física: orientación, gestos, teclado, permisos, reanudación, modelo/versión Android, escalado, rendimiento sostenido y comportamiento en otros dispositivos siguen sin validarse. La integración debe revisarse en una rama/PR separada y no debe fusionarse en `main` hasta que los colaboradores la aprueben.

## Componentes nativos

- `scripts/termux-native/install.sh --check`: consulta herramientas sin usar `pkg`.
- `install.sh --install`: vuelve a pedir confirmación y usa `pkg install` para el repo oficial Termux `x11-repo` y los paquetes seleccionados `termux-x11-nightly` y `xfce`. No corre actualizaciones globales ni elimina paquetes. La instalación normal no añade TUR ni repositorios de terceros; la opción Blender va separada y con confirmación. No instala APKs y no toca preferencias del usuario.
- `doctor.sh`: comandos requeridos, almacenamiento opcional, estado, marcador de perfil y recordatorio de app X11. Informa si `blender-5.2` está instalado; es de solo lectura.
- `install.sh --install-blender`: modo experimental, solo AArch64 y opt-in; pide confirmación para añadir el repositorio externo TUR e instalar el paquete `blender5` del componente `tur-on-device`. El paquete actual comprobado instala el comando `blender-5.2`. Sus dependencias son grandes y la aceleración GPU/compatibilidad no están certificadas. No ejecuta `pkg upgrade`; si falla la vinculación de bibliotecas, no repara ni modifica paquetes adicionales.
- `start.sh` / `stop.sh`: inician/detienen una sesión administrada en `:1` por defecto. El supervisor registra sus propios PID/token y señala únicamente sus hijos con token coincidente; no ejecuta `pkill` ni barre sesiones ajenas. Si un hijo de esa sesión no responde a SIGTERM, solo se escala su señal si el token de propiedad aún coincide. Si el supervisor no se detiene, `stop.sh` no usa SIGKILL sobre él y avisa para revisar el log.
- `browser.sh URL`: permite solo URL HTTP(S). Si `DISPLAY` está activo y `$PREFIX/bin/chromium-browser` existe, inicia Chromium dentro de XFCE; fuera de X11 o sin Chromium, usa `termux-open-url` como fallback al navegador Android. Chromium se instala de forma opt-in mediante `install.sh --install-chromium`; no instala `*-host-tools` ni ejecuta `pkg upgrade`. TUR no forma parte de la instalación normal; Blender tiene un modo experimental separado y explícitamente confirmado.
- `mobile-profile.sh --apply`: solo por elección explícita; solicita confirmación y copia los archivos de perfil previos a un directorio de respaldo privado. Emite panel XFCE de altura/tamaño experimental con menú MiniAriño y launchers de Terminal, Thunar y navegador web (Chromium en X11 si está instalado; Android como fallback). El perfil usa `XDG_CONFIG_HOME`/`XDG_DATA_HOME` aislados bajo nombres MiniAriño; no copia sobre `~/.config/xfce4` ni `~/Desktop`. `--restore` pide confirmación y revierte solo si los archivos siguen idénticos a los emitidos; conflictos abortan sin sobrescribir y dejan el respaldo disponible.
- `session.log` y metadatos se guardan bajo `$PREFIX/var/run/minios-native-xfce/`.

El uso del perfil y el panel sigue siendo experimental: aunque está aislado y es reversible, solo una sesión real puede revelar compatibilidad con la versión XFCE, plugins, tamaño de pantalla, rotación, densidad, toque/scroll, teclado en pantalla y reanudación Android.

## Test local/CI

```sh
bash -n scripts/termux-native/*.sh tests/test-termux-native.sh
bash tests/test-termux-native.sh
make
```

Las pruebas usan `HOME`, `PREFIX`, `pkg` y `termux-open-url` falsos. Incluyen rechazo fuera de Termux, cancelación, confirmación de comandos de paquetes esperados, validación HTTP(S), aplicación, conflicto y restauración del perfil. No ejecutan un paquete real, no acceden a Android, no prueban el parser XFCE real y no confirman una interfaz visual.

La CI normal en `.github/workflows/native-tests.yml` revisa sintaxis, ejecuta mocks y comprueba que `make` imprime la ayuda nativa sin construir una imagen. No instala herramientas de escritorio. Los workflows de imagen Debian y bare-metal son `workflow_dispatch` manuales y están fuera de la ruta CI del producto principal.

## Prueba física requerida — Termux + Termux:X11

Haz estos pasos con el teléfono que se usará para probar. Revisa el contenido de los scripts antes de ejecutarlos. Obtén Termux y Termux:X11 desde una fuente oficial compatible; no uses APKs publicados por este árbol.

1. Abre Termux y Termux:X11. En la raíz del código ejecuta:

   ```sh
   ./scripts/termux-native/install.sh --check
   ```

   Confirma que no llama a `pkg`. Si faltan paquetes, revisa sus fuentes/versiones y después elige instalar:

   ```sh
   ./scripts/termux-native/install.sh --install
   ```

   Rechaza el prompt para probar cancelación sin cambios; solo acepta después de revisar la lista. El script usa `pkg`; no hagas `pkg upgrade` como parte de esta prueba. Si falla la resolución de paquetes o el canal oficial ya cambió, detente y registra el detalle en lugar de añadir TUR u otros repositorios.
2. Ejecuta `./scripts/termux-native/doctor.sh`. Confirma comandos requeridos y abre la app Termux:X11 en Android. El doctor no puede saber si la app Android está instalada/abierta.
3. Si deseas probar el perfil móvil experimental, aplica antes de iniciar el escritorio:

   ```sh
   ./scripts/termux-native/mobile-profile.sh --status
   ./scripts/termux-native/mobile-profile.sh --apply
   ```

   Revisa panel inferior, menú MiniAriño y botones grandes Terminal/Thunar/Navegador Android. «Navegador web» debe abrir una terminal para introducir una URL y, con Chromium instalado, iniciar el navegador dentro de XFCE; sin Chromium o sin `DISPLAY`, debe usar el fallback al navegador Android. Prueba orientación retrato y paisaje, legibilidad, iconos, tamaño táctil, menú, teclado en pantalla, entrada de texto, toque/clic/scroll, cambio de app, segundo plano/reanudación y suspensión. No des por adecuado el tamaño del panel por una prueba estática.
4. Inicia y detén:

   ```sh
   ./scripts/termux-native/start.sh
   ./scripts/termux-native/doctor.sh
   ./scripts/termux-native/stop.sh
   ```

   Abre Thunar y Terminal; revisa `$PREFIX/var/run/minios-native-xfce/session.log` si algo falla. Repite arranque/detención y prueba `:2` solo si no colisiona con otra sesión. No borres metadatos de sesión o procesos a ciegas.
5. Para probar almacenamiento compartido, ejecuta `termux-setup-storage` de forma manual y concede el permiso Android explícitamente; revisa Thunar. Denegarlo no debe impedir trabajar en `$HOME`.
6. Repite `doctor.sh`, browser handoff y start/stop después de volver de segundo plano. Revisa que no se hayan cambiado preferencias de `~/.config/xfce4` ni archivos de `~/Desktop`.
7. Para revertir el perfil (con XFCE detenido):

   ```sh
   ./scripts/termux-native/mobile-profile.sh --restore
   ./scripts/termux-native/mobile-profile.sh --status
   ```

   Si el script detecta ediciones posteriores al perfil, no las pisa. Guarda la ruta de respaldo y resuelve la diferencia manualmente antes de reintentar; no borres el respaldo hasta comprobar preferencias.
8. Reporta modelo del teléfono, versión Android, versión Termux, fuente/versión de Termux:X11, arquitectura, resultado de cada paso, incidencias/logs relevantes y capturas opcionales. Solo entonces ajustar tamaños/compatibilidad; no generalizar a todos los dispositivos Android.

## Límites y camino heredado

Termux ofrece paquetes nativos, no un Linux Desktop universal. El proyecto no promete que todas las apps Linux funcionen ni certifica aceleración de Blender. Chromium desde `x11-repo` sí se probó en un dispositivo ARM64 con Termux:X11. Blender5 desde TUR se ofrece únicamente como experimento opt-in; no se ha probado en el dispositivo del usuario ni se garantiza que arranque o aproveche la GPU. No se abre ningún puerto ni servicio remoto.

El constructor Debian/QEMU permanece disponible solo manualmente. `make` a secas no construye imagen; usa `make legacy-image`, `make legacy-verify` y `make legacy-run` si trabajas conscientemente con esa compatibilidad. Detalles y limitaciones están en [`LEGACY_QEMU.md`](LEGACY_QEMU.md). Los archivos `packages/*.txt` son dependencias de la imagen Debian heredada, no instrucciones para instalar una distro dentro del Android.
