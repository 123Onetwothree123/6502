/*
 * reu_mgr_init.c - REU manager initialization and shim bitmap sync
 */

#include "reu_mgr.h"

static void reu_sync_from_bitmap(void) {
    unsigned char bitmap_lo = *SHIM_REU_BITMAP_LO;
    unsigned char bitmap_hi = *SHIM_REU_BITMAP_HI;
    unsigned char bitmap_xhi = *SHIM_REU_BITMAP_XHI;
    unsigned char bank;
    unsigned char phys;
    unsigned char mask;
    unsigned char skip = *SHIM_REU_BANK_SKIP;

    for (bank = 0; bank < skip; ++bank) {
        REU_ALLOC_TABLE[bank] = REU_SKIPPED;
    }

    REU_ALLOC_TABLE[REU_READYOS_GLOBAL_PHYSICAL()] = REU_GLOBAL;
    REU_ALLOC_TABLE[REU_LAUNCHER_PHYSICAL()] = REU_LAUNCHER;
    REU_ALLOC_TABLE[REU_LAUNCHER_OVERLAY_PHYSICAL()] = REU_LAUNCHER;

    for (bank = 1; bank < 8; ++bank) {
        mask = (unsigned char)(1 << bank);
        phys = REU_LOGICAL_TO_PHYSICAL(bank);
        REU_ALLOC_TABLE[phys] = (bitmap_lo & mask) ? REU_APP_STATE : REU_RESERVED;
    }

    for (bank = 0; bank < 8; ++bank) {
        mask = (unsigned char)(1 << bank);
        phys = REU_LOGICAL_TO_PHYSICAL((unsigned char)(bank + 8));
        REU_ALLOC_TABLE[phys] = (bitmap_hi & mask) ? REU_APP_STATE : REU_RESERVED;
    }

    for (bank = 0; bank < 8; ++bank) {
        mask = (unsigned char)(1 << bank);
        phys = REU_LOGICAL_TO_PHYSICAL((unsigned char)(bank + 16));
        REU_ALLOC_TABLE[phys] = (bitmap_xhi & mask) ? REU_APP_STATE : REU_RESERVED;
    }
}

static void reu_apply_fixed_system_banks(void) {
    REU_ALLOC_TABLE[REU_BANK_RS_DEBUG] = REU_RS_DEBUG;
}

void reu_mgr_init(void) {
    if (*REU_SYS_MAGIC == REU_MAGIC_VALUE) {
        reu_sync_from_bitmap();
        reu_apply_fixed_system_banks();
        return;
    }

    {
        unsigned int i;
        for (i = 0; i < REU_TOTAL_BANKS; ++i) {
            REU_ALLOC_TABLE[i] = REU_FREE;
        }
    }
    *REU_SYS_MAGIC = REU_MAGIC_VALUE;
    reu_sync_from_bitmap();
    reu_apply_fixed_system_banks();
}
