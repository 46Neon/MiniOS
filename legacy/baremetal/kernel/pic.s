# =====================================================================
#  kernel/pic.s - Controlador de interrupciones 8259 (PIC)  [Hitos 91-110]
#  Remapea IRQ0-7 -> vectores 0x20-0x27 e IRQ8-15 -> 0x28-0x2F y
#  enmascara todas las IRQ. pic_unmask habilita una IRQ concreta.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global pic_init, pic_unmask

pic_init:
    push eax
    mov  al, 0x11                    # ICW1: inicializacion + espera ICW4
    out  0x20, al
    out  0x80, al                    # pequena espera de E/S
    out  0xA0, al
    out  0x80, al
    mov  al, 0x20                    # ICW2: desplazamiento maestro = 0x20
    out  0x21, al
    out  0x80, al
    mov  al, 0x28                    # ICW2: desplazamiento esclavo = 0x28
    out  0xA1, al
    out  0x80, al
    mov  al, 0x04                    # ICW3: esclavo en IRQ2 del maestro
    out  0x21, al
    out  0x80, al
    mov  al, 0x02                    # ICW3: identidad en cascada del esclavo
    out  0xA1, al
    out  0x80, al
    mov  al, 0x01                    # ICW4: modo 8086
    out  0x21, al
    out  0x80, al
    out  0xA1, al
    out  0x80, al
    mov  al, 0xFF                    # OCW1: enmascarar todas las IRQ
    out  0x21, al
    out  0xA1, al
    pop  eax
    ret

# EAX = numero de IRQ (0-15) a habilitar
pic_unmask:
    push eax
    push ecx
    push edx
    mov  ecx, eax
    mov  dx, 0x21
    cmp  ecx, 8
    jb   1f
    mov  dx, 0xA1
    sub  ecx, 8
1:  mov  ah, 1
    shl  ah, cl
    not  ah
    in   al, dx
    and  al, ah
    out  dx, al
    pop  edx
    pop  ecx
    pop  eax
    ret
