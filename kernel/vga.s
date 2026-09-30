# =====================================================================
#  kernel/vga.s - Salida de texto VGA (0xB8000, 80x25)     [Hitos 131-150]
#  Fila 0 = barra de estado fija. Filas 1-24 = consola con scroll.
#  Todas las rutinas preservan todos los registros salvo indicacion.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global vga_init, vga_clear, vga_putc, vga_print, vga_print_hex, vga_print_dec
.global vga_set_color, vga_draw_str, vga_draw_dec

# Dibuja la barra de estado y limpia la consola
vga_init:
    pushad
    cld
    mov  byte ptr [vga_attr], 0x07
    mov  edi, VGA_BASE
    mov  ax, 0x1F20                  # espacio blanco sobre azul
    mov  ecx, VGA_COLS
    rep  stosw
    mov  esi, offset str_title
    mov  edi, VGA_BASE + 2
    mov  bl, 0x1F
    call vga_draw_str
    call vga_clear
    popad
    ret

# Limpia filas 1..24 y coloca el cursor en (1,0)
vga_clear:
    pushad
    cld
    mov  edi, VGA_BASE + VGA_COLS*2
    movzx eax, byte ptr [vga_attr]
    shl  eax, 8
    or   eax, 0x20
    mov  ecx, VGA_COLS*(VGA_ROWS-1)
    rep  stosw
    mov  dword ptr [vga_row], 1
    mov  dword ptr [vga_col], 0
    call vga_update_cursor
    popad
    ret

# AL = caracter. Maneja \n (10), \r (13), backspace (8) y tab (9)
vga_putc:
    pushfd
    cli                              # protege fila/columna ante multitarea
    pushad
    cmp  al, 10
    je   vp_newline
    cmp  al, 13
    je   vp_cr
    cmp  al, 8
    je   vp_bs
    cmp  al, 9
    je   vp_tab
    movzx edx, al
    call vga_offset                  # EDI = direccion de la celda actual
    movzx eax, byte ptr [vga_attr]
    shl  eax, 8
    or   eax, edx
    mov  [edi], ax
    inc  dword ptr [vga_col]
    cmp  dword ptr [vga_col], VGA_COLS
    jb   vp_done
vp_newline:
    mov  dword ptr [vga_col], 0
    inc  dword ptr [vga_row]
    cmp  dword ptr [vga_row], VGA_ROWS
    jb   vp_done
    call vga_scroll
    mov  dword ptr [vga_row], VGA_ROWS-1
    jmp  vp_done
vp_cr:
    mov  dword ptr [vga_col], 0
    jmp  vp_done
vp_bs:
    cmp  dword ptr [vga_col], 0
    je   vp_done
    dec  dword ptr [vga_col]
    call vga_offset
    movzx eax, byte ptr [vga_attr]
    shl  eax, 8
    or   eax, 0x20
    mov  [edi], ax
    jmp  vp_done
vp_tab:
    mov  eax, [vga_col]
    add  eax, 8
    and  eax, 0xFFFFFFF8
    mov  [vga_col], eax
    cmp  eax, VGA_COLS
    jae  vp_newline
vp_done:
    call vga_update_cursor
    popad
    popfd
    ret

# EDI = VGA_BASE + (fila*80 + columna)*2
vga_offset:
    push eax
    mov  eax, [vga_row]
    imul eax, VGA_COLS
    add  eax, [vga_col]
    lea  edi, [VGA_BASE + eax*2]
    pop  eax
    ret

# Sube filas 2..24 a 1..23 y limpia la fila 24
vga_scroll:
    pushad
    cld
    mov  esi, VGA_BASE + VGA_COLS*4
    mov  edi, VGA_BASE + VGA_COLS*2
    mov  ecx, VGA_COLS*(VGA_ROWS-2)*2/4
    rep  movsd
    movzx eax, byte ptr [vga_attr]
    shl  eax, 8
    or   eax, 0x20
    mov  edi, VGA_BASE + VGA_COLS*(VGA_ROWS-1)*2
    mov  ecx, VGA_COLS
    rep  stosw
    popad
    ret

# Mueve el cursor de hardware (puertos CRTC 0x3D4/0x3D5)
vga_update_cursor:
    push eax
    push ebx
    push edx
    mov  eax, [vga_row]
    imul eax, VGA_COLS
    add  eax, [vga_col]
    mov  ebx, eax
    mov  dx, 0x3D4
    mov  al, 0x0F
    out  dx, al
    inc  dx
    mov  al, bl
    out  dx, al
    dec  dx
    mov  al, 0x0E
    out  dx, al
    inc  dx
    mov  al, bh
    out  dx, al
    pop  edx
    pop  ebx
    pop  eax
    ret

# ESI = cadena ASCIZ
vga_print:
    push eax
    push esi
1:  mov  al, [esi]
    test al, al
    jz   2f
    call vga_putc
    inc  esi
    jmp  1b
2:  pop  esi
    pop  eax
    ret

# EAX = valor -> imprime "0x" + 8 digitos hexadecimales
vga_print_hex:
    push eax
    push ebx
    push ecx
    mov  ebx, eax
    mov  al, 0x30
    call vga_putc
    mov  al, 0x78
    call vga_putc
    mov  ecx, 8
1:  rol  ebx, 4
    mov  eax, ebx
    and  eax, 0x0F
    mov  al, [hex_digits + eax]
    call vga_putc
    loop 1b
    pop  ecx
    pop  ebx
    pop  eax
    ret

# EAX = valor sin signo -> decimal
vga_print_dec:
    push eax
    push ebx
    push ecx
    push edx
    mov  ebx, 10
    xor  ecx, ecx
1:  xor  edx, edx
    div  ebx
    add  edx, 0x30
    push edx
    inc  ecx
    test eax, eax
    jnz  1b
2:  pop  eax
    call vga_putc
    loop 2b
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

# AL = atributo de color para la consola
vga_set_color:
    mov  [vga_attr], al
    ret

# ESI = cadena, EDI = direccion VGA, BL = atributo. Avanza ESI y EDI.
vga_draw_str:
    push eax
    mov  ah, bl
1:  mov  al, [esi]
    test al, al
    jz   2f
    mov  [edi], ax
    add  edi, 2
    inc  esi
    jmp  1b
2:  pop  eax
    ret

# EAX = valor, EDI = direccion VGA, BL = atributo. Avanza EDI; deja 2 espacios.
vga_draw_dec:
    push eax
    push ecx
    push edx
    push esi
    mov  esi, 10
    xor  ecx, ecx
1:  xor  edx, edx
    div  esi
    add  edx, 0x30
    push edx
    inc  ecx
    test eax, eax
    jnz  1b
2:  pop  eax
    mov  ah, bl
    mov  [edi], ax
    add  edi, 2
    loop 2b
    mov  al, 0x20
    mov  ah, bl
    mov  [edi], ax
    mov  [edi+2], ax
    pop  esi
    pop  edx
    pop  ecx
    pop  eax
    ret

.section .data
vga_row:    .long 1
vga_col:    .long 0
vga_attr:   .byte 0x07
hex_digits: .ascii "0123456789ABCDEF"
str_title:  .asciz "MiniOS x86 - modo protegido de 32 bits"
