# OPEN ITEMS CHECKLIST — part 7 (28 October 2026)

Changes since part 6 (17 October 2026). Stages 6f to 6h add the Search-Order word
set (the "wordlist tranche"). Assembler unit tests and ANS tests all pass in MAME
(reported 27 October). Source: `forth6809_stage_6h.asm`; shadow:
`forth6809 20261027.shd`; documentation: `ClaudeForth 20261028`.

## Search-Order word set (stages 6f to 6h)

- [x] **Phase 1 (6f).** `WORDLIST`, `FORTH-WORDLIST`, `GET-ORDER`, `SET-ORDER`,
      `SEARCH-WORDLIST`, `GET-CURRENT`, `SET-CURRENT`, `DEFINITIONS`. `FIND` now
      searches the search order (`SRCHORD`), then ROOT. `HEADER` links into the
      CURRENT wordlist. `LATEST` still means "newest header of any wordlist" and is
      used by `IMMEDIATE`, `SETDOES` and the smudge clear.
- [x] **Phase 2 (6g, 6h).** `ONLY`, `ALSO`, `PREVIOUS`, `FORTH`, `ROOT`,
      `VOCABULARY`, `ORDER`. All sit in the ROOT chain, so they are found after
      `0 SET-ORDER`. ROOT and FORTH have WIDs (the first two `WLHEADS` cells).
- [x] **Data structures (page zero).** `WLEND`, `CURRENT`, `ORDEND`, `ORDER` (8 cells)
      form the 22-byte `SRCHSAVE` block; `WLHEADS` (10 cells) and `WLNAMES` (10
      cells) follow. `GLOBALS_USED` is 131 (`$00`-`$82`).
- [x] **ROOT chain.** The 15 Search-Order headers come first in `BASEDICT`. The
      oldest FORTH header (`H_BRTHEN`) links to `BASEROOTLATEST`, so the FORTH chain
      ends in the ROOT words and `FORTH-WORDLIST` contains them (260 words in all).
- [x] **`MARKER`** now saves the search-order block (30 bytes in all) and `DOMARKER`
      restores it, then calls `PRUNE`, which unlinks every RAM header at or above the
      saved `DPHERE` from every wordlist. `QUIT` calls `PRUNE` after a caught error.
      Wordlists made after the marker vanish (`WLEND` restored); `CURRENT` and the
      order return to their values at the marker.
- [x] **Revised words:** `FIND`, `WORDS` (lists the first wordlist only), `SNAME`
      (searches every wordlist), `MARKER`, `QUIT`, `ENVIRONMENT?` (`WORDLISTS` = 8).
- [x] **ANS test file `33_search_order.tests.fs`**, 76 tests, written for this
      project (the standard's test suite has no Search-Order tests). Passes.
- [x] **Bugs found while testing, all fixed:** `ALSO` and `PREVIOUS` worked on the
      wrong end of the `ORDER` array (the first tests were symmetric and missed it;
      asymmetric tests added); `BSR` out of range in the new routines (changed to
      `JSR`); stale size constants for 6g (interrupt code 9802, not 9780).
- [x] **Unit-test fixes.** `FIND` ignoring a faked chain: nine tests now also set
      `WLHEADS`. `TSTWORDS` saves and sets `WLHEADS`. `TSTREPORT` calls `WLINIT`
      (a header built by an earlier test had made the `TSTMARKER` header link to
      itself and hang). `COLDSTRT` calls `WLINIT` before the tests, since tests run
      before `COLD`. The labels `SODONE` and `PRDONE` clashed with unit-test labels
      and are now `SORDONE` and `PRNDONE`.
- [x] **Unit test group 8 split** (stage 6h): group 8 keeps `VARIABLE`, `CONSTANT`,
      `:`, `CREATE`/`DOES>`, `2VARIABLE`, `2CONSTANT`; new group 19 has `BUFFER:`,
      `VALUE`/`TO`, `DEFER`, `DEFER@`/`DEFER!`, `IS`/`ACTION-OF`, `MARKER`.
      Selectors now run 0 to 19; selector 0 calls all of them. `TSTEND EQU *` is a
      permanent fixture marking the end of each group.

## ROM layout

- [x] `BASECODE` `$D95C`, `BASEDICT` `$CFC3`. `BASEDICT` 2457 bytes; `BASECODE` 9478
      polled (`$D95C`-`$FE61`), 9797 interrupt-driven (`$D95C`-`$FFA0`); `INITSIZE` 75.
      Padding below `INITCODE`: 322 bytes polled, **3 bytes interrupt-driven**.
- [ ] **Interrupt-driven headroom is 3 bytes.** Any addition to the base code needs
      `BASECODE`/`BASEDICT` lowered again. The spare ROM below `BASEDICT` is 3779
      bytes, but the unit-test groups are assembled there: group 9 ends `$CFBD`
      (6 bytes spare at the current `BASEDICT`) and group 19 ends `$CA6C`. Lowering
      `BASEDICT` further will need another group split.

## Open items

- [ ] **Add `19` to `run all tests.sh` and `build all tests.sh`** (their selector
      lists and section-name arrays stop at 18). Add a `3.9_DefWords2` name.
- [ ] **Add `33` to the `--sections` list** in the `ans_test_runner.py` command line
      (README and README_ANS.md). The runner finds `33_*.tests.fs` by prefix, so no
      change to the script itself is expected; confirm `DEFAULT_SECTIONS` too.
- [ ] **No assembler unit-test group for the Search-Order words.** They are covered
      by the ANS file only (76 tests). A group would have to fit below `BASEDICT`
      (see headroom above).
- [ ] **`ENVIRONMENT?` does not answer `SEARCH-ORDER` or `SEARCH-ORDER-EXT`.** Only
      `WORDLISTS` (8) was added. The word set is complete, so these two could be
      added to `ENVTABLE` (a few bytes each; mind the interrupt-build headroom).
- [ ] **SERIALPOLL=0 coverage.** Developed and checked in an emulator with the polled
      build only; the interrupt-driven `TSTWORDS` test was not run there. Confirm the
      `run all tests.sh --serialpoll 0` result is recorded.
- [ ] **Header comment of `33_search_order.tests.fs`** still says "Phase 1" and lists
      FIND; it covers both phases.
- [ ] README and README_ANS.md: see `README_search_order_changes.md`. The "153 test
      blocks across 17 section files" line is already out of date and was not
      recounted.

## Design points to remember (deliberate, documented in ClaudeForth Sections 3.19, 4.4, 4.5)

- [x] `0 SET-ORDER` leaves an empty order in which ROOT is still searched (not
      required by the standard). `FIND` is in FORTH, so it is not found there.
- [x] ONLY = FORTH alone; `-1 SET-ORDER` selects the same.
- [x] `SEARCH-WORDLIST` returns 0 for a name longer than 31 characters.
- [x] A `MARKER` can not see an xt or WID stored in surviving data (`DEFER`/`IS`,
      `VALUE`, a table, a `VARIABLE`): after the marker runs, those reference freed
      space or a wordlist cell that may be reused. No *compiled* call can dangle,
      because every word that calls a pruned word is itself newer than the marker.
- [x] `QUIT` after an error prunes the wordlists but does not restore `WLEND`,
      `CURRENT` or the order: a wordlist created by a failing line survives, empty.
- [x] Wordlists are never deleted individually; 10 wordlists in all, 8 in the order.

## Documentation

- [x] `ClaudeForth 20261027` and `20261028` (docx and PDF): glossary section 3.19
      (15 words, 260 in all), Memory Map subsection "Search-Order Data Structures"
      with a pointer-operations table, Section 4.4 (MARKER and wordlists), Section
      4.5 (how the search order works), Section 7.2, memory-map figures, selector
      table (group 19), Section 5 item, source appendix regenerated (stage 6h).
- [x] Timeline entry "Design and implementation of ANS Word Lists: 5 days
      (~20 hours)" added (28 October).
- [ ] Older checklists (parts 3 to 6) still list the Search-Order word set as not
      implemented; this part supersedes them.
