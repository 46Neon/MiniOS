# fs/dir.s - Directorio de MiniFS (sector LBA 128)
# Entrada de 32 bytes: nombre[16], LBA, sectores, tamano, reservado
.section .text
.global _start
_start:
    .ascii "hola.bin"
    .fill  8, 1, 0
    .long  129, 1, 512, 0
    .ascii "contador.bin"
    .fill  4, 1, 0
    .long  130, 1, 512, 0
.org 512
