/*
 * reu_control_bank.h - ReadyOS logical REU bank 0 control mirror
 *
 * This is intentionally small. Early refactor phases mirror existing
 * resident state into bank 0; they do not make bank 0 runtime authority.
 */

#ifndef REU_CONTROL_BANK_H
#define REU_CONTROL_BANK_H

#include "reu_mgr.h"

#define REUCB_SCHEMA_VERSION 2

#define REUCB_MAGIC0 'R'
#define REUCB_MAGIC1 'C'
#define REUCB_MAGIC2 'B'
#define REUCB_MAGIC3 '0'

#define REUCB_HEADER_OFF        0x0000u
#define REUCB_HEADER_SIZE       0x0040u
#define REUCB_RESERVED_OFF      0x0040u
#define REUCB_BANK_TYPE_OFF     0x0100u
#define REUCB_BANK_TYPE_SIZE    0x0100u
#define REUCB_RESOURCE_OFF      0x0200u
#define REUCB_RESOURCE_SIZE     8u
#define REUCB_RESOURCE_COUNT    10u
#define REUCB_APP_REG_OFF       0x0300u
#define REUCB_APP_REG_SIZE      8u
#define REUCB_APP_REG_COUNT     64u
#define REUCB_APP_META_OFF      0x0500u
#define REUCB_APP_META_SIZE     16u
#define REUCB_APP_META_COUNT    64u
#define REUCB_DEP_OFF           0x0900u
#define REUCB_DEP_SIZE          24u
#define REUCB_DEP_COUNT         128u
#define REUCB_AUDIT_OFF         0x1500u

#define REUCB_NULL_DEP          0xFFu

#define REUCB_APP_FLAG_LOADED   0x01u
#define REUCB_APP_FLAG_HAS_DEPS 0x02u

#define REUCB_DEP_KIND_RS_CACHE 1u
#define REUCB_DEP_KIND_RB_CORE  2u
#define REUCB_DEP_KIND_RB_CODE  3u

#define REUCB_WRITER_LAUNCHER   1u
#define REUCB_WRITER_REUVIEWER  2u

#define REUCB_OWNER_SYSTEM      1u
#define REUCB_OWNER_LAUNCHER    2u
#define REUCB_OWNER_READYSHELL  3u
#define REUCB_OWNER_READYBASIC  4u

#define REUCB_ROLE_GLOBAL       1u
#define REUCB_ROLE_SNAPSHOT     2u
#define REUCB_ROLE_OVERLAY      3u
#define REUCB_ROLE_CACHE        4u
#define REUCB_ROLE_DEBUG        5u
#define REUCB_ROLE_SCRATCH      6u
#define REUCB_ROLE_CORE         7u
#define REUCB_ROLE_CODE         8u

void reu_control_bank_sync_and_mirror(unsigned char writer_id);

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
    const char *app_file_buf,
    unsigned char app_file_stride,
    const unsigned char *apps_loaded);

#endif /* REU_CONTROL_BANK_H */
