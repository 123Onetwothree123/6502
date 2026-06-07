/*
 * reu_phys.c - physical REU size probe and allocation-table policy
 */

#include "reu_phys.h"

void reu_phys_apply_to_alloc_table(unsigned char encoded_count) {
    unsigned int bank;

    for (bank = 0u; bank < REU_TOTAL_BANKS; ++bank) {
        if (reu_phys_is_unavailable(encoded_count, (unsigned char)bank)) {
            REU_ALLOC_TABLE[bank] = REU_UNAVAIL;
        } else if (REU_ALLOC_TABLE[bank] == REU_UNAVAIL) {
            REU_ALLOC_TABLE[bank] = REU_FREE;
        }
    }
}

unsigned char reu_phys_count_from_alloc_table(void) {
    unsigned int bank;

    for (bank = 0u; bank < REU_TOTAL_BANKS; ++bank) {
        if (REU_ALLOC_TABLE[bank] == REU_UNAVAIL) {
            return (unsigned char)bank;
        }
    }
    return REU_PHYS_COUNT_256;
}
