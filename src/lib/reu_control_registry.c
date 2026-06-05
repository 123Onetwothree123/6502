/*
 * reu_control_registry.c - launcher-only long-form bank 0 registry writer
 *
 * Keep this intentionally plain: bank 0 stores normalized launcher arrays in
 * separate blocks so future tools can copy just the hot subset they need.
 */

#include "reu_control_bank.h"

#define REUCB_APP_ARRAY_LEN 64u

void reu_control_bank_write_launcher_registry(
    unsigned char first_app_index,
    unsigned char app_count,
    const unsigned char *app_banks,
    const unsigned char *app_drives,
    const unsigned char *app_default_slots,
    const unsigned char *app_resource_sets,
    const unsigned char *app_resource_loaded,
    const unsigned char *app_rs_bank1,
    const unsigned char *app_rs_bank2,
    const unsigned char *app_rs_bank3,
    const unsigned char *app_rs_bank4,
    const char *app_file_buf,
    unsigned char app_file_stride,
    const unsigned char *apps_loaded) {
    unsigned char control_bank = REU_READYOS_GLOBAL_PHYSICAL();
    unsigned int file_off;

    (void)app_count;

    reu_dma_stash((unsigned int)(app_banks + first_app_index), control_bank,
                  REUCB_APP_REG_OFF, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(apps_loaded + first_app_index), control_bank,
                  REUCB_APP_REG_OFF + 0x0040u, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(app_resource_sets + first_app_index), control_bank,
                  REUCB_APP_REG_OFF + 0x0080u, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(app_resource_loaded + first_app_index), control_bank,
                  REUCB_APP_REG_OFF + 0x00C0u, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(app_drives + first_app_index), control_bank,
                  REUCB_APP_REG_OFF + 0x0100u, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(app_default_slots + first_app_index), control_bank,
                  REUCB_APP_REG_OFF + 0x0140u, REUCB_APP_ARRAY_LEN);

    file_off = (unsigned int)first_app_index * app_file_stride;
    reu_dma_stash((unsigned int)(app_file_buf + file_off), control_bank,
                  REUCB_APP_META_OFF,
                  (unsigned int)REUCB_APP_ARRAY_LEN * app_file_stride);

    reu_dma_stash((unsigned int)(app_rs_bank1 + first_app_index), control_bank,
                  REUCB_DEP_OFF, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(app_rs_bank2 + first_app_index), control_bank,
                  REUCB_DEP_OFF + 0x0040u, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(app_rs_bank3 + first_app_index), control_bank,
                  REUCB_DEP_OFF + 0x0080u, REUCB_APP_ARRAY_LEN);
    reu_dma_stash((unsigned int)(app_rs_bank4 + first_app_index), control_bank,
                  REUCB_DEP_OFF + 0x00C0u, REUCB_APP_ARRAY_LEN);
}
