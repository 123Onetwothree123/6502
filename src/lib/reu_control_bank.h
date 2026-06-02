/*
 * reu_control_bank.h - ReadyOS logical REU bank 0 control mirror
 *
 * This is intentionally small. Early refactor phases mirror existing
 * resident state into bank 0; they do not make bank 0 runtime authority.
 */

#ifndef REU_CONTROL_BANK_H
#define REU_CONTROL_BANK_H

#include "reu_mgr.h"

#define REUCB_SCHEMA_VERSION 1

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
#define REUCB_AUDIT_OFF         0x0280u

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

#endif /* REU_CONTROL_BANK_H */
