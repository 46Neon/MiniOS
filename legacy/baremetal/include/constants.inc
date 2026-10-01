# =====================================================================
#  include/constants.inc - Constantes globales de MiniOS
#  Mapa de memoria fisica, estructura del PCB y parametros de hardware.
# =====================================================================

# ---- Disco (MiniOS usa direccionamiento LBA) ----
.equ KERNEL_LBA,       5            # LBA0 = MBR, LBA1-4 = stage2, LBA5.. = kernel
.equ FS_DIR_LBA,       128          # sector del directorio MiniFS

# ---- Mapa de memoria fisica ----
.equ BOOT_DRIVE_ADDR,  0x00000500   # byte : unidad de arranque (la escribe stage2)
.equ MEM_KB_ADDR,      0x00000504   # dword: KB de RAM sobre 1 MB (INT 15h/88h)
.equ STAGE2_BASE,      0x00008000   # stage2 (16 bits)
.equ KERNEL_BASE,      0x00010000   # kernel plano (32 bits)
.equ KSTACK_TOP,       0x0009F000   # pila inicial del kernel (= pila de idle)
.equ VGA_BASE,         0x000B8000   # buffer de texto VGA
.equ IDT_BASE,         0x00100000   # 256 entradas * 8 bytes = 2 KB
.equ PAGE_DIR,         0x00101000   # directorio de paginas (4 KB)
.equ PAGE_TABLES,      0x00102000   # 4 tablas de paginas = 16 MB (16 KB)
.equ PCB_TABLE,        0x00106000   # tabla de PCB
.equ MEM_BITMAP,       0x00107000   # bitmap de marcos fisicos
.equ FRAME_BASE,       0x00200000   # el gestor de memoria administra desde 2 MB
.equ FRAME_LIMIT,      0x01000000   # ... hasta 16 MB

# ---- VGA texto 80x25 (fila 0 = barra de estado) ----
.equ VGA_COLS,         80
.equ VGA_ROWS,         25

# ---- Procesos ----
.equ MAX_TASKS,        8
.equ PCB_SIZE,         64
.equ PCB_STATE,        0            # dword: estado
.equ PCB_ESP,          4            # dword: ESP del kernel guardado
.equ PCB_PID,          8            # dword: identificador
.equ PCB_STACK,        12           # dword: pagina de pila asignada
.equ PCB_WAKE,         16           # dword: tick en que despierta (dormido)
.equ PCB_ARG,          20           # dword: argumento (base de carga del programa)
.equ PCB_IMGN,         24           # dword: paginas de imagen a liberar al terminar
.equ PCB_NAME,         28           # 16 bytes: nombre ASCIZ

.equ ST_FREE,          0
.equ ST_READY,         1
.equ ST_SLEEP,         2
.equ ST_ZOMBIE,        3

# ---- Temporizador ----
.equ PIT_DIVISOR,      11931        # 1193182 Hz / 11931 = ~100 Hz
.equ TICKS_PER_SEC,    100
