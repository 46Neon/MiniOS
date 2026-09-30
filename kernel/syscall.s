# =====================================================================
#  kernel/syscall.s - Llamadas al sistema por INT 0x80      [Hitos 276-285]
#  EAX = numero de servicio; EBX, ECX, EDX = argumentos. Resultado en EAX.
#  Todos los demas registros se preservan (PUSHAD/POPAD).
#    1 write(EBX=cadena ASCIZ)        6 ticks()  -> EAX
#    2 putchar(BL=caracter)           7 sleep(EBX=milisegundos)
#    3 getchar() -> EAX (bloquea)     8 print_dec(EBX=valor)
#    4 exit()                         9 getpid() -> EAX
#    5 yield()
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global isr_syscall

.equ SYSCALL_COUNT, 10

isr_syscall:
    pushad                           # [esp+28] = EAX guardado (valor de retorno)
    cmp  eax, SYSCALL_COUNT
    jae  sc_bad
    call [syscall_table + eax*4]
    mov  [esp + 28], eax
    popad
    iretd
sc_bad:
    mov  dword ptr [esp + 28], -1
    popad
    iretd

sys_nop:
    xor  eax, eax
    ret

sys_write:
    mov  esi, ebx
    call vga_print
    xor  eax, eax
    ret

sys_putchar:
    mov  al, bl
    call vga_putc
    xor  eax, eax
    ret

sys_getchar:
    call kb_getchar
    movzx eax, al
    ret

sys_exit:
    mov  eax, [current_pcb]
    mov  dword ptr [eax + PCB_STATE], ST_ZOMBIE
1:  call schedule
    jmp  1b                          # un zombi nunca vuelve a ser elegido

sys_yield:
    call schedule
    xor  eax, eax
    ret

sys_ticks:
    mov  eax, [ticks]
    ret

sys_sleep:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 1000 / TICKS_PER_SEC   # ms por tick = 10
    div  ecx
    inc  eax                         # al menos un tick
    add  eax, [ticks]
    mov  ecx, [current_pcb]
    mov  [ecx + PCB_WAKE], eax
    mov  dword ptr [ecx + PCB_STATE], ST_SLEEP
    call schedule
    xor  eax, eax
    ret

sys_print_dec:
    mov  eax, ebx
    call vga_print_dec
    xor  eax, eax
    ret

sys_getpid:
    mov  eax, [current_pcb]
    mov  eax, [eax + PCB_PID]
    ret

.section .data
.align 4
syscall_table:
    .long sys_nop         # 0
    .long sys_write       # 1
    .long sys_putchar     # 2
    .long sys_getchar     # 3
    .long sys_exit        # 4
    .long sys_yield       # 5
    .long sys_ticks       # 6
    .long sys_sleep       # 7
    .long sys_print_dec   # 8
    .long sys_getpid      # 9
