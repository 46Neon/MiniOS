BITS 32
GLOBAL _start
EXTERN kernel_main

SECTION .text
_start:
    cli
    cld
    mov esp, 0x0009F000
    xor ebp, ebp
    push eax                    ; stage2 passes physical boot_info in EAX
    call kernel_main
.hang:
    cli
    hlt
    jmp .hang
