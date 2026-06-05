#ifndef RS_UI_STATE_H
#define RS_UI_STATE_H

#include "../platform/rs_platform.h"

/*
 * Shared ReadyShell state lives in a launcher-assigned REU state bank instead
 * of overlay or resident heap RAM. Keep these as relative offsets so the
 * platform layer can resolve the current physical bank without teaching
 * ReadyShell about the launcher registry.
 */
#define RS_REU_CMD_REG_HDR_REL         0x8010u
#define RS_REU_CMD_REG_HDR_OFF         rs_reu_state_abs(RS_REU_CMD_REG_HDR_REL)
#define RS_REU_CMD_REG_HDR_LEN         8u
#define RS_REU_CMD_REG_DESC_REL        0x8020u
#define RS_REU_CMD_REG_DESC_OFF        rs_reu_state_abs(RS_REU_CMD_REG_DESC_REL)
#define RS_REU_CMD_REG_DESC_LEN        6u
#define RS_REU_CMD_REG_DESC_CAP        16u
#define RS_REU_CMD_REG_STATE_REL       0x8080u
#define RS_REU_CMD_REG_STATE_OFF       rs_reu_state_abs(RS_REU_CMD_REG_STATE_REL)
#define RS_REU_CMD_REG_STATE_LEN       18u
#define RS_REU_CMD_REG_STATE_CAP       6u

#define RS_REU_SHARED_META_REL         0x80F0u
#define RS_REU_SHARED_META_OFF         rs_reu_state_abs(RS_REU_SHARED_META_REL)
#define RS_REU_OVL_CACHE_META_OFF      RS_REU_SHARED_META_OFF
#define RS_REU_OVL_CACHE_META_LEN      36u
#define RS_REU_OVL_CACHE_META_VERSION  4u
#define RS_REU_OVL_CACHE_META_REC_OFF  8u
#define RS_REU_OVL_CACHE_META_REC_LEN  3u
#define RS_REU_OVL_CACHE_PARSE_REL     0x0000u
#define RS_REU_OVL_CACHE_EXEC_REL      0x3800u
#define RS_REU_OVL_CACHE_CMD3_REL      0x7000u
#define RS_REU_OVL_CACHE_CMD5_REL      0xA800u
#define RS_REU_OVL_CACHE_CMD4_REL      0x0000u
#define RS_REU_OVL_CACHE_CMD6_REL      0x3800u
#define RS_REU_OVL_CACHE_CMD7_REL      0x7000u
#define RS_REU_OVL_CACHE_CMD8_REL      0xA800u
#define RS_REU_OVL_CACHE_EDIT_REL      0x0000u
#define RS_REU_OVL_CACHE_SLOT_LEN      0x3800u
#define RS_REU_OVL_CACHE_VALID_PARSE   0x0001u
#define RS_REU_OVL_CACHE_VALID_EXEC    0x0002u
#define RS_REU_OVL_CACHE_VALID_CMD3    0x0004u
#define RS_REU_OVL_CACHE_VALID_CMD4    0x0008u
#define RS_REU_OVL_CACHE_VALID_CMD5    0x0010u
#define RS_REU_OVL_CACHE_VALID_CMD6    0x0020u
#define RS_REU_OVL_CACHE_VALID_CMD7    0x0040u
#define RS_REU_OVL_CACHE_VALID_CMD8    0x0080u
#define RS_REU_OVL_CACHE_VALID_EDIT    0x0100u

#define RS_REU_UI_FLAGS_REL 0x8114u
#define RS_REU_UI_FLAGS_OFF rs_reu_state_abs(RS_REU_UI_FLAGS_REL)
#define RS_UI_FLAG_PAUSED 0x01u

#endif
