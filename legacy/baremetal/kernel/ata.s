# =====================================================================
#  kernel/ata.s - Disco ATA PIO, LBA28, canal primario     [Hitos 256-275]
#  Puertos 0x1F0-0x1F7 (maestro). Lectura/escritura por sondeo (sin IRQ14).
#  Convencion: CF = 1 en caso de error. Preservan todos los registros.
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global ata_read_sectors, ata_write_sectors

# CF=1 si el controlador sigue ocupado tras el tiempo limite
ata_wait_idle:
    push ecx
    push edx
    mov  dx, 0x1F7
    mov  ecx, 0x100000
1:  in   al, dx
    test al, 0x80                    # BSY
    jz   2f
    dec  ecx
    jnz  1b
    stc
    jmp  3f
2:  clc
3:  pop  edx
    pop  ecx
    ret

# Espera DRQ (datos listos). CF=1 si hay ERR/DF o se agota el tiempo.
ata_poll_drq:
    push ecx
    push edx
    mov  dx, 0x1F7
    in   al, dx                      # 4 lecturas ~ 400 ns de retardo
    in   al, dx
    in   al, dx
    in   al, dx
    mov  ecx, 0x100000
1:  in   al, dx
    test al, 0x80                    # BSY: seguir esperando
    jnz  2f
    test al, 0x21                    # ERR o DF
    jnz  3f
    test al, 0x08                    # DRQ
    jnz  4f
2:  dec  ecx
    jnz  1b
3:  stc
    jmp  5f
4:  clc
5:  pop  edx
    pop  ecx
    ret

# Programa LBA (EBX), cantidad (ESI) y unidad maestra
ata_setup:
    push eax
    push edx
    mov  dx, 0x1F6
    mov  eax, ebx
    shr  eax, 24
    and  al, 0x0F
    or   al, 0xE0                    # modo LBA, unidad 0
    out  dx, al
    mov  dx, 0x1F2
    mov  eax, esi
    out  dx, al                      # cantidad de sectores
    mov  dx, 0x1F3
    mov  al, bl
    out  dx, al                      # LBA 0-7
    mov  dx, 0x1F4
    mov  al, bh
    out  dx, al                      # LBA 8-15
    mov  dx, 0x1F5
    mov  eax, ebx
    shr  eax, 16
    out  dx, al                      # LBA 16-23
    pop  edx
    pop  eax
    ret

# EAX = LBA, ECX = cantidad (1..255), EDI = buffer destino
ata_read_sectors:
    pushad
    cld
    mov  ebx, eax
    mov  esi, ecx
    call ata_wait_idle
    jc   ar_err
    call ata_setup
    mov  dx, 0x1F7
    mov  al, 0x20                    # comando READ SECTORS
    out  dx, al
ar_loop:
    call ata_poll_drq
    jc   ar_err
    mov  dx, 0x1F0
    mov  ecx, 256
    rep  insw                        # 256 palabras = 512 bytes
    dec  esi
    jnz  ar_loop
    clc
    jmp  ar_end
ar_err:
    stc
ar_end:
    popad
    ret

# EAX = LBA, ECX = cantidad (1..255), ESI = buffer origen
ata_write_sectors:
    pushad
    cld
    mov  ebx, eax
    mov  edi, ecx                    # contador de sectores
    call ata_wait_idle
    jc   aw_err
    push esi                         # ata_setup usa ESI como cantidad
    mov  esi, edi
    call ata_setup
    pop  esi
    mov  dx, 0x1F7
    mov  al, 0x30                    # comando WRITE SECTORS
    out  dx, al
aw_loop:
    call ata_poll_drq
    jc   aw_err
    mov  dx, 0x1F0
    mov  ecx, 256
    rep  outsw
    dec  edi
    jnz  aw_loop
    mov  dx, 0x1F7
    mov  al, 0xE7                    # CACHE FLUSH
    out  dx, al
    call ata_wait_idle
    jc   aw_err
    clc
    jmp  aw_end
aw_err:
    stc
aw_end:
    popad
    ret
