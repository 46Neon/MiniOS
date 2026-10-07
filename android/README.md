# MiniAriño Android: guía de desarrollo de la APK independiente

El objetivo del producto es una sola APK Android con interfaz MiniAriño, runtime PRoot y servidor gráfico Lorie integrado: no requiere instalar Termux, Termux:X11, QEMU, una terminal externa ni TUR, y no deriva al usuario a otra aplicación para mostrar el escritorio. En el primer inicio de escritorio, el prototipo verifica y extrae a almacenamiento privado el rootfs Debian Bookworm-slim ARM64 fijado, instala XFCE y aplicaciones desde repositorios Debian firmados, inicia Lorie con los datos XKB de Debian, lanza la sesión XFCE invitada y abre el display integrado después de superar el control de readiness.

Esto sigue siendo una **integración experimental, no un escritorio XFCE verificado en teléfono**. La CI ejecuta el launcher y un comando PRoot invitado en emuladores x86_64 con esta matriz obligatoria: Android 8/API 26, Android 10/API 29, Android 11/API 30 y Android 15/API 35. Esto acredita esos smoke tests de emulador, no cualquier dispositivo o build de fabricante. No ejecuta el PRoot ARM64 de producción en un teléfono, no instala XFCE, no prueba renderizado/entrada Lorie, no muestra el escritorio completo y no cubre el ciclo de vida en dispositivo físico. No describas el escritorio completo como funcional hasta superar las comprobaciones ARM64 físicas indicadas más abajo.

Consulta también la [hoja de ruta y puertas de aceptación](../docs/APK_DESKTOP_ROADMAP.md). La imagen Debian/QEMU de 16 GB es material heredado, no una alternativa para el producto ni un artefacto de este flujo Android.

## Compilar y probar

La compilación local requiere JDK 17, Android SDK con plataformas/build-tools indicadas por Gradle, NDK `29.0.14206865`, CMake `3.22.1`, los submódulos inicializados y red para descargar las entradas fijadas. El flujo soportado y verificado es el workflow [Android single-APK desktop](https://github.com/46Neon/MiniOS/actions/workflows/android-apk-desktop.yml); su matriz corre una emulación por API, en orden, antes de construir y subir la APK ARM64 de depuración.

Los pasos de compilación relevantes (en el orden del workflow) son:

```sh
python3 android/scripts/test_debian_xfce_contract.py
python3 android/scripts/prepare_x11.py
python3 android/scripts/fetch_proot_runtime.py android/app/src/main/assets/proot
python3 android/scripts/fetch_proot_runtime.py --arch x86_64 android/test-assets/proot-test-x86_64
```

Después de preparar la variante de prueba y arrancar **cada emulador por separado** en API 26, 29, 30 y 35:

```sh
android/vendor/termux-x11/gradlew -p android --no-daemon -PminiarinoAbiFilter=x86_64 :app:connectedDebugAndroidTest
```

Tras pasar los cuatro gates, crear el APK ARM64 de prueba:

```sh
android/vendor/termux-x11/gradlew -p android --no-daemon -PminiarinoAbiFilter=arm64-v8a :app:assembleDebug
```

La salida es `android/app/build/outputs/apk/debug/app-debug.apk`, paquete `org.miniarino.desktop.sdk28test`, etiqueta **MiniAriño prueba**, `minSdk 26`, `targetSdk 28`. El artefacto de CI tiene retención limitada (actualmente 14 días) y puede descargarse desde la pestaña Actions del workflow indicado. Para comprobar cambios reproducibles, no omitas las pruebas por API ni describas como prueba ARM64 el fixture x86_64.

`android/scripts/prepare_x11.py` es una adaptación **de fuentes durante el build** sobre el submódulo Termux:X11/Lorie fijado: compatibilidad de Gradle e integración/identidad embebida. No parchea una app instalada, no modifica el sistema del usuario y no instala ni llama a Termux/Termux:X11 durante la ejecución. El servidor Lorie y sus clases/nativos se integran en la APK. La migración a un módulo/fork mantenido dentro del repositorio está prevista; no quites la adaptación mientras el build del servidor necesite sus cambios.

## Por qué cambió la ejecución de PRoot

La APK anterior copiaba PRoot al directorio escribible privado `files/linux/usr/bin/` y después llamaba a `chmod`. Android rechaza `execve()` desde el almacenamiento privado escribible de una app con target API 29 o superior; el bit ejecutable no evita esa restricción. Termux conserva target SDK 28 para ese comportamiento heredado. MiniAriño también usa target SDK 28 y guarda/ejecuta su runtime Linux dentro del directorio privado propio, sin copiar PRoot a otra ubicación de app ni depender de otra aplicación.

Esta es una decisión de prototipo sideload: target 28 está por debajo de los requisitos actuales de envío a Google Play y puede mostrar advertencias de compatibilidad. No se debe describir el prototipo como listo o elegible para Play Store. La matriz API 26/29/30/35 instala el paquete debug aislado `.sdk28test`, resuelve y abre su actividad launcher, después ejecuta PRoot y requiere una marca exacta de comando en un root invitado sintético. Comprueba la ruta de ejecución privada para ese target SDK, pero no prueba un rootfs Debian ARM64 ni un escritorio completo.

## Contrato de compatibilidad Android y manifest

- El prototipo declara `minSdkVersion 26` (Android 8.0) y `targetSdkVersion 28`. CI prueba instalación/launcher y ejecución del comando invitado en API 26, 29, 30 y 35. API 35 conserva la ruta moderna de regresión ya establecida.
- Mantener target SDK 28 es una decisión deliberada de sideload: Android 10/API 29 y posteriores restringen `execve()` de ejecutables en almacenamiento privado escribible para apps dirigidas a API 29+, mientras MiniAriño guarda PRoot en `getFilesDir()`. Es una excepción de compatibilidad del prototipo, no una configuración de tienda.
- El manifest combinado requiere `INTERNET` y `ACCESS_NETWORK_STATE` para descargar rootfs/paquetes, e incluye `FOREGROUND_SERVICE` heredado de Lorie. La creación del canal de notificación de Lorie está protegida para API 26+ y el aviso runtime `POST_NOTIFICATIONS` para API 33+; el permiso no produce prompt en API 26/29/30. `WRITE_SECURE_SETTINGS` es una declaración upstream protegida, no un permiso que CI espere concedido.
- La app no solicita permisos amplios de almacenamiento compartido. El runtime/rootfs/workspace se guarda en almacenamiento privado de la aplicación; carpetas compartidas elegidas por el usuario usan Android Storage Access Framework. Las actividades principales y las heredadas de Lorie declaran `android:exported` explícitamente.
- Las pruebas automatizadas solo afirman instalación en emulador, creación de UI launcher y ejecución x86_64 de PRoot/comando invitado. No demuestran compatibilidad ARM64 real, permiso para configuración protegida, comportamiento del kernel/fabricante ni usabilidad de Lorie/XFCE.

## Primer inicio del escritorio (flujo previsto; requiere validar en teléfono)

1. Toca **Install XFCE desktop + start session** en MiniAriño. La app debe permanecer en MiniAriño mientras prepara rootfs e instala paquetes; no debe abrir display vacío ni informar éxito antes de tiempo.
2. La app descarga, verifica y extrae el rootfs Debian ARM64 fijado si hace falta; después ejecuta APT para instalar `xfce4`, `xfce4-terminal`, `thunar` y `dbus-x11`. Los paquetes proporcionan `/usr/share/X11/xkb`.
3. Lorie se inicia con `TMPDIR` apuntando al temporal privado compartido de MiniAriño y `XKB_CONFIG_ROOT` apuntando a los datos Debian instalados. La app espera el socket Unix privado `:0` antes de iniciar la sesión invitada. PRoot enlaza ese directorio como Debian `/tmp` y ejecuta el script de sesión XFCE empaquetado.
4. El script requiere los comandos y archivos XKB, inicia una sesión D-Bus privada, espera a `org.xfce.SessionManager` y confirma que Thunar, terminal XFCE y proceso de sesión siguen vivos. Solo después de la marca `MINIARINO_XFCE_SESSION_READY` la app abre la actividad Lorie integrada.
5. Si algo falla, la UI debe mostrar una razón concisa. Los botones **Copy diagnostics** y **Share diagnostics** adjuntan fallo y logs recientes de instalador/XFCE/X11. **Stop MiniAriño session** señala los procesos PRoot y Lorie controlados. Este flujo implementado debe verificarse todavía en el teléfono ARM64, incluidas las ventanas visibles y la entrada real.

La primera descarga del rootfs e instalación APT requieren red y bastante almacenamiento privado. La capa comprimida Debian fijada es aproximadamente 28 MB, pero la expansión y el uso instalado XFCE ocupan más y aún deben medirse en dispositivo; la imagen heredada de 16 GB no describe el formato de almacenamiento de la APK. La aplicación mantiene rootfs, paquetes, scripts y logs en almacenamiento privado. Las carpetas compartidas elegidas por el usuario usan SAF.

## Runtime y entradas fijadas

- ABI/usuarios: Android ARM64 (`arm64-v8a`) y Debian ARM64 sobre el kernel host Android.
- PRoot: paquete Termux `5.1.107.96`, metadatos/fuentes en commit [`de39661946f7e8175b5dd0755121fa28cb0aebd1`](https://github.com/termux/termux-packages/commit/de39661946f7e8175b5dd0755121fa28cb0aebd1). URLs de paquetes ARM64 fijadas, SHA-256, arquitectura y staging APK en `scripts/fetch_proot_runtime.py`. PRoot GPL-2.0; `libtalloc` GPL-3.0; `libandroid-shmem` BSD-3-Clause. Las licencias se empaquetan en `app/src/main/assets/proot-licenses/`.
- Debian: `debian:bookworm-slim` de Docker Library, manifest OCI ARM64 `sha256:a1b86db52ce3daef089e45aabe36dfec4091f82464c25c1fdcf03de197cbe82a`. La app verifica el hash del manifest y un descriptor de capa esperado. La capa comprimida de 28,137,179 bytes debe coincidir con `sha256:c75f989a229d12b2d2613a5997de9ff3546f664c22da9248720033a2410220f6` antes de extraer.
- Runtime en almacenamiento privado: el binario PRoot y sus bibliotecas host se copian a `getFilesDir()` y se ejecutan ahí bajo la compatibilidad target SDK 28. Los archivos invitados Debian también son datos privados; el smoke test usa un ELF invitado real, no solo `proot --version`.

## Qué verifica la CI que pasa

El workflow comprueba contratos de paquete/inicio XFCE en Debian Bookworm, prepara PRoot ARM64 fijado para el APK final y staging PRoot x86_64 exclusivo para instrumentación. Arranca emuladores Android x86_64 API 26, 29, 30 y 35 por turnos. En cada uno, `:app:connectedDebugAndroidTest` comprueba que el paquete de prueba siga siendo `org.miniarino.desktop.sdk28test`, target SDK 28, resuelve su launcher, abre `HomeActivity` y confirma que se infló la UI; copia PRoot x86_64 y dependencias fijadas a almacenamiento privado escribible, ejecuta PRoot ahí y requiere que `/system/bin/sh` a través del root invitado sintético emita exactamente `MINIARINO_PROOT_GUEST_OK`. Solo después de superar los cuatro gates construye y sube una APK ARM64 de depuración, verificando package ID, min SDK 26, target SDK 28, permisos, bibliotecas ARM64, activos/licencias PRoot y SHA-256.

Son comprobaciones reales de instalación de paquete Android, launcher y ruta `execve`/PRoot/comando invitado en emulador, no solo revisión del manifest. El PRoot de prueba es x86_64 y el invitado sintético usa `/system/bin/sh` del emulador; **no** ejecuta el PRoot de producción ARM64 ni un Debian ARM64. Tampoco instala paquetes XFCE, arranca Lorie, comprueba socket o entrada de teclado, abre el escritorio ni prueba SELinux/kernel físico/ciclo de vida. Esas son puertas pendientes en el teléfono objetivo ARM64: instalar APK sideload, confirmar PRoot ARM64 y ejecución del guest Debian, completar APT, confirmar gestor de sesión/terminal/gestor de archivos visibles, verificar entrada y cambio de app, detener/reiniciar y repetir después de pausa o recuperación de proceso. Godot, Chromium y Blender no pertenecen a esta fase.

## Problemas de instalacion

Se ha reportado un aviso de Android con el texto «no se instaló la aplicación de Google Play» para una compilación `.sdk28test`. Ese texto por sí solo no identifica la causa; no se debe atribuir sin evidencia a firma, conflicto de paquete, Play Protect u otro motivo. Para diagnosticar, solicitar una captura completa del aviso de instalación (y, si se llega desde otra pantalla, de esa pantalla anterior), modelo de teléfono, versión de Android, nombre/SHA-256 del APK e indicar si la app ya estaba instalada. No desinstalar primero: eso puede borrar rootfs Debian, paquetes, workspace y logs privados.

Un APK de depuración firmado con una clave distinta no puede sustituir una instalación existente; Android puede informar incompatibilidad de firma. Además, la identidad `.sdk28test` evita colisión de nombre con otra aplicación, pero no permite actualizar un build firmado con certificado diferente. Las claves de firma han cambiado entre ejecuciones CI y la firma estable futura sigue sin resolverse. Conserva/exporta los datos antes de considerar desinstalar/reinstalar; la APK de prototipo no promete una clave estable.
