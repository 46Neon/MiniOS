#ifndef MINIARINO_BOOT_INFO_H
#define MINIARINO_BOOT_INFO_H

#include <stdint.h>

#define BOOT_INFO_PHYS       0x7000u
#define E820_MAP_PHYS        0x5000u
#define BOOT_INFO_MAGIC      0x32334D42u /* "BM32" */
#define BOOT_INFO_VERSION    1u
#define BOOT_FLAG_E820       (1u << 0)
#define BOOT_FLAG_VBE_LFB    (1u << 1)
#define E820_MAX_ENTRIES     64u

/* Exact low-memory ABI written by boot/stage2.asm; all addresses are physical. */
struct boot_info {
    uint32_t magic;             /* 0x00 */
    uint16_t version;           /* 0x04 */
    uint16_t size;              /* 0x06 */
    uint32_t flags;             /* 0x08 */
    uint16_t width;             /* 0x0c */
    uint16_t height;            /* 0x0e */
    uint16_t bpp;               /* 0x10 */
    uint16_t reserved;          /* 0x12 */
    uint32_t pitch;             /* 0x14 */
    uint32_t framebuffer;       /* 0x18 */
    uint16_t e820_count;        /* 0x1c */
    uint16_t e820_entry_size;   /* 0x1e */
    uint32_t e820_address;      /* 0x20 */
} __attribute__((packed));

/* BIOS SMAP record (E820 with ECX=24). */
struct e820_entry {
    uint64_t base;
    uint64_t length;
    uint32_t type;
    uint32_t attributes;
} __attribute__((packed));

_Static_assert(sizeof(struct boot_info) == 36, "boot_info ABI size");
_Static_assert(sizeof(struct e820_entry) == 24, "E820 ABI size");

#endif
