# MiniAriño — escritorio Linux en una sola APK

**Dirección del producto:** una aplicación Android MiniAriño que instale e inicie un escritorio Linux sin requerir Termux, Termux:X11 ni ninguna otra aplicación auxiliar. La APK debe administrar desde su propia interfaz la preparación inicial y el inicio del escritorio. El producto objetivo no es una imagen de disco de 16 GB ni una sesión de QEMU.

> **Estado actual, sin exagerar:** existe un prototipo Android de una sola APK que integra la interfaz de MiniAriño, PRoot y el servidor gráfico Lorie. La CI instala y ejecuta PRoot con un comando invitado mínimo en emuladores Android API 26, 29, 30 y 35. Esto **no demuestra** todavía que Debian ARM64, XFCE o Lorie funcionen como escritorio en un teléfono. La ejecución real de PRoot ARM64, la instalación de XFCE, el dibujo e interacción gráfica, y la validación de uso en dispositivo siguen pendientes. No se debe presentar el escritorio completo como probado.

## Obtener la APK de prueba

La CI publica un artefacto de depuración cuando pasan las cuatro pruebas de emulador. Abre [las ejecuciones del flujo Android APK](https://github.com/46Neon/MiniOS/actions/workflows/android-apk-desktop.yml), elige una ejecución satisfactoria y descarga su artefacto `miniarino-apk-desktop-sdk28test-…`. El paquete de prueba se identifica como `org.miniarino.desktop.sdk28test` y muestra la etiqueta **MiniAriño prueba**. Los artefactos se conservan por tiempo limitado (actualmente 14 días); esta descarga es una compilación de prueba, no un lanzamiento firmado estable.

La APK está concebida para instalarse sin Termux ni Termux:X11. El instalador de Android puede rechazar un APK por razones distintas; no adivinaremos la causa sin ver el mensaje exacto. Si Android muestra «no se instaló la aplicación de Google Play» u otro error, consulta [solución de problemas de instalación](android/README.md#problemas-de-instalación) y comparte una captura completa del aviso, incluida la pantalla anterior si es posible.

## Desarrollo Android

- [Guía detallada de compilación, pruebas y límites de la APK](android/README.md)
- [Hoja de ruta y puertas de aceptación](docs/APK_DESKTOP_ROADMAP.md)
- [Procedencia de PRoot y rootfs](android/PROOT_AND_ROOTFS_PROVENANCE.md)

La APK contiene PRoot y el código/nativos de Lorie como componentes integrados. El flujo Android actual usa el submódulo fijado de Termux:X11 como fuente para compilar Lorie y aplica `android/scripts/prepare_x11.py` **durante la compilación** a ese código fuente fijado (compatibilidad Gradle e integración/identidad embebida). Ese script no modifica una app instalada, no instala Termux ni Termux:X11 en ejecución y no es una dependencia de otra APK. Reemplazar esa transformación de fuentes por un módulo/fork mantenido dentro del repositorio es una tarea de arquitectura explícita; no se elimina el paso mientras el servidor compilado aún dependa de sus cambios.

## Alcance y límites

- El objetivo es una sola APK Android con su propia interfaz, preparación y escritorio; no requiere instalar una terminal externa ni transferir al usuario a Termux:X11.
- La comprobación CI actual es un smoke test de emulador x86_64 y shell invitada sintética. No certifica el rootfs Debian ARM64 en el teléfono, la pantalla Lorie, XFCE, teclado/táctil, suspensión o reinicio.
- La aplicación usa `minSdk 26` y `targetSdk 28`. El target 28 es un compromiso de prototipo sideload para el modo actual de ejecutar PRoot desde el almacenamiento privado; no es una declaración de compatibilidad con políticas actuales de Google Play. Consulta la guía antes de instalar o actualizar.
- Todavía no hay una clave de firma estable verificada para las APKs futuras. Un APK de depuración firmado con otra clave no puede actualizar una instalación previa. No desinstales una instalación con datos que quieras conservar.
- El antiguo generador Debian/QEMU y la imagen de 16 GB se conservan como material **heredado**, pero no son el producto, no participan en CI predeterminada/de pull requests y solo se ejecutan mediante acciones manuales explícitas. No se borra el código ni los recursos históricos. Véase [`docs/LEGACY_QEMU.md`](docs/LEGACY_QEMU.md).

## Flujo y comandos seguros

Desde la raíz, `make` solo presenta ayuda. Los objetivos de imagen heredada son siempre explícitos (`make legacy-image`, `make legacy-verify`, `make legacy-run`) y no forman parte del camino Android. Consulta `make help` y la guía Android para las pruebas de APK. Las herramientas/scripts Termux preservados son trabajo histórico/experimental, no una forma de instalar el producto APK.

Las pruebas host-safe preservadas pueden ejecutarse con:

```sh
make test
```

Estas pruebas no construyen la APK ni una imagen ni demuestran un escritorio Android. Para las pruebas APK, usa los pasos reproducibles y la matriz API enumerada en [`android/README.md`](android/README.md).
