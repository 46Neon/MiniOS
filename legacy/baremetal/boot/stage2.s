# =====================================================================
#  boot/stage2.s - Segunda etapa (16 bits, en 0000:8000)   [Hitos 11-90]
#  1) Habilita la linea A20 (BIOS, puerto 0x92, controlador 8042)
#  2) Mide la RAM (INT 15h AH=88h) y guarda los KB en 0x504
#  3) Carga el kernel (KERNEL_SECTORS sectores desde LBA 5) en 0x10000
#  4) Carga la GDT, activa CR0.PE y salta al kernel en modo protegido
#  KERNEL_SECTORS lo define el Makefile (--defsym).
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code16
.section .text
.global stage2_start

stage2_start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00
    sti
    mov  byte ptr [BOOT_DRIVE_ADDR], dl

    mov  si, offset msg_stage2
    call print16

    call enable_a20
    mov  si, offset msg_a20
    call print16

    call detect_memory
    call load_kernel

    mov  si, offset msg_pm
    call print16

    cli
    lgdt [gdt_descriptor]
    mov  eax, cr0
    or   eax, 1                      # CR0.PE = 1 -> modo protegido
    mov  cr0, eax
    .byte 0x66, 0xEA                 # JMP FAR 0008:00010000 (prefijo 66 + EA off32 sel16)
    .long KERNEL_BASE
    .word 0x0008

# ---------------------------------------------------------------------
# Habilitar A20: prueba -> BIOS -> puerto 0x92 -> controlador de teclado
# ---------------------------------------------------------------------
enable_a20:
    call check_a20
    test ax, ax
    jnz  a20_done
    mov  ax, 0x2401                  # BIOS: habilitar A20
    int  0x15
    call check_a20
    test ax, ax
    jnz  a20_done
    in   al, 0x92                    # "Fast A20"
    or   al, 0x02
    and  al, 0xFE
    out  0x92, al
    call check_a20
    test ax, ax
    jnz  a20_done
    cli                              # metodo clasico 8042
    call a20_wait_in
    mov  al, 0xAD
    out  0x64, al                    # desactivar teclado
    call a20_wait_in
    mov  al, 0xD0
    out  0x64, al                    # leer puerto de salida
    call a20_wait_out
    in   al, 0x60
    push ax
    call a20_wait_in
    mov  al, 0xD1
    out  0x64, al                    # escribir puerto de salida
    call a20_wait_in
    pop  ax
    or   al, 0x02                    # bit 1 = A20
    out  0x60, al
    call a20_wait_in
    mov  al, 0xAE
    out  0x64, al                    # reactivar teclado
    call a20_wait_in
    sti
a20_done:
    ret

a20_wait_in:                         # esperar buffer de entrada del 8042 vacio
    in   al, 0x64
    test al, 0x02
    jnz  a20_wait_in
    ret

a20_wait_out:                        # esperar dato disponible en el 8042
    in   al, 0x64
    test al, 0x01
    jz   a20_wait_out
    ret

# AX = 1 si A20 activa, 0 si no (compara 0000:0600 con FFFF:0610)
check_a20:
    push ds
    push es
    push si
    push di
    xor  ax, ax
    mov  es, ax
    not  ax
    mov  ds, ax
    mov  di, 0x0600
    mov  si, 0x0610
    mov  al, es:[di]
    push ax
    mov  al, ds:[si]
    push ax
    mov  byte ptr es:[di], 0x00
    mov  byte ptr ds:[si], 0xFF
    cmp  byte ptr es:[di], 0xFF
    pop  ax
    mov  ds:[si], al
    pop  ax
    mov  es:[di], al
    mov  ax, 0
    je   1f                          # iguales -> la memoria "dio la vuelta" -> A20 apagada
    mov  ax, 1
1:  pop  di
    pop  si
    pop  es
    pop  ds
    ret

# ---------------------------------------------------------------------
# RAM sobre 1 MB en KB (INT 15h AH=88h). Si falla, asume 15 MB.
# ---------------------------------------------------------------------
detect_memory:
    mov  ah, 0x88
    int  0x15
    jnc  1f
    mov  ax, 0x3C00
1:  movzx eax, ax
    mov  dword ptr [MEM_KB_ADDR], eax
    ret

# ---------------------------------------------------------------------
# Cargar el kernel sector a sector: segmento destino += 0x20 por sector
# ---------------------------------------------------------------------
load_kernel:
    mov  word  ptr [dap_off], 0x0000
    mov  word  ptr [dap_seg], 0x1000         # 0x1000:0000 = 0x10000
    mov  dword ptr [dap_lba], KERNEL_LBA
    mov  cx, KERNEL_SECTORS
lk_loop:
    push cx
    mov  ah, 0x42
    mov  dl, [BOOT_DRIVE_ADDR]
    mov  si, offset dap
    int  0x13
    pop  cx
    jc   lk_error
    add  word ptr [dap_seg], 0x20            # +512 bytes
    inc  dword ptr [dap_lba]
    loop lk_loop
    ret
lk_error:
    mov  si, offset msg_err
    call print16
lk_halt:
    cli
    hlt
    jmp  lk_halt

print16:
    lodsb
    test al, al
    jz   1f
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    jmp  print16
1:  ret

msg_stage2: .asciz "Stage2 OK\r\n"
msg_a20:    .asciz "A20 habilitada\r\n"
msg_pm:     .asciz "Entrando a modo protegido...\r\n"
msg_err:    .asciz "Error de disco (kernel)\r\n"

dap:
    .byte 0x10, 0x00
    .word 1
dap_off: .word 0
dap_seg: .word 0
dap_lba: .long 0, 0

# ---- GDT provisional: nulo, codigo 32 bits (0x08), datos 32 bits (0x10) ----
.align 8
gdt_start:
    .quad 0x0000000000000000
    .word 0xFFFF, 0x0000
    .byte 0x00, 0x9A, 0xCF, 0x00     # codigo: base 0, limite 4 GB, ring 0
    .word 0xFFFF, 0x0000
    .byte 0x00, 0x92, 0xCF, 0x00     # datos : base 0, limite 4 GB, ring 0
gdt_end:
gdt_descriptor:
    .word gdt_end - gdt_start - 1
    .long gdt_start

.org 2048                            # stage2 ocupa exactamente 4 sectores
