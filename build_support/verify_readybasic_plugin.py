#!/usr/bin/env python3
"""Static guardrails for the ReadyBASIC REU plugin layout."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASM = ROOT / "src/apps/readybasic/readybasic.s"
MAP = ROOT / "obj/readybasic.map"
REU_HDR = ROOT / "src/lib/reu_mgr.h"
PRG = ROOT / "bin/readybasic.prg"


def fail(message: str) -> None:
    raise SystemExit(f"readybasic plugin check failed: {message}")


def require(pattern: str, text: str, description: str) -> None:
    if not re.search(pattern, text, re.MULTILINE):
        fail(description)


def parse_segments(map_text: str) -> dict[str, tuple[int, int, int]]:
    segments: dict[str, tuple[int, int, int]] = {}
    for line in map_text.splitlines():
        match = re.match(r"^([A-Z][A-Z0-9_]*)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+", line)
        if match:
            name, start, end, size = match.groups()
            segments[name] = (int(start, 16), int(end, 16), int(size, 16))
    return segments


def main() -> None:
    asm = ASM.read_text()
    reu_hdr = REU_HDR.read_text()
    if not MAP.exists():
        fail("obj/readybasic.map is missing; build bin/readybasic.prg first")
    if not PRG.exists():
        fail("bin/readybasic.prg is missing; build it first")
    segments = parse_segments(MAP.read_text())

    require(r"^BASIC_START\s*=\s*\$2AC1\b", asm, "BASIC_START must be $2AC1")
    require(r"^BASIC_LIMIT\s*=\s*\$A000\b", asm, "BASIC_LIMIT must be $A000")
    require(r"^RB_REU_CORE_BANK\s*=\s*\$44\b", asm, "ReadyBASIC core bank must be $44")
    require(r"^RB_REU_CODE_BANK\s*=\s*\$45\b", asm, "ReadyBASIC code bank must be $45")
    require(r"^RB_REU_DESC_OFF\s*=\s*\$1000\b", asm, "descriptor table must live at REU offset $1000")
    require(r"^RB_REU_HANDLE_OFF\s*=\s*\$0800\b", asm, "handle directory must live at REU offset $0800")
    require(r"^RB_REU_HEAP_OFF\s*=\s*\$0C00\b", asm, "heap bitmap must live at REU offset $0C00")
    require(r"^RB_REU_COMMON_LIMIT\s*=\s*\$4000\b", asm, "ReadyBASIC common area must reserve 16KB")
    require(r"^RB_REU_DATA_OFF\s*=\s*\$4000\b", asm, "typed heap must start at REU offset $4000")
    require(r"^RB_CMD_DESC_COUNT\s*=\s*128\b", asm, "command registry must expose 128 descriptor slots")
    require(r"^RB_HANDLE_COUNT\s*=\s*128\b", asm, "handle directory must expose 128 live handles")
    require(r"^RB_HEAP_PAGES\s*=\s*192\b", asm, "typed heap must expose 192 pages / 48KB")
    require(r"^RB_REU_RUNTIME_ZP_OFF\s*=\s*\$0A00\b", asm, "runtime ZP snapshot must live at REU offset $0A00")
    require(r"^RB_REU_RUNTIME_STACK_OFF\s*=\s*\$0B00\b", asm, "runtime stack snapshot must live at REU offset $0B00")
    require(r"^SIG_UPPER\s*=\s*3\b", asm, "UPPER signature must replace STRUP")
    require(r"^SIG_LOWER\s*=\s*4\b", asm, "LOWER signature must be registered")
    require(r"^SIG_SCRCAP\s*=\s*14\b", asm, "SCRCAP signature must be registered")
    require(r"^SIG_SCRPUT\s*=\s*15\b", asm, "SCRPUT signature must be registered")
    require(r"^SIG_FADD\s*=\s*16\b", asm, "FADD signature must be registered")
    require(r"^SIG_ZPAUSE\s*=\s*SIG_BUFFREE\b", asm, "ZPAUSE must reuse the one-integer parser signature")
    require(r"#define\s+REU_RB_CORE\s+14\b", reu_hdr, "REU_RB_CORE type must stay in sync")
    require(r"#define\s+REU_RB_CODE\s+15\b", reu_hdr, "REU_RB_CODE type must stay in sync")
    require(r"#define\s+REU_BANK_RB_CORE\s+0x44\b", reu_hdr, "REU_BANK_RB_CORE must be 0x44")
    require(r"#define\s+REU_BANK_RB_CODE\s+0x45\b", reu_hdr, "REU_BANK_RB_CODE must be 0x45")

    for name in ("ENTRY", "RESIDENT", "LOWPACK", "SLOTPACK1", "SLOTPACK2", "HIDDEN", "BRIDGE", "REGSEED"):
        if name not in segments:
            fail(f"map is missing segment {name}")

    resident = segments["RESIDENT"]
    lowpack = segments["LOWPACK"]
    slotpack1 = segments["SLOTPACK1"]
    slotpack2 = segments["SLOTPACK2"]
    hidden = segments["HIDDEN"]
    bridge = segments["BRIDGE"]
    regseed = segments["REGSEED"]

    if resident[0] != 0x1200 or resident[1] >= 0x2AC0:
        fail(f"RESIDENT must fit in $1200-$2ABF, got ${resident[0]:04X}-${resident[1]:04X}")
    if resident[2] > 0x18B8:
        fail(f"RESIDENT grew past command-module slot budget $18B8, got ${resident[2]:04X}")
    if lowpack[0] != 0xA800 or lowpack[1] > 0xAFFF:
        fail(f"command slot 0 must fit under BASIC ROM at $A800-$AFFF, got ${lowpack[0]:04X}-${lowpack[1]:04X}")
    if lowpack[2] != 0x069F:
        fail(f"command slot 0 size changed from measured $069F, got ${lowpack[2]:04X}")
    if slotpack1[0] != 0xB000 or slotpack1[1] > 0xB7FF:
        fail(f"command slot 1 must fit under BASIC ROM at $B000-$B7FF, got ${slotpack1[0]:04X}-${slotpack1[1]:04X}")
    if slotpack1[2] != 0x0015:
        fail(f"command slot 1 size changed from measured $0015, got ${slotpack1[2]:04X}")
    if slotpack2[0] != 0xB800 or slotpack2[1] > 0xBFFF:
        fail(f"command slot 2 must fit under BASIC ROM at $B800-$BFFF, got ${slotpack2[0]:04X}-${slotpack2[1]:04X}")
    if slotpack2[2] != 0x0015:
        fail(f"command slot 2 size changed from measured $0015, got ${slotpack2[2]:04X}")
    if hidden[0] != 0xA000 or hidden[1] > 0xA7FF:
        fail(f"HIDDEN helper/common area must fit in $A000-$A7FF, got ${hidden[0]:04X}-${hidden[1]:04X}")
    if hidden[2] > 0x0368:
        fail(f"HIDDEN helper/common area grew past measured $0368, got ${hidden[2]:04X}")
    if bridge[0] != 0xC000 or bridge[1] >= 0xC200:
        fail(f"BRIDGE must stay below relocated shared frames at $C200, got ${bridge[0]:04X}-${bridge[1]:04X}")
    if bridge[2] > 0x01FF:
        fail(f"BRIDGE grew past command-module budget $01FF, got ${bridge[2]:04X}")
    require(r"^RB_CF\s*=\s*\$C200\b", asm, "RB_CF must be relocated to $C200")
    require(r"^RB_RF\s*=\s*\$C300\b", asm, "RB_RF must be relocated to $C300")
    require(r"^RB_DESC_BUF\s*=\s*\$C480\b", asm, "RB_DESC_BUF must be relocated to $C480")
    require(r"^RB_CMDBUF\s*=\s*\$C4A0\b", asm, "RB_CMDBUF must be relocated to $C4A0")
    require(r"^RB_PAGEBUF\s*=\s*\$C500\b", asm, "RB_PAGEBUF must be relocated to $C500")
    require(r"^RB_SLOT0_BASE\s*=\s*\$A800\b", asm, "slot 0 base must be $A800")
    require(r"^RB_SLOT1_BASE\s*=\s*\$B000\b", asm, "slot 1 base must be $B000")
    require(r"^RB_SLOT2_BASE\s*=\s*\$B800\b", asm, "slot 2 base must be $B800")
    require(r"^RB_LOW_BASE\s*=\s*RB_SLOT0_BASE\b", asm, "legacy low base alias must point at slot 0")
    require(r"^RUNTIME_ZP_BUF\s*=\s*\$C400\b", asm, "RUNTIME_ZP_BUF must be $C400")
    require(r"^RUNTIME_STACK_BUF\s*=\s*\$C500\b", asm, "RUNTIME_STACK_BUF must be $C500")
    require(r"^HIDDEN_SHADOW\s*=\s*\$C280\b", asm, "HIDDEN_SHADOW must be visible RAM at $C280")
    hidden_shadow_end = 0xC280 + hidden[2] - 1
    if hidden_shadow_end >= 0xC600:
        fail(f"HIDDEN shadow copy must stay below $C600, got $C280-${hidden_shadow_end:04X}")
    if regseed[0] != 0x5000 or regseed[2] > 0x1200:
        fail(f"REGSEED must stay within cold seed $5000-$61FF, got ${regseed[0]:04X} size ${regseed[2]:04X}")
    expected_payload = 0x6200 - 0x1000
    actual_payload = PRG.stat().st_size - 2
    if actual_payload < expected_payload:
        fail(
            "PRG payload does not cover the load-image seed span "
            f"$1000-$61FF: got ${actual_payload:04X}, need ${expected_payload:04X}"
        )

    print("readybasic plugin static check OK")


if __name__ == "__main__":
    main()
