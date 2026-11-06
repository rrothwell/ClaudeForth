# OPEN ITEMS CHECKLIST — part 5 (16 October 2026)

Changes since part 4 (15 October 2026). Every stage was assembled in all four
builds (`SERIALPOLL` 0/1 by `UNITTESTS` 0/1) and with test selectors 0, 10, 11
and 17, and the assembler unit tests and ANS tests were run by the user in MAME
after each stage.

## Page-zero scratch removed (stages 5k to 5m)

`GLOBALS` now uses **69 of 256 bytes** (127 before stage 5k). Polled `BASECODE`
is 7963 bytes (was 8273), ending at `$FBDE`; interrupt-driven is 8282, ending at
`$FD1D`. `BASEDICT` is unchanged (`$D498`-`$DCC3`).

- [x] **Stage 5k.** `WORD` (S frame: delimiter and start), `PARSE` and
      `PARSE-NAME` (start address is the result c-addr, length is the pointer
      difference), `-TRAILING`, `HEADER` (S frame), `SNAME`, `ENVIRONMENT?`,
      `ELSE`/`ENDOF` (orig1 parked on S), `UNTIL`/`AGAIN`/`LOOP`/`+LOOP` (the
      parked dest is already under the operand address, so `PATCH` is called
      directly), `REPEAT` (S frame) and `EXIT` (Y counts the DO frames). The
      `S"` family: `PARSEQUOTE` leaves `c-addr u` on the data stack and one
      helper, `CSTRCOMP`, compiles the call and the counted string for `S"`,
      `."`, `ABORT"` and `SLITERAL`. `DOABORTQUOTE` no longer pushes a stray
      register before its `THROW`. `CURXT` had shared a cell with `NEWHDR`; it
      now has its own. Shadow entry `WORDW.7`.
- [x] **Stage 5l.** `FIND` keeps the counted string on the data stack for the whole
      search and replaces it with the result; `SETDOES` reads the length byte
      into B. Shadow entry `FINDW.1`.
- [x] **Stage 5m.** `>NUMBER`/`NUMLOOP`/`UDMULADD` work in place on the
      `( ud c-addr u )` frame, which `NUMBER?` now builds itself (with a 3-byte
      S frame for the original c-addr and the negate flag, and an in-place
      32-bit negate). `#` and `#S` divide the double in place (`UDDIGIT`
      returns the remainder in A). `.`, `.R`, `D.` and `D.R` hold their sign
      cell on S. Shadow entry `NUMBERQ.6`.
- [x] **Decision: stop here.** What is left is the shared multiply/divide
      convention (`PRODHI`/`PRODLO`, `DIVNUM`/`DIVDEN`/`DIVREM`, `MAHI`-`MBLO`,
      the sign flags) and the four `MSCR` cells, about 45 bytes. Those words
      share the cells deliberately, and moving them to the stack would rewrite
      about 800 lines, make them larger and slower, and free space nothing
      needs.
- [x] **Idea considered and rejected:** using the `DP` register as a byte-save
      location. `TFR` to or from `DP` takes 6 cycles against 4 for a direct-page
      `STA`/`LDA` and 4-5 for a stack-frame access, it would break direct
      addressing of `GLOBALS` while active, and `IRQH` could fire with the wrong
      direct page. No loop in the source saves and restores a byte on every pass.

## Documentation

- [x] `ClaudeForth.docx` and preview PDF dated 16 October 2026: memory map table
      and ROM sizes (padding 965 / 646 bytes; unused ROM 5985 / 5666 bytes),
      Section 5 items, regenerated source appendix (stage 5m), rebuilt index
      and page numbers. Memory-map SVG and PDF regenerated.
- [ ] **Timeline** on the title page not updated.
