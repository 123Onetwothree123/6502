/*
 * reu_control_bank.c - mirror resident REU state into logical bank 0
 */

#include "reu_control_bank.h"

static unsigned char reucb_header[REUCB_HEADER_SIZE];
static unsigned char reucb_zero[REUCB_HEADER_SIZE];
static unsigned char reucb_record[REUCB_RESOURCE_SIZE];
static unsigned char reucb_generation;

static void reucb_zero_buf(unsigned char *buf, unsigned char len) {
    unsigned char i;

    for (i = 0; i < len; ++i) {
        buf[i] = 0;
    }
}

static void reucb_sync_from_bitmap(void) {
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
        mask = (unsigned char)(1u << bank);
        phys = REU_LOGICAL_TO_PHYSICAL(bank);
        REU_ALLOC_TABLE[phys] = (bitmap_lo & mask) ? REU_APP_STATE : REU_RESERVED;
    }

    for (bank = 0; bank < 8; ++bank) {
        mask = (unsigned char)(1u << bank);
        phys = REU_LOGICAL_TO_PHYSICAL((unsigned char)(bank + 8u));
        REU_ALLOC_TABLE[phys] = (bitmap_hi & mask) ? REU_APP_STATE : REU_RESERVED;
    }

    for (bank = 0; bank < 8; ++bank) {
        mask = (unsigned char)(1u << bank);
        phys = REU_LOGICAL_TO_PHYSICAL((unsigned char)(bank + 16u));
        REU_ALLOC_TABLE[phys] = (bitmap_xhi & mask) ? REU_APP_STATE : REU_RESERVED;
    }

    REU_ALLOC_TABLE[REU_BANK_RS_DEBUG] = REU_RS_DEBUG;
    REU_ALLOC_TABLE[REU_BANK_RB_CORE] = REU_RB_CORE;
    REU_ALLOC_TABLE[REU_BANK_RB_CODE] = REU_RB_CODE;
    REU_ALLOC_TABLE[REU_BANK_RS_SCRATCH] = REU_RS_SCRATCH;
}

static void reucb_write_header(unsigned char control_bank, unsigned char writer_id) {
    reucb_zero_buf(reucb_header, REUCB_HEADER_SIZE);

    reucb_header[0] = REUCB_MAGIC0;
    reucb_header[1] = REUCB_MAGIC1;
    reucb_header[2] = REUCB_MAGIC2;
    reucb_header[3] = REUCB_MAGIC3;
    reucb_header[4] = REUCB_SCHEMA_VERSION;
    reucb_header[5] = REUCB_HEADER_SIZE;
    reucb_header[6] = ++reucb_generation;
    reucb_header[7] = writer_id;
    reucb_header[8] = *SHIM_REU_BANK_SKIP;
    reucb_header[9] = control_bank;
    reucb_header[10] = REU_LAUNCHER_PHYSICAL();
    reucb_header[11] = REU_LAUNCHER_OVERLAY_PHYSICAL();
    reucb_header[12] = REU_FIRST_DYNAMIC_PHYSICAL();
    reucb_header[13] = REU_TOTAL_BANKS & 0xFFu; /* 0 means 256 banks. */
    reucb_header[14] = (unsigned char)(REUCB_BANK_TYPE_OFF & 0xFFu);
    reucb_header[15] = (unsigned char)(REUCB_BANK_TYPE_OFF >> 8);
    reucb_header[16] = (unsigned char)(REUCB_BANK_TYPE_SIZE & 0xFFu);
    reucb_header[17] = (unsigned char)(REUCB_BANK_TYPE_SIZE >> 8);
    reucb_header[18] = (unsigned char)(REUCB_RESOURCE_OFF & 0xFFu);
    reucb_header[19] = (unsigned char)(REUCB_RESOURCE_OFF >> 8);
    reucb_header[20] = REUCB_RESOURCE_COUNT;
    reucb_header[21] = REUCB_RESOURCE_SIZE;

    reu_dma_stash((unsigned int)reucb_header, control_bank,
                  REUCB_HEADER_OFF, REUCB_HEADER_SIZE);
}

static void reucb_write_resource(unsigned char control_bank,
                                 unsigned char index,
                                 unsigned char bank,
                                 unsigned char type,
                                 unsigned char owner,
                                 unsigned char role) {
    reucb_zero_buf(reucb_record, REUCB_RESOURCE_SIZE);
    reucb_record[0] = bank;
    reucb_record[1] = type;
    reucb_record[2] = owner;
    reucb_record[3] = 0;
    reucb_record[4] = role;
    reucb_record[5] = 0;
    reucb_record[6] = 0;
    reucb_record[7] = 0;

    reu_dma_stash((unsigned int)reucb_record, control_bank,
                  (unsigned int)(REUCB_RESOURCE_OFF +
                                 ((unsigned int)index * REUCB_RESOURCE_SIZE)),
                  REUCB_RESOURCE_SIZE);
}

static void reucb_write_resources(unsigned char control_bank) {
    reucb_write_resource(control_bank, 0, REU_READYOS_GLOBAL_PHYSICAL(),
                         REU_GLOBAL, REUCB_OWNER_SYSTEM, REUCB_ROLE_GLOBAL);
    reucb_write_resource(control_bank, 1, REU_LAUNCHER_PHYSICAL(),
                         REU_LAUNCHER, REUCB_OWNER_LAUNCHER, REUCB_ROLE_SNAPSHOT);
    reucb_write_resource(control_bank, 2, REU_LAUNCHER_OVERLAY_PHYSICAL(),
                         REU_LAUNCHER, REUCB_OWNER_LAUNCHER, REUCB_ROLE_OVERLAY);
    reucb_write_resource(control_bank, 6, REU_BANK_RS_DEBUG,
                         REU_RS_DEBUG, REUCB_OWNER_READYSHELL, REUCB_ROLE_DEBUG);
    reucb_write_resource(control_bank, 7, REU_BANK_RB_CORE,
                         REU_RB_CORE, REUCB_OWNER_READYBASIC, REUCB_ROLE_CORE);
    reucb_write_resource(control_bank, 8, REU_BANK_RB_CODE,
                         REU_RB_CODE, REUCB_OWNER_READYBASIC, REUCB_ROLE_CODE);
    reucb_write_resource(control_bank, 9, REU_BANK_RS_SCRATCH,
                         REU_RS_SCRATCH, REUCB_OWNER_READYSHELL, REUCB_ROLE_SCRATCH);
}

void reu_control_bank_sync_and_mirror(unsigned char writer_id) {
    unsigned char control_bank = REU_READYOS_GLOBAL_PHYSICAL();

    reucb_sync_from_bitmap();
    reucb_write_header(control_bank, writer_id);

    reucb_zero_buf(reucb_zero, REUCB_HEADER_SIZE);
    reu_dma_stash((unsigned int)reucb_zero, control_bank, 0x0040u, REUCB_HEADER_SIZE);
    reu_dma_stash((unsigned int)reucb_zero, control_bank, 0x0080u, REUCB_HEADER_SIZE);
    reu_dma_stash((unsigned int)reucb_zero, control_bank, 0x00C0u, REUCB_HEADER_SIZE);

    reu_dma_stash((unsigned int)REU_ALLOC_TABLE, control_bank,
                  REUCB_BANK_TYPE_OFF, REUCB_BANK_TYPE_SIZE);
    reucb_write_resources(control_bank);
}
