# Search-Order Phase 2 - implementation notes (stage 6g)

Source: `forth6809_stage_6g.asm.txt`, built from your forth6809.asm.txt (stage 6f with the
label fixes and TSTEND). Shadow: `forth6809 20261027.shd.txt`. Tests:
`33_search_order.tests.fs.txt` (76 tests, now including Phase 2).
`unit_tests.asm.txt` has the TSTWORDS fix only.

## Words added
ONLY, ALSO, PREVIOUS, FORTH, ROOT, VOCABULARY, ORDER. All are in the ROOT chain, so they
are found after `0 SET-ORDER` and through FORTH-WORDLIST.

- ONLY = the minimum order, FORTH only (`-1 SET-ORDER` now jumps to it).
- ALSO duplicates the first wordlist; -49 if the order is full, -50 if it is empty.
- PREVIOUS drops the first wordlist; -50 if the order is empty.
- FORTH / ROOT replace the first wordlist (or become the only one if the order is empty).
- VOCABULARY name: a new wordlist plus a word that replaces the first wordlist. Built like
  CONSTANT, behaviour DOVOCAB, data field = the WID. Throws -8 with 10 wordlists.
- ORDER prints the order, first wordlist first, then ` Current: ` and the CURRENT list.
  Names come from a new WLNAMES array; a wordlist with no name (from WORDLIST) is shown as
  its WID number.

## Changes to Phase 1 structures
- ROOT now has a WID (the second WLHEADS cell, $5D), so ROOT works as a word and as an
  argument to SEARCH-WORDLIST. FORTH is the first cell ($5B). SRCHORD reads ROOT's head
  from that cell, so words added with `ROOT DEFINITIONS` are found.
- WLHEADS is 10 cells (FORTH, ROOT, 8 more). WLNAMES is a new parallel 10 cells.
  GLOBALS_USED 107 -> 131. ENVIRONMENT? WORDLISTS stays 8 (the order depth).

## ROM
BASEDICT 2382 -> 2457, BASECODE 9266 -> 9461 (polled) / 9585 -> 9780 (interrupt).
BASECODE = $D96C, BASEDICT = $CFD3. The interrupt build ends at $FFA0, 4 bytes below INITCODE.
Unit-test region $C100-$CFD3. Group 8 (ends $D016) is now 67 bytes too big and needs
splitting. Group 9 (ends $CFAA) still fits, with 41 bytes spare. With 8 and 9 you listed, 9 now
has little room if its tests grow. TSTEND values reproduce your list for 0, 7, 8, 9, 12, 18.

## Checks (emulator, polled build)
- 33_search_order: 76 run, 0 failed. Sections 12 (73) and 8 (71): 0 failed.
- Unit tests for every group except 8 run to the end with no FAIL, other than TSTKEYQ (group 0),
  which also fails on stage 6e (the emulator has no keyboard).
- All groups assemble with the new labels (group 8 checked with a lower BASEDICT).
- Bug found and fixed while testing: ALSO and PREVIOUS first worked on the wrong end of the array.
- Not run: SERIALPOLL=0 builds in the emulator, the other ANS sections, MAME.
