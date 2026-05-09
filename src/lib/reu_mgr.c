/*
 * reu_mgr.c - REU Memory Manager Implementation
 * Manages 256 REU banks with allocation table at $C600
 */

#include "reu_mgr.h"

/* REU hardware registers */
#define REU_STATUS   (*(unsigned char*)0xDF00)
#define REU_COMMAND  (*(unsigned char*)0xDF01)
#define REU_C64_LO   (*(unsigned char*)0xDF02)
#define REU_C64_HI   (*(unsigned char*)0xDF03)
#define REU_REU_LO   (*(unsigned char*)0xDF04)
#define REU_REU_HI   (*(unsigned char*)0xDF05)
#define REU_REU_BANK (*(unsigned char*)0xDF06)
#define REU_LEN_LO   (*(unsigned char*)0xDF07)
#define REU_LEN_HI   (*(unsigned char*)0xDF08)

#define REU_CMD_STASH 0x90
#define REU_CMD_FETCH 0x91

/*---------------------------------------------------------------------------
 * Sync allocation table from shim's reu_bitmap ($C836-$C838)
 * Banks 0-23 are app-slot banks:
 *   - set bit   -> APP_STATE
 *   - clear bit -> RESERVED
 *---------------------------------------------------------------------------*/
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
        if (bitmap_lo & mask) {
            REU_ALLOC_TABLE[phys] = REU_APP_STATE;
        } else {
            REU_ALLOC_TABLE[phys] = REU_RESERVED;
        }
    }

    for (bank = 0; bank < 8; ++bank) {
        mask = (unsigned char)(1 << bank);
        phys = REU_LOGICAL_TO_PHYSICAL((unsigned char)(bank + 8));
        if (bitmap_hi & mask) {
            REU_ALLOC_TABLE[phys] = REU_APP_STATE;
        } else {
            REU_ALLOC_TABLE[phys] = REU_RESERVED;
        }
    }

    for (bank = 0; bank < 8; ++bank) {
        mask = (unsigned char)(1 << bank);
        phys = REU_LOGICAL_TO_PHYSICAL((unsigned char)(bank + 16));
        if (bitmap_xhi & mask) {
            REU_ALLOC_TABLE[phys] = REU_APP_STATE;
        } else {
            REU_ALLOC_TABLE[phys] = REU_RESERVED;
        }
    }
}

static void reu_apply_fixed_system_banks(void) {
    REU_ALLOC_TABLE[REU_BANK_RS_CACHE] = REU_RS_CACHE;
    REU_ALLOC_TABLE[REU_BANK_RS_CACHE2] = REU_RS_CACHE;
    REU_ALLOC_TABLE[REU_BANK_RS_CACHE3] = REU_RS_CACHE;
    REU_ALLOC_TABLE[REU_BANK_RS_DEBUG] = REU_RS_DEBUG;
    REU_ALLOC_TABLE[REU_BANK_RS_SCRATCH] = REU_RS_SCRATCH;
}

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
        case REU_BANK_RS_CACHE: return REU_RS_CACHE;
        case REU_BANK_RS_CACHE2: return REU_RS_CACHE;
        case REU_BANK_RS_CACHE3: return REU_RS_CACHE;
        case REU_BANK_RS_DEBUG: return REU_RS_DEBUG;
        case REU_BANK_RS_SCRATCH: return REU_RS_SCRATCH;
        default:                return 0xFF;
    }
}

/*---------------------------------------------------------------------------
 * Initialize REU manager
 *---------------------------------------------------------------------------*/
void reu_mgr_init(void) {
    if (*REU_SYS_MAGIC == REU_MAGIC_VALUE) {
        /* Already initialized - just sync from shim bitmap */
        reu_sync_from_bitmap();
        reu_apply_fixed_system_banks();
        return;
    }

    /* First-time init: zero the table and set magic */
    {
        unsigned int i;
        for (i = 0; i < REU_TOTAL_BANKS; ++i) {
            REU_ALLOC_TABLE[i] = REU_FREE;
        }
    }
    *REU_SYS_MAGIC = REU_MAGIC_VALUE;

    /* Sync from shim bitmap in case apps were already loaded */
    reu_sync_from_bitmap();
    reu_apply_fixed_system_banks();
}

/*---------------------------------------------------------------------------
 * Allocate a free bank
 *---------------------------------------------------------------------------*/
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

    return 0xFF;  /* No free banks */
}

/*---------------------------------------------------------------------------
 * Free a bank
 *---------------------------------------------------------------------------*/
void reu_free_bank(unsigned char bank) {
    unsigned char mask;
    unsigned char fixed_type = reu_fixed_bank_type(bank);

    if (fixed_type != 0xFF) {
        REU_ALLOC_TABLE[bank] = fixed_type;
        return;
    }

    if (bank < REU_FIRST_DYNAMIC_PHYSICAL()) {
        /* App slot banks are reserved; never return them to dynamic free pool. */
        REU_ALLOC_TABLE[bank] = REU_RESERVED;
        if (bank <= REU_LAUNCHER_OVERLAY_PHYSICAL()) {
            return;
        }
        bank = (unsigned char)(bank - *SHIM_REU_BANK_SKIP - 2u);
        if (bank == 0) {
            return;
        }
        if (bank < 8) {
            mask = (unsigned char)(1 << bank);
            *SHIM_REU_BITMAP_LO &= (unsigned char)~mask;
        } else if (bank < 16) {
            mask = (unsigned char)(1 << (bank - 8));
            *SHIM_REU_BITMAP_HI &= (unsigned char)~mask;
        } else {
            mask = (unsigned char)(1 << (bank - 16));
            *SHIM_REU_BITMAP_XHI &= (unsigned char)~mask;
        }
        return;
    }

    REU_ALLOC_TABLE[bank] = REU_FREE;
}

/*---------------------------------------------------------------------------
 * Get bank type
 *---------------------------------------------------------------------------*/
unsigned char reu_bank_type(unsigned char bank) {
    return REU_ALLOC_TABLE[bank];
}

/*---------------------------------------------------------------------------
 * Count free banks
 *---------------------------------------------------------------------------*/
unsigned char reu_count_free(void) {
    unsigned int i;
    unsigned char count = 0;

    for (i = 0; i < REU_TOTAL_BANKS; ++i) {
        if (REU_ALLOC_TABLE[i] == REU_FREE) {
            ++count;
            if (count == 255) break;  /* Prevent overflow */
        }
    }

    return count;
}

/*---------------------------------------------------------------------------
 * Count banks of a given type
 *---------------------------------------------------------------------------*/
unsigned char reu_count_type(unsigned char type) {
    unsigned int i;
    unsigned char count = 0;

    for (i = 0; i < REU_TOTAL_BANKS; ++i) {
        if (REU_ALLOC_TABLE[i] == type) {
            ++count;
            if (count == 255) break;
        }
    }

    return count;
}

/*---------------------------------------------------------------------------
 * DMA Stash: C64 memory -> REU
 *---------------------------------------------------------------------------*/
void reu_dma_stash(unsigned int c64_addr, unsigned char bank,
                   unsigned int reu_offset, unsigned int length) {
    REU_C64_LO   = (unsigned char)(c64_addr & 0xFF);
    REU_C64_HI   = (unsigned char)(c64_addr >> 8);
    REU_REU_LO   = (unsigned char)(reu_offset & 0xFF);
    REU_REU_HI   = (unsigned char)(reu_offset >> 8);
    REU_REU_BANK = bank;
    REU_LEN_LO   = (unsigned char)(length & 0xFF);
    REU_LEN_HI   = (unsigned char)(length >> 8);
    REU_COMMAND   = REU_CMD_STASH;
}

/*---------------------------------------------------------------------------
 * DMA Fetch: REU -> C64 memory
 *---------------------------------------------------------------------------*/
void reu_dma_fetch(unsigned int c64_addr, unsigned char bank,
                   unsigned int reu_offset, unsigned int length) {
    REU_C64_LO   = (unsigned char)(c64_addr & 0xFF);
    REU_C64_HI   = (unsigned char)(c64_addr >> 8);
    REU_REU_LO   = (unsigned char)(reu_offset & 0xFF);
    REU_REU_HI   = (unsigned char)(reu_offset >> 8);
    REU_REU_BANK = bank;
    REU_LEN_LO   = (unsigned char)(length & 0xFF);
    REU_LEN_HI   = (unsigned char)(length >> 8);
    REU_COMMAND   = REU_CMD_FETCH;
}
