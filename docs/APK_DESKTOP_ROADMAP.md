# Hoja de ruta: escritorio MiniAriño en una sola APK

> **Decisión/propuesta de arquitectura, todavía no implementada ni validada.** El objetivo recomendado es una APK con PRoot ARM64, compositor Wayland de host en Android/NDK y un escritorio XFCE 4.20+ sobre Wayland mediante labwc. Esta hoja no afirma que Wayland, labwc o XFCE estén funcionando en MiniAriño. Véase también [`ARCHITECTURE.md`](../ARCHITECTURE.md).

## Decisión de producto y arquitectura objetivo

La entrega objetivo es **una sola APK** que configura e inicia el escritorio desde su propia interfaz. No debe depender en tiempo de ejecución de Termux, Termux:X11, VNC ni otra aplicación externa, y no debe exigir developer options. El usuario no debe tener que ejecutar comandos en una terminal externa. La imagen histórica Debian/QEMU de hasta 16 GB no es el producto: conservar su código/recursos solo como legado o compatibilidad, sin afirmar que ya se retiró o que la ruta actual fue reemplazada.

Arquitectura recomendada para evaluar:

- **Almacenamiento:** userland ARM64 PRoot, provisionado incrementalmente en almacenamiento privado de la APK, no una imagen fija de 16 GB. Mantener base verificada separada del estado mutable de paquetes, configuración, cachés y archivos de usuario.
- **Candidato inicial de rootfs:** Debian Trixie ARM64 es el candidato preferido a evaluar primero porque el índice oficial de paquetes de Trixie lista `xfce4-session` `4.20.2-2`. Esto solo confirma que existe un paquete candidato; no demuestra una sesión Wayland operativa. Arch ARM64 queda como comparación, no como predeterminado.
- **Gráficos:** un compositor Wayland alojado por la app Android/NDK renderiza en la superficie nativa de Android y ofrece un socket Wayland a clientes invitados. **labwc es el componente compositor/sesión anidado del lado invitado**; no es el compositor Wayland Android-host ni debe usarse por sí solo como primera prueba Android. Tras el PoC del host, evaluar labwc; después evaluar XFCE 4.20 o posterior sobre Wayland en labwc. La compatibilidad Wayland de XFCE 4.20 es experimental y requiere validación real.
- **X11 heredado:** Xwayland es opcional y posterior, únicamente si hacen falta aplicaciones X11. No es parte obligatoria del camino Wayland inicial.
- **Código legado:** la arquitectura final no debe tener un parche/transformación de Lorie durante la compilación. El prototipo actual sí usa Lorie/X11 y su integración existente se mantiene como prototipo hasta que haya una alternativa implementada, probada y sustituible de manera segura; esta decisión no afirma que se haya retirado Lorie.

## PoC gráfico obligatorio: host Wayland real primero

El primer PoC debe construir y ejecutar dentro de la aplicación Android un **compositor Wayland de host**, integrado mediante Android/NDK y renderizado en la superficie nativa de Android. Debe exponer su socket a un cliente Wayland mínimo que corre dentro del PRoot ARM64 invitado y demostrar, de extremo a extremo:

1. conexión del cliente invitado al socket del compositor host, verificando ruta, acceso/permisos y el mecanismo de exposición a través de PRoot;
2. renderizado en Android de una ventana de prueba de color sólido creada por el cliente invitado; y
3. envío de entrada táctil y de teclado desde Android, a través del compositor, al cliente invitado, con confirmación observable de recepción.

Comprobar también inicio, cierre, pérdida de superficie, errores y limpieza de procesos/socket. **Solo después** de pasar esta puerta se añade labwc como compositor/sesión anidado del invitado, y después XFCE.

Esto es sustancialmente más que dibujar una superficie o maqueta con `Canvas`: requiere un servidor Wayland y protocolo cliente-servidor reales, buffers/superficies y composición, traducción de eventos de entrada, socket accesible entre Android y PRoot, sincronización, ciclo de vida y diagnósticos. Una vista Canvas de color o un renderizado de prueba que no involucre al cliente invitado no pasa la puerta.

## Estado verificado y límites actuales

- El prototipo actual empaqueta interfaz Android, PRoot y código/nativos del servidor gráfico **Lorie/X11**. El APK declara `targetSdk 28`.
- Existe `android/scripts/prepare_x11.py`, que transforma durante compilación fuentes relacionadas con Lorie procedentes del submódulo Termux:X11 fijado. No es una modificación de una app Termux:X11 instalada ni una dependencia de runtime de Termux/Termux:X11; sin embargo, sí es parte de la ruta de build actual. La arquitectura final propuesta no debe depender de este parche de compilación.
- La rama todavía no ha validado XFCE en un dispositivo físico. No hay validación física de escritorio XFCE.
- La evidencia de CI existente es solo un **smoke PRoot en emulador x86_64**: instalación/arranque de la aplicación y comando en un root invitado sintético. No prueba PRoot ARM64, rootfs Debian ARM64 real, paquetes APT de XFCE, compositor integrado, renderizado Wayland/X11, entrada táctil/teclado ni una sesión de escritorio utilizable.
- El diseño Wayland, compositor Android/NDK, comunicación socket host-invitado, labwc y XFCE Wayland todavía **no son código**. Ninguna funcionalidad de esta propuesta debe presentarse como implementada o validada.
- El rootfs Debian ARM64 fijado en la ruta existente se ha descrito con una capa comprimida de aproximadamente 28 MB; la ocupación expandida, las dependencias del candidato Trixie y la huella instalada no están medidas por dispositivo. No extrapolar esa medida del rootfs existente al nuevo candidato ni publicar una cifra instalada hasta medirla.
- No borrar ni describir falsamente la ruta actual de Lorie/X11 como reemplazada. La migración solo podrá declararse al implementar y validar un sustituto y actualizar explícitamente el estado de las fases.

## Fases y puertas de aceptación

### 0. Identidad, firma y actualización — pendiente

**Trabajo:** decidir identidad permanente de paquete, `versionCode`/`versionName`, clave de firma y custodia, rotación respaldada y política debug/release. El sufijo `.sdk28test` del paquete debug actual no es identidad de lanzamiento; APKs debug de distintas ejecuciones pueden tener claves distintas.

**Puerta:** APK firmada con clave acordada instala limpia y actualiza versión previa conservando datos; CI comprueba metadatos y certificado. Documentar custodia/restauración. No prometer actualización fluida ni estabilidad de firma antes de pasar esta puerta.

### 1. APK reproducible y cobertura Android — parcialmente superada

**Trabajo:** conservar la APK de prueba ARM64 y su identidad separada, artefactos CI reproducibles y matriz de emulador API 26, 29, 30 y 35. Identificar con precisión arquitectura y alcance de cada prueba; ninguna debe confundirse con ejecución del escritorio en teléfono.

**Puerta:** build APK ARM64 y comprobaciones de paquete, label, `minSdk`, `targetSdk`, permisos, bibliotecas, activos y hash; smoke existentes de instalación, launcher y PRoot invitado verdes. Reportar explícitamente que CI es x86_64 emulado y que no valida escritorio ARM64.

### 2. Selección del rootfs, preflight de almacenamiento y recuperación — pendiente

**Trabajo:** evaluar primero Debian Trixie ARM64, fijar fuentes/versiones y hashes, comparar Arch ARM64 y medir cada candidato. Implementar preparación transaccional/resumible dentro del almacenamiento privado de la APK y separar la base del estado mutable del usuario y paquetes. No empaquetar una imagen monolítica de 16 GB.

La preflight debe ser **parte de la aplicación Android**, consultar `StatFs` sobre el volumen/destino de app-private storage y mostrar claramente:

- bytes comprimidos requeridos para descargar el rootfs;
- bytes medidos para expandir la base;
- bytes medidos para paquetes XFCE + labwc y dependencias;
- espacio máximo temporal necesario para descargas, caché de paquetes, extracción y staging; y
- reserva medida para rollback/recuperación mientras se conserva base o datos previos.

Mostrar por separado descarga, ocupación instalada y pico temporal. Recalcular/revisar espacio disponible antes de fases grandes. **No** sustituir la preflight de producto por un script Python/shell para que lo ejecute el usuario, y no afirmar una huella instalada sin mediciones reproducibles en dispositivos ARM64.

El primer uso debe tener progreso, checkpoints validados y reanudación tras cierre o muerte del proceso; validar integridad antes de activar una base; promover staging de forma atómica; hacer posible rollback sin perder datos. Definir explícitamente red y modo offline: descargar solo entradas fijadas/verificables; permitir modo sin conexión únicamente si todos los insumos necesarios ya están presentes y validados. Si falta alguno, la UI explica qué requiere conexión y ofrece reintentar. Errores de falta de espacio, red, hash, extracción, cancelación o rollback deben tener UI comprensible, una acción segura y diagnóstico útil; no pedir comandos externos.

**Puerta:** instalación interrumpida en cada etapa puede continuar o revertirse sin rootfs corrupto, y los archivos/configuración del usuario sobreviven a actualización. En teléfono ARM64 se reportan tamaños comprimidos, expandidos, paquetes y pico temporal con método y espacio libre observado.

### 3. PRoot ARM64 y Debian ARM64 real — no comprobada en dispositivo

**Trabajo:** probar binarios ARM64 fijados, dependencias, loader, binds, permisos y comandos invitados sobre Android, usando el almacenamiento privado de la propia APK. No extrapolar resultados de fixture x86_64.

**Puerta:** en dispositivo ARM64 real la app monta e inicia el rootfs ARM64, confirma arquitectura, ejecuta comandos de prueba sin Termux ni app auxiliar y repite tras instalación limpia y reanudación. Registrar dispositivo, Android/API, APK/hash y logs depurados.

### 4. Compositor Wayland host Android/NDK — no implementado

**Trabajo:** implementar el primer PoC en la app Android: compositor servidor host que dibuja en la superficie nativa, socket accesible desde PRoot ARM64, cliente invitado mínimo, ventana de prueba de color sólido, entrada touch y teclado con confirmación, y gestión de ciclo de vida/errores. Asegurar límites, permisos y modo de exposición del socket sin asumir que el namespace invitado lo ve automáticamente. No usar labwc solo como sustituto del servidor host. No considerar una pantalla Canvas como éxito.

**Puerta:** en teléfono ARM64, el cliente invitado se conecta realmente al Wayland server de la app, pinta en la superficie Android y recibe entrada táctil/teclado; repetir ciclo parar/reiniciar, pérdida/restauración de superficie y error sin proceso/socket zombi. Adjuntar evidencia/logs. Esta fase precede a labwc y XFCE.

### 5. labwc invitado anidado — no implementado

**Trabajo:** después de validar fase 4, evaluar labwc como compositor/sesión Wayland anidado del invitado, ejecutado como cliente del compositor host. Verificar configuración, protocolos requeridos, foco, ventanas, entrada y ciclo de vida; medir paquetes y dependencias para la preflight.

**Puerta:** labwc se inicia dentro del ARM64 PRoot usando el socket del host, muestra una superficie de sesión y pasa pruebas visibles de dibujo, toque, teclado, inicio, cierre y recuperación en dispositivo. Esto no certifica todavía XFCE.

### 6. Usuario no-root, sesión y XFCE Wayland — no comprobada en dispositivo

**Requisito de producto:** la app prepara automáticamente un usuario invitado no-root y su sesión usable, sin instrucciones para que el usuario complete setup desde una shell externa. Esta es una tarea futura, no una capacidad ya demostrada. No prometer `sudo` ni creación automática de usuarios/sesiones existente; definir, implementar y probar un modelo de privilegios compatible con PRoot.

**Trabajo:** sobre labwc validado, instalar desde repositorios Debian firmados y fijados el candidato Debian Trixie ARM64 y XFCE 4.20+; confirmar `xfce4-session` 4.20.2-2 en el índice como disponibilidad de paquete, no compatibilidad probada. Investigar la sesión experimental Wayland de XFCE 4.20, D-Bus, session manager, panel, terminal y gestor de archivos. Añadir readiness gate, logs y diagnóstico en UI.

**Puerta:** setup automático crea/prepara el usuario y sesión no-root; desde arranque limpio aparece y funciona una sesión XFCE con panel, terminal y gestor de archivos sobre labwc/host Wayland en dispositivo ARM64. Demostrar touch/teclado, detener/reiniciar, cierre limpio y recuperación. Si la sesión falla, presentar error claro; no declarar soporte hasta que pase.

### 7. Uso móvil, ciclo de vida y almacenamiento persistente — pendiente

**Trabajo:** decidir orientación, escala, controles Android, teclado en pantalla/físico, touch/gestos, retroceso y navegación de ventanas. Gestionar suspensión, app en background, muerte de proceso, pérdida de memoria, rotación, apagado/reinicio, actualización y estado de sesión; mantener datos del usuario separados del rootfs base.

**Puerta:** las pruebas acordadas de interacción y ciclo de vida pasan en los dispositivos soportados, con sesión viva reportada solo cuando los procesos lo están y sin pérdida de datos tras recuperación o actualización.

### 8. Pruebas físicas, compatibilidad y migración — pendiente

**Trabajo:** probar el teléfono ARM64 objetivo y al menos un segundo dispositivo Android compatible. Registrar modelo, Android/API, ABI, espacio disponible, versión APK, SHA-256, resultado y logs. Mantener resultados emulados y físicos en columnas separadas. Retirar Lorie y la transformación de build únicamente después de que el camino reemplazante haya superado sus puertas y se haya actualizado el inventario/licencias correspondiente.

**Puerta:** aceptación desde instalación limpia hasta setup, escritorio XFCE Wayland, render/input, pausa/reanudación, falta de red/espacio, parar/reiniciar, actualización y conservación de datos. Solo tras las pruebas de reemplazo se puede afirmar que la ruta Lorie/X11 fue sustituida; preservar los scripts/recursos históricos que aún sean necesarios para compatibilidad o documentar su eliminación deliberada.

### 9. Xwayland y aplicaciones adicionales — opcional/posterior

**Trabajo:** evaluar Xwayland como compatibilidad opcional después del escritorio Wayland estable. Chromium, Godot, Blender u otras aplicaciones requieren decisión separada por memoria/almacenamiento, arquitectura, licencia, actualizaciones y controles móviles.

**Puerta:** cada compatibilidad se demuestra mediante instalación y uso en dispositivo ARM64, con presupuestos medidos. No contar esos paquetes como aceptación básica ni afirmar soporte sin prueba.

## Política Android y distribución

El prototipo actual declara `minSdk 26` (Android 8), `targetSdk 28` y ABI de producto `arm64-v8a`. Mantener estas características como hechos del prototipo, no como decisión validada para el producto final. El método actual de ejecución de PRoot y sus restricciones de Android no autorizan a inferir compatibilidad con targets actuales ni elegibilidad para Google Play. Cualquier cambio de target requiere rediseñar y probar el modelo de ejecución; no cambiar el número sin evidencia. No exigir developer options.

La matriz CI conocida usa emuladores x86_64 API 26, 29, 30 y 35, con fixture PRoot x86_64 y root invitado sintético. Aunque pase, no demuestra desktop PRoot ARM64, sesión Wayland/XFCE o uso en un teléfono.
