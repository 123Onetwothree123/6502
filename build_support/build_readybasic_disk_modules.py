#!/usr/bin/env python3
"""Build tiny ReadyBASIC disk-loadable command module PRGs."""

from __future__ import annotations

import argparse
from pathlib import Path


LOAD_ADDR = 0xC500
SIG_SCRCAP = 14

RB_SLOT_PROOF_1 = 0x02
RB_SLOT_PROOF_2 = 0x04
RB_SLOT_PROOF_12 = RB_SLOT_PROOF_1 | RB_SLOT_PROOF_2


def int_command_payload(value: int) -> bytes:
    """Return assembler-equivalent 6502 code for a no-arg integer command."""
    return bytes(
        [
            0xA9,
            0x00,
            0x8D,
            0x00,
            0xC3,
            0xA9,
            0x01,
            0x8D,
            0x02,
            0xC3,
            0xA9,
            value & 0xFF,
            0x8D,
            0x03,
            0xC3,
            0xA9,
            0x00,
            0x8D,
            0x04,
            0xC3,
            0x60,
        ]
    )


def descriptor(
    *,
    command_id: int,
    module_id: int,
    reu_offset: int,
    payload_size: int,
    submodule_id: int,
    overlay_id: int,
    slot_mask: int,
    generation: int,
    signature_id: int,
    name: str,
) -> bytes:
    name_bytes = name.encode("ascii")
    if len(name_bytes) > 15:
        raise ValueError(f"command name too long: {name}")
    return bytes(
        [
            command_id,
            module_id,
            reu_offset & 0xFF,
            reu_offset >> 8,
            payload_size & 0xFF,
            payload_size >> 8,
            submodule_id,
            overlay_id,
            slot_mask,
            generation,
            0,
            0,
            0,
            0,
            signature_id,
            len(name_bytes),
        ]
    ) + name_bytes.ljust(16, b"\x00")


def build_module(
    *,
    module_id: int,
    desc_reu_offset: int,
    commands: list[dict[str, int | str]],
) -> bytes:
    descriptors: list[bytes] = []
    payloads: list[tuple[int, bytes]] = []
    for command in commands:
        payload = int_command_payload(int(command["return_value"]))
        reu_offset = int(command["reu_offset"])
        descriptors.append(
            descriptor(
                command_id=int(command["command_id"]),
                module_id=module_id,
                reu_offset=reu_offset,
                payload_size=len(payload),
                submodule_id=int(command["submodule_id"]),
                overlay_id=int(command["overlay_id"]),
                slot_mask=int(command["slot_mask"]),
                generation=1,
                signature_id=SIG_SCRCAP,
                name=str(command["name"]),
            )
        )
        payloads.append((reu_offset, payload))

    desc_blob = b"".join(descriptors)
    desc_offset = 16
    payload_dir_offset = desc_offset + len(desc_blob)
    payload_offset = payload_dir_offset + 6 * len(payloads)
    payload_dir = bytearray()
    payload_blob = bytearray()
    for reu_offset, payload in payloads:
        payload_dir.extend(
            [
                payload_offset & 0xFF,
                reu_offset & 0xFF,
                reu_offset >> 8,
                len(payload) & 0xFF,
                len(payload) >> 8,
                0,
            ]
        )
        payload_blob.extend(payload)
        payload_offset += len(payload)

    blob = bytearray()
    blob.extend(b"RBM!")
    blob.extend(
        [
            1,
            module_id,
            len(descriptors),
            len(payloads),
            desc_offset,
            payload_dir_offset,
            desc_reu_offset & 0xFF,
            desc_reu_offset >> 8,
            0,
            0,
            0,
            0,
        ]
    )
    blob.extend(desc_blob)
    blob.extend(payload_dir)
    blob.extend(payload_blob)
    if len(blob) > 254:
        raise ValueError(
            f"module {module_id} is too large for the $C500 loader page: {len(blob)} bytes"
        )
    return bytes([LOAD_ADDR & 0xFF, LOAD_ADDR >> 8]) + bytes(blob)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    modules = {
        "rbm1.prg": build_module(
            module_id=3,
            desc_reu_offset=0x1500,
            commands=[
                {
                    "command_id": 29,
                    "name": "ZDM1",
                    "return_value": 61,
                    "reu_offset": 0x3000,
                    "submodule_id": 1,
                    "overlay_id": 0,
                    "slot_mask": RB_SLOT_PROOF_1,
                }
            ],
        ),
        "rbm2.prg": build_module(
            module_id=4,
            desc_reu_offset=0x1600,
            commands=[
                {
                    "command_id": 30,
                    "name": "ZDM2S",
                    "return_value": 74,
                    "reu_offset": 0x3200,
                    "submodule_id": 2,
                    "overlay_id": 0,
                    "slot_mask": RB_SLOT_PROOF_12,
                },
                {
                    "command_id": 31,
                    "name": "ZDOV1",
                    "return_value": 72,
                    "reu_offset": 0x3300,
                    "submodule_id": 5,
                    "overlay_id": 1,
                    "slot_mask": RB_SLOT_PROOF_2,
                },
                {
                    "command_id": 32,
                    "name": "ZDOV2",
                    "return_value": 73,
                    "reu_offset": 0x3400,
                    "submodule_id": 5,
                    "overlay_id": 2,
                    "slot_mask": RB_SLOT_PROOF_2,
                },
            ],
        ),
    }
    for filename, payload in modules.items():
        (args.out_dir / filename).write_bytes(payload)


if __name__ == "__main__":
    main()
