# MiniAriño bare-metal x86-32 — alcance y diseño propuesto

## Estado

Esta vía separada tiene ahora fuentes reales para el primer subgate de arranque
(MBR/EDD, stage2 E820/VBE, carga de kernel, protected mode y diagnóstico serial)
y una receta de build/CI. Ninguna se ha compilado ni arrancado en el entorno de
trabajo; no se acredita todavía ningún hito. Paginación, allocator, primitivas de
dibujo y bitmap font siguen pendientes. El objetivo inmediato es exclusivamente
Fase 1 (hitos 1–10); no se debe crear una segunda arquitectura/versión Debian ni
modificar la raíz existente. Ver `docs/LIMITES_Y_GATES.md` para estado completo.

## Plataforma invariable

- CPU x86 de 32 bits; arranque BIOS legado compatible con SeaBIOS en QEMU.
- Imagen de disco raw con MBR de 512 bytes y firma `55 AA`; disco IDE/QEMU.
- No UEFI, no GRUB requerido y no Termux como target de aceptación.
- Fuente nueva y ligera bajo `baremetal32/`; ninguna reutilización del código de
  la vía Linux como solución bare-metal.
- NASM + C freestanding de 32 bits solo con flags y herramientas reproducibles
  en CI. No se da por construido hasta que build limpio y emulación pasen.

## Propuesta de layout (pendiente de implementación y validación)

| Elemento | Layout propuesto | Restricción por comprobar |
|---|---:|---|
| MBR | LBA 0, exactamente 512 bytes | Firma en bytes 510–511; EDD BIOS IDE |
| stage2 | LBA 1–8; hasta 4096 bytes | El MBR lee exactamente el límite acordado; no excederlo |
| kernel raw | Desde LBA 9, carga inicial a 0x10000 | Acordar y validar límite de tamaño, destino y fin de lectura |
| E820 buffer | Dirección física baja fija (propuesta 0x5000) | Máximo de entradas, tamaño, terminación y bounds |
| Boot-info | Dirección física baja fija (propuesta 0x7000) | Firma/versión, modo, ancho/alto/bpp/pitch/LFB y E820 |
| Transición | Modo protegido de 32 bits | Pila, A20, segmento plano y contrato de entrada comprobables |
| Page directory | Región reservada explícitamente bajo 16 MiB | Identidad para estructuras; mapeo framebuffer >16 MiB |

Las direcciones de la tabla son un diseño inicial, no un contrato ya consumido
por código. La implementación deberá documentar de forma concordante offsets,
tamaños, alineación, unidades, límites y reservas. La imagen y los sectores no
se truncarán en silencio.

## Requisitos técnicos del gate gráfico/memoria

1. BIOS carga desde IDE y control de flujo llega al kernel; serial emite un
   marcador de arranque que el test observa.
2. stage2 obtiene mapa E820 mediante BIOS, valida firma y tamaños devueltos y
   conserva regiones utilizables/no utilizables sin asumir RAM contigua.
3. Intento real de modo VBE 640x480 en BIOS; inspeccionar modo y modo-info,
   exigir pitch/bpp válidos y activar framebuffer lineal cuando esté disponible.
   Si el firmware no ofrece modo válido, mantener un camino de texto explícito;
   el test QEMU normal debe demostrar 640x480, no solo ejercitar fallback.
4. Boot-info pasa resolución, profundidad, pitch y dirección física del
   framebuffer, junto con entradas E820 y flags consistentes.
5. kernel x86-32 inicializa paginación y mapea la región framebuffer aunque su
   base física sea superior a 16 MiB (por ejemplo, páginas grandes PSE o una
   solución equivalente justificada y probada). No suponer que el LFB cabe en
   el primer mapeo identity.
6. allocator de frames deriva disponibilidad del tipo usable E820, incluye RAM
   usable por encima de 16 MiB y reserva kernel, boot-info, mapa E820, page
   tables, framebuffer y metadata. Rechaza regiones inválidas/overflow.
7. Primitivas de framebuffer (pixel, rectángulo, clear) respetan dimensiones,
   pitch y bytes/pixel sin escribir fuera del buffer.
8. bitmap font renderiza al framebuffer y comprueba límites de clipping.
9–10. El contrato completo de paginación/reservas y salida 640x480 queda cubierto
   por pruebas de aceptación automatizadas y un artefacto/screenshot legible.

Las pruebas de puntos 3–10 y un test QEMU BIOS/IDE, incluida captura de pantalla,
son gates obligatorios, no aspiraciones opcionales. Se informarán resultados por
SHA exacto. No se permitirá declarar la fase completa solo con compilación o
marcadores simulados.

## Gate y pasos de ejecución

La secuencia prevista para Fase 1 es: MBR/layout, carga stage2/kernel, transición
x86-32, E820, VBE, boot-info, paginación/framebuffer alto, allocator E820, dibujo
y font, y aceptación integral QEMU/CI. Antes de su merge hacen falta al menos:

- `make clean && make` partiendo sin `build/` produce la imagen esperada.
- Verificador comprueba tamaño/formato MBR, 55AA y offsets/capacidades.
- QEMU SeaBIOS arranca la imagen como disco IDE y alcanza el kernel.
- Logs seriales prueban E820 y modo VBE real 640x480 junto al boot-info.
- Ruta fallback a texto tiene una prueba alcanzable si puede forzarse el fallo
  de VBE sin falsear el caso gráfico.
- Paginación y allocator comprueban direcciones altas y reservas.
- Pruebas de pixel/rect/clear/font incluyen límites y overflow.
- CI adjunta logs y screenshot/artifact legible y no depende de outputs previos.

No modificar `Makefile` raíz, scripts del build Debian, `build/os.img` raíz,
PR #2 ni la arquitectura Debian. No almacenar en Git imágenes de 16 GiB. No
abrir una PR que presente como fase completa un estado parcial. Fases 2–6 no
comienzan hasta superar este gate.
