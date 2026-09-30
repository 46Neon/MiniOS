# =====================================================================
#  kernel/shell.s - Interprete de comandos                  [Hitos 276-300]
#  Corre como tarea y usa el sistema operativo igual que un programa de
#  usuario: toda su E/S pasa por INT 0x80.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global shell_main

.macro SYS n
    mov  eax, \n
    int  0x80
.endm
.macro PRINT label
    mov  ebx, offset \label
    mov  eax, 1
    int  0x80
.endm
.macro PUTC ch
    mov  bl, \ch
    mov  eax, 2
    int  0x80
.endm

shell_main:
    PRINT msg_welcome
shell_loop:
    PRINT msg_prompt
    mov  edi, offset line_buf
    call read_line
    mov  esi, offset line_buf
    call skip_spaces
    cmp  byte ptr [esi], 0
    je   shell_loop
    mov  ebp, offset cmd_table
sh_find:
    mov  edi, [ebp]
    test edi, edi
    jz   sh_unknown
    call match_cmd
    jz   sh_run
    add  ebp, 8
    jmp  sh_find
sh_run:
    call [ebp + 4]                   # ESI = argumentos
    jmp  shell_loop
sh_unknown:
    PRINT msg_unknown
    jmp  shell_loop

# EDI = buffer -> EAX = longitud. Edicion con Backspace, Enter finaliza.
read_line:
    push ebx
    push ecx
    xor  ecx, ecx
rl_loop:
    SYS  3                           # getchar
    cmp  al, 10
    je   rl_done
    cmp  al, 8
    je   rl_bs
    cmp  al, 32
    jb   rl_loop
    cmp  al, 126
    ja   rl_loop
    cmp  ecx, 78
    jae  rl_loop
    mov  [edi + ecx], al
    inc  ecx
    mov  bl, al
    SYS  2                           # eco del caracter
    jmp  rl_loop
rl_bs:
    test ecx, ecx
    jz   rl_loop
    dec  ecx
    PUTC 8
    jmp  rl_loop
rl_done:
    mov  byte ptr [edi + ecx], 0
    PUTC 10
    mov  eax, ecx
    pop  ecx
    pop  ebx
    ret

skip_spaces:
    cmp  byte ptr [esi], 0x20
    jne  1f
    inc  esi
    jmp  skip_spaces
1:  ret

# ESI = linea, EDI = nombre de comando. ZF=1 si coincide y entonces ESI
# queda apuntando a los argumentos. Si no coincide, ESI no cambia.
match_cmd:
    push eax
    push edx
    mov  edx, esi
mc_loop:
    mov  al, [edi]
    test al, al
    jz   mc_end_cmd
    cmp  al, [edx]
    jne  mc_no
    inc  edi
    inc  edx
    jmp  mc_loop
mc_end_cmd:
    mov  al, [edx]
    test al, al
    jz   mc_yes
    cmp  al, 0x20
    jne  mc_no
mc_yes:
    cmp  byte ptr [edx], 0x20
    jne  mc_set
    inc  edx
    jmp  mc_yes
mc_set:
    mov  esi, edx
    xor  eax, eax                    # ZF = 1
    pop  edx
    pop  eax
    ret
mc_no:
    mov  al, 1
    test al, al                      # ZF = 0
    pop  edx
    pop  eax
    ret

# ------------------------- comandos -------------------------
cmd_help:
    PRINT msg_help
    ret

cmd_clear:
    call vga_clear
    ret

cmd_mem:
    PRINT msg_mem1
    call mem_count_free
    shl  eax, 2                      # paginas -> KB
    mov  ebx, eax
    SYS  8
    PRINT msg_mem2
    mov  ebx, [mem_npages]
    shl  ebx, 2
    SYS  8
    PRINT msg_mem3
    ret

cmd_ps:
    PRINT msg_ps_head
    mov  esi, PCB_TABLE
    mov  ebp, MAX_TASKS
ps_loop:
    mov  ecx, [esi + PCB_STATE]
    test ecx, ecx
    jz   ps_next
    mov  ebx, [esi + PCB_PID]
    SYS  8
    PUTC 9
    mov  ecx, [esi + PCB_STATE]
    mov  ebx, [state_names + ecx*4]
    SYS  1
    PUTC 9
    lea  ebx, [esi + PCB_NAME]
    SYS  1
    PUTC 10
ps_next:
    add  esi, PCB_SIZE
    dec  ebp
    jnz  ps_loop
    ret

cmd_ls:
    call fs_list
    ret

cmd_run:
    cmp  byte ptr [esi], 0
    jne  run_go
    PRINT msg_run_usage
    ret
run_go:
    call exec_file
    cmp  eax, -2
    je   run_nf
    cmp  eax, -1
    je   run_err
    mov  ebp, eax
    PRINT msg_run_ok
    mov  ebx, ebp
    SYS  8
    PUTC 10
    ret
run_nf:
    PRINT msg_run_nf
    ret
run_err:
    PRINT msg_run_err
    ret

cmd_uptime:
    PRINT msg_up1
    SYS  6
    xor  edx, edx
    mov  ecx, TICKS_PER_SEC
    div  ecx
    mov  ebx, eax
    SYS  8
    PRINT msg_up2
    ret

cmd_echo:
    mov  ebx, esi
    SYS  1
    PUTC 10
    ret

cmd_reboot:
    PRINT msg_reboot
    mov  al, 0xFE                    # pulso de reset por el controlador 8042
    out  0x64, al
1:  hlt
    jmp  1b

cmd_halt:
    PRINT msg_halt
    cli
1:  hlt
    jmp  1b

.section .data
line_buf: .fill 80, 1, 0

cmd_table:
    .long s_help,   cmd_help
    .long s_clear,  cmd_clear
    .long s_mem,    cmd_mem
    .long s_ps,     cmd_ps
    .long s_ls,     cmd_ls
    .long s_run,    cmd_run
    .long s_uptime, cmd_uptime
    .long s_echo,   cmd_echo
    .long s_reboot, cmd_reboot
    .long s_halt,   cmd_halt
    .long 0, 0

s_help:   .asciz "help"
s_clear:  .asciz "clear"
s_mem:    .asciz "mem"
s_ps:     .asciz "ps"
s_ls:     .asciz "ls"
s_run:    .asciz "run"
s_uptime: .asciz "uptime"
s_echo:   .asciz "echo"
s_reboot: .asciz "reboot"
s_halt:   .asciz "halt"

state_names: .long sn_free, sn_ready, sn_sleep, sn_zombie
sn_free:   .asciz "LIBRE"
sn_ready:  .asciz "LISTO"
sn_sleep:  .asciz "DORMIDO"
sn_zombie: .asciz "ZOMBI"

msg_welcome: .asciz "MiniOS listo. Escribe 'help' para ver los comandos.\n"
msg_prompt:  .asciz "minios> "
msg_unknown: .asciz "Comando desconocido. Prueba 'help'.\n"
msg_help:
    .ascii "Comandos:\n"
    .ascii "  help           esta ayuda\n"
    .ascii "  clear          limpia la pantalla\n"
    .ascii "  mem            memoria libre\n"
    .ascii "  ps             procesos\n"
    .ascii "  ls             archivos de MiniFS\n"
    .ascii "  run <archivo>  ejecuta un binario plano (ej: run hola.bin)\n"
    .ascii "  uptime         tiempo encendido\n"
    .ascii "  echo <texto>   imprime texto\n"
    .ascii "  reboot         reinicia el equipo\n"
    .asciz "  halt           detiene el CPU\n"
msg_mem1:    .asciz "Memoria libre: "
msg_mem2:    .asciz " KB de "
msg_mem3:    .asciz " KB gestionados\n"
msg_ps_head: .asciz "PID\tESTADO\tNOMBRE\n"
msg_run_usage: .asciz "Uso: run <archivo>\n"
msg_run_ok:  .asciz "Proceso iniciado, PID "
msg_run_nf:  .asciz "Archivo no encontrado (usa 'ls').\n"
msg_run_err: .asciz "No se pudo iniciar el programa.\n"
msg_up1:     .asciz "Tiempo encendido: "
msg_up2:     .asciz " segundos\n"
msg_reboot:  .asciz "Reiniciando...\n"
msg_halt:    .asciz "CPU detenido. Ya puedes apagar el equipo.\n"
