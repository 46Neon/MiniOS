# =====================================================================
#  Makefile de MiniOS - solo requiere binutils (as, ld), make, dd y QEMU.
#  No se usa ningun compilador: as traduce mnemonicos a opcodes 1 a 1.
#  En macOS/Windows use un binutils cruzado: make AS=i686-elf-as LD=i686-elf-ld
# =====================================================================
AS      ?= as
LD      ?= ld
QEMU    ?= qemu-system-i386

ASFLAGS  = --32 -mx86-used-note=no -I include
LDFLAGS  = -m elf_i386
B        = build

# entry.o DEBE ir primero: kernel_entry queda en 0x10000
KOBJS = $(B)/entry.o $(B)/gdt.o $(B)/vga.o $(B)/pic.o $(B)/idt.o \
        $(B)/paging.o $(B)/memory.o $(B)/process.o $(B)/pit.o \
        $(B)/keyboard.o $(B)/ata.o $(B)/fs.o $(B)/syscall.o \
        $(B)/clock.o $(B)/shell.o

.PHONY: all run debug hex clean
all: $(B)/os.img

$(B):
	mkdir -p $(B)

$(B)/%.o: kernel/%.s include/constants.inc | $(B)
	$(AS) $(ASFLAGS) $< -o $@

# ---- Kernel plano en 0x10000 (maximo 123 sectores: LBA 5..127) ----
$(B)/kernel.bin: $(KOBJS) linker/kernel.ld
	$(LD) $(LDFLAGS) -T linker/kernel.ld --oformat binary -o $@ $(KOBJS)
	@test `wc -c < $@` -le 62976 || { echo "ERROR: kernel > 123 sectores"; exit 1; }
	@echo "kernel.bin: `wc -c < $@` bytes"

# ---- Etapa 1: MBR de 512 bytes ----
$(B)/boot.bin: boot/boot.s | $(B)
	$(AS) $(ASFLAGS) $< -o $(B)/boot.o
	$(LD) $(LDFLAGS) -Ttext=0x7C00 --oformat binary -o $@ $(B)/boot.o

# ---- Etapa 2: depende del tamano del kernel (sectores a cargar) ----
$(B)/stage2.bin: boot/stage2.s include/constants.inc $(B)/kernel.bin
	S=$$(( ($$(wc -c < $(B)/kernel.bin) + 511) / 512 )); \
	$(AS) $(ASFLAGS) --defsym KERNEL_SECTORS=$$S $< -o $(B)/stage2.o
	$(LD) $(LDFLAGS) -Ttext=0x8000 -e stage2_start --oformat binary -o $@ $(B)/stage2.o

# ---- Programas planos (enlazados en 0: codigo independiente de posicion) ----
$(B)/%.bin: programs/%.s | $(B)
	$(AS) $(ASFLAGS) $< -o $(B)/$*.o
	$(LD) $(LDFLAGS) -Ttext=0 --oformat binary -o $@ $(B)/$*.o

$(B)/dir.bin: fs/dir.s | $(B)
	$(AS) $(ASFLAGS) $< -o $(B)/dir.o
	$(LD) $(LDFLAGS) -Ttext=0 --oformat binary -o $@ $(B)/dir.o

# ---- Imagen de disco: LBA0 MBR | 1-4 stage2 | 5.. kernel | 128 dir | 129.. programas ----
$(B)/os.img: $(B)/boot.bin $(B)/stage2.bin $(B)/kernel.bin $(B)/dir.bin \
             $(B)/hola.bin $(B)/contador.bin
	dd if=/dev/zero        of=$@ bs=512 count=8192 2>/dev/null
	dd if=$(B)/boot.bin    of=$@ bs=512 seek=0   conv=notrunc 2>/dev/null
	dd if=$(B)/stage2.bin  of=$@ bs=512 seek=1   conv=notrunc 2>/dev/null
	dd if=$(B)/kernel.bin  of=$@ bs=512 seek=5   conv=notrunc 2>/dev/null
	dd if=$(B)/dir.bin     of=$@ bs=512 seek=128 conv=notrunc 2>/dev/null
	dd if=$(B)/hola.bin    of=$@ bs=512 seek=129 conv=notrunc 2>/dev/null
	dd if=$(B)/contador.bin of=$@ bs=512 seek=130 conv=notrunc 2>/dev/null
	@echo "Imagen lista: $@"

run: $(B)/os.img
	$(QEMU) -drive file=$(B)/os.img,format=raw,if=ide -m 64

# Muestra interrupciones/excepciones y no se reinicia ante un triple fallo
debug: $(B)/os.img
	$(QEMU) -drive file=$(B)/os.img,format=raw,if=ide -m 64 -d int,cpu_reset -no-reboot

# Bytes reales (opcodes) del sector de arranque
hex: $(B)/boot.bin
	od -A x -t x1z -v $(B)/boot.bin

clean:
	rm -rf $(B)
