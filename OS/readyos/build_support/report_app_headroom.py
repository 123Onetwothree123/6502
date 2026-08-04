#!/usr/bin/env python3
"""Emit ReadyOS app memory/headroom facts from cc65 linker maps.

This is intentionally a report, not a pass/fail gate.  The gate remains
verify_memory_map.py.  This file gives REU refactor work a stable artifact for
before/after comparison before bank allocation authority or micromodule layout
changes are made.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import verify_memory_map as memmap


ROOT = Path(__file__).resolve().parents[1]
APP_WINDOW_END = 0xC5FF


def hex4(value: int) -> str:
    return f"0x{value:04X}"


def readyshell_heap_report(txt: str, segs: dict[str, tuple[int, int, int]]):
    if "BSS" not in segs:
        return None
    try:
        overlay_loadaddr = memmap.parse_map_symbol(txt, "__OVERLAY_LOADADDR__")
        overlay_start = memmap.parse_map_symbol(txt, "__OVERLAYSTART__")
        himem = memmap.parse_map_symbol(txt, "__HIMEM__")
    except ValueError:
        return None

    bss_end = segs["BSS"][1]
    heap_start = bss_end + 1
    if heap_start & 1:
        heap_start += 1
    heap_end = overlay_loadaddr - 1
    heap_size = heap_end - heap_start + 1 if heap_end >= heap_start else 0
    overlay_window = himem - overlay_start
    return {
        "heap_start": hex4(heap_start),
        "heap_end": hex4(heap_end),
        "heap_size": heap_size,
        "overlay_loadaddr": hex4(overlay_loadaddr),
        "overlay_start": hex4(overlay_start),
        "himem": hex4(himem),
        "overlay_window": overlay_window,
    }


def map_report(rel: str, spec: dict) -> dict:
    path = ROOT / rel
    txt, segs = memmap.parse_map_segments(path)
    main_names = spec["main_segments"]
    used_segments = {
        name: {
            "start": hex4(start),
            "end": hex4(end),
            "size": size,
        }
        for name, (start, end, size) in segs.items()
        if name in main_names
    }
    max_end = max(end for name, (_start, end, _size) in segs.items() if name in main_names)
    total_size = sum(size for name, (_start, _end, size) in segs.items() if name in main_names)
    report = {
        "name": Path(rel).stem,
        "map": rel,
        "runtime_end": hex4(max_end),
        "app_window_end": hex4(APP_WINDOW_END),
        "app_window_headroom": APP_WINDOW_END - max_end,
        "main_segment_total": total_size,
        "segments": used_segments,
    }
    if rel.endswith("readyshell.map"):
        heap = readyshell_heap_report(txt, segs)
        if heap:
            report["readyshell"] = heap
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional JSON output path. Prints to stdout when omitted.",
    )
    args = parser.parse_args()

    spec = json.loads(memmap.SPEC_PATH.read_text(encoding="utf-8"))
    reports = []
    for rel in spec["map_files"]:
        path = ROOT / rel
        if not path.exists():
            print(f"missing map file: {rel}", file=sys.stderr)
            return 1
        reports.append(map_report(rel, spec))

    payload = {
        "app_window_start": hex4(int(str(spec["ram_windows"]["app_runtime"]["start"]), 0)),
        "app_window_end": hex4(APP_WINDOW_END),
        "maps": reports,
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
