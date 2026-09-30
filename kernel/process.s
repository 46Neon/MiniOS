# =====================================================================
#  kernel/process.s - Procesos, planificador y cambio de contexto
#  [Hitos 191-225]  PCB de 64 bytes (ver constants.inc), round-robin.
#  Cada tarea tiene su propia pila de kernel de 4 KB (una pagina del bitmap).
#  Cambio de contexto: se guardan EBP/EBX/ESI/EDI y se intercambia ESP.
#  (Las demas registros ya los guarda PUSHAD en la entrada de la interrupcion.)
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global process_init, task_create, schedule, current_pcb, task_exit

# La PCB 0 es la tarea "idle": el propio contexto de arranque del kernel
process_init:
    pushad
    cld
    mov  edi, PCB_TABLE
    xor  eax, eax
    mov  ecx, MAX_TASKS*PCB_SIZE/4
    rep  stosd
    mov  edi, PCB_TABLE
    mov  dword ptr [edi + PCB_STATE], ST_READY
    mov  dword ptr [edi + PCB_PID], 0
    mov  dword ptr [edi + PCB_NAME], 0x656C6469      # "idle"
    mov  [current_pcb], edi
    mov  dword ptr [next_pid], 1
    popad
    ret

# Entrada: EAX = punto de entrada, EBX = argumento (llega en EAX a la tarea),
#          ECX = paginas de imagen a liberar al terminar (0 si no aplica),
#          ESI = nombre ASCIZ (max 15 caracteres)
# Salida : EAX = PID, o -1 si no hay espacio/memoria
task_create:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    pushfd
    cli
    mov  ebp, eax                    # EBP = entrada
    mov  edx, ebx                    # EDX = argumento
    mov  ebx, ecx                    # EBX = paginas de imagen
    mov  edi, PCB_TABLE + PCB_SIZE   # buscar ranura libre (la 0 es idle)
    mov  ecx, MAX_TASKS - 1
1:  mov  eax, [edi + PCB_STATE]
    cmp  eax, ST_FREE
    je   3f
    cmp  eax, ST_ZOMBIE
    je   2f
    add  edi, PCB_SIZE
    dec  ecx
    jnz  1b
    jmp  tc_fail
2:  mov  eax, [edi + PCB_STACK]      # reciclar ranura zombi: liberar sus recursos
    call mem_free_page
    mov  ecx, [edi + PCB_IMGN]
    test ecx, ecx
    jz   3f
    mov  eax, [edi + PCB_ARG]
    call mem_free_pages
3:  call mem_alloc_page              # pila de 4 KB para la nueva tarea
    test eax, eax
    jz   tc_fail
    mov  [edi + PCB_STACK], eax
    add  eax, 4096
    sub  eax, 20                     # marco inicial: EDI ESI EBX EBP RET
    mov  dword ptr [eax], 0          # EDI
    mov  dword ptr [eax + 4], 0      # ESI
    mov  [eax + 8], ebp              # EBX = punto de entrada
    mov  dword ptr [eax + 12], 0     # EBP
    mov  dword ptr [eax + 16], offset task_start
    mov  [edi + PCB_ESP], eax
    mov  [edi + PCB_ARG], edx
    mov  [edi + PCB_IMGN], ebx
    mov  eax, [next_pid]
    mov  [edi + PCB_PID], eax
    inc  dword ptr [next_pid]
    xor  ecx, ecx                    # copiar nombre
4:  mov  al, [esi + ecx]
    mov  [edi + PCB_NAME + ecx], al
    test al, al
    jz   5f
    inc  ecx
    cmp  ecx, 15
    jb   4b
    mov  byte ptr [edi + PCB_NAME + 15], 0
5:  mov  dword ptr [edi + PCB_WAKE], 0
    mov  dword ptr [edi + PCB_STATE], ST_READY   # ultimo: la tarea ya es valida
    mov  eax, [edi + PCB_PID]
    jmp  tc_done
tc_fail:
    mov  eax, -1
tc_done:
    popfd
    pop  ebp
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret

# Primer codigo que ejecuta una tarea nueva (EBX = entrada). Llega con IF=0.
task_start:
    sti
    mov  eax, [current_pcb]
    mov  eax, [eax + PCB_ARG]        # argumento -> EAX
    call ebx
task_exit:                           # la tarea termino (ret o syscall exit)
    mov  eax, [current_pcb]
    mov  dword ptr [eax + PCB_STATE], ST_ZOMBIE
1:  call schedule
    hlt
    jmp  1b

# Planificador round-robin. Se invoca con IF=0 (IRQ0, syscalls).
schedule:
    push esi
    push edi
    mov  esi, [current_pcb]
    mov  edi, esi
sch_next:
    add  edi, PCB_SIZE
    cmp  edi, PCB_TABLE + MAX_TASKS*PCB_SIZE
    jb   sch_check
    mov  edi, PCB_TABLE
sch_check:
    mov  eax, [edi + PCB_STATE]
    cmp  eax, ST_SLEEP
    jne  sch_notsleep
    mov  ecx, [ticks]
    cmp  ecx, [edi + PCB_WAKE]
    jb   sch_skip                    # aun no le toca despertar
    mov  dword ptr [edi + PCB_STATE], ST_READY
    mov  eax, ST_READY
sch_notsleep:
    cmp  eax, ST_READY
    je   sch_found
sch_skip:
    cmp  edi, esi
    jne  sch_next
    jmp  sch_done                    # vuelta completa: nadie mas listo
sch_found:
    cmp  edi, esi
    je   sch_done
    mov  [current_pcb], edi
    push edi                         # arg2: PCB nueva
    push esi                         # arg1: PCB vieja
    call switch_to
    add  esp, 8
sch_done:
    pop  edi
    pop  esi
    ret

# void switch_to(PCB *vieja, PCB *nueva)
switch_to:
    push ebp
    push ebx
    push esi
    push edi
    mov  eax, [esp + 20]             # vieja
    mov  edx, [esp + 24]             # nueva
    mov  [eax + PCB_ESP], esp        # guardar pila de la tarea saliente
    mov  esp, [edx + PCB_ESP]        # cargar pila de la tarea entrante
    pop  edi
    pop  esi
    pop  ebx
    pop  ebp
    ret

.section .data
current_pcb: .long 0
next_pid:    .long 1
