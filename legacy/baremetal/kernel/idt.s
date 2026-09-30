# =====================================================================
#  kernel/idt.s - IDT, excepciones del CPU e IRQ de hardware [Hitos 111-130]
#  - Vectores 0-31 : excepciones (muestran diagnostico y detienen el CPU)
#  - Vectores 32-47: IRQ0-15 (via irq_common -> tabla irq_handlers)
#  - Vector 0x80   : llamadas al sistema (isr_syscall, en syscall.s)
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global idt_init

# EAX = vector, EBX = direccion del manejador, DL = atributos (0x8E / 0xEE)
idt_set_gate:
    pushad
    lea  edi, [IDT_BASE + eax*8]
    mov  word ptr [edi], bx          # offset bits 0-15
    mov  word ptr [edi+2], 0x0008    # selector de codigo del kernel
    mov  byte ptr [edi+4], 0
    mov  byte ptr [edi+5], dl        # P=1, DPL, tipo 0xE = interrupt gate 32 bits
    shr  ebx, 16
    mov  word ptr [edi+6], bx        # offset bits 16-31
    popad
    ret

idt_init:
    pushad
    cld
    mov  edi, IDT_BASE               # limpiar las 256 entradas
    xor  eax, eax
    mov  ecx, 512
    rep  stosd
    mov  dl, 0x8E                    # compuerta de interrupcion, ring 0
    xor  ecx, ecx
1:  mov  eax, ecx
    mov  ebx, [isr_table + ecx*4]
    call idt_set_gate
    inc  ecx
    cmp  ecx, 32
    jb   1b
    xor  ecx, ecx
2:  lea  eax, [ecx + 0x20]
    mov  ebx, [irq_table + ecx*4]
    call idt_set_gate
    inc  ecx
    cmp  ecx, 16
    jb   2b
    mov  eax, 0x80                   # int 0x80: DPL=3 (preparado para ring 3)
    mov  ebx, offset isr_syscall
    mov  dl, 0xEE
    call idt_set_gate
    lidt [idt_ptr]
    popad
    ret

# ---------------------------------------------------------------------
# Stubs de excepciones: el CPU empuja codigo de error solo en 8,10-14,17,30
# ---------------------------------------------------------------------
.macro ISR_NOERR n
isr\n:
    push 0                           # codigo de error falso
    push \n
    jmp  exc_common
.endm
.macro ISR_ERR n
isr\n:
    push \n
    jmp  exc_common
.endm

ISR_NOERR 0
ISR_NOERR 1
ISR_NOERR 2
ISR_NOERR 3
ISR_NOERR 4
ISR_NOERR 5
ISR_NOERR 6
ISR_NOERR 7
ISR_ERR   8
ISR_NOERR 9
ISR_ERR   10
ISR_ERR   11
ISR_ERR   12
ISR_ERR   13
ISR_ERR   14
ISR_NOERR 15
ISR_NOERR 16
ISR_ERR   17
ISR_NOERR 18
ISR_NOERR 19
ISR_NOERR 20
ISR_NOERR 21
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28
ISR_NOERR 29
ISR_ERR   30
ISR_NOERR 31

# Pila al entrar: [esp]=vector [esp+4]=error [esp+8]=EIP [esp+12]=CS [esp+16]=EFLAGS
exc_common:
    cli
    mov  al, 0x4F                    # blanco sobre rojo
    call vga_set_color
    mov  esi, offset msg_exc
    call vga_print
    mov  eax, [esp]
    call vga_print_dec
    mov  al, 0x20
    call vga_putc
    mov  eax, [esp]
    mov  esi, [exc_names + eax*4]
    call vga_print
    mov  esi, offset msg_err
    call vga_print
    mov  eax, [esp+4]
    call vga_print_hex
    mov  esi, offset msg_eip
    call vga_print
    mov  eax, [esp+8]
    call vga_print_hex
    mov  esi, offset msg_cs
    call vga_print
    mov  eax, [esp+12]
    call vga_print_hex
    mov  esi, offset msg_efl
    call vga_print
    mov  eax, [esp+16]
    call vga_print_hex
    cmp  dword ptr [esp], 14         # fallo de pagina: mostrar CR2
    jne  1f
    mov  esi, offset msg_cr2
    call vga_print
    mov  eax, cr2
    call vga_print_hex
1:  mov  esi, offset msg_halt
    call vga_print
2:  cli
    hlt
    jmp  2b

# ---------------------------------------------------------------------
# Stubs de IRQ: empujan el numero de IRQ y saltan al despachador comun
# ---------------------------------------------------------------------
.macro IRQ_STUB n
irq\n:
    push \n
    jmp  irq_common
.endm

IRQ_STUB 0
IRQ_STUB 1
IRQ_STUB 2
IRQ_STUB 3
IRQ_STUB 4
IRQ_STUB 5
IRQ_STUB 6
IRQ_STUB 7
IRQ_STUB 8
IRQ_STUB 9
IRQ_STUB 10
IRQ_STUB 11
IRQ_STUB 12
IRQ_STUB 13
IRQ_STUB 14
IRQ_STUB 15

# Pila: [esp+32] = numero de IRQ (tras PUSHAD). El EOI se envia ANTES de
# llamar al manejador, porque el manejador del timer puede cambiar de tarea.
irq_common:
    pushad
    mov  ebx, [esp+32]
    mov  al, 0x20
    cmp  ebx, 8
    jb   1f
    out  0xA0, al                    # EOI al PIC esclavo
1:  out  0x20, al                    # EOI al PIC maestro
    mov  eax, [irq_handlers + ebx*4]
    test eax, eax
    jz   2f
    call eax                         # el manejador puede alterar cualquier registro
2:  popad
    add  esp, 4                      # descartar numero de IRQ
    iretd

.section .data
.align 4
isr_table:
    .long isr0,  isr1,  isr2,  isr3,  isr4,  isr5,  isr6,  isr7
    .long isr8,  isr9,  isr10, isr11, isr12, isr13, isr14, isr15
    .long isr16, isr17, isr18, isr19, isr20, isr21, isr22, isr23
    .long isr24, isr25, isr26, isr27, isr28, isr29, isr30, isr31
irq_table:
    .long irq0,  irq1,  irq2,  irq3,  irq4,  irq5,  irq6,  irq7
    .long irq8,  irq9,  irq10, irq11, irq12, irq13, irq14, irq15
irq_handlers:                        # IRQ0 = timer, IRQ1 = teclado
    .long pit_handler, keyboard_handler, 0, 0, 0, 0, 0, 0
    .long 0, 0, 0, 0, 0, 0, 0, 0
idt_ptr:
    .word 256*8 - 1
    .long IDT_BASE

exc_names:
    .long n0,  n1,  n2,  n3,  n4,  n5,  n6,  n7
    .long n8,  n9,  n10, n11, n12, n13, n14, n15
    .long n16, n17, n18, n19, nres, nres, nres, nres
    .long nres, nres, nres, nres, nres, nres, n30, nres
n0:   .asciz "Division por cero"
n1:   .asciz "Debug"
n2:   .asciz "Interrupcion no enmascarable"
n3:   .asciz "Breakpoint"
n4:   .asciz "Desbordamiento (INTO)"
n5:   .asciz "Limite de rango (BOUND)"
n6:   .asciz "Opcode invalido"
n7:   .asciz "Dispositivo no disponible (FPU)"
n8:   .asciz "Doble falta"
n9:   .asciz "Segmento de coprocesador"
n10:  .asciz "TSS invalido"
n11:  .asciz "Segmento no presente"
n12:  .asciz "Falla de segmento de pila"
n13:  .asciz "Proteccion general (GPF)"
n14:  .asciz "Fallo de pagina"
n15:  .asciz "Reservada"
n16:  .asciz "Error de FPU x87"
n17:  .asciz "Comprobacion de alineacion"
n18:  .asciz "Machine check"
n19:  .asciz "Excepcion SIMD"
n30:  .asciz "Seguridad"
nres: .asciz "Reservada"

msg_exc:  .asciz "\n*** EXCEPCION #"
msg_err:  .asciz "\n ERR="
msg_eip:  .asciz "  EIP="
msg_cs:   .asciz "  CS="
msg_efl:  .asciz "  EFLAGS="
msg_cr2:  .asciz "\n CR2="
msg_halt: .asciz "\n Sistema detenido.\n"
