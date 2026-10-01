OUTPUT_FORMAT(elf32-i386)
OUTPUT_ARCH(i386)
ENTRY(_start)
SECTIONS
{
    . = 0x00010000;
    .text : { KEEP(*(.text)) *(.text.*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    .bss : { *(COMMON) *(.bss*) }
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
