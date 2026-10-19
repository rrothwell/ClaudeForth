# OPEN ITEMS CHECKLIST — part 7 (19 October 2026)

Changes since part 6 (17 October 2026).

## Programming-Tools conditional compilation (stage 6d)

- [x] **`[IF]`, `[ELSE]`, `[THEN]` added to the ROM** (immediate; headers `H_BRIF`,
      `H_BRELSE`, `H_BRTHEN`; code `BRIFW`/`BRELSEW`/`BRTHENW`, helper `BRCMP`).
      One shared skip routine scans with `PARSE-NAME`, counts nested `[IF]`s on
      the return stack, matches the three names exactly (case matters, as for
      every name here; a first version folded case, which was inconsistent because
      the interpreter never finds `[if]` anyway) and calls `REFILL` when the line
      runs out; it stops at the end of an `EVALUATE` string.
      Cost: 144 bytes of code and 31 of headers.
- [x] **Assembler unit test `TSTBRCOND`** (group 17, `TSTSELECTOR=17`), table driven:
      skip to `[ELSE]`, nested `[IF]`s, lower and mixed case names ignored, `[THEN]`
      only, no terminator, true flag, `[ELSE]` entered directly, look-alike names.
- [x] **Checked off target.** `TSTBRCOND` and the three words were run on a small
      6809 emulator (not MAME). It found a real defect in the first version of the
      test (`LDD` destroyed the mode held in `A`), now fixed. 3000 random inputs
      matched a model of the standard algorithm, with the data stack and return
      stack unchanged.
- [x] **ROLL defect found by test 30 in MAME and fixed.** `ROLL` read u with `PULU D`
      and branched with `BEQ`; `PULU` does not set the condition codes, so with
      u >= 1 and Z set it did nothing. The unit test passed by luck (the `STU`
      before the call always clears Z). Now `LDD ,U++` (same size) sets the flags
      and `TSTROLL` leaves Z set before the call. Checked on the emulator: the old
      code fails the new test, the new code passes it and 500 random cases.
      Same pattern elsewhere: a scan of every branch whose previous instruction does
      not set the flags found only `FINDW` (`TFR A,B` then `BEQ FMATCH`, where the
      flag comes from the `LEAX` before it, so that branch never fires; unreachable
      for a real name, since an empty name is rejected earlier) - left as is.
- [x] **MAME confirmation** of `TSTBRCOND` (group 17) and of
      `31_tools_conditionals.tests.fs`: the whole assembler test suite passes, and
      the ANS file passes after the case tests were corrected (the case-folding
      version of the ROM word and tests was wrong; see above).
- [x] **`00a_tool_ext_conditionals.fs` removed** from the harness list in
      `ans_test_runner.py` (and the README load order). The runner's static
      stripping of ttester's `HAS-FLOATING` blocks stays: it still avoids a reply
      timeout for every line the target would skip.
- [x] **Full ANS suite run as a batch (sections 08 to 31) to look for regressions:**
      all tests pass, no errors.

## ROM layout

- [x] **`BASECODE` and `BASEDICT` lowered** to `$DBF0` and `$D322` (were `$DC44` and
      `$D395`). Polled `BASECODE` is 8803 bytes (`$DBF0`-`$FE52`), interrupt-driven
      9122 (`$DBF0`-`$FF91`), `BASEDICT` 2254 (`$D322`-`$DBEF`). Padding below
      `INITCODE`: 337 bytes polled, **18 bytes interrupt-driven**.
- [x] All 19 unit-test selectors (0 to 18) assemble in all four builds, and the
      assembler tests pass in MAME.
- [ ] **Interrupt-driven headroom is 18 bytes.** The next addition to the base code
      needs another downward shift (the unused ROM below `BASEDICT` is now 4642
      bytes, shared with the unit-test code) or a saving.

## New ANS tests

- [x] **`30_coreext_misc.tests.fs`** for the 25 words that had no ANS test and are
      testable (see the README). Values for `WITHIN` and `U>` were checked against
      a model of 16-bit arithmetic. MAME run by hand: `ROLL` failed (real bug, fixed
      above); `TIB 0106 =` failed only because the user's abbreviated test framework
      had not set the base to HEX (the test is unchanged and correct).
      [x] **MAME re-run: all 113 tests in the file pass** with the ROLL fix and the
      HEX base.
- [x] **`31_tools_conditionals.tests.fs`** passes in MAME (see above).
- [ ] Words with no ANS test, by nature: `KEY`, `KEY?`, `EXPECT`, `QUERY`, `SPAN`,
      `QUIT`, `.S`, `WORDS`, `DUMP`, `?` (interactive or print only).

## Documentation

- [x] `ClaudeForth` docx and PDF (19 October 2026, second issue): three new
      glossary and index entries (245 words), memory map table (new sizes, the
      unused ROM row now `$C100-$D321`, 4642 bytes), ROM size text, Section 4.3
      paragraph on conditional compilation, Section 5 items, test-runner text
      without `00a`, regenerated source appendix (stage 6d). Memory-map SVG and
      PDF regenerated.
