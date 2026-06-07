#!/usr/bin/env python3
"""Static checks for the ReadyOS logical REU bank 0 control mirror."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}")
        raise SystemExit(1)
    print(f"OK: {message}")


def define_int(text: str, name: str) -> int:
    pattern = rf"(?m)^#define\s+{re.escape(name)}\s+(.+?)\s*$"
    match = re.search(pattern, text)
    if not match:
        raise ValueError(f"missing define {name}")
    raw = match.group(1).strip()
    raw = raw.rstrip("uUlL")
    if raw.startswith("'") and raw.endswith("'") and len(raw) == 3:
        return ord(raw[1])
    return int(raw, 0)


def make_var(text: str, name: str) -> str:
    match = re.search(rf"(?m)^{re.escape(name)}\s*=\s*(.+)$", text)
    if not match:
        raise ValueError(f"missing Makefile variable {name}")
    return match.group(1)


def main() -> int:
    hdr = read("src/lib/reu_control_bank.h")
    src = read("src/lib/reu_control_bank.c")
    registry = read("src/lib/reu_control_registry.c")
    launcher = read("src/apps/launcher/launcher.c")
    reuviewer = read("src/apps/reuviewer/reuviewer.c")
    makefile = read("Makefile")

    require(define_int(hdr, "REUCB_SCHEMA_VERSION") == 3, "schema version is 3")
    require(define_int(hdr, "REUCB_HEADER_OFF") == 0x0000, "header starts at $0000")
    require(define_int(hdr, "REUCB_HEADER_SIZE") == 0x0040, "header is 64 bytes")
    require(define_int(hdr, "REUCB_BANK_TYPE_OFF") == 0x0100, "bank table mirror starts at $0100")
    require(define_int(hdr, "REUCB_BANK_TYPE_SIZE") == 0x0100, "bank table mirror is 256 bytes")
    require(define_int(hdr, "REUCB_RESOURCE_OFF") == 0x0200, "resource records start at $0200")
    require(define_int(hdr, "REUCB_RESOURCE_SIZE") == 8, "resource records are 8 bytes")
    require(define_int(hdr, "REUCB_RESOURCE_COUNT") == 10, "fixed resource record count is 10")
    require(define_int(hdr, "REUCB_APP_REG_OFF") == 0x0300, "64-app registry starts at $0300")
    require(define_int(hdr, "REUCB_APP_REG_SIZE") == 8, "app registry records are 8 bytes")
    require(define_int(hdr, "REUCB_APP_REG_COUNT") == 64, "app registry has 64 entries")
    require(define_int(hdr, "REUCB_APP_META_OFF") == 0x0500, "app metadata starts at $0500")
    require(define_int(hdr, "REUCB_APP_META_SIZE") == 13, "app filename records are 13 bytes")
    require(define_int(hdr, "REUCB_DEP_OFF") == 0x0900, "dependency records start at $0900")
    require(define_int(hdr, "REUCB_DEP_COUNT") == 128, "dependency record capacity is 128")
    require(define_int(hdr, "REUCB_RSRC_REC_OFF") == 0x0A00, "rich resource records start at $0A00")
    require(define_int(hdr, "REUCB_RSRC_REC_SIZE") == 16, "rich resource records are 16 bytes")
    require(define_int(hdr, "REUCB_RSRC_REC_COUNT") == 64, "rich resource record capacity is 64")
    require(define_int(hdr, "REUCB_DEP_LINE_OFF") == 0x0E00, "dependency lines start at $0E00")
    require(define_int(hdr, "REUCB_DEP_LINE_SIZE") == 128, "dependency line records are 128 bytes")
    require(define_int(hdr, "REUCB_CATALOG_TEXT_OFF") == 0x3000, "cold catalog text starts at $3000")
    require(define_int(hdr, "REUCB_CATALOG_NAME_OFF") == 0x3000, "catalog names start at $3000")
    require(define_int(hdr, "REUCB_CATALOG_NAME_SIZE") == 32, "catalog name records are 32 bytes")
    require(define_int(hdr, "REUCB_CATALOG_DESC_OFF") == 0x3800, "catalog descriptions start at $3800")
    require(define_int(hdr, "REUCB_CATALOG_DESC_SIZE") == 39, "catalog description records are 39 bytes")
    require(define_int(hdr, "REUCB_CATALOG_FILE_OFF") == 0x4200, "catalog file tokens start at $4200")
    require(define_int(hdr, "REUCB_CATALOG_FILE_SIZE") == 13, "catalog file token records are 13 bytes")

    require("REU_READYOS_GLOBAL_PHYSICAL()" in src, "control mirror records ReadyOS global bank")
    require("REU_LAUNCHER_PHYSICAL()" in src, "control mirror records launcher bank")
    require("REU_BANK_RS_CACHE" not in src, "control mirror no longer records fixed ReadyShell cache banks")
    require("REU_BANK_RS_SCRATCH" not in src, "control mirror no longer records fixed ReadyShell scratch bank")
    require("REU_BANK_RS_DEBUG" not in src, "control mirror no longer records fixed ReadyShell debug bank")
    require("REU_BANK_RB_CORE" not in src and "REU_BANK_RB_CODE" not in src,
            "control mirror must not record fixed ReadyBASIC core/code banks")
    require("reu_dma_stash((unsigned int)REU_ALLOC_TABLE" in src,
            "control mirror stashes resident bank table")
    require("reu_control_bank_write_launcher_registry" in registry,
            "control mirror writes launcher 64-app registry")
    require("app_rs_bank1 + first_app_index" in registry and
            "app_rs_bank3 + first_app_index" in registry and
            "app_rs_bank4 + first_app_index" in registry,
            "control mirror records loader-owned dependency/resource bank arrays")

    require("REU_CONTROL_BANK_SRC = $(LIB_DIR)/reu_control_bank.c" in makefile,
            "Makefile defines REU_CONTROL_BANK_SRC")
    require("REU_CONTROL_REGISTRY_SRC = $(LIB_DIR)/reu_control_registry.c" in makefile,
            "Makefile defines launcher-only control registry source")
    require("$(REU_CONTROL_BANK_SRC)" in make_var(makefile, "LIB_LAUNCHER"),
            "launcher links control bank module")
    require("$(REU_CONTROL_REGISTRY_SRC)" in make_var(makefile, "LIB_LAUNCHER"),
            "launcher links control registry module")
    require("$(REU_CONTROL_BANK_SRC)" in make_var(makefile, "LIB_REUVIEWER"),
            "reuviewer links control bank module")
    require("$(REU_CONTROL_REGISTRY_SRC)" not in make_var(makefile, "LIB_REUVIEWER"),
            "reuviewer does not link launcher registry writer")
    require("$(REU_CONTROL_BANK_SRC)" not in make_var(makefile, "LIB_REU_DMA"),
            "normal REU DMA library does not link control bank module")
    require("$(REU_CONTROL_BANK_SRC)" not in make_var(makefile, "LIB_REU_DMA_STATS"),
            "normal REU DMA/stats library does not link control bank module")

    require("launcher_mirror_reu_control();" in launcher,
            "launcher refreshes control mirror")
    require("reu_control_bank_write_launcher_registry(" in launcher,
            "launcher mirrors app registry into control bank")
    require("catalog_store_entry" in launcher and
            "REUCB_CATALOG_NAME_OFF" in launcher and
            "REUCB_CATALOG_DESC_OFF" in launcher and
            "REUCB_CATALOG_FILE_OFF" in launcher,
            "launcher stores cold catalog strings in logical REU bank 0")
    require("catalog_name_cache[APPS_HEIGHT]" in launcher and
            "catalog_text_buf[MAX_DESC_LEN + 1]" in launcher,
            "launcher keeps only visible catalog-name cache and one text scratch buffer")
    require("app_name_buf[" not in launcher and
            "app_desc_buf[" not in launcher and
            "app_file_buf[" not in launcher and
            "launcher_menu_items[" not in launcher,
            "launcher no longer keeps full catalog text arrays in C64 RAM")
    require("tui_handle_global_hotkey" in launcher and
            "$(TUI_HOTKEY_SRC)" in make_var(makefile, "LIB_LAUNCHER"),
            "launcher still uses the shared TUI hotkey path")
    require("launcher_control_write_resource_record" in launcher and
            "launcher_control_write_dep_line" in launcher,
            "launcher writes rich resource/dependency metadata")
    require("readyshell_overlay_names" not in launcher and
            "readyshell_overlay_offsets" not in launcher,
            "disk launcher does not carry hard-coded ReadyShell overlay placement tables")
    require("launcher_resolve_snapshot_bank" in launcher,
            "launcher has snapshot-bank resolver")
    require("bank = launcher_resolve_snapshot_bank(index);" in launcher,
            "launcher preload/REU launch paths use resolver")
    require("*SHIM_CURRENT_BANK = bank;" in launcher,
            "launcher disk path writes resolved bank to shim current bank")
    require("reu_control_bank_sync_and_mirror(REUCB_WRITER_REUVIEWER)" in reuviewer,
            "reuviewer refreshes control mirror")
    require("reuviewer_read_control_bank_header" in reuviewer and '"CB:"' in reuviewer and
            "control_bank_generation" in reuviewer,
            "reuviewer displays compact control-bank header status")
    require("reuviewer_find_resource_for_bank" in reuviewer and "OWNER:" in reuviewer,
            "reuviewer decodes rich app/resource ownership records")

    print("REU control bank static checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
