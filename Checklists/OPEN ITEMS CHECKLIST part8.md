# OPEN ITEMS CHECKLIST — part 8 (30 October 2026)

Changes since part 7 (28 October 2026). Stage 6i gives `HEADER` a dictionary
entry, adds `SMUDGE`, and splits the largest unit-test group. Source:
`forth6809_stage_6i.asm`, `unit_tests.asm`; documentation: `ClaudeForth 20261030`.
The shadow file is unchanged (`forth6809 20261027.shd`): no comment was moved out
of the new code.

## HEADER and SMUDGE (stage 6i)

- [x] **`HEADER` ( smudge-flag "name" -- )** is now a word. The routine was already
      complete and stack-clean; only a header was needed (11 bytes). A true flag
      sets the smudge bit, so the word is hidden until `SMUDGE`.
- [x] **`SMUDGE` ( -- )** toggles bit 6 of the header `LATEST` names (9 bytes of
      code, an 11-byte header). Calling it twice restores the header.
- [x] Both headers sit at the tail of the FORTH chain, directly after the ROOT
      headers in `BASEDICT`: `H_HEADER` links to `BASEROOTLATEST`, `H_SMUDGE` to
      `H_HEADER`, and `H_BRTHEN` to `H_SMUDGE`. The words are not in ROOT.
      ROM words: 262 (247 FORTH, 15 ROOT).
- [x] **ROM layout.** `BASEDICT` `$CFA3`, `BASECODE` `$D952` (both `$20` lower).
      `BASEDICT` 2479 bytes; `BASECODE` 9487 polled (`$D952`-`$FE60`), 9806
      interrupt-driven (`$D952`-`$FF9F`); padding below `INITCODE`: 323 bytes
      polled, **4 bytes interrupt-driven**. Spare ROM below `BASEDICT` 3747 bytes.
- [x] **ANS test file `34_header_smudge.tests.fs`**, 15 tests. It defines `CODE` and
      `END-CODE` from the two words (including the `ALSO <vocabulary>` order) and
      runs a CODE word. Passes. 33 (76), 12 (73) and 8 (71) still pass.
- [x] **Unit tests `TSTHEADER` and `TSTSMUDGE`** in group 19 (DefWords part 2).
      Group 19 now ends at `$CC7C`.
- [x] **Unit test group 9 split** (it would not fit once `BASEDICT` moved down):
      group 9 keeps `IMMEDIATE` to `POSTPONE`; the new **group 20** has `[COMPILE]`,
      `>BODY`, `EXECUTE`, `SLITERAL` and `ABORT"`. Both print under the "CompWords"
      heading. Group 9 ends `$CAB4`, group 20 `$C8A2`. Selectors now run 0 to 20.
- [x] Largest groups now: group 11 (`$CEA6`, 253 bytes spare), group 10 (`$CE9D`,
      262 spare), group 4 (`$CE2B`), group 7 (`$CE10`).
- [x] Documentation: glossary entries (3.9), new Section 4.7 (building CODE and
      END-CODE; note the order `ALSO ASSEMBLER`, not `ASSEMBLER ALSO`), memory-map
      figures, selector table (20), Section 5 item, 262 words.

## Open items

- [ ] **Scripts:** `run all tests.sh` and `build all tests.sh` need selectors 19 and
      20 added (loop bound 21 and two names in `SECTION_NAMES`, for example
      `"3.9_DefWords2" "3.10_CompWords2"` after `"3.12_StrParse2"`). If 18 is also
      missing in your copy, add `"3.12_StrParse2"` as well, in selector order.
- [ ] **Runner:** add `34` to the `--sections` list (README, README_ANS.md).
- [ ] **Interrupt-driven headroom is 4 bytes** (part 7 had 3). The next addition of
      even a few bytes needs the same remedy again: lower `BASECODE`/`BASEDICT`,
      which takes space from the unit-test region (group 11 has 253 bytes spare).
- [ ] **Not run here:** MAME, and the interrupt-driven (SERIALPOLL=0) unit tests.
      Assembly of every group was checked for both serial modes; the groups were
      run in the emulator in the polled build only. Please confirm
      `run all tests.sh` for both `--serialpoll` values, 0 to 20.
- [ ] `HEADER` does not check the name length: a name over 31 characters corrupts the
      flag bits of the length byte (the same applies to `:` and `CREATE`; see the
      older item on `WORD`'s cap). A CODE word with a long name would be caught
      only by the assembler's own checks.
- [ ] Items still open from part 7 apply (ENVIRONMENT? `SEARCH-ORDER` queries; no
      assembler unit-test group for the Search-Order words; README edits).
- [ ] Part 7's note on the 6 spare bytes in group 9 and the 3-byte headroom is
      superseded by this part.
