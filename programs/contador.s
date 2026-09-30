# programs/contador.s - Cuenta de 1 a 10 durmiendo 500 ms entre numeros.
# Mientras corre, el shell sigue respondiendo (multitarea expropiativa).
.intel_syntax noprefix
.code32
.section .text
.global _start
_start:
    mov  ebp, eax                    # EBP = base de carga
    mov  esi, 1                      # contador
cnt_loop:
    lea  ebx, [ebp + msg1]
    mov  eax, 1
    int  0x80                        # write "[contador] "
    mov  ebx, esi
    mov  eax, 8
    int  0x80                        # print_dec
    lea  ebx, [ebp + msg2]
    mov  eax, 1
    int  0x80                        # write "\n"
    mov  ebx, 500
    mov  eax, 7
    int  0x80                        # sleep 500 ms
    inc  esi
    cmp  esi, 11
    jb   cnt_loop
    mov  eax, 4
    int  0x80                        # exit
msg1: .asciz "[contador] "
msg2: .asciz "\n"
.org 512
