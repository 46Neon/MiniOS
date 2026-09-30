# =====================================================================
#  boot/boot.s - Sector de arranque (MBR) de 512 bytes      [Hitos 1-55]
#  La BIOS carga este sector en 0000:7C00 y salta a el con DL = unidad.
#  Tareas: segmentos, pila, cargar stage2 (4 sectores, LBA 1) y saltar.
#  Firma obligatoria 0x55 0xAA en los bytes 510 y 511.
# =====================================================================
.intel_syntax noprefix
.code16
.section .text
.global _start

_start:
    cli                              # sin interrupciones mientras se configura
    xor  ax, ax
    mov  ds, ax                      # DS = ES = SS = 0
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00                  # pila justo debajo del sector de arranque
    sti
    mov  [boot_drive], dl            # la BIOS deja la unidad en DL

    mov  si, offset msg_boot
    call print

    mov  si, offset dap              # INT 13h AH=42h: lectura LBA extendida
    mov  ah, 0x42
    mov  dl, [boot_drive]
    int  0x13
    jc   disk_error

    mov  dl, [boot_drive]            # stage2 recibe la unidad en DL
    .byte 0xEA                       # JMP FAR 0000:8000 (opcode EA off16 seg16)
    .word 0x8000
    .word 0x0000

disk_error:
    mov  si, offset msg_err
    call print
halt:
    cli
    hlt
    jmp  halt

# SI = cadena ASCIZ -> teletipo BIOS (INT 10h AH=0Eh)
print:
    lodsb
    test al, al
    jz   1f
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    jmp  print
1:  ret

msg_boot:   .asciz "MiniOS: cargando stage2...\r\n"
msg_err:    .asciz "Error de disco (MBR)\r\n"
boot_drive: .byte 0

# Disk Address Packet: tamano, reservado, sectores, offset, segmento, LBA(64)
dap:
    .byte 0x10, 0x00
    .word 4                          # 4 sectores = 2048 bytes de stage2
    .word 0x8000                     # offset destino
    .word 0x0000                     # segmento destino
    .long 1, 0                       # LBA 1

.org 510
.word 0xAA55                         # firma de arranque
