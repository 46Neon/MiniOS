/* linker/kernel.ld - kernel plano enlazado en 0x10000 (entry.o debe ir primero) */
ENTRY(kernel_entry)
SECTIONS
{
    . = 0x10000;
    .text   : { *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) }
    .data   : { *(.data .data.*) }
    .bss    : { *(.bss .bss.*) *(COMMON) }
    /DISCARD/ : { *(.note*) *(.comment) *(.eh_frame) }
}
