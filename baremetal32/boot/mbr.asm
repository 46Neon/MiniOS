BITS 16
ORG 0x7C00

; BIOS loads this sector at 0000:7C00. EDD reads stage2 from LBA 1..8.
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld
    sti
    mov [boot_drive], dl

    mov si, dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error
    jmp 0x0000:0x8000

disk_error:
    mov si, disk_msg
.print:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

boot_drive db 0
disk_msg db 'MBR disk read error', 0
align 4
dap:
    db 0x10, 0
    dw 8                    ; sectors
    dw 0x8000, 0            ; destination 0000:8000
    dq 1                    ; LBA

times 446-($-$$) db 0
; Empty partition table (the image is booted as a raw BIOS disk).
times 64 db 0
dw 0xAA55
