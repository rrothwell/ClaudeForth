# OPEN ITEMS CHECKLIST — part 10 (5 November 2026)

Changes since part 9. Stage 6n closes three items from part 9. Source:
`forth6809_stage_6n.asm`; documentation: `ClaudeForth 20261105` (rebuilt);
shadow file: `forth6809 20261105.shd` (HEADER.2, ENVSEARCH.1, MEMMAP.21).

- [x] **HEADER checks the name length.** Throws -16 for no name and -19 for a name
      over 31 characters, before anything is changed. `:`, `CREATE`, `VARIABLE`,
      `CONSTANT` and the other defining words are covered. +17 bytes.
- [x] **ENVIRONMENT? answers `SEARCH-ORDER` and `SEARCH-ORDER-EXT`** (true true).
      +40 bytes.
- [x] **BASECODE and BASEDICT lowered by $40** in all three states
      (`$D8F6/$CF47`, `$D200/$C840`, `$CE80/$C4B8`). Default build: 12237 bytes of
      code polled (343 spare), 12556 interrupt (**24 spare**). Unit-test region with
      both options on: 952 bytes. The same groups fit (13 and 15; and 0, 2, 5, 13-17
      with `DECOMP=0`); the scripts need no change.
- [x] **Tests:** ANS 33 now 78 tests (two ENVIRONMENT? queries), ANS 34 now 23 tests
      (empty name, 31 and 32 character names for `:`, `CREATE` and `CONSTANT`, and
      a dictionary check after a failed header). 27 (50), 36 (14), 37 (64), 8 (71),
      12 (73) and `see_check.py` (19) pass; all 21 unit-test groups pass with
      `DISASM=0`, and the `DISASM=1` groups pass. Run in my emulator only.
- [x] Documentation: memory map and size figures, the Feature Flags tables, the
      HEADER and ENVIRONMENT? glossary entries, and two new Section 5 items.

## Open items

- [ ] **Please confirm in lwasm and MAME:** the 6n source assembles, ANS 33 and 34 pass
      (the interrupt-driven build has 24 bytes spare).
- [ ] **READMEs:** not reviewed. I could not find the updated READMEs in the project
      (only README.md and README_search_order_changes.md from October); please
      upload them again.
- [ ] `CASE` is not rebuilt by `SEE` and other `SEE` limits (part 9) still apply.
- [ ] A unit test group for the Search-Order words is still missing; the
      `ENVIRONMENT?` unit test group (16) does not yet check the new queries.
