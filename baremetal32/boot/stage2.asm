BITS 16
ORG 0x8000

%define BOOTINFO       0x7000
%define E820_BASE      0x5000
%define E820_MAX       64
%define BI_MAGIC       0x7000
%define BI_VERSION     0x7004
%define BI_SIZE        0x7006
%define BI_FLAGS       0x7008
%define BI_WIDTH       0x700C
%define BI_HEIGHT      0x700E
%define BI_BPP         0x7010
%define BI_RESERVED    0x7012
%define BI_PITCH       0x7014
%define BI_LFB         0x7018
%define BI_E820_COUNT  0x701C
%define BI_E820_ADDR   0x7020
%define BI_E820_ENTRY_SIZE 0x701E
%define FLAG_E820      1
%define FLAG_VBE       2

stage2_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld
    sti
    mov [boot_drive], dl

    ; Initialize versioned boot-info at physical 0x7000.
    mov dword [BI_MAGIC], 0x32334D42 ; "BM32"
    mov word [BI_VERSION], 1
    mov word [BI_SIZE], 36
    mov dword [BI_FLAGS], 0
    mov dword [BI_WIDTH], 0
    mov dword [BI_BPP], 0
    mov dword [BI_PITCH], 0
    mov dword [BI_LFB], 0
    mov word [BI_E820_COUNT], 0
    mov word [BI_E820_ENTRY_SIZE], 24
    mov dword [BI_E820_ADDR], E820_BASE

    call collect_e820
    call try_vbe
    call load_kernel
    jc boot_fail

    ; Enable A20 via the fast gate. Enter flat 32-bit protected mode.
    in al, 0x92
    or al, 2
    and al, 0xFE
    out 0x92, al
    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword 0x08:protected_entry

collect_e820:
    mov dword [e820_next], 0
    mov word [BI_E820_COUNT], 0
    mov dword [e820_ok], 0
.e820_loop:
    movzx eax, word [BI_E820_COUNT]
    cmp eax, E820_MAX
    jae .e820_done
    ; ES:DI points at the next packed 24-byte SMAP record.
    mov bx, ax
    imul bx, 24
    mov di, E820_BASE
    add di, bx
    xor ax, ax
    mov es, ax
    mov dword [es:di+20], 1
    mov eax, 0xE820
    mov edx, 0x534D4150
    mov ecx, 24
    mov ebx, [e820_next]
    push ds
    push es
    int 0x15
    pop es
    pop ds
    jc .e820_done
    cmp eax, 0x534D4150
    jne .e820_done
    cmp ecx, 20
    jb .e820_done
    inc word [BI_E820_COUNT]
    mov dword [e820_ok], 1
    mov [e820_next], ebx
    test ebx, ebx
    jnz .e820_loop
.e820_done:
    cmp dword [e820_ok], 0
    je .ret
    or dword [BI_FLAGS], FLAG_E820
.ret:
    ret

try_vbe:
    ; Ask VBE for 640x480x24 linear framebuffer (VBE mode 112h).
    mov ax, 0x4F01
    mov cx, 0x0112
    mov di, 0x6200
    push ds
    push es
    int 0x10
    pop es
    pop ds
    cmp ax, 0x004F
    jne .fallback
    test word [0x6200], 0x0001 ; ModeAttributes bit 0: mode supported
    jz .fallback
    test word [0x6200], 0x0080 ; ModeAttributes bit 7: linear framebuffer
    jz .fallback
    cmp word [0x6212], 640
    jne .fallback
    cmp word [0x6214], 480
    jne .fallback
    cmp byte [0x6219], 24
    jne .fallback
    cmp word [0x6232], 1920     ; LinBytesPerScanLine, 640 * 3
    jb .fallback
    cmp dword [0x6228], 0
    je .fallback
    mov bx, 0x8112             ; mode + bit 15 requests the linear framebuffer
    mov ax, 0x4F02
    push ds
    push es
    int 0x10
    pop es
    pop ds
    cmp ax, 0x004F
    jne .fallback
    mov word [BI_WIDTH], 640
    mov word [BI_HEIGHT], 480
    movzx eax, byte [0x6219]
    mov [BI_BPP], ax
    movzx eax, word [0x6232]   ; LinBytesPerScanLine from VBE mode info
    mov [BI_PITCH], eax
    mov eax, [0x6228]           ; PhysBasePtr
    mov [BI_LFB], eax
    or dword [BI_FLAGS], FLAG_VBE
    ret
.fallback:
    ; Restore BIOS text mode; boot-info explicitly reports no LFB.
    mov ax, 0x0003
    int 0x10
    mov dword [BI_WIDTH], 0
    mov dword [BI_HEIGHT], 0
    mov dword [BI_BPP], 0
    mov dword [BI_PITCH], 0
    mov dword [BI_LFB], 0
    ret

load_kernel:
    ; 64 sectors at LBA 9 into physical 0x10000. Build pads kernel to this size.
    mov si, kernel_dap
    mov dl, [boot_drive]
    mov ah, 0x42
    push ds
    push es
    int 0x13
    pop es
    pop ds
    ret

boot_fail:
    mov si, fail_msg
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

BITS 32
protected_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x0009F000
    mov eax, BOOTINFO
    jmp 0x00010000

BITS 16
boot_drive db 0
e820_next dd 0
e820_ok dd 0
fail_msg db 'stage2/kernel load failed', 0
align 4
kernel_dap:
    db 0x10, 0
    dw 64
    dw 0, 0x1000              ; 1000:0000 = 0x10000
    dq 9
align 8
gdt_start:
    dq 0
    dq 0x00CF9A000000FFFF     ; flat 4 GiB code
    dq 0x00CF92000000FFFF     ; flat 4 GiB data
gdt_end:
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

times 4096-($-$$) db 0
