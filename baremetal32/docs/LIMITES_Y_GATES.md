# Experimento bare-metal archivado — límites/gates históricos

> No forma parte del escritorio MiniAriño Termux/XFCE. Se conserva la evaluación de la antigua imagen de prueba; su ejecución de build/QEMU es solo manual.

## Alcance de esta entrega

Se implementó código real para el primer subgate: MBR BIOS/EDD → stage2 de ocho
sectores → recolección E820 y tentativa VBE → carga de una ventana fija de 64
sectores → modo protegido x86-32 → kernel de diagnóstico por COM1. La imagen es
independiente de la ruta Debian y se construye en `build/os.img` desde este
subdirectorio.

Este avance NO completa Fase 1 ni acredita aún el subgate: en este entorno no hay
NASM, GCC/ld multilib ni QEMU instalados, por lo que no se ejecutó el ensamblado,
el enlace, `make`, el verificador ni la emulación. GitHub Actions contiene una
receta reproducible para correrlo desde cero, pero no se ha observado su resultado.

## Contrato implementado (pendiente de validación con herramientas)

- Sector 0: bootstrap BIOS de 512 bytes, lectura EDD LBA 1..8 a `0000:8000`,
  firma `55 AA`; tabla de particiones vacía en una imagen raw de disco completo.
- Sectores 1..8: stage2 de 4096 bytes. LBA 9..72: kernel de hasta 32768 bytes,
  rellenado a 64 sectores. El stage2 pide exactamente esa ventana a BIOS EDD.
- Mapa E820: hasta 64 registros SMAP de 24 bytes en `0x5000`; boot-info versionado
  en `0x7000`, ABI definido también en `include/boot_info.h`.
- VBE: consulta e intenta modo `0x112` (640x480x24) con framebuffer lineal;
  el kernel recibe texto-fallback explícito cuando no se activa. El test de QEMU
  normal exige marcador gráfico, pero aún no ha sido ejecutado.
- Transición a modo protegido con GDT plana, A20 por fast gate y salto a `0x10000`.
  Kernel inicializa COM1, valida el encabezado boot-info y registra marcadores.

## No implementado / gates pendientes

- No existe aún un kernel que cree tablas de páginas ni mapee el LFB físico si
  supera 16 MiB. El kernel actual sólo valida/describe el boot-info y se detiene.
- No hay allocator de frames basado en E820 ni reservas de kernel, mapa, boot-info,
  page tables o framebuffer; no se ha probado asignación de RAM sobre 16 MiB.
- No hay operaciones de pixel/rect/clear, clipping, bitmap font ni salida gráfica
  producida por el kernel.
- El fallback a texto está codificado pero no hay una prueba que lo fuerce.
- No hay screenshot ni aceptación de salida legible. Tampoco se ha pasado el gate
  completo de hitos 1–10 ni se debe iniciar la fase siguiente.
- Antes de afirmar incluso el primer subgate hacen falta build limpio, verificador,
  QEMU SeaBIOS BIOS/IDE, marcadores kernel/E820/VBE/boot-info y revisión de logs;
  se debe informar el SHA exacto del resultado CI.

## Comandos declarados por la receta (NO ejecutados localmente)

Desde `miniOS/baremetal32/`:

```sh
make clean && make verify
make qemu-test
```

La workflow nueva ejecuta ambos comandos en un runner Ubuntu con NASM, GCC/ld
multilib, binutils y QEMU; publica imagen y log serial como artefactos de CI. La
workflow se limita a cambios bajo `miniOS/baremetal32/**` o a sí misma y no altera
el workflow Debian existente.
