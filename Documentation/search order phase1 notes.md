# Search-Order Phase 1 - implementation notes (stage 6f)

Source: `forth6809_stage_6f.asm.txt` (from stage 6e). Shadow: `forth6809 20261026.shd.txt`
(new blocks WLHEADS.1, BASEROOTLATEST.1, SEARCHORDER.1). Tests: `33_search_order.tests.fs.txt`.

## Words added
WORDLIST, FORTH-WORDLIST, GET-ORDER, SET-ORDER, SEARCH-WORDLIST, GET-CURRENT,
SET-CURRENT, DEFINITIONS. FIND was reworked. ENVIRONMENT? WORDLISTS = 8.

## Data (page zero, 38 bytes, GLOBALS_USED 69 -> 107)
WLEND $45, CURRENT $47, ORDEND $49, ORDER $4B (8 cells), WLHEADS $5B (8 cells).
A WID is the address of its WLHEADS cell (FORTH-WORDLIST = $5B = 91). ROOT has no WID.

## Behaviour
- FIND searches ORDER first-to-last, then ROOT. ROOT is the 8 new words. The FORTH chain
  continues into ROOT, so FORTH-WORDLIST contains them.
- HEADER links new words into the CURRENT wordlist. LATEST is still "newest header of any
  wordlist", so IMMEDIATE, SETDOES and ; are unchanged.
- QUIT error path and MARKER both call PRUNE, which unlinks RAM headers at or above the
  saved DPHERE from every wordlist. MARKER also saves and restores WLEND, CURRENT, ORDEND
  and ORDER (22 bytes more per marker).
- SNAME searches every wordlist. WORDS lists the first wordlist of the order.
- Throws: -49 (n > 8), -50 (n < -1, or DEFINITIONS with an empty order), -11 (bad WID),
  -8 (WORDLIST when 8 exist).
- Not standard: `0 SET-ORDER` leaves an empty order in which ROOT is still searched.
  FIND is not in ROOT, so it is unavailable after `0 SET-ORDER`.

## ROM
BASEDICT 2254 -> 2382, BASECODE 8803 -> 9266 (polled) / 9122 -> 9585 (interrupt),
INITCODE 72 -> 75. BASECODE = $DA30, BASEDICT = $D0E2. Unit-test region $C100-$D0E2
(3,938 bytes). All unit-test groups from your list (largest end $D016) still fit. Interrupt
build ends $FFA1, 3 bytes below INITCODE.

## Unit tests - check these
`unit_tests.asm` was not visible to me. FIND now ignores LATEST and uses WLHEADS/ORDER.
COLDSTRT calls WLINIT before the tests so FIND works. A test that rewinds the dictionary
by `LATEST = BASELATEST` no longer rewinds FIND: it must also set `WLHEADS` ($5B) to
BASELATEST. Tests that call HEADER now also move the head at WLHEADS.

## How it was checked (no MAME; own assembler and 6809 emulator)
- Assembled both builds. Sizes of stage 6e reproduce lwasm's exactly.
- Emulator boots the real image. Section 12 (73 tests), section 8 (71) and the prelude pass
  on 6f exactly as on 6e. `33_search_order.tests.fs`: 51 run, 0 failed.
- Checked by hand: error pruning in QUIT, MARKER pruning, SNAME, WORDS, -8/-11/-49/-50.
- Not run: the unit tests, the interrupt-driven build, the other ANS sections.

## Phase 2 still to do
ONLY, PREVIOUS, ALSO, FORTH, ORDER, VOCABULARY, ROOT. Expect about 350 bytes more.
