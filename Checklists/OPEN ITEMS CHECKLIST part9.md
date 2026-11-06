# OPEN ITEMS CHECKLIST — part 9 (5 November 2026)

Changes since part 8 (30 October 2026). Stages 6j and 6k make the string words
optional, stage 6l adds a disassembler, stage 6m adds a decompiler. Source:
`forth6809_stage_6m.asm`; documentation: `ClaudeForth 20261105`; shadow file:
`forth6809 20261105.shd`.

## Optional string words (stages 6j, 6k)

- [x] `STRINGSET` (default 1) assembles the String word set; `STRINGEXT` (default
      1) assembles the String extension. Each can be set to 0 with
      `--define=STRINGSET=0` / `--define=STRINGEXT=0`.
- [x] `ENVIRONMENT?` answers `STRING` and `STRING-EXT` true only when the matching
      switch is 1; otherwise it gives the normal false result.
- [x] `UNITTESTS=1` needs both switches at 1. The source stops with
      `ERROR "UNITTESTS=1 needs STRINGSET=1 and STRINGEXT=1"` (guard confirmed in
      lwasm).
- [x] ANS test file 27 split: **27** (String word set, 50 tests) and **36** (String
      extension, 14 tests).
- [x] ROM saved: `STRINGSET=0` 274 bytes, `STRINGEXT=0` 657 bytes, both 931.

## Disassembler (stage 6l): `DASM`, `DIS`

- [x] `DISASM` switch, default 1; default 0 when `UNITTESTS` is nonzero.
- [x] `DASM ( addr -- addr' )` sends one instruction as text and returns the next
      address; `DIS ( addr u -- )` lists the instructions that start in
      addr to addr+u-1, one per line. lwasm-style, hexadecimal only.
- [x] ANS test file **37_disassembler.tests.fs**: 64 run, 0 failed.
- [x] Round trip through the assembler: only 4 known `PSHS #$00` differences and
      1,083 non-canonical postbytes. Details in shadow `DISASM.1`.

## Decompiler (stage 6m): `SEE`

- [x] `DECOMP` switch, default = `DISASM`. `DECOMP=1` with `DISASM=0` stops with
      `ERROR "DECOMP=1 needs DISASM=1"`.
- [x] `SEE ( "name" -- )` rebuilds IF/ELSE/THEN, BEGIN/UNTIL/AGAIN/WHILE/REPEAT,
      DO/?DO/LOOP/+LOOP, EXIT, the string words and DOES>; CODE words print as
      `CODE name` with `DASM` lines. `see_check.py`: 19 definitions, 0 differ.
- [x] Handler labels use the prefix `HND_` (the `H_` prefix is for headers; the
      first 6m source clashed on `H_DO`, `H_LOOP`, `H_PLUS`, `H_QDO`, `H_EXIT`).
- [x] The source has a new **SECTION 28** (disassembler and decompiler); the main
      document lists it as 8.29.

## ROM layout (default build, DISASM=1 DECOMP=1)

- [x] `BASECODE` `$CEC0`, `BASEDICT` `$C4F8`, set by conditional EQUs (table in shadow
      `MEMMAP.20`). 265 headers; `BASEDICT` 2504 bytes; `BASECODE` 12180 bytes
      polled (ends `$FE54`, 336 spare) and 12499 interrupt-driven (ends `$FF93`,
      **17 spare**). Unused ROM below `BASEDICT`: 1016 bytes.
- [x] Cost of the options: `DISASM` +1,789 bytes; `DISASM`+`DECOMP` +2,690 bytes
      (`DECOMP` alone 901).
- [x] Globals: 171 bytes used (`GLOBALS_USED = 131+19*DISASM+21*DECOMP`), page zero
      `$00`-`$AA`.
- [x] Unit tests: all 19 groups pass with `DISASM=0` (the default when `UNITTESTS` is
      set). With `DISASM=1 DECOMP=0` groups 0, 2, 5, 13 to 17 fit and pass; with
      both on only groups 13 and 15 fit (both pass).

## Open items

- [ ] **Scripts:** `run all tests.sh` and `build all tests.sh` need the `DISASM`
      define handled for groups that do not fit (use `DISASM=0`), and 36 and 37
      added to the ANS runner `--sections` list.
- [ ] **Interrupt-driven headroom is 17 bytes.** Any further addition needs a
      lower `BASECODE`/`BASEDICT`.
- [ ] **Not run here:** MAME for the new stages was confirmed by manual testing only;
      the full `run all tests.sh` in both serial modes with all flag combinations
      should be repeated.
- [ ] `SEE` limits: `CASE`/`OF`/`ENDOF` are not rebuilt; an `AGAIN` at the end of an
      `IF` branch is shown as `REPEAT`; a headerless word shows as `JSR $xxxx`;
      output stops after 255 items.
- [ ] Items still open from part 8 apply (the `HEADER` name-length check;
      `SEARCH-ORDER` queries in `ENVIRONMENT?`; README edits).
