# Wordlist ROM Size Estimate

Based on `wordlist_design.md` (26 Oct 2026 revision) and stage 6e source.

## Summary

- The wordlist feature set costs about **980 bytes of ROM** (plausible range 800 to 1,200).
  - Phase 1, the minimum Search-Order set: about 630 bytes.
  - Phase 2, the extension and compatibility words: about 350 bytes.
- The interrupt-driven build has only **18 bytes** of headroom below INITCODE, so BASEDICT and
  BASECODE must be lowered together by about **960 bytes** (range 780 to 1,180).
- That lowers the unit-test region ($C100 to BASEDICT-1) from **4,642 bytes to about 3,680**
  (range 3,460 to 3,860). Production builds are not affected, because that region is
  `$FF` fill when UNITTESTS=0.
- The one number that decides whether the tests still fit is the size of the **largest test
  group** (TSTSELECTOR 0 to 17), which is not available to me. See "What to measure".

## How the estimate was made

1. I wrote a small 6809 instruction-size counter (inherent, immediate, direct, extended,
   indexed offsets, page 2 and 3 prefixes, short and long branches, FCB/FDB/FCC/RMB,
   SERIALPOLL conditionals) and ran it over the stage 6e source.
2. Calibration against the real assembler figures in the documentation:

| Region | Real (lwasm) | Counter | Error |
| --- | --- | --- | --- |
| BASEDICT | 2,254 | 2,253 | -1 |
| BASECODE, polled | 8,803 | 8,825 | +22 (0.25%) |
| BASECODE, interrupt | 9,122 | 9,144 | +22 (0.24%) |

3. Existing routines measured with the same counter, used as yardsticks: FIND 94, WORDS 48,
   SNAME 49, HEADER 57, MARKER 53, DOMARKER 19, ENVIRONMENT? dispatcher 132, COLD 55,
   QUIT 161 bytes.
4. New routines were sized by hand against those yardsticks. The counter is accurate for
   existing code; the new-code figures are my own estimates, so allow roughly +/-25%.

## New and changed code

| Item | Bytes | Notes |
| --- | --- | --- |
| SEARCH-WORDLIST core + FIND rework | 90 | Existing FIND loop reused as the single-list search. Added: c-addr/u adaptation, loop over the order array, ROOT last, original c-addr kept for the not-found result |
| WORDLIST | 28 | Capacity check (-49), WID calculation, clear head, bump count |
| FORTH-WORDLIST | 6 | Constant |
| GET-ORDER | 30 | Copy loop plus count |
| SET-ORDER | 95 | -1 case, size check, WID validation (-11), copy loop |
| GET-CURRENT, SET-CURRENT | 31 | SET-CURRENT validates the WID |
| DEFINITIONS | 25 | Top of order to CURRENT, -50 on empty |
| Initialisation in COLD | 50 | Copy ROM heads, clear the rest, set order and CURRENT |
| HEADER | 10 | Link from CURRENT's head, update that head |
| SNAME | 25 | Walks every wordlist in the order |
| WORDS | 10 | Lists the top wordlist |
| MARKER + DOMARKER | 55 | Snapshot/restore all heads, counts, order, CURRENT |
| QUIT checkpoint | 12 | Roll back CURRENT's head as well |
| ENVIRONMENT? WORDLISTS | 15 | Table entry plus string |
| Throw stubs (-49, -50, -11) | 20 | Shared |
| **Phase 1 code** | **~500** | |
| ONLY | 8 | `-1 SET-ORDER` |
| PREVIOUS | 12 | |
| ALSO | 25 | |
| FORTH | 18 | |
| ORDER | 120 | Name lookup, raw WID fallback, "current" line |
| VOCABULARY (definer + runtime) | 75 | |
| ROOT | 10 | Replaces top of order |
| **Phase 2 code** | **~270** | |

## New dictionary headers

Each header is name length + 5 bytes (flag/length, link, xt). FIND already has one.

| Phase | Words | Bytes |
| --- | --- | --- |
| 1 | WORDLIST 13, FORTH-WORDLIST 18, GET-ORDER 14, SET-ORDER 14, SEARCH-WORDLIST 20, GET-CURRENT 16, SET-CURRENT 16, DEFINITIONS 16 | 127 |
| 2 | ONLY 9, PREVIOUS 13, ALSO 9, FORTH 10, ORDER 10, VOCABULARY 15, ROOT 9 | 75 |

Plus the ROM head array: 4 bytes if only ROOT and FORTH cells are stored (the rest are cleared
at start-up), 16 if all 8 cells are stored.

## Totals

| | Code | Headers + data | Total | Range |
| --- | --- | --- | --- | --- |
| Phase 1 | ~500 | ~131 | ~630 | 500 to 800 |
| Phase 2 | ~270 | ~75 | ~350 | 280 to 430 |
| **Both** | **~770** | **~210** | **~980** | **800 to 1,200** |

RAM is not an issue: LATEST-PTRS, WIDS, counts, CURRENT, ROOT cell and a name array need about
60 bytes, and page zero has 187 free. Each MARKER body grows from 8 to about 38 bytes of
dictionary.

## Effect on the memory map

Both ROM regions move down together by the growth minus the headroom of the tight (interrupt)
build:

| | Now | After (nominal) |
| --- | --- | --- |
| Headroom below INITCODE, interrupt build | 18 | 0 |
| Headroom below INITCODE, polled build | 338 | about 320 |
| BASECODE start | $DBF0 | about $D830 |
| BASEDICT start | $D322 | about $CF60 |
| Unit-test region ($C100 to BASEDICT-1) | 4,642 | about 3,680 |

Total ROM is not short: free space after the feature is still about 3,700 bytes in the
interrupt build. The squeeze is purely that the test group sits in the same fixed region.

## What to measure

Every test group must fit in the shrunken region, and the new Search-Order test group
(TSTSELECTOR 18) adds a group of its own. To get the real figures:

1. Add `TSTEND EQU *` just before the `ROM:` label in `forth6809.asm`.
2. For each TSTSELECTOR 0 to 18 (the ones that exist), assemble with
   `--define=UNITTESTS=1 --list` and read `TSTEND - USROMSTRT` from the symbol table.
3. Take the largest. It must be at most 3,680 minus a safety margin of about 150.

`FILL $FF,BASEDICT-ROM` already makes the assembler reject an overrun, so a build that does not
fit fails loudly rather than corrupting anything.

## Options if the largest test group is too big

In order of least pain:

1. **Phase the work.** Phase 1 alone needs about 630 bytes, so the region only drops to about
   4,030.
2. **Make Phase 2 conditional** (`IFNE WORDLISTEXT`). ORDER, VOCABULARY and ROOT are about
   240 bytes with their headers. Test builds of large groups can assemble with it off.
3. **Move ORDER, VOCABULARY and ROOT into a Forth source file** loaded on demand (for example
   by an ASSEMBLER utility). This is about 240 bytes saved in ROM.
4. **Drop the -11 WID validation** in SET-ORDER and SET-CURRENT. About 40 bytes saved, at the
   cost of the safety net you wanted.
5. **Implement ONLY, PREVIOUS, ALSO and FORTH as JSR chains** instead of assembly. Saves a few
   bytes only.
6. **Split the largest test group** into two TSTSELECTOR values.

## Caveats

- The size counter is calibrated to within 0.3% on existing code, but the new routines are my
  hand estimates and have not been assembled. No lwasm is available here.
- Branch lengths (short or long) in new code can move a routine by 5 to 10%.
- The MARKER change assumes the full snapshot; the design document's simpler "prune CURRENT
  only" approach would cut about 40 bytes but would not restore other wordlists' heads.
