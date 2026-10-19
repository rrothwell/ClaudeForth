# OPEN ITEMS CHECKLIST — part 6 (17 October 2026)

Changes since part 5 (16 October 2026). Stages 6a to 6c complete the Double-Number
and Core Extension word sets and the `ENVIRONMENT?` query table. Every stage was
assembled in all four builds (`SERIALPOLL` 0/1 by `UNITTESTS` 0/1) and with
every test selector from 0 to 18.

## Double-Number word set (stage 6a)

- [x] **Added `D0=`, `D0<`, `D2*`, `D2/`, `M*/`, `2LITERAL`, `2VALUE`**, and `TO`
      now recognizes a `2VALUE` (it checks the behaviour cell at xt+3 for
      `DO2VALUE`; a 2VALUE stores x2 at the lower address like `2CONSTANT`).
- [x] **`M*/` method.** Take the magnitudes; form `|d1.lo|*|n1|` and `|d1.hi|*|n1|`
      with `UMUL32` and add them into a 3-cell product on an S frame; divide by
      `|n2|` in three 32/16 `UDIV32` steps (each quotient is under 65536); negate
      the result if an odd number of `d1`, `n1`, `n2` are negative. Symmetric
      division (truncates toward zero), `THROW -10` for a zero divisor. The method
      was checked against exact integers in a Python model (200000 random cases
      including the extremes) before it was written in assembler. Shadow entry
      `M*/W.1`.
- [x] **Assembler unit tests** for `D0=`, `D0<`, `D2*`, `D2/` and `M*/` (including
      the divide-by-zero case) in the DArithmetic group (selector 4).
- [x] **ANS test file `28_double_word.tests.fs`** built from the forth-standard.org
      Double-Number tests. Constants come from `D2/`, `M*/` and `MAX-D` instead
      of hard-coded values; typos fixed; the previously disabled blocks enabled.
      All tests pass in MAME. The `D.`/`D.R` test is visual (lines in pairs).

## ENVIRONMENT? (stages 6a and 6b)

- [x] **`CORE`, `CORE-EXT`, `DOUBLE` and `DOUBLE-EXT` answer.** A word-set query
      returns a value flag and then the recognized flag (`true true`). This matches
      the standard's table, where those queries return a flag, and gforth. An
      unknown name still returns a single `false`.
- [x] **Section 24 tests cover the whole standard query table**, with `/HOLD` and
      `/PAD` checked against the standard minimums (34 and 84).
- [x] The first version of the DOUBLE tests expected a single flag; the test was
      wrong, not the code.

## Core Extension word set (stages 6b and 6c)

- [x] **Added `.(`, `C"`, `SAVE-INPUT`, `RESTORE-INPUT` (6b), `S\"` and `CONVERT` (6c).**
      Found by auditing the dictionary against the standard word lists. Core had no
      gaps (`."`, `S"` and `ABORT"` only looked missing because of how their names
      are spelled in the source). `CORE-EXT` was briefly reported complete at 6b
      while `S\"` and `CONVERT` were still missing; the audit caught it.
- [x] **`SAVE-INPUT`** saves the source address, source length and `>IN` (three
      cells and the count 3). **`RESTORE-INPUT`** restores `>IN` only if the source
      address and length match, and otherwise returns true, so it cannot restore
      across `REFILL` or into a different `EVALUATE` string.
- [x] **`S\"`** translates `\a \b \e \f \l \m \n \q \r \t \v \z \" \\` and `\xhh`
      into PAD, then shares the `S"` code path (label `SQSTATE`). More than 255
      characters throws -18. **`CONVERT`** is `>NUMBER` with no length limit.
- [x] **ANS test file `29_coreext_strings.tests.fs`.** A `T{ ... >R ... R> ... }T`
      line at top level reset the target (`>R` leaves the value under the
      interpreter's return address); the test now uses a definition.
- [x] **MAME confirmation of stage 6c** (`S\"`, `CONVERT` and the section 29 tests):
      all unit tests and ANS tests pass. The section 29 file was then tidied by
      hand (formatting consistent with the other section files, base set to HEX).

## ROM layout and unit tests

- [x] **`BASECODE` and `BASEDICT` lowered** to `$DC44` and `$D395` (were `$DCC4` and
      `$D458`). The interrupt-driven build no longer fitted below `INITCODE` once
      `S\"` was added. The dictionary ends exactly at `BASECODE`.
- [x] Polled `BASECODE` is 8659 bytes (`$DC44`-`$FE16`), interrupt-driven 8978
      (`$DC44`-`$FF55`), `BASEDICT` 2223 (`$D395`-`$DC43`). Padding below
      `INITCODE`: 397 bytes polled, **78 bytes interrupt-driven**.
- [ ] **Interrupt-driven headroom is 78 bytes.** The next addition to the base code
      needs another downward shift of `BASECODE`/`BASEDICT` (the spare ROM below
      `BASEDICT` is about 5 KB, but the unit test code sits there too) or a saving.
- [x] **Unit test group 11 split.** In the interrupt-driven build the StrParse tests
      overran `BASEDICT` by 17 bytes. `REPLACES`, `SUBSTITUTE`, `CLR-REPLACES`,
      `SNAME` and `UNESCAPE` now run as group 18 (`TSTSTRPARSE2`); group 11 keeps
      the rest. Selector 0 calls both. `run all tests.sh` and `build all tests.sh`
      need `18` added to their selector lists.

## Documentation

- [x] `ClaudeForth.docx` and preview PDF dated 17 October 2026: 13 new glossary
      entries and index entries (`D0=`, `D0<`, `D2*`, `D2/`, `M*/`, `2LITERAL`,
      `2VALUE`, `.(`, `C"`, `S\"`, `CONVERT`, `SAVE-INPUT`, `RESTORE-INPUT`),
      updated `TO` and `ENVIRONMENT?` entries, the glossary count (242 words;
      the earlier text said 227 while 229 entries existed), memory map table and
      ROM sizes, selector table (18), test-suite text, Section 5 items and the
      regenerated source appendix (stage 6c). Memory-map SVG and PDF regenerated.
- [x] README (and README_ANS.md): sections 27 to 29, query-table and double
      notes, `>R` guidance; the Double-Number entries removed from the open items.
- [ ] **Timeline** on the title page not updated.
- [ ] Older checklists (parts 3 and 4) still list the Double-Number gap as open;
      this part supersedes them.
