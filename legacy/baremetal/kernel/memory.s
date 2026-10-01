# =====================================================================
#  kernel/memory.s - Gestor de marcos fisicos con bitmap    [Hitos 171-190]
#  Administra paginas de 4 KB entre FRAME_BASE (2 MB) y el menor entre la RAM
#  detectada y FRAME_LIMIT (16 MB). Bit = 1 -> marco ocupado.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global mem_init, mem_alloc_page, mem_alloc_pages
.global mem_free_page, mem_free_pages, mem_count_free, mem_npages

mem_init:
    push eax
    push ecx
    push edi
    cld
    mov  eax, [MEM_KB_ADDR]          # KB sobre 1 MB
    shl  eax, 10
    add  eax, 0x100000               # tope de RAM
    cmp  eax, FRAME_LIMIT
    jbe  1f
    mov  eax, FRAME_LIMIT
1:  cmp  eax, FRAME_BASE
    jae  2f
    xor  eax, eax
    jmp  3f
2:  sub  eax, FRAME_BASE
3:  shr  eax, 12                     # bytes -> paginas
    mov  [mem_npages], eax
    mov  edi, MEM_BITMAP
    xor  eax, eax
    mov  ecx, 128                    # 512 bytes de bitmap
    rep  stosd
    pop  edi
    pop  ecx
    pop  eax
    ret

# Salida: EAX = direccion fisica de una pagina libre, o 0
mem_alloc_page:
    push ecx
    pushfd
    cli
    xor  ecx, ecx
1:  cmp  ecx, [mem_npages]
    jae  3f
    bts  [MEM_BITMAP], ecx           # CF = valor anterior del bit
    jnc  2f
    inc  ecx
    jmp  1b
2:  mov  eax, ecx
    shl  eax, 12
    add  eax, FRAME_BASE
    jmp  4f
3:  xor  eax, eax
4:  popfd
    pop  ecx
    ret

# Entrada: ECX = n paginas contiguas. Salida: EAX = direccion fisica o 0
mem_alloc_pages:
    push ebx
    push edx
    push esi
    push edi
    pushfd
    cli
    test ecx, ecx
    jz   9f
    mov  edi, ecx                    # EDI = n
    xor  esi, esi                    # ESI = indice candidato
1:  mov  eax, esi
    add  eax, edi
    cmp  eax, [mem_npages]
    ja   9f                          # ya no caben n paginas
    xor  edx, edx
2:  lea  ebx, [esi + edx]
    bt   [MEM_BITMAP], ebx
    jc   3f                          # ocupado: reiniciar tras este bit
    inc  edx
    cmp  edx, edi
    jb   2b
    xor  edx, edx                    # encontrado: marcar n bits
4:  lea  ebx, [esi + edx]
    bts  [MEM_BITMAP], ebx
    inc  edx
    cmp  edx, edi
    jb   4b
    mov  eax, esi
    shl  eax, 12
    add  eax, FRAME_BASE
    jmp  8f
3:  lea  esi, [ebx + 1]
    jmp  1b
9:  xor  eax, eax
8:  popfd
    pop  edi
    pop  esi
    pop  edx
    pop  ebx
    ret

# Entrada: EAX = direccion fisica de la pagina
mem_free_page:
    push eax
    pushfd
    cli
    cmp  eax, FRAME_BASE
    jb   1f
    sub  eax, FRAME_BASE
    shr  eax, 12
    btr  [MEM_BITMAP], eax
1:  popfd
    pop  eax
    ret

# Entrada: EAX = direccion fisica, ECX = n paginas
mem_free_pages:
    push eax
    push ecx
    pushfd
    cli
    cmp  eax, FRAME_BASE
    jb   2f
    sub  eax, FRAME_BASE
    shr  eax, 12
1:  test ecx, ecx
    jz   2f
    btr  [MEM_BITMAP], eax
    inc  eax
    dec  ecx
    jmp  1b
2:  popfd
    pop  ecx
    pop  eax
    ret

# Salida: EAX = cantidad de paginas libres
mem_count_free:
    push ecx
    xor  eax, eax
    xor  ecx, ecx
1:  cmp  ecx, [mem_npages]
    jae  3f
    bt   [MEM_BITMAP], ecx
    jc   2f
    inc  eax
2:  inc  ecx
    jmp  1b
3:  pop  ecx
    ret

.section .data
mem_npages: .long 0
