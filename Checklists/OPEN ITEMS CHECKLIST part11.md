# OPEN ITEMS CHECKLIST — part 11 (5 November 2026)

Changes since part 10. Stage 6o adds chained interrupt handlers and redirectable
character I/O. Source: `forth6809_stage_6o.asm`; documentation:
`ClaudeForth 20261105` (rebuilt, new Section 4.9); shadow file:
`forth6809 20261105.shd` (IOVEC.1, IRQH.1, MEMMAP.22).

## Done in stage 6o (tested in my emulator, polled build)

- [x] **Redirectable `EMIT`, `KEY` and `KEY?`.** They are now `JMP [EMITV]`,
      `JMP [KEYV]` and `JMP [KEYQV]` (page-zero cells). The serial routines are
      renamed `EMITACIA`, `KEYACIA`, `KEYQACIA`. New words `(EMIT)`, `(KEY)`,
      `(KEY?)` return the cell addresses: `' MYEMIT (EMIT) !`, `(EMIT) @`.
      `IOVINIT` resets the cells at cold start, warm start and in `QUIT` after a
      caught error (before `ERROR n` is printed). `PUTXON` and `PUTXOFF` bypass the
      vectors. `ACCEPT`'s echo goes through `EMIT`.
- [x] **Chained interrupt handlers.** When `IRQH` finds the interrupt is not from
      the ACIA it does `JMP [IRQCHAIN]`; the cell starts at an RTI (`IRQRTI`). The
      polled build's `IRQH` is the same jump, so chaining works in both builds. New
      word `IRQ-CHAIN ( -- addr )`. The cell is set by cold start only. FIRQ and
      NMI are not chained.
- [x] **Space:** 4 headers (+46 bytes), +68 bytes of code, +8 page-zero bytes
      (`GLOBALS_USED` 139+19*DISASM+21*DECOMP). The init code had 1 byte spare, so
      `INITCODE` moved from `$FFA4` to `$FF9C` (INITSIZE 81). `BASECODE`/`BASEDICT`:
      `$D876/$CE99`, `$D180/$C792`, `$CE00/$C40A` (DISASM/DECOMP 0 0, 1 0, 1 1).
      Default build: 269 headers, 12305 bytes of code polled (395 spare), 12624
      interrupt (**76 spare**), dictionary 2550.
- [x] **Unit-test region shrank** (778 bytes with both options on, 1682 with
      `DECOMP=0`, 3225 with `DISASM=0`). Effects: group 10 (Memory) no longer fitted
      even with `DISASM=0` (3485 bytes), so it is **split into groups 10 and 21**
      (`TSTCMOVE`, `TSTCMOVEGT`, `TSTMOVE1-3` moved to 21). Both scripts now run 22
      groups. With `DISASM=1 DECOMP=0` groups 0, 2, 13, 14, 15, 17 fit (5 dropped,
      10 bytes over); with both on **none** fit (13 is 18 bytes over, 15 is 152).
      `FIT_DISASM` and `FIT_DECOMP` updated in both scripts.
- [x] **Tests (emulator):** new `38_io_vectors.tests.fs` (18 tests: cells in page
      zero and distinct; `IRQ-CHAIN @ C@` is `$3B`; output captured through `EMIT`,
      `TYPE`, `.`, `SPACE`, `CR`; restore; `KEY` and `KEY?` redirected; `ACCEPT`
      fed from a string with its echo captured). Checked by hand: the vectors are
      reset after an undefined word, after `ABORT` and after a division error.
      Regression: ANS 33 (78), 34 (23), 27 (50), 36 (14), 37 (64), 8 (71), 12 (73),
      `see_check.py` 19/0. Unit-test groups 0-21 pass with `DISASM=0` (group 0
      `TSTKEYQ FAIL` is the known emulator artifact); 0, 2, 13, 14, 15, 17 pass with
      `DISASM=1 DECOMP=0`.
- [x] **Documentation:** four glossary entries; `KEY`, `KEY?`, `EMIT`, `ACCEPT` and
      `QUIT` entries mention the vectors; new Section 4.9; memory map, size
      figures, BASECODE/BASEDICT and unit-test tables, group 21, counts 265 → 269;
      Section 5 item; index.

## Fixes after Richard's run (6 November)

- [x] ANS tests all pass (lwasm/MAME).
- [x] **Group 11 (StrParse) overflowed by 13 bytes with `SERIALPOLL=0`** ("Invalid fill
      length"). `TSTDASHTRAILING` and `TSTSLASHSTRING` moved to group 18 (StrParse2).
      Group 11 now reports 15 tests, group 18 reports 10. Every group was re-measured
      in all four SERIALPOLL/DISASM combinations I can assemble; none is now within 60
      bytes of overflowing. (My earlier check measured only the polled build.)
- [x] Manual: Section 4.9 split into 4.9 Redirecting Character I/O and 4.10 Interrupt
      Chaining; timeline entry added ("Addition of character I/O redirection and
      interruption chaining: 1 day (~5 hours)").

## Open items

- [ ] **Please run in lwasm and MAME:** all combinations of `SERIALPOLL`, `DISASM`
      and `DECOMP` assemble; `38_io_vectors.tests.fs` (add `38` to `--sections`);
      the unit-test scripts (22 groups; some groups are SKIPPED with `DISASM=1`).
      My emulator cannot run the interrupt-driven build (`SERIALPOLL=0`), so I
      checked that build only by assembling it and reading the bytes
      (`JMP [IRQCHAIN]` is `6E 9F 00 83`).
- [ ] **A test of a real chained interrupt is missing.** `IRQ-CHAIN` is tested only
      for its initial value. A proper test needs an interrupt source other than the
      ACIA (in MAME, a timer) to hit a chained handler.
- [ ] Decide whether the lost unit-test coverage matters: with the disassembler on,
      groups 5, 13 and 15 (and 16 since 6n) can no longer be built. To get 13 and 15
      back with both options on, about 150 bytes would have to be found.
- [ ] `CASE` is not rebuilt by `SEE` and other `SEE` limits (part 9) still apply.
- [ ] A unit test group for the Search-Order words is still missing.
- [ ] README_ANS.md: add `38` to the `--sections` list and list
      `38_io_vectors.tests.fs`; README.md Plans: "Vectored I/O" and "Interrupt
      chaining" can be ticked (see `README_review_6o.md`).
