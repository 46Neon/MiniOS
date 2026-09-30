# MiniOS - sistema operativo x86 bare-metal en ensamblador

Sistema operativo de 32 bits que arranca desde BIOS (MBR), sin compilador ni
lenguaje de alto nivel: solo ensamblador GNU `as` en sintaxis Intel, donde cada
mnemonico se convierte 1 a 1 en su opcode x86. Pensado para una CPU comercial
sin GPU dedicada (usa el modo texto VGA 80x25 que expone el BIOS/CSM).

ESTADO HONESTO: todo el proyecto ensambla y enlaza sin errores y se verifico de
forma estatica (tamanos, firma 0x55AA, desensamblado de los puntos criticos,
orden de enlazado). NO se pudo ejecutar en QEMU en el entorno donde se genero.
Pruebalo tu y, si algo falla, reporta la salida de `make debug`.

---------------------------------------------------------------------------
## 1. Auditoria: como funciona una CPU comercial promedio sin GPU

1. **Reset**: al dar corriente, el procesador arranca en modo real (16 bits) y
   ejecuta la primera instruccion en el vector de reset 0xFFFFFFF0 (mapeado a la
   ROM del firmware).
2. **BIOS/UEFI + POST**: el firmware inicializa DRAM, chipset y controladores,
   y detecta dispositivos. En equipos UEFI, el modulo CSM (modo compatibilidad)
   emula un BIOS clasico; MiniOS necesita ese modo (o QEMU con BIOS).
3. **Arranque**: el BIOS lee el sector 0 del disco (512 bytes) a 0x7C00 y, si
   los ultimos 2 bytes son 0x55 0xAA, salta ahi (`boot/boot.s`).
4. **Modo real (16 bits)**: direccionamiento segmento:offset, 1 MB de espacio,
   sin proteccion. Se usa para llamar al BIOS (INT 13h disco, INT 15h memoria).
5. **Linea A20**: hay que habilitarla para acceder por encima de 1 MB
   (`boot/stage2.s`: BIOS, puerto 0x92 o controlador 8042).
6. **Modo protegido (32 bits)**: se carga la GDT, se activa CR0.PE y un salto
   lejano recarga CS. Segmentacion "plana" de 4 GB (base 0, limite 4 GB).
7. **Interrupciones**: dos PIC 8259 (remapeados a los vectores 0x20-0x2F para no
   chocar con las excepciones 0-31) y la IDT de 256 entradas.
8. **Paginacion**: MMU con directorio y tablas de 4 KB (CR3/CR0.PG). MiniOS usa
   mapeo identidad de 16 MB y deja la pagina 0 sin mapear para atrapar NULL.
9. **Perifericos clasicos**: temporizador PIT 8254 (100 Hz), teclado PS/2
   (puertos 0x60/0x64; el BIOS emula PS/2 sobre USB "legacy"), disco ATA en modo
   compatibilidad (puertos 0x1F0-0x1F7, PIO LBA28).
10. **Video sin GPU**: el modo texto VGA 80x25 es memoria mapeada en 0xB8000
    (2 bytes por celda: caracter + atributo). Sin GPU no hay aceleracion, pero
    el framebuffer del chipset grafico integrado sigue siendo accesible.

---------------------------------------------------------------------------
## 2. Estructura del proyecto

```
miniOS/
|-- Makefile                 targets: all, run, debug, hex, clean
|-- include/constants.inc    mapa de memoria, offsets de PCB, constantes
|-- linker/kernel.ld         kernel enlazado en 0x10000
|-- boot/
|   |-- boot.s               MBR (512 B): lee stage2 con INT 13h ext., firma 55AA
|   `-- stage2.s             A20, memoria, carga kernel, GDT, salto a 32 bits
|-- kernel/
|   |-- entry.s              punto de entrada, orden de init, idle con HLT
|   |-- gdt.s  idt.s  pic.s  GDT definitiva, IDT/excepciones/IRQ/int 0x80, PIC
|   |-- vga.s                consola texto: putc/print/hex/dec, scroll, barra
|   |-- paging.s  memory.s   paginacion y gestor de marcos (bitmap)
|   |-- process.s            PCB, planificador round-robin, cambio de contexto
|   |-- pit.s  keyboard.s    timer 100 Hz y teclado PS/2 (scancode set 1)
|   |-- ata.s  fs.s          disco ATA PIO y MiniFS (directorio + binarios)
|   |-- syscall.s            int 0x80 (10 servicios)
|   |-- clock.s              tarea del reloj en la barra de estado
|   `-- shell.s              interprete de comandos
|-- fs/dir.s                 directorio de MiniFS (LBA 128)
`-- programs/                hola.s, contador.s (binarios planos)
```

Disco: LBA0 MBR | 1-4 stage2 | 5.. kernel | 128 directorio | 129-130 programas.

Mapa de memoria: kernel 0x10000 | pila 0x9F000 | IDT 0x100000 |
PAGE_DIR 0x101000 | PAGE_TABLES 0x102000 | PCB 0x106000 | bitmap 0x107000 |
marcos libres 0x200000-0x1000000 (2 MB a 16 MB).

---------------------------------------------------------------------------
## 3. Ruta de 300 hitos -> archivos (aproximado)

| Hitos     | Fase                        | Archivos / rutinas                                   |
|-----------|-----------------------------|------------------------------------------------------|
| 1 - 75    | Arranque                    | boot/boot.s, boot/stage2.s (GDT, CR0.PE, far jump), kernel/entry.s |
| 76 - 150  | Hardware core               | stage2.s (A20), gdt.s, pic.s, idt.s, vga.s           |
| 151 - 225 | Memoria y multitarea        | paging.s, memory.s (bitmap), process.s (PCB, switch_to) |
| 226 - 275 | Drivers                     | keyboard.s (0x60), pit.s, ata.s (0x1F0-0x1F7), fs.s  |
| 276 - 300 | Syscalls y estabilidad      | syscall.s, fs.s (exec_file), programs/, shell.s, entry.s (idle + HLT) |

---------------------------------------------------------------------------
## 4. Compilar y ejecutar

Requisitos: binutils (`as`, `ld`), `make`, `qemu-system-i386`.

```
make            # genera build/os.img
make run        # qemu-system-i386 -drive file=build/os.img,format=raw,if=ide -m 64
make debug      # QEMU con log de interrupciones/excepciones (-d int,cpu_reset -no-reboot)
make hex        # muestra los bytes reales (opcodes) del sector de arranque
make clean
```

En macOS/Windows usa un binutils cruzado: `make AS=i686-elf-as LD=i686-elf-ld`.
Importante: usa `-drive ...if=ide`; `-fda` (disquete) no sirve porque el stage2
lee por LBA con INT 13h extendido.

Comandos del shell: help, clear, mem, ps, ls, run <programa>, uptime, echo,
reboot, halt. Programas incluidos: hola.bin, contador.bin.

Syscalls (int 0x80, numero en EAX): 1 write, 2 putchar, 3 getchar, 4 exit,
5 yield, 6 ticks, 7 sleep(ms), 8 print_dec, 9 getpid.

---------------------------------------------------------------------------
## 5. Limitaciones conocidas

- Todo corre en ring 0: no hay TSS ni modo usuario (ring 3), asi que no hay
  aislamiento real entre programas.
- Solo BIOS/CSM: sin UEFI nativo, sin AHCI/NVMe, sin USB propio (el teclado
  depende de la emulacion PS/2 del BIOS).
- Consola de texto 80x25: sin modo grafico, sin raton, sin red.
- Sistema de archivos minimo (solo lectura de un directorio plano); los
  binarios son "planos", independientes de posicion, no ELF/PE/Mach-O.
- Mensajes en ASCII sin tildes (el modo texto VGA usa CP437).
- No ejecuta programas de Windows, Linux o macOS, ni tiene navegador, red ni
  suite ofimatica. Ver la hoja de ruta abajo.

---------------------------------------------------------------------------
## 6. Hoja de ruta realista hacia un escritorio

Orden sugerido (cada paso es utilizable por si solo):

1. Terminal ampliada: historial, cd/cat/write, edicion de archivos, escritura
   en MiniFS, pipes sencillos.
2. Modo grafico VESA (framebuffer lineal), fuentes bitmap, raton PS/2 y un
   gestor de ventanas basico.
3. Modo usuario (ring 3, TSS) + paginacion por proceso.
4. Cargador ELF32 y un subconjunto de syscalls de Linux (binarios estaticos).
5. Red: driver e1000/RTL8139, ARP/IP/UDP/TCP, DHCP, DNS, HTTP.
6. TLS, un motor HTML/CSS/JS y decodificacion de video: cada uno equivale a
   proyectos de cientos de miles a millones de lineas. Es el punto donde
   proyectos reales (Linux, ReactOS, Haiku) adaptan software existente en vez
   de reescribirlo.
