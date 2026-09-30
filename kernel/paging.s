# =====================================================================
#  kernel/paging.s - Paginacion x86 de 2 niveles           [Hitos 151-170]
#  Mapeo identidad (virtual = fisica) de los primeros 16 MB con paginas de
#  4 KB: 1 directorio + 4 tablas. La pagina 0 queda NO presente para atrapar
#  punteros nulos (genera #PF).
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global paging_init

paging_init:
    push eax
    push ecx
    push edi
    cld
    # 4 tablas * 1024 entradas: entrada i -> direccion i*4096, P=1 RW=1
    mov  edi, PAGE_TABLES
    mov  eax, 0x00000003
    mov  ecx, 4096
1:  mov  [edi], eax
    add  edi, 4
    add  eax, 0x1000
    loop 1b
    mov  dword ptr [PAGE_TABLES], 0  # pagina 0 no presente
    # directorio: limpiar 1024 entradas
    mov  edi, PAGE_DIR
    xor  eax, eax
    mov  ecx, 1024
    rep  stosd
    # primeras 4 entradas del directorio -> las 4 tablas
    mov  edi, PAGE_DIR
    mov  eax, PAGE_TABLES + 3
    mov  ecx, 4
2:  mov  [edi], eax
    add  edi, 4
    add  eax, 0x1000
    loop 2b
    mov  eax, PAGE_DIR
    mov  cr3, eax                    # base del directorio
    mov  eax, cr0
    or   eax, 0x80000000             # CR0.PG = 1
    mov  cr0, eax
    pop  edi
    pop  ecx
    pop  eax
    ret
