# =====================================================================
#  kernel/pit.s - Temporizador 8253/8254 (PIT) a 100 Hz     [Hitos 241-255]
#  IRQ0 -> cuenta ticks y llama al planificador (multitarea expropiativa).
# =====================================================================
.intel_syntax noprefix
.include "constants.inc"
.code32
.section .text
.global pit_init, pit_handler, ticks

pit_init:
    mov  al, 0x36                    # canal 0, lobyte/hibyte, modo 3, binario
    out  0x43, al
    mov  ax, PIT_DIVISOR
    out  0x40, al                    # byte bajo del divisor
    mov  al, ah
    out  0x40, al                    # byte alto
    ret

# Llamado por irq_common (EOI ya enviado)
pit_handler:
    inc  dword ptr [ticks]
    call schedule
    ret

.section .data
ticks: .long 0
