# REU Refactor Headroom Deltas

## Baseline Bank 0 Mirror Delta

Compared the pre-refactor baseline to commit `e7b5487 Add REU control bank
mirror baseline`.

| App | Before headroom | After headroom | Change | Runtime end before -> after |
|---|---:|---:|---:|---|
| launcher | 12643 | 11122 | -1521 | $949C -> $9A8D |
| editor | 11665 | 11665 | 0 | $986E -> $986E |
| quicknotes | 9471 | 9471 | 0 | $A100 -> $A100 |
| calcplus | 6593 | 6593 | 0 | $AC3E -> $AC3E |
| hexview | 32277 | 32277 | 0 | $47EA -> $47EA |
| clipmgr | 13439 | 13439 | 0 | $9180 -> $9180 |
| reuviewer | 31611 | 29372 | -2239 | $4A84 -> $5343 |
| sysinfo | 30022 | 30022 | 0 | $50B9 -> $50B9 |
| tasklist | 6022 | 6022 | 0 | $AE79 -> $AE79 |
| simplefiles | 12637 | 12637 | 0 | $94A2 -> $94A2 |
| game2048 | 28580 | 28580 | 0 | $565B -> $565B |
| deminer | 22167 | 22167 | 0 | $6F68 -> $6F68 |
| cal26 | 8704 | 8704 | 0 | $A3FF -> $A3FF |
| dizzy | 1834 | 1834 | 0 | $BED5 -> $BED5 |
| readyirc | 28959 | 28959 | 0 | $54E0 -> $54E0 |
| rirc-rrnet | 18173 | 18173 | 0 | $7F02 -> $7F02 |
| readybasic | 1031 | 1031 | 0 | $C1F8 -> $C1F8 |
| readme | 22748 | 22748 | 0 | $6D23 -> $6D23 |
| readyshell | 16585 | 16585 | 0 | $8536 -> $8536 |

## Dynamic Allocation Delta

Compared the current dynamic allocation build against committed bank `0` mirror
baseline `e7b5487`.

| App | Bank 0 baseline headroom | Dynamic headroom | Change | Runtime end |
|---|---:|---:|---:|---|
| cal26 | 8704 | 8703 | -1 | $A400 |
| calcplus | 6593 | 6593 | 0 | $AC3E |
| clipmgr | 13439 | 13439 | 0 | $9180 |
| deminer | 22167 | 22167 | 0 | $6F68 |
| dizzy | 1834 | 1834 | 0 | $BED5 |
| editor | 11665 | 11664 | -1 | $986F |
| game2048 | 28580 | 28580 | 0 | $565B |
| hexview | 32277 | 32277 | 0 | $47EA |
| launcher | 11122 | 8062 | -3060 | $A681 |
| quicknotes | 9471 | 9470 | -1 | $A101 |
| readme | 22748 | 22748 | 0 | $6D23 |
| readybasic | 1031 | 1031 | 0 | $C1F8 |
| readyirc | 28959 | 28958 | -1 | $54E1 |
| readyshell | 16585 | 16585 | 0 | $8536 |
| reuviewer | 29372 | 29372 | 0 | $5343 |
| rirc-rrnet | 18173 | 18172 | -1 | $7F03 |
| simplefiles | 12637 | 12636 | -1 | $94A3 |
| sysinfo | 30022 | 30021 | -1 | $50BA |
| tasklist | 6022 | 6021 | -1 | $AE7A |

Notes:

- The first dynamic implementation lost `8583` bytes in launcher headroom
  because a 64-entry catalog was duplicated in a resident resume cache. That
  cache was removed before acceptance.
- The accepted launcher delta is `-3060` bytes. This is primarily the real
  cost of growing resident catalog arrays from 24 to 65 entries plus dynamic
  allocation/unload code.
- The `-1` byte normal-app deltas come from broadening the shared hotkey helper
  to accept logical banks above `23`; no normal app gets the launcher allocator
  or bank `0` mirror module.
