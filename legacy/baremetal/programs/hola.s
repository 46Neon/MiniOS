# programs/hola.s - Binario plano de ejemplo. Recibe en EAX su direccion base.
.intel_syntax noprefix
.code32
.section .text
.global _start
_start:
    lea  ebx, [eax + msg]            # codigo independiente de la posicion
    mov  eax, 1                      # syscall write
    int  0x80
    mov  eax, 4                      # syscall exit
    int  0x80
msg: .asciz "Hola desde un programa binario plano cargado del disco!\n"
.org 512
