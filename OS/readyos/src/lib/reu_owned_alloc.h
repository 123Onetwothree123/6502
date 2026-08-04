/*
 * reu_owned_alloc.h - app-owned REU allocation metadata helpers
 */

#ifndef REU_OWNED_ALLOC_H
#define REU_OWNED_ALLOC_H

unsigned char reu_alloc_owned_bank(unsigned char slot_id, const char *tag);
void reu_free_owned_bank(unsigned char bank);

#endif /* REU_OWNED_ALLOC_H */
