# =====================================================================
#  kernel/keyboard.s - Teclado PS/2 (puertos 0x60/0x64, IRQ1) [Hitos 226-240]
#  Scancodes set 1 -> ASCII (disposicion US), Shift, Bloq Mayus y buffer
#  circular de 256 bytes. kb_getchar bloquea con HLT (bajo consumo).
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global kb_init, keyboard_handler, kb_getchar

kb_init:
    mov  dword ptr [kb_head], 0
    mov  dword ptr [kb_tail], 0
    mov  byte ptr [kb_shift], 0
    mov  byte ptr [kb_caps], 0
    mov  byte ptr [kb_ext], 0
    in   al, 0x60                    # vaciar cualquier byte pendiente
    ret

# IRQ1. Los registros ya fueron guardados por irq_common.
keyboard_handler:
    in   al, 0x60
    cmp  al, 0xE0                    # prefijo de tecla extendida: ignorar
    jne  1f
    mov  byte ptr [kb_ext], 1
    ret
1:  cmp  byte ptr [kb_ext], 0
    je   2f
    mov  byte ptr [kb_ext], 0
    ret
2:  test al, 0x80                    # bit 7 = tecla soltada
    jnz  kbh_release
    cmp  al, 0x2A                    # Shift izquierdo
    je   kbh_shift_on
    cmp  al, 0x36                    # Shift derecho
    je   kbh_shift_on
    cmp  al, 0x3A                    # Bloq Mayus
    je   kbh_caps
    cmp  al, 0x39
    ja   kbh_ignore
    movzx ebx, al
    cmp  byte ptr [kb_shift], 0
    jne  kbh_use_shift
    mov  al, [scan_normal + ebx]
    jmp  kbh_got
kbh_use_shift:
    mov  al, [scan_shift + ebx]
kbh_got:
    test al, al
    jz   kbh_ignore
    cmp  byte ptr [kb_caps], 0
    je   kbh_store
    mov  ah, al                      # Bloq Mayus invierte solo las letras
    or   ah, 0x20
    cmp  ah, 0x61
    jb   kbh_store
    cmp  ah, 0x7A
    ja   kbh_store
    xor  al, 0x20
kbh_store:
    mov  ebx, [kb_head]
    mov  [kb_buf + ebx], al
    inc  ebx
    and  ebx, 255
    cmp  ebx, [kb_tail]
    je   kbh_ignore                  # buffer lleno: descartar
    mov  [kb_head], ebx
kbh_ignore:
    ret
kbh_shift_on:
    mov  byte ptr [kb_shift], 1
    ret
kbh_caps:
    xor  byte ptr [kb_caps], 1
    ret
kbh_release:
    and  al, 0x7F
    cmp  al, 0x2A
    je   kbh_shift_off
    cmp  al, 0x36
    je   kbh_shift_off
    ret
kbh_shift_off:
    mov  byte ptr [kb_shift], 0
    ret

# Salida: AL = caracter (bloquea hasta que haya uno). Conserva EBX.
kb_getchar:
    push ebx
1:  mov  ebx, [kb_tail]
    cmp  ebx, [kb_head]
    jne  2f
    sti                              # esperar interrupcion con el CPU dormido
    hlt
    jmp  1b
2:  movzx eax, byte ptr [kb_buf + ebx]
    inc  ebx
    and  ebx, 255
    mov  [kb_tail], ebx
    pop  ebx
    ret

.section .data
kb_head:  .long 0
kb_tail:  .long 0
kb_shift: .byte 0
kb_caps:  .byte 0
kb_ext:   .byte 0
kb_buf:   .fill 256, 1, 0

# Indice = scancode (0x00..0x39)
scan_normal:
    .byte 0, 27
    .ascii "1234567890-="
    .byte 8, 9
    .ascii "qwertyuiop[]"
    .byte 10, 0
    .ascii "asdfghjkl;'`"
    .byte 0
    .ascii "\\zxcvbnm,./"
    .byte 0
    .ascii "*"
    .byte 0
    .ascii " "
scan_shift:
    .byte 0, 27
    .ascii "!@#$%^&*()_+"
    .byte 8, 9
    .ascii "QWERTYUIOP{}"
    .byte 10, 0
    .ascii "ASDFGHJKL:\"~"
    .byte 0
    .ascii "|ZXCVBNM<>?"
    .byte 0
    .ascii "*"
    .byte 0
    .ascii " "
