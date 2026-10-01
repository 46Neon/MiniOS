#include <stdint.h>
#include "boot_info.h"

#define COM1 0x3F8u

static inline void outb(uint16_t port, uint8_t value) {
    __asm__ volatile ("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t value;
    __asm__ volatile ("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

static void serial_init(void) {
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x80);
    outb(COM1 + 0, 0x01); /* 115200 baud */
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03); /* 8N1 */
    outb(COM1 + 2, 0xC7);
    outb(COM1 + 4, 0x0B);
}

static void putc(char c) {
    while ((inb(COM1 + 5) & 0x20u) == 0) { }
    outb(COM1, (uint8_t)c);
}

static void puts(const char *s) {
    while (*s) putc(*s++);
}

static void put_u16(uint16_t value) {
    char digits[5];
    unsigned n = 0;
    if (value == 0) { putc('0'); return; }
    while (value && n < sizeof(digits)) {
        digits[n++] = (char)('0' + value % 10u);
        value = (uint16_t)(value / 10u);
    }
    while (n) putc(digits[--n]);
}

static void text_fallback(void) {
    static const char line1[] = "MiniArino BIOS text fallback";
    static const char line2[] = "VBE 640x480 not available";
    volatile uint16_t *vga = (volatile uint16_t *)0x000B8000u;
    unsigned i;
    for (i = 0; line1[i] != 0; ++i)
        vga[i] = (uint16_t)(0x0700u | (uint8_t)line1[i]);
    for (i = 0; line2[i] != 0; ++i)
        vga[80u + i] = (uint16_t)(0x0700u | (uint8_t)line2[i]);
}

void kernel_main(const struct boot_info *bi) {
    serial_init();
    puts("BAREMETAL32:KERNEL\r\n");
    if (!bi || bi->magic != BOOT_INFO_MAGIC || bi->version != BOOT_INFO_VERSION ||
        bi->size != sizeof(*bi) || bi->e820_entry_size != sizeof(struct e820_entry) ||
        bi->e820_address != E820_MAP_PHYS || bi->e820_count == 0 ||
        bi->e820_count > E820_MAX_ENTRIES || !(bi->flags & BOOT_FLAG_E820)) {
        puts("BOOTINFO:INVALID\r\n");
        for (;;) __asm__ volatile ("cli; hlt");
    }

    puts("E820:count=");
    put_u16(bi->e820_count);
    puts(" entry_size=");
    put_u16(bi->e820_entry_size);
    puts(" addr=0x5000\r\n");

    if ((bi->flags & BOOT_FLAG_VBE_LFB) && bi->width == 640 && bi->height == 480) {
        puts("VBE:640x480x");
        put_u16(bi->bpp);
        puts(" pitch=");
        put_u16((uint16_t)bi->pitch);
        puts(" lfb=");
        /* Keep output compact; address is available in the boot-info ABI. */
        puts("present\r\n");
    } else {
        text_fallback();
        puts("VIDEO:TEXT_FALLBACK\r\n");
    }
    puts("GATE:BOOTINFO_OK\r\n");
    for (;;) __asm__ volatile ("cli; hlt");
}
