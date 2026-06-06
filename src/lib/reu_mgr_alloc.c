/*
 * reu_mgr_alloc.c - REU allocation/free helpers
 */

#include "reu_mgr.h"

static unsigned char reu_fixed_bank_type(unsigned char bank) {
    if (bank < *SHIM_REU_BANK_SKIP) {
        return REU_SKIPPED;
    }
    if (bank == REU_READYOS_GLOBAL_PHYSICAL()) {
        return REU_GLOBAL;
    }
    if (bank == REU_LAUNCHER_PHYSICAL()) {
        return REU_LAUNCHER;
    }
    if (bank == REU_LAUNCHER_OVERLAY_PHYSICAL()) {
        return REU_LAUNCHER;
    }
    switch (bank) {
        case REU_BANK_RS_DEBUG: return REU_RS_DEBUG;
        default:                return 0xFF;
    }
}

unsigned char reu_alloc_bank(unsigned char type) {
    unsigned int bank;

    for (bank = REU_FIRST_DYNAMIC_PHYSICAL(); bank < REU_TOTAL_BANKS; ++bank) {
        if (reu_fixed_bank_type((unsigned char)bank) != 0xFF) {
            continue;
        }
        if (REU_ALLOC_TABLE[bank] == REU_FREE) {
            REU_ALLOC_TABLE[bank] = type;
            return (unsigned char)bank;
        }
    }

    return 0xFF;
}

void reu_free_bank(unsigned char bank) {
    unsigned char fixed_type = reu_fixed_bank_type(bank);

    if (fixed_type != 0xFF) {
        REU_ALLOC_TABLE[bank] = fixed_type;
        return;
    }

    REU_ALLOC_TABLE[bank] = REU_FREE;
}
