# =====================================================================
#  kernel/gdt.s - GDT definitiva del kernel                 [Hitos 56-75]
#  Modelo plano: base 0, limite 4 GB. Selector 0x08 = codigo, 0x10 = datos.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global gdt_init

gdt_init:
    lgdt [gdt_ptr]
    .byte 0xEA                       # JMP FAR 0008:1f  (recarga CS)
    .long 1f
    .word 0x0008
1:  mov  ax, 0x10                    # recargar DS, ES, FS, GS, SS
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax
    ret

.section .data
.align 8
gdt_start:
    .quad 0x0000000000000000         # 0x00 descriptor nulo
    .word 0xFFFF, 0x0000             # 0x08 codigo: P=1 DPL=0 S=1 tipo=A (exec/read)
    .byte 0x00, 0x9A, 0xCF, 0x00     #      G=1 D=1 -> paginas de 4 KB, 32 bits
    .word 0xFFFF, 0x0000             # 0x10 datos : P=1 DPL=0 S=1 tipo=2 (read/write)
    .byte 0x00, 0x92, 0xCF, 0x00
gdt_end:
gdt_ptr:
    .word gdt_end - gdt_start - 1
    .long gdt_start
