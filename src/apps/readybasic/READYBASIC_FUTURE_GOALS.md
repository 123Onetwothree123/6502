# ReadyBASIC Future Goals

This document captures intended ReadyBASIC directions that are not part of the
current implemented design. The current source of truth remains
`readybasic.s` plus `READYBASIC_CURRENT_DESIGN.md`; items here are planning
notes for future implementation work.

## REU-Backed Handle System

ReadyBASIC should grow from the current small sample handle table into a
REU-backed handle descriptor system. The default target should be 64 live
handles, with RAM holding only enough scratch space to fetch, validate, and
update one descriptor at a time. The canonical descriptor table and allocator
metadata should live in REU so larger handle counts do not consume scarce
resident or bridge RAM.

The current implementation keeps the V1 live-handle table at eight entries but
now proves the type model with both byte-buffer handles and screen text+color
handles. That is the stepping stone, not the endpoint: the next handle-table
growth should move descriptor metadata itself into REU and keep only one
descriptor-sized RAM buffer resident.

Handles should be typed from the start rather than treated as generic memory
blocks. Some future handles will represent plain byte buffers, but others will
represent structured C64 resources such as text screen buffers, text-plus-color
screen buffers, bitmap or graphics screen buffers, variable character sets,
sprites, sprite sheets, file/cache objects, or command-private working sets.
Each command family should validate the handle type it accepts, so a screen
command cannot accidentally consume a sprite-sheet handle and a memory command
cannot silently reinterpret a structured graphics buffer.

Useful descriptor fields would likely include allocation state, type, flags,
REU bank, REU offset or page, byte length, and a generation/version byte. The
generation byte would let ReadyBASIC reject stale handles after free/reuse while
still keeping the BASIC-visible handle value compact.

## Command Signatures

The current signature parser is intentionally small and resident-code driven.
Future work should consider a compact REU-backed signature table so commands can
share parameter shapes without adding one resident parser branch per new
command. The goal is not a large dynamic parser, but a small data-driven layer
for common forms such as numeric inputs, string inputs, array base/count pairs,
typed handles, and optional output targets.

## Command Naming

Future public command names should be screened against C64 BASIC tokenization
before implementation. Avoid names that contain BASIC keywords, functions,
operators, pseudo-variables, or short token names as substrings. In practice,
that means avoiding embedded words such as `SAVE`, `LOAD`, `RUN`, `LIST`, `NEW`,
`PRINT`, `INPUT`, `DATA`, `REM`, `SYS`, `FN`, `FRE`, and `PI`. Prefer a short
synonym over adding another resident parser exception.

Every new name should have direct and stored-program probes that cover `LIST`,
`RUN`, colon chains, and `IF ... THEN !COMMAND`. This catches tokenizer surprises
before the command becomes part of the user-facing vocabulary.

## Resource-Oriented Commands

Future command families should favor stable handles for long-lived resources
instead of copying large values through BASIC variables. BASIC should keep small
integers and short strings visible to the user, while REU stores larger command
state and resource data. This keeps the BASIC workspace readable and compact
while allowing richer graphics, text, storage, and tool workflows.
