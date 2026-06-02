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
    launcher = read("src/apps/launcher/launcher.c")
    reuviewer = read("src/apps/reuviewer/reuviewer.c")
    makefile = read("Makefile")

    require(define_int(hdr, "REUCB_SCHEMA_VERSION") == 1, "schema version is 1")
    require(define_int(hdr, "REUCB_HEADER_OFF") == 0x0000, "header starts at $0000")
    require(define_int(hdr, "REUCB_HEADER_SIZE") == 0x0040, "header is 64 bytes")
    require(define_int(hdr, "REUCB_BANK_TYPE_OFF") == 0x0100, "bank table mirror starts at $0100")
    require(define_int(hdr, "REUCB_BANK_TYPE_SIZE") == 0x0100, "bank table mirror is 256 bytes")
    require(define_int(hdr, "REUCB_RESOURCE_OFF") == 0x0200, "resource records start at $0200")
    require(define_int(hdr, "REUCB_RESOURCE_SIZE") == 8, "resource records are 8 bytes")
    require(define_int(hdr, "REUCB_RESOURCE_COUNT") == 10, "fixed resource record count is 10")

    require("REU_READYOS_GLOBAL_PHYSICAL()" in src, "control mirror records ReadyOS global bank")
    require("REU_LAUNCHER_PHYSICAL()" in src, "control mirror records launcher bank")
    require("REU_BANK_RS_CACHE" not in src, "control mirror no longer records fixed ReadyShell cache banks")
    require("REU_BANK_RS_SCRATCH" in src, "control mirror records ReadyShell scratch bank")
    require("REU_BANK_RB_CORE" in src and "REU_BANK_RB_CODE" in src,
            "control mirror records ReadyBASIC core/code banks")
    require("reu_dma_stash((unsigned int)REU_ALLOC_TABLE" in src,
            "control mirror stashes resident bank table")

    require("REU_CONTROL_BANK_SRC = $(LIB_DIR)/reu_control_bank.c" in makefile,
            "Makefile defines REU_CONTROL_BANK_SRC")
    require("$(REU_CONTROL_BANK_SRC)" in make_var(makefile, "LIB_LAUNCHER"),
            "launcher links control bank module")
    require("$(REU_CONTROL_BANK_SRC)" in make_var(makefile, "LIB_REUVIEWER"),
            "reuviewer links control bank module")
    require("$(REU_CONTROL_BANK_SRC)" not in make_var(makefile, "LIB_REU_DMA"),
            "normal REU DMA library does not link control bank module")
    require("$(REU_CONTROL_BANK_SRC)" not in make_var(makefile, "LIB_REU_DMA_STATS"),
            "normal REU DMA/stats library does not link control bank module")

    require("launcher_mirror_reu_control();" in launcher,
            "launcher refreshes control mirror")
    require("launcher_resolve_snapshot_bank" in launcher,
            "launcher has snapshot-bank resolver")
    require("bank = launcher_resolve_snapshot_bank(index);" in launcher,
            "launcher preload/REU launch paths use resolver")
    require("*SHIM_CURRENT_BANK = bank;" in launcher,
            "launcher disk path writes resolved bank to shim current bank")
    require("reu_control_bank_sync_and_mirror(REUCB_WRITER_REUVIEWER)" in reuviewer,
            "reuviewer refreshes control mirror")
    require("reuviewer_read_control_bank_header" in reuviewer and "CBGEN:" in reuviewer,
            "reuviewer displays control-bank header status")

    print("REU control bank static checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
