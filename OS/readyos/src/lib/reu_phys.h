/*
 * reu_phys.h - physical REU size probe and allocation-table policy
 */

#ifndef REU_PHYS_H
#define REU_PHYS_H

#include "reu_mgr.h"

/* Encoded bank count: 0 means 256 banks so it fits in one byte. */
#define REU_PHYS_COUNT_256 0u

#define reu_phys_display_count(encoded_count) \
    (((encoded_count) == REU_PHYS_COUNT_256) ? 256u : (unsigned int)(encoded_count))
#define reu_phys_is_unavailable(encoded_count, bank) \
    ((unsigned char)((encoded_count) != REU_PHYS_COUNT_256 && \
                     (unsigned char)(bank) >= (encoded_count)))

unsigned char reu_phys_detect_bank_count(void);
void reu_phys_apply_to_alloc_table(unsigned char encoded_count);
unsigned char reu_phys_count_from_alloc_table(void);

#endif /* REU_PHYS_H */
