# =====================================================================
#  kernel/clock.s - Tarea "reloj": demuestra multitarea expropiativa
#  Actualiza el tiempo encendido y un indicador giratorio en la barra de
#  estado (fila 0) cuatro veces por segundo, durmiendo con la syscall 7.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global clock_main

clock_main:
ck_loop:
    mov  edi, VGA_BASE + (VGA_COLS-30)*2
    mov  esi, offset str_uptime
    mov  bl, 0x1F                    # blanco sobre azul
    call vga_draw_str
    mov  eax, [ticks]
    xor  edx, edx
    mov  ecx, TICKS_PER_SEC
    div  ecx                         # EAX = segundos encendido
    call vga_draw_dec
    mov  eax, [spin_idx]             # indicador giratorio | / - \
    inc  eax
    and  eax, 3
    mov  [spin_idx], eax
    mov  al, [spin_chars + eax]
    mov  ah, 0x1E                    # amarillo sobre azul
    mov  [VGA_BASE + (VGA_COLS-2)*2], ax
    mov  ebx, 250                    # dormir 250 ms
    mov  eax, 7
    int  0x80
    jmp  ck_loop

.section .data
spin_idx:   .long 0
spin_chars: .ascii "|/-\\"
str_uptime: .asciz "Tiempo: "
