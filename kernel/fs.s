# =====================================================================
#  kernel/fs.s - MiniFS y cargador de binarios planos      [Hitos 286-295]
#  Directorio en el sector LBA 128: 16 entradas de 32 bytes
#     +0  nombre ASCIZ (16)   +16 LBA inicial   +20 sectores
#     +24 tamano en bytes     +28 reservado
#  Un programa plano se copia a paginas del bitmap y se ejecuta desde su
#  primer byte; recibe en EAX su direccion base (codigo independiente).
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global fs_list, fs_find, exec_file

fs_read_dir:                         # CF=1 si falla
    push eax
    push ecx
    push edi
    mov  eax, FS_DIR_LBA
    mov  ecx, 1
    mov  edi, offset fs_dirbuf
    call ata_read_sectors
    pop  edi
    pop  ecx
    pop  eax
    ret

# ESI = nombre -> EAX = puntero a la entrada, o 0 si no existe
fs_find:
    push ebx
    push ecx
    push edx
    call fs_read_dir
    jc   fsf_none
    mov  ebx, offset fs_dirbuf
    mov  ecx, 16
fsf_entry:
    cmp  byte ptr [ebx], 0           # entrada vacia
    je   fsf_next
    xor  edx, edx
fsf_cmp:
    mov  al, [ebx + edx]
    cmp  al, [esi + edx]
    jne  fsf_next
    test al, al
    jz   fsf_found                   # ambos terminan a la vez: coincide
    inc  edx
    cmp  edx, 16
    jb   fsf_cmp
    jmp  fsf_found
fsf_next:
    add  ebx, 32
    dec  ecx
    jnz  fsf_entry
fsf_none:
    xor  eax, eax
    jmp  fsf_end
fsf_found:
    mov  eax, ebx
fsf_end:
    pop  edx
    pop  ecx
    pop  ebx
    ret

# Imprime el directorio (kernel: usa VGA directamente)
fs_list:
    push eax
    push ebx
    push ecx
    push esi
    call fs_read_dir
    jc   fl_err
    mov  ebx, offset fs_dirbuf
    mov  ecx, 16
fl_loop:
    cmp  byte ptr [ebx], 0
    je   fl_next
    mov  esi, ebx
    call vga_print
    mov  al, 9
    call vga_putc
    mov  al, 9
    call vga_putc
    mov  eax, [ebx + 24]
    call vga_print_dec
    mov  esi, offset fl_bytes
    call vga_print
fl_next:
    add  ebx, 32
    dec  ecx
    jnz  fl_loop
    jmp  fl_end
fl_err:
    mov  esi, offset fl_errmsg
    call vga_print
fl_end:
    pop  esi
    pop  ecx
    pop  ebx
    pop  eax
    ret

# ESI = nombre de archivo -> EAX = PID, -1 = error, -2 = no encontrado
exec_file:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov  ebp, esi                    # conservar el nombre
    call fs_find
    test eax, eax
    jz   ex_notfound
    mov  ebx, eax                    # EBX = entrada del directorio
    mov  edx, [ebx + 20]             # EDX = sectores
    test edx, edx
    jz   ex_fail
    cmp  edx, 255
    ja   ex_fail
    lea  ecx, [edx + 7]
    shr  ecx, 3                      # paginas = ceil(sectores*512 / 4096)
    push ecx
    call mem_alloc_pages
    pop  ecx
    test eax, eax
    jz   ex_fail
    mov  edi, eax                    # destino = base de carga
    push eax                         # guardar base
    push ecx                         # guardar paginas
    mov  eax, [ebx + 16]             # LBA
    mov  ecx, edx                    # sectores
    call ata_read_sectors
    pop  ecx                         # paginas
    pop  edx                         # base
    jc   ex_readfail
    mov  eax, edx                    # entrada = base
    mov  ebx, edx                    # argumento = base
    mov  esi, ebp
    call task_create                 # ECX = paginas a liberar al terminar
    cmp  eax, -1
    jne  ex_done
    mov  eax, edx                    # sin ranura: devolver las paginas
    call mem_free_pages
    mov  eax, -1
    jmp  ex_done
ex_readfail:
    mov  eax, edx
    call mem_free_pages
ex_fail:
    mov  eax, -1
    jmp  ex_done
ex_notfound:
    mov  eax, -2
ex_done:
    pop  ebp
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret

.section .data
fl_bytes:  .asciz " bytes\n"
fl_errmsg: .asciz "Error leyendo el disco\n"
fs_dirbuf: .fill 512, 1, 0
