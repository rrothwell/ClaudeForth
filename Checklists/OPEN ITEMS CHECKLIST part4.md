# OPEN ITEMS CHECKLIST — part 4 (15 October 2026)

Changes since part 3 (11 October 2026). Every item was verified by assembling all
four builds (`SERIALPOLL` 0/1 by `UNITTESTS` 0/1) and by the assembler unit tests
and ANS tests run by the user in MAME.

## Static temporaries in page zero reduced (stages 5a to 5e)

- [x] **Working values moved from page zero onto the stacks.** Parameters stay on
      the data stack and are reached `U`-relative; locals live in short `LEAU` or
      `S` frames (they survive `THROW`, because `CATCH`/`THROW` restore `S`); `X`
      and `Y` are used as temporaries. Covers `CMOVE`, `FILL`, `COMPARE`,
      `SEARCH`, `TYPE`, `SPACES`, `ROLL`, `2>R`, `2R>`, `2R@`, `.S`, `WORDS`,
      `.R`, `U.R`, `D.R` (shared helper `RTYPE`), `DUMP`, `UNESCAPE`,
      `SUBSTITUTE`/`SUBCOPY` and `ACCEPT`, among others. `GLOBALS` now uses 127
      of 256 bytes (was 255); `MVSCRATCH` is gone and `$0100-$0105` is unclaimed.
- [x] **Unit-test harness defect (stage 5c).** The assembler unit tests run before
      `COLD`, with `CODEHERE` = 0, so `PAD` fell at `$80` in page zero and
      overwrote `TYPE`'s variables once they had been renumbered (found by the
      user with `SERIALPOLL=0`, `TSTDOTS`). `TSTRUNNER` now sets `CODEHERE` to
      `APPCODE`. No change to the Forth source.
- [ ] **Remaining page-zero temporaries** (not yet moved): the multiply and divide
      scratch (`MSCR`-`MSCR4`, `PRODHI`/`PRODLO`, `DIV*`, `UDHI`/`UDLO`) and a few
      others.
- [ ] **Idea, not started:** use the `DP` register as a byte-save location in inner
      loops where a byte is currently saved and restored.

## String words (stages 5f to 5j)

Found by the optional String word tests (`27_optional_strings`), which had the
right expectations.

- [x] **`SEARCH`** returned the needle's length as `u3`. It now returns the
      characters remaining from the match, and an empty needle matches at the
      start. `TSTSEARCH1` had the same wrong expectation (3) and now expects 5.
- [x] **`REPLACES`** held one registration. It is now a table in `SUBPOOL`
      (64 bytes, `$0200-$023F`): a linked list of entries (link 2, name length 1,
      text length 1, capacity 1, name, text), headed by `SUBHEAD`, next free byte
      `SUBFREE`. It keeps its own copy of both strings. Redefinition is in place
      when the new text fits, otherwise a new entry (old space not reclaimed).
      Names are case sensitive; entries are not scoped by `MARKER`. Name or text
      over 255 throws -18, a full pool -8. Three 8-character pairs fit (21 bytes
      each); the ANS tests need 25 bytes. `APPVARS` moved to `$0240`.
- [x] **`SUBSTITUTE`** no longer throws on error: it returns a negative `n`
      (-18 output overflow, -9 source and destination are the same buffer).
- [x] **`BLANK`** added (`32 FILL`).
- [x] **`CLR-REPLACES`** added (non-standard): empties the `REPLACES` table.
- [x] **`S"`, `."` and `ABORT"` with an empty string** ran on past the closing
      quote, because `WORD` skips leading delimiters. They now parse with `PARSE`
      (helper `PARSEQUOTE`); over 255 characters throws -18. The 3-byte `CODEHERE`
      reserve they used to make is gone, so `WORDMAXCHARS` could be 3 larger; it
      was left alone (comment fixed in stage 5j).
- [x] **New tests.** Assembler: `TSTBLANK`, `TSTCMOVEOVL`, `TSTCMOVEGTOVL`,
      `TSTCMOVELONG`, `TSTSEARCH3/4`, `TSTREPLSUBS3/4`, `TSTCLRREPL`,
      `TSTSQUOTE3`. ANS file: `BLANK`, `CMOVE`, `CMOVE>`, `SEARCH` u3, `SUBSTITUTE`
      errors, `CLR-REPLACES`.
- [x] **Shadow files.** Added `ACCEPTW.5`, `UNESCAPEW.5`, `SUBSTITUTEW.5` (stage 5e
      references that had no entry), and put the stage 5f-5j entries in assembler
      order.

## Memory map (stage 5h)

`BASEDICT` `$D498`-`$DCC3` (2092 bytes); `BASECODE` `$DCC4`-`$FD14` polled (8273
bytes) or `$FE53` interrupt-driven (8592); `SUBPOOL` `$0200`-`$023F`; `APPVARS`
`$0240`-`$1FFF` (7616). ROM content 10453 bytes polled / 10772 interrupt-driven
(unused 5675 / 5356 of the 16K part after the 256-byte `INOUT` shadow).

## Documentation

- [x] `ClaudeForth.docx` and preview PDF dated 15 October 2026: memory map and ROM
      sizes, glossary (`BLANK`, `CLR-REPLACES`; `SEARCH`, `REPLACES`,
      `SUBSTITUTE`, `S"`, `."`, `ABORT"`, `CMOVE`, `CMOVE>`, `WORD` revised),
      Section 5 items, regenerated source appendix (stage 5j), rebuilt index and
      page numbers. Memory-map SVG and PDF regenerated.
- [ ] **Timeline** on the title page not updated (hours since 11 October).
