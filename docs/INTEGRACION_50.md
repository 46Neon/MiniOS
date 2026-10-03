# Integración histórica de los 50 hitos en una base Linux

> Documento heredado de la propuesta Debian/QEMU. No describe el producto principal actual, que es un escritorio nativo Termux/XFCE, ni debe usarse como afirmación de compatibilidad o arquitectura de esa ruta.

La decisión Debian convierte muchos hitos de implementar a **integrar, configurar y verificar**. Los hitos siguen siendo aceptación funcional; la implementación concreta ya no usa el kernel ensamblador antiguo.

## Fase 1 — base y gráficos

1. Preservar la imagen previamente probada con copia y SHA-256. No se recibió `os.img` con el repositorio: este punto queda pendiente hasta que Lennd comparta esa copia.
2. Mantener BIOS/SeaBIOS, QEMU e IDE; la arquitectura recomendada es amd64. Si se mantiene literalmente x86 de 32 bits, habría que usar una base distinta/más antigua y aceptar sus límites.
3. `make clean && make` crea `build/os.img` siempre desde cero. `clean` no elimina la imagen previa; el constructor la archiva antes de reemplazarla.
4. Verificar tamaño raw, MBR, firma `55 AA`, partición única, GRUB BIOS, kernel/initramfs y que todos los datos quedan dentro de la imagen. No existe `stage2` propio en la variante Linux.
5. El kernel Linux/GRUB recibe el mapa BIOS de memoria; contrastarlo en los logs del kernel.
6. La memoria física y las páginas reservadas las administra Linux; verificar con logs y configuración QEMU.
7. Configurar modo gráfico GRUB/framebuffer y conservar consola textual de emergencia.
8. El handoff framebuffer lo negocian GRUB y Linux; comprobar el dispositivo de vídeo disponible en QEMU, sin definir una estructura de arranque propia.
9. El mapeo y permisos del framebuffer quedan a cargo de kernel/controlador/servidor gráfico; no se escribe VRAM desde un kernel MiniOS.
10. Configurar el modo inicial a 640×480 e incluir esa resolución en las pruebas; una prueba de arranque headless no basta para certificarla.

## Fase 2 — escritorio y terminal

11. Teclas y teclas especiales llegan por Linux input/evdev y XFCE; validar teclado PS/2 emulado.
12. Usar el dispositivo apuntador emulado de QEMU y la pila de entrada de Linux; probar botones, movimiento y bordes.
13. Usar Xorg/Xfwm y el compositor de XFCE para dibujar ventanas.
14. Configurar fondo, panel, menú y accesos directos del escritorio MiniAriño.
15. Foco, movimiento, cierre y redibujado corresponden al gestor de ventanas XFCE.
16. Usar terminal XFCE con Bash, entrada, historial y scrollback.
17. Incluir accesos a terminal, Thunar, Firefox y una aplicación real instalada.
18. Bloque de salida: arrancar el escritorio nuevo en QEMU y operar teclado/ratón antes de aceptar la fase gráfica.

## Fase 3 — aplicaciones y aislamiento

19. Documentar el perfil MiniAriño: Debian/amd64, ELF Linux y compatibilidad de paquetes; no crear llamadas al sistema privadas incompatibles con Linux.
20. TSS y ring 3 los proporciona el kernel Linux; probar procesos no privilegiados y llamadas denegadas.
21. Linux ya separa procesos y espacios de direcciones; probar aislamiento con dos procesos.
22. El cargador ELF es `execve`/kernel Linux y el enlazador dinámico correspondiente.
23. Usar syscalls Linux para consola, teclado, memoria, procesos, reloj, archivos y sockets.
24. `exit`, `wait` y la recolección de procesos los proporciona Linux; probar procesos terminados y recursos liberados.
25. Usar APIs gráficas de escritorio compatibles con XFCE, por ejemplo GTK/X11, en lugar de una ABI de ventanas propia.
26. Construir `hola` y `contador` como ELF Linux amd64; si se conserva una variante de 32 bits, compilarla y probarla por separado.
27. Probar concurrencia, cierre, syscall desconocida y excepción de usuario; ninguna debe detener el sistema.

## Fase 4 — archivos e instalación

28. Usar ext4/VFS como filesystem activo; mantener la antigua MiniFS en `legacy/` y definir una conversión de datos si se recupera una imagen vieja.
29. Usar operaciones POSIX/Linux de rutas, directorios, lectura, escritura, renombrado y borrado.
30. Delegar IDE/ATA al controlador Linux; probar errores, escrituras y persistencia en QEMU.
31. Usar Thunar como gestor gráfico conectado al filesystem Linux.
32. Bash y coreutils proporcionan `pwd`, `cd`, `mkdir`, `cat`, `cp`, `mv` y `rm`; probar nombres/rutas inválidos y válidos.
33. Usar `.deb` firmado, arquitectura amd64, metadatos Debian y dependencias en lugar de inventar un formato incompatible.
34. Usar `apt`/`dpkg` para instalar y desinstalar, validando firmas, dependencias, espacio y recuperación de errores.
35. Instalar un paquete, reiniciar la misma imagen no efímera y comprobar que programa y configuración persisten.

## Fase 5 — red

36. Añadir e1000 al comando QEMU y dejarlo documentado/reproducible.
37. Linux enumera PCI y opera e1000 con su driver y DMA; comprobar la interfaz desde el invitado.
38. Usar la pila Ethernet/ARP/IPv4/ICMP de Linux; probar primero conectividad local.
39. Usar NetworkManager/DHCP/DNS y validar respuestas y tiempos de espera.
40. Usar TCP/IP del kernel Linux; probar conexiones y desconexiones.
41. Exponer sockets estándar Linux; limitar bloqueos mediante APIs/procesos y aplicar controles del sistema.
42. Firefox/curl implementan HTTP/1.1, lecturas parciales y chunked; comprobar descargas grandes y fallos.
43. Sincronizar hora y usar autoridades del sistema/OpenSSL/NSS; certificados inválidos deben producir error visible.
44. En QEMU, probar primero un servidor local y luego HTTPS; validar integridad y firma del `.deb` descargado.

## Fase 6 — navegador e integración

45. Alcance: navegador Linux real (Firefox ESR empaquetado para la arquitectura elegida), no navegador moderno hecho desde cero.
46. Probar barra, carga, atrás/adelante y estado de conexión en la ventana del navegador.
47. Reutilizar motor existente y fijar versión/dependencias de Debian; no declarar compatibilidad web sin probar sitios y TLS.
48. Probar enlaces, descargas a `~/Downloads`, fallos TLS, interrupciones y formatos no admitidos.
49. Prueba integral: escritorio → terminal → carpetas → HTTPS → descarga de `.deb` → verificación/instalación → apertura de app.
50. Solo publicar imagen si build limpio, boot, resolución, escritorio, procesos, archivos, red, HTTPS y paquetes pasan; documentar el commit, hashes y límites.

## Condición arquitectónica

Los puntos 5–9, 11–16, 20–24, 28–32 y 36–43 se resuelven principalmente con componentes Linux. Si se exigiera que MiniAriño contuviera implementaciones propias de esos mecanismos, se estaría volviendo al sistema bare-metal y se perdería la compatibilidad con el ecosistema Linux que motivó el cambio.
