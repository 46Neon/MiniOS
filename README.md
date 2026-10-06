# MiniAriño — escritorio nativo de Termux + Termux:X11

**Producto principal:** un escritorio XFCE nativo dentro de Termux, mostrado localmente por la aplicación Android Termux:X11. El camino principal no usa imagen de disco, QEMU, PRoot ni una distribución Linux. Tampoco es una APK independiente ni un servidor/backend.

> **Estado:** el escritorio XFCE nativo y Chromium ya están en `main`; el usuario confirmó que ambos funcionan en un Android ARM64 con Termux 0.118.3. La opción experimental de Blender mediante TUR se revisa por separado y aún necesita prueba en el teléfono. Orientación, suspensión/reanudación, almacenamiento y otros dispositivos siguen pendientes de aceptación completa.

## Primer uso en Android

1. Instala Termux y Termux:X11 desde fuentes oficiales compatibles entre sí. Instala/abre la app Android Termux:X11 en el mismo teléfono. No descargues APKs desde este repositorio.
2. Usa una copia local revisada de este árbol dentro de Termux. Si necesitas clonar el repositorio y no tienes `git`, la instalación de `git` es una decisión tuya; usa `pkg install git` solamente si lo confirmas. No uses `curl | bash`.
3. Inspecciona las dependencias sin cambiar paquetes:

   ```sh
   ./scripts/termux-native/install.sh --check
   ```

4. Solo si quieres instalar XFCE y el paquete acompañante de Termux:X11, solicita esa acción explícita:

   ```sh
   ./scripts/termux-native/install.sh --install
   ```

   El comando vuelve a pedir confirmación y usa `pkg` de Termux para añadir el repositorio oficial `x11-repo` y solicitar los paquetes seleccionados `termux-x11-nightly` y `xfce`. No añade TUR/repositorios de terceros, no ejecuta `pkg upgrade`, no elimina paquetes y no instala APKs. Comprueba las instrucciones oficiales vigentes para la combinación de app Android y paquetes.
4a. Chromium es opcional, grande y se instala por separado desde el repositorio oficial `x11-repo` (no instales los paquetes `*-host-tools`). Primero revisa el resumen de `pkg`; el script no ejecuta `pkg upgrade`:

   ```sh
   ./scripts/termux-native/install.sh --install-chromium
   ```

   Termux es rolling-release. Si sus bibliotecas están desactualizadas, la configuración de dependencias puede fallar; detente y revisa el diagnóstico antes de actualizar paquetes.
4b. Blender es una opción experimental separada. Solo si aceptas TUR (repositorio de terceros) y las dependencias grandes, ejecuta:

   ```sh
   ./scripts/termux-native/install.sh --install-blender
   ```

   La acción pide confirmación, se limita a AArch64 y solicita `blender5` desde `tur-on-device`; no forma parte del instalador normal ni ejecuta `pkg upgrade`. El paquete instala un lanzador XFCE versionado (`blender-5.2` en el paquete comprobado), pero GPU, consumo de memoria y estabilidad aún deben probarse en el teléfono. Si `pkg` muestra errores de bibliotecas, detente; el script no repara el sistema automáticamente.
4c. Godot 4 es otra opción opt-in desde el repositorio oficial `x11-repo`, solo para Termux AArch64 con Termux:X11 y XFCE ya instalados:

   ```sh
   ./scripts/termux-native/install.sh --install-godot
   ```

   El instalador confirma antes de llamar `pkg install x11-repo godot`; no habilita TUR. La instalación del paquete no demuestra que el editor gráfico funcione: valida `godot --version` y abre el editor dentro de XFCE en el propio teléfono. Compatibilidad con Termux:X11/llvmpipe, estabilidad, memoria y aceleración GPU no están garantizadas y siguen pendientes de prueba en dispositivo.
5. Abre la aplicación Termux:X11; en Termux ejecuta el diagnóstico de solo lectura:

   ```sh
   ./scripts/termux-native/doctor.sh
   ```

6. Opcional: para habilitar el panel MiniAriño y los accesos en XFCE, aplica el perfil móvil después de revisar el script. Es aislado, opt-in y reversible:

   ```sh
   ./scripts/termux-native/mobile-profile.sh --status
   ./scripts/termux-native/mobile-profile.sh --apply
   ```

   `--apply` solicita confirmación y conserva una copia de seguridad. No modifica `~/.config/xfce4` ni `~/Desktop`; pone sus archivos propios bajo `~/.config/miniarino-native` y `~/.local/share/miniarino-native`. El perfil experimental incluye un panel XFCE con identidad MiniAriño, menú y accesos Terminal, Archivos (Thunar) y Navegador web. Si Chromium está instalado, el lanzador lo abre dentro de XFCE; si no, entrega URL al navegador Android. El perfil añade una entrada propia de Godot al menú MiniAriño; instala Godot antes de aplicarlo para que el acceso funcione. La entrada del perfil no instala Godot. Blender conserva el acceso que aporta su paquete en el menú de XFCE. El diagnóstico solo confirma la presencia de comandos, no que las ventanas gráficas funcionen. Para revertir, primero detén XFCE, ejecuta `mobile-profile.sh --restore` y confirma; se restaura únicamente si los archivos del perfil no cambiaron desde que se aplicó. Si hubo cambios, no los pisa y conserva el respaldo para revisión.
7. Inicia y detén el escritorio administrado:

   ```sh
   ./scripts/termux-native/start.sh
   ./scripts/termux-native/stop.sh
   ```

   Predeterminado: display `:1`. Variantes opcionales: `MINIOS_X11_DISPLAY=:2 ./scripts/termux-native/start.sh` o `MINIOS_X11_DPI=120 ./scripts/termux-native/start.sh`. DPI es una experimentación, no una recomendación universal. Los targets Make `termux-native-*` son solo conveniencia; `make` a secas no instala, construye ni inicia nada.
8. El acceso «Navegador web» pide una URL. Con `DISPLAY` activo y el paquete `chromium` instalado, abre `chromium-browser` dentro de XFCE; si no, entrega la URL con `termux-open-url` al navegador Android. El fallback puede abrir fuera del escritorio. La prueba real confirmó que Chromium abre en el X11 del dispositivo; vuelve a validar tras cada actualización.
9. Para acceso opcional al almacenamiento compartido, ejecuta manualmente `termux-setup-storage` y acepta el permiso de Android. No se solicita ese permiso automáticamente.

El registro de sesión está en `$PREFIX/var/run/minios-native-xfce/session.log`. Termux:X11 debe estar instalada y abierta; `doctor.sh` comprueba el comando de Termux, no puede certificar la app Android ni el dibujo del escritorio.

## Límites y seguridad

- MiniAriño integra XFCE/Thunar/terminal nativos de Termux en el entorno de la propia app; no promete compatibilidad con todas las aplicaciones de escritorio Linux, binarios de otras distribuciones, apps Windows/macOS o dependencias arbitrarias.
- El sistema de archivos accesible es el de Termux, sujeto a permisos Android. El enlace de almacenamiento compartido requiere permiso explícito del usuario.
- El perfil móvil presenta una configuración XFCE experimental; la escala, orientación, panel, teclado en pantalla, gestos, rendimiento y comportamiento al reanudar deben ajustarse tras probar el teléfono.
- Termux:X11 es local al dispositivo. Los scripts no instalan ni configuran VNC/RDP, túneles, servicios de red ni un servidor remoto.
- Los únicos paquetes instalables por este scaffold son los nombres explícitos que pasan a `pkg`; no usa `apt`, `curl | bash`, `pkg upgrade`, desinstalaciones ni APKs.

## Validación local

Desde la raíz del árbol:

```sh
bash -n scripts/termux-native/*.sh tests/test-termux-native.sh
bash tests/test-termux-native.sh
make
```

La suite usa un `PREFIX`, `HOME`, `pkg` y `termux-open-url` falsos dentro de un directorio temporal. Comprueba rechazos fuera de Termux, cancelación/confirmación de la instalación, entrega HTTP(S) y copia/restauración del perfil. No instala paquetes ni prueba Android, XFCE ni una pantalla gráfica. GitHub Actions ejecuta estas comprobaciones host-safe sin instalar dependencias de compilación.

## Ruta Debian/QEMU preservada (heredada y manual)

Se conservan el constructor Debian, las listas de paquetes de imagen, los scripts QEMU, el workflow y los archivos bare-metal históricos para revisión/compatibilidad; ya no son el producto predeterminado. La imagen se construye únicamente de forma explícita (`make legacy-image`) o al ejecutar manualmente el workflow heredado. No se elimina código fuente ni se usa esa ruta en la instalación nativa. Consulta [`docs/LEGACY_QEMU.md`](docs/LEGACY_QEMU.md) y [`docs/TERMUX_NATIVE_MIGRATION.md`](docs/TERMUX_NATIVE_MIGRATION.md).
