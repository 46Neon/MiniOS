# =====================================================================
#  kernel/entry.s - Punto de entrada del kernel de 32 bits (0x10000)
#  [Hitos 41-75 y 296-300]  stage2 salta aqui en modo protegido.
#  Orden de inicializacion y bucle "idle" con HLT (bajo consumo).
#  ESTE ARCHIVO DEBE ENLAZARSE PRIMERO: kernel_entry ocupa el byte 0.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global kernel_entry

.macro LOG label
    mov  esi, offset \label
    call vga_print
.endm

kernel_entry:
    cli
    mov  ax, 0x10                    # selector de datos de la GDT provisional
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax
    mov  esp, KSTACK_TOP             # pila inicial (crece hacia abajo)
    cld

    call gdt_init                    # GDT definitiva del kernel
    call vga_init
    LOG  m_boot
    call pic_init                    # remapeo del PIC, todo enmascarado
    LOG  m_pic
    call idt_init                    # excepciones + IRQ + int 0x80
    LOG  m_idt
    call mem_init                    # bitmap de marcos (lee 0x504: antes de paginar)
    LOG  m_mem
    mov  eax, [mem_npages]
    shl  eax, 2
    call vga_print_dec
    LOG  m_kb
    call paging_init                 # paginacion con mapeo identidad
    LOG  m_paging
    call pit_init                    # timer a 100 Hz
    LOG  m_pit
    call kb_init
    LOG  m_kb_ok
    call process_init                # PCB 0 = idle (este mismo contexto)
    LOG  m_proc

    mov  eax, offset clock_main      # tarea 1: reloj de la barra de estado
    xor  ebx, ebx
    xor  ecx, ecx
    mov  esi, offset name_clock
    call task_create
    mov  eax, offset shell_main      # tarea 2: interprete de comandos
    xor  ebx, ebx
    xor  ecx, ecx
    mov  esi, offset name_shell
    call task_create
    LOG  m_ready

    xor  eax, eax                    # habilitar IRQ0 (timer)
    call pic_unmask
    mov  eax, 1                      # habilitar IRQ1 (teclado)
    call pic_unmask
    sti                              # desde aqui el planificador expropia tareas

idle_loop:                           # tarea idle: dormir el CPU hasta la proxima IRQ
    hlt
    jmp  idle_loop

.section .data
m_boot:    .asciz "[OK] Modo protegido de 32 bits, GDT cargada\n"
m_pic:     .asciz "[OK] PIC remapeado (IRQ -> vectores 0x20-0x2F)\n"
m_idt:     .asciz "[OK] IDT: excepciones, IRQ e int 0x80\n"
m_mem:     .asciz "[OK] Gestor de memoria (bitmap): "
m_kb:      .asciz " KB gestionados\n"
m_paging:  .asciz "[OK] Paginacion activada (mapeo identidad 16 MB)\n"
m_pit:     .asciz "[OK] Temporizador PIT a 100 Hz\n"
m_kb_ok:   .asciz "[OK] Teclado PS/2\n"
m_proc:    .asciz "[OK] Procesos: PCB 0 = idle\n"
m_ready:   .asciz "[OK] Iniciando tareas...\n\n"
name_clock: .asciz "reloj"
name_shell: .asciz "shell"
