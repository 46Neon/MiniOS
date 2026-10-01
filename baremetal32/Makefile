NASM ?= nasm
CC = gcc
LD ?= ld
OBJCOPY ?= objcopy
PYTHON ?= python3
QEMU ?= qemu-system-i386
BUILD := build
KERNEL_SECTORS := 64
KERNEL_BYTES := $(shell expr $(KERNEL_SECTORS) \* 512)
CFLAGS := -m32 -std=c11 -O2 -Wall -Wextra -Werror -ffreestanding -fno-pie -fno-pic -fno-stack-protector -fno-builtin -fno-asynchronous-unwind-tables -fno-unwind-tables -nostdlib -Iinclude
ASFLAGS := -f elf32

.PHONY: all clean verify qemu-test
all: $(BUILD)/os.img

$(BUILD):
	mkdir -p $@

$(BUILD)/mbr.bin: boot/mbr.asm | $(BUILD)
	$(NASM) -f bin -Wall -Werror -o $@ $<

$(BUILD)/stage2.bin: boot/stage2.asm | $(BUILD)
	$(NASM) -f bin -Wall -Werror -o $@ $<

$(BUILD)/kernel_entry.o: kernel/entry.asm | $(BUILD)
	$(NASM) $(ASFLAGS) -Wall -Werror -o $@ $<

$(BUILD)/kernel.o: kernel/kernel.c include/boot_info.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/kernel.elf: $(BUILD)/kernel_entry.o $(BUILD)/kernel.o linker/kernel.ld
	$(LD) -m elf_i386 -T linker/kernel.ld -o $@ $(BUILD)/kernel_entry.o $(BUILD)/kernel.o

$(BUILD)/kernel.raw: $(BUILD)/kernel.elf
	$(OBJCOPY) -O binary $< $@
	@test "$$(wc -c < $@)" -le $(KERNEL_BYTES) || { echo 'kernel exceeds fixed 64-sector load window' >&2; exit 1; }

$(BUILD)/kernel.bin: $(BUILD)/kernel.raw
	cp $< $@
	truncate -s $(KERNEL_BYTES) $@

$(BUILD)/os.img: $(BUILD)/mbr.bin $(BUILD)/stage2.bin $(BUILD)/kernel.bin
	@test "$$(wc -c < $(BUILD)/mbr.bin)" -eq 512
	@test "$$(wc -c < $(BUILD)/stage2.bin)" -eq 4096
	cat $(BUILD)/mbr.bin $(BUILD)/stage2.bin $(BUILD)/kernel.bin > $@
	$(PYTHON) tests/check_image.py $@

verify: $(BUILD)/os.img
	$(PYTHON) tests/check_image.py $(BUILD)/os.img

qemu-test: verify
	QEMU='$(QEMU)' sh tests/run_qemu.sh $(BUILD)/os.img

clean:
	rm -rf $(BUILD)
