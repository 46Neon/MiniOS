# Hoja de ruta: escritorio MiniAriño en una sola APK

## Decisión de producto

La entrega objetivo es una APK de MiniAriño que se instala y presenta el escritorio desde la propia aplicación Android. No debe requerir Termux, Termux:X11, una segunda APK, comandos en una terminal ajena ni un salto de aplicación para mostrar la pantalla. La imagen histórica Debian/QEMU de hasta 16 GB queda fuera del producto y de las rutas de CI predeterminada y pull request; sus scripts y recursos se conservan solo para compatibilidad/revisión.

El modelo de almacenamiento objetivo no es empaquetar una imagen monolítica de 16 GB. Debe usar una base de sistema pequeña, fijada e íntegra que se descargue una vez y se extraiga dentro del almacenamiento privado de la APK, más una capa de datos privada para paquetes instalados, actualizaciones, caché, configuración y archivos del usuario. El rootfs de Debian ARM64 actualmente fijado tiene una capa comprimida de aproximadamente 28 MB; el espacio extraído y el de XFCE y sus dependencias es mayor y todavía debe medirse en dispositivos reales. La app debe informar del espacio necesario antes de descargar, distinguir descarga/base de uso instalado, gestionar fallos/pausa/reanudación y permitir recuperación segura. No publicar una cifra de huella instalada hasta medirla.

## Estado verificado y límites

El prototipo actual empaqueta la interfaz Android, PRoot y código/nativos del servidor gráfico Lorie. Los emuladores x86_64 API 26, 29, 30 y 35 verifican instalación/arranque de la app y un comando de PRoot en un root invitado sintético. No verifican PRoot ARM64, Debian ARM64, instalación APT de XFCE, renderizado o entrada de Lorie, un escritorio completo ni uso en teléfono.

Lorie procede del submódulo Termux:X11 fijado y `android/scripts/prepare_x11.py` transforma su código durante la compilación. Esto es una adaptación de fuentes de compilación, no una modificación de una app instalada ni una dependencia de Termux/Termux:X11 en tiempo de ejecución. Mantener la transformación mientras sea necesaria para construir el servidor; reemplazarla por un módulo/fork de Lorie mantenido en el repositorio es una fase planificada, no una eliminación silenciosa que rompa el APK.

## Fases y puertas de aceptación

### 0. Identidad, firma y ciclo de actualización — pendiente

**Trabajo:** decidir la identidad permanente de paquete, `versionCode`/`versionName`, clave y proceso de custodia de firma, rotación respaldada y política debug/release. El sufijo `.sdk28test` evita colisión al probar el paquete debug actual, pero no es una identidad de lanzamiento. Los APKs de depuración de ejecuciones distintas pueden tener claves distintas.

**Puerta:** una APK firmada con la clave acordada instala limpia y actualiza una versión anterior sin desinstalar ni perder datos; los metadatos de identidad y certificado se comprueban en CI. Documentar custodia/restauración de clave. Hasta entonces no prometer actualización fluida ni estabilidad de firma.

### 1. APK reproducible y pruebas de compatibilidad — parcialmente superada

**Trabajo:** mantener el armado reproducible ARM64, identidad aislada de la APK de prueba y paquete de CI descargable. Conservar el smoke de emulador API 26, 29, 30 y 35 y aclarar en cada informe su alcance.

**Puerta:** compilación válida del APK ARM64, verificación automática de paquete/label/minSdk/targetSdk/permisos/bibliotecas/activos/hash y las cuatro pruebas de instalación/launcher/PRoot invitado verdes. La salida se llama de manera inequívoca APK de prueba, con retención y firma descritas. Ninguno de estos resultados se cuenta como prueba de escritorio en ARM64.

### 2. Base Debian, espacio y recuperación — en desarrollo

**Trabajo:** conservar una base ARM64 fijada por hashes; diseñar preparación transaccional/resumible, progreso, verificación, falta de red/espacio, reintentos y recuperación ante cierre del proceso. Separar raíz base de datos de paquetes y datos de usuario para evitar sobrescribir trabajo al actualizar. Mostrar espacio descargado y huella adicional estimada/medida; no usar una imagen fija de 16 GB.

**Puerta:** en teléfono ARM64 limpio, instalación interrumpida en cada etapa puede reanudarse o revertirse sin rootfs corrupto; checksums se validan antes de extraer; los datos del usuario sobreviven a una actualización de la base; la app comunica un mínimo de espacio con evidencia medida y ofrece cancelación limpia. Medir tanto descarga comprimida como espacio real de base, XFCE y cachés.

### 3. PRoot y Debian ARM64 real — no comprobada en dispositivo

**Trabajo:** probar los binarios ARM64 fijados, dependencias, loader, binds, permisos y comandos invitados en el kernel de Android. Mantener las pruebas de emulador x86_64 como cobertura distinta.

**Puerta:** en teléfono ARM64 objetivo, MiniAriño inicia el PRoot ARM64 desde su propio almacenamiento, monta el rootfs invitado Debian ARM64, verifica arquitectura, ejecuta shell y comandos de prueba sin Termux ni app auxiliar. Repetir tras reinstalación limpia y tras reanudar preparación. Adjuntar versión/dispositivo/logs depurados.

### 4. Servidor gráfico integrado (Lorie) — no comprobada en dispositivo

**Trabajo:** mantener servidor y bibliotecas dentro de la APK y el mismo proceso de flujo de producto; proporcionar socket, datos XKB, resolución, ciclo de vida y errores desde MiniAriño. Migrar la adaptación `prepare_x11.py` a módulo/fork integrado y probado, preservando explícitamente licencias, atribución y origen de cada dependencia.

**Puerta:** Lorie se inicia y termina desde la APK en el teléfono ARM64; la ventana/display embebidos aparecen sin instalar/abrir otra aplicación; prueba real de dibujo, XKB, toque/gesto y una aplicación gráfica mínima; sin dependencia en runtime de una app externa Termux:X11. Verificar que iniciar, parar y fallar deja procesos/socket limpios.

### 5. XFCE y preparación de sesión — no comprobada en dispositivo

**Trabajo:** instalar desde repositorios Debian firmados los paquetes XFCE fijados/permitidos; readiness gate que comprueba D-Bus, gestor de sesión, panel, terminal y gestor de archivos; registrar diagnóstico útil en la app; evitar declarar éxito hasta que sesión y display estén preparados. Hacer que iniciar/detener/reparar pueda hacerse desde la UI.

**Puerta:** tras instalación inicial y reinicio, aparecen y funcionan sesión XFCE, panel, terminal y Thunar en el display integrado; cerrar/parar no deja procesos colgados; un fallo presenta un diagnóstico comprensible y permite recuperación sin terminal externa ni perder archivos. Confirmar conexión teclado/táctil con apps visibles.

### 6. Uso móvil y ciclo de vida — pendiente

**Trabajo:** definir orientación horizontal/vertical, áreas táctiles, teclado en pantalla/teclado físico, escala, navegación de ventanas, retroceso, notificaciones y controles de sesión. Administrar suspensión, pérdida de proceso/memoria, cierre de pantalla, rotación, app en segundo plano y reinicio explícito.

**Puerta:** pruebas de aceptación acordadas pasan con tacto y teclado; la sesión no se informa como viva si su proceso terminó; al volver de suspensión se restaura o reinicia de forma predecible sin pantalla negra; rotación/cambio de app no pierde datos ni rompe Lorie. Documentar límites de fabricantes y pedir captura/log si aparece un error no clasificado.

### 7. Validación en dispositivos — pendiente

**Trabajo:** probar teléfono ARM64 objetivo y como mínimo un segundo dispositivo Android compatible, registrar modelo, versión/API, arquitectura, espacio libre, versión APK, SHA-256, resultado y logs. Añadir las rutas de fallo y actualización que no cubren emuladores.

**Puerta:** completar checklist desde instalación limpia hasta sesión XFCE, entrada, suspensión/reanudación, parar/reiniciar, actualización y conservación de datos en los dispositivos acordados. La aceptación del emulador y la del dispositivo se reportan separadamente.

### 8. Aplicaciones adicionales — posterior

**Trabajo:** valorar navegador, Godot, Blender u otras aplicaciones solo después de un escritorio estable; definir por aplicación memoria/almacenamiento, arquitectura, licencia, actualizaciones, controles y comportamiento Android. No incorporar de golpe paquetes pesados ni afirmar compatibilidad sin ejecución en teléfono.

**Puerta:** cada aplicación tiene prueba de instalación/arranque/interacción en el dispositivo ARM64 soportado, presupuesto medido de almacenamiento y memoria y una decisión explícita de inclusión o carácter opcional. Chromium, Godot y Blender no forman parte de la aceptación base actual.

## Política de Android y distribución

El prototipo actual declara `minSdk 26` (Android 8), `targetSdk 28` y ABI de producto `arm64-v8a`. El target 28 es una decisión de sideload ligada al método actual de ejecutar PRoot desde almacenamiento privado y a restricciones de ejecución de Android para targets más nuevos. Tiene coste de avisos/restricciones y no cumple por sí solo los requisitos actuales de Google Play. No afirmar elegibilidad para Play Store. La migración a target actual exige rediseñar y verificar el modelo de ejecución antes de cambiar el número.

Las pruebas de compatibilidad CI conocidas son emuladores x86_64 API 26, 29, 30 y 35 y prueban el fixture PRoot x86_64 más un root invitado sintético. La APK candidata es ARM64; ni esa matriz ni la existencia de su artefacto prueban el escritorio ARM64 completo.
