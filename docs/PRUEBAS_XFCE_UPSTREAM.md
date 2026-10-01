# Pruebas upstream de Xfce y cobertura MiniAriño

Auditoría focalizada de los 19 proyectos visibles en el grupo oficial [`xfce`](https://gitlab.xfce.org/xfce), sus manifiestos de pruebas y el template compartido `xfce4-dev-tools/ci/build_project.yml`. Consulta: 2026-10-01. No es una revisión línea por línea ni una afirmación de que todas las pruebas upstream pasen en Debian.

## Inventario observado

| Proyecto | Pruebas declaradas en el repositorio | Matiz de ejecución |
|---|---|---|
| `xfconf` | CRUD de propiedades; lectura de tipos; reset; lista de canales; señales `property-changed`; bindings de objetos; casos misceláneos. | `tests/meson.build` crea y registra los programas con `test()`. El CI usa `xvfb-run` en `meson dist` porque esta batería necesita D-Bus y una pantalla virtual. |
| `thunar` | `test-resolve-symlink`. | Registrada con `test()` en Meson; comprueba la resolución de enlaces simbólicos del gestor. |
| `exo` | `test-exo-noop` y `test-exo-string`. | En `TESTS`; el test del selector de iconos aparece en `check_PROGRAMS`, pero no en la lista `TESTS`. |
| `garcon` | `test-menu-parser`, `test-menu-spec` y `test-display-menu`. | Las dos primeras son pruebas normales; la última está en el suite `gui`, excluido por la configuración `default`. |
| `libxfce4ui` | `test-ui`. | Suite `gui`, excluido en `default`; requiere selección explícita del setup completo y entorno gráfico. |
| `libxfce4windowing` | `xfw-enum-monitors`, `xfw-enum-windows`, `xfw-enum-workspaces`, `xfw-monitor-offon`. | Suite `gui`, excluido en `default`. |
| `xfdesktop` | `test-gradient-benchmarking`, `test-icon-position-parsing`, `test-icon-position-saving`. | `tests/meson.build` crea ejecutables, pero no los registra con `test()`: se compilan, no los ejecuta el runner de Meson tal como está declarado. |
| `xfce4-dev-tools` | `test-xdt-csource`, con datos binarios y de texto para probar generación de código. | Está en `TESTS` de Automake. |
| `xfwl4` | Workspace Rust que incluye `test-clients`. | El template central define `cargo test --workspace --all-features`; es la ruta Wayland, no la sesión X11 que usa MiniAriño. |
| `xfce4-session`, `xfce4-panel`, `xfwm4`, `xfce4-settings`, `xfce4-power-manager`, `xfce4-appfinder`, `tumbler`, `thunar-volman`, `libxfce4util`, `xfce-wayland-protocols` | No encontré un directorio de pruebas en la raíz de esos repositorios en la consulta realizada. | El template compartido compila/lint-ea componentes; eso no sustituye pruebas de interacción del escritorio completo. |

Las carpetas de pruebas de `xfconf`, `thunar`, `exo`, `garcon`, `libxfce4ui`, `libxfce4windowing`, `xfdesktop`, `xfce4-dev-tools` y `xfwl4` son código upstream ligado a sus APIs internas. MiniAriño instala los paquetes binarios de Debian 13 `trixie`, no instala esos ejecutables de prueba de los repositorios fuente. Por eso la batería implementada comprueba el sistema instalado y su sesión, inspirándose en esas categorías sin copiar ni afirmar que ejecuta los tests C/Rust upstream.

## Pruebas añadidas a MiniAriño

- `scripts/verify-xfce-image.py`, invocado por `scripts/verify-image.sh` sobre el rootfs montado: paquetes Debian requeridos, binarios, usuario, LightDM/autologin/sesión, enlaces de servicios, servicio de bienvenida, wallpaper/configuración XFCE, carpetas de usuario, sintaxis freedesktop de launchers y resolución de sus comandos dentro de la imagen.
- `/usr/local/bin/miniarino-selftest`, ejecutable como usuario normal dentro de la sesión gráfica desde «Diagnóstico MiniAriño»: sesión X11, D-Bus, procesos XFCE, gestor de ventanas EWMH, servicios, lectura/escritura/reset de Xfconf en un canal temporal único, launchers, herramientas, carpetas personales y operación temporal de archivo/enlace simbólico. Limpia el canal y los archivos temporales al finalizar.
- `scripts/desktop-smoke-qemu.sh`: arranque BIOS/SeaBIOS, espera del saludo, captura del framebuffer tras el inicio de la sesión y artefactos de diagnóstico en CI. Es una comprobación visual; no simula clics ni certifica uso interactivo.

La imagen actual usa X11 con LightDM. Las pruebas GUI Wayland upstream quedan fuera del alcance de esta imagen. El diagnóstico en sesión no instala ni ejecuta las pruebas internas upstream, y la interacción manual con teclado, ratón, navegador/red, instalación de paquetes y Termux sigue requiriendo verificación manual.
