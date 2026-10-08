# 6809 Forth — Open Items Checklist (Part 3: ANS Test Suite Era)

**This is part 3**, picking up where part 2 ends. Part 2's last entry is the
`ECHOEMIT` fix and the `BASECODE`/`BASEDICT` shift to `$DE5E`/`$D673`.
Parts 1 and 2 are kept unchanged as project history. Where something
below overturns an entry in those files, it says so under "Earlier
entries superseded".

Sources for this part: the current `forth6809.asm` in the Project (the
baseline that assembles and passes all 17 ANS test sections), the ANS
Test Suite `README.md` and `bug_fixes.md`, and the session notes kept
while fixing the defects listed here. Status marks:

- `[x]` resolved and confirmed by a real test run (MAME and/or minicom).
- `[ ]` open.
- *Not re-assembled here* means the figure comes from reading the
  source, not from a fresh `lwasm` listing. No assembler is available in
  the environment this file was written in.

## Changes since part 2 — serial I/O and dictionary

- [x] **`IRQH` rewritten for symmetry between its RX and TX halves, with a
      single exit point, and receiver errors are now counted.** Framing,
      overrun and parity errors increment `FECOUNT`, `OVRNCOUNT` and
      `PECOUNT` (page-zero cells), cleared by `INITSERIAL` at cold and
      warm start. The polling `KEY` counts the same three errors too (only
      the interrupt path checked them before). A new `POLLREADYCNT` counts
      polling-mode `KEY` calls that found a character already waiting, as
      a backlog signal distinct from a true overrun. `BASECODE` and
      `BASEDICT` shifted down `$30` (48 bytes) to make room.
- [x] **Polling-mode software flow control added: `PUTXON` / `PUTXOFF`.**
      `ACCEPT` sends XON at the start of each line and XOFF the moment a
      line is complete (CR seen), before interpretation or compilation
      begins, because a polling build has no ring buffer to absorb a
      host that keeps sending. The bytes go straight to the ACIA without
      touching the data stack. `XONCH`=`$11`, `XOFFCH`=`$13`.       See the open item under "Carried forward" for what is still not
      implemented.
- [x] **Dictionary headers added for words that already had code or were
      new:** `:NONAME` (header added, `BASECODE` shifted), `>NUMBER` (code
      existed and worked but had no header and was unreachable by name;
      found by an audit), and `[COMPILE]` (new word `XCOMPILE`, needed for
      Annex F F.6.2.2530). `[COMPILE]` always compiles a direct call
      regardless of the IMMEDIATE flag; unlike `POSTPONE` it is wrong for
      default-compilation words such as `CREATE`/`DOES>` words, which is
      why `[COMPILE]` is obsolescent. `BASECODE` shifted up `$0C` and
      `$0E` for the `>NUMBER` and `[COMPILE]` headers respectively,
      following the 5-bytes-per-entry overhead formula (the earlier
      4-byte estimate had caused a 3-byte overflow).
- [x] **Current memory-map anchors (read from the source's `EQU` lines).**
      `INOUT` `$C000`-`$C0FF` (ACIA at `INOUT+8`), `USROMSTRT` `$C100`,
      `BASEDICT` `$D543`, `BASECODE` `$DD54`, `INITCODE` `$FFA4`,
      `VECTORS` `$FFF0`. RAM: `RSTACK` occupied `$BD00`-`$BFFF`, `DSTACK`
      top `$BCFF` (1024 bytes) and `CODETOP` `$B900`, `APPCODE` `$7000`,
      `APPDICT` `$2000`, `APPVARS` `$021B` ending at `APPVARSEND` =
      `APPDICT-1` (`$1FFF`), `TIBBUF` `$0106` (80 bytes), serial buffer
      block from `$0176`/`$0180`. *Not re-assembled here.* The `ClaudeForth`
      document's Memory Map section still shows earlier values (see
      "Documentation to refresh").

## Changes since part 2 — defects found and fixed by testing

Each was found by the unit tests, the ANS Annex F tests, or a real run.
`bug_fixes.md` in the ANS Test Suite directory records the last five.

- [x] **`EXIT` inside a `CASE` / `OF` clause hung in MAME.** The compile-time
      scan for enclosing structures steps in fixed 4-byte strides, but
      `CASEW` left a lone 2-byte `TAGCASE` cell, so the scan ran past
      `CSP` forever. `CASEW` now leaves a 2-cell frame (filler +
      `TAGCASE`), and `ENDCASE`'s `ECDONE` path pops the paired filler.
- [x] **`+LOOP` had three separate bugs in `DOPLUSTEST`.** (1) An extra
      test exited one pass early whenever the new index landed exactly on
      the limit with a step other than +1; removed. (2) `LEAVE`-triggered
      exits skipped popping the step value, leaving a stray stack item;
      the pop now happens unconditionally first. (3) The sign-flip
      crossing test is wrong in general because a signed 16-bit
      difference changes sign at two points on the 65536-ring; replaced by
      an unsigned-wraparound test (step>0: crossed iff new<old unsigned;
      step<0: crossed iff new>old). Verified by simulation and by Annex F
      section 12.
- [x] **`RECURSE` inside `:NONAME` resolved to the wrong word.** It found
      "the word being compiled" by walking `LATEST`, but `:NONAME` never
      updates `LATEST`. Added `CURXT` (an alias of the `NEWHDR` cell, since
      page zero is full) which `:` and `:NONAME` both set to their own
      execution token; `RECURSE` reads it directly.
- [x] **`UDIV32` mishandled a 17th remainder bit.** `UM/MOD` with an
      unsigned divisor near `$FFFF` (Annex F `MAX-UINT MAX-UINT UM*
      MAX-UINT UM/MOD`) needs a transient 17th bit that the final
      `ROL DIVREM` produced in carry but never tested. Fixed with a
      `BCS` test after that rotate. Only `UM/MOD` can reach it; the
      signed-divisor words cannot. Regression test `TSTUMSM2` added to
      `unit_tests.asm`.
- [x] **`WORD`, `PARSE` and `PARSE-NAME` treated `>IN` beyond the end of
      input as a huge remaining length** (unsigned wrap), parsing stale
      memory. Annex F's `>IN` tests set it past the end deliberately. All
      three now check for borrow and treat overshoot as an exhausted parse
      area.
- [x] **`2@` / `2!` / `2CONSTANT` cell order.** The standard puts x2 at the
      address and x1 at address+cell. Annex F section 18 failed until
      `DFETCH`, `DSTORE` and `TWOCONSTANT` were made to match. This
      overturns the earlier part 2 entry that "fixed" `2@` the other way.
- [x] **`CATCH` / `THROW` did not preserve the input source.** A throw out
      of a nested `EVALUATE` lost the rest of the calling line and left
      stray data-stack cells (four after section 11). The `CATCH` frame
      now also saves `SRCADDR`, `SRCLEN`, `SRCID` and `>IN`, and `THROW`
      restores them.
- [x] **`EVALUATE` kept the outer source in global `EVSAVE*` cells, which
      nesting clobbered.** It now saves and restores them on the return
      stack (the `EVSAVE*` cells are unused).
- [x] **`ABORT` did not throw**, so `CATCH` could not intercept it. It is
      now `-1 THROW` (`ABORTW`); the top level resets silently on `-1`.
      `COLD` ends with `BRA ABORT` to keep its fall-through to the reset
      entry.
- [x] **`UNLOOP` and `EXIT` loop-frame handling.** A `DO` frame on the
      return stack is 6 bytes (index, limit, `LEAVE` flag); `EXITUNLOOP`
      discarded 8 per enclosing loop and `UNLOOP` did nothing. `UNLOOP`
      now drops the frame, and `EXIT` no longer discards frames (the
      standard: use `UNLOOP` first). Found by Annex F test `GD6` in
      section 12.

## Changes since part 2 — test infrastructure

- [x] **All 17 ANS Annex F test sections (`ans_tests/08` to `26`) pass with
      clean data stacks** on MAME (Python runner) and via minicom pasting,
      after the fixes above. Section files are independent (`MARKER Mnn`),
      adapted for 16-bit cells where Annex F assumes 32, and corrected
      where the published test text is wrong.
- [x] **`TEST-BEGIN` / `TEST-END`** (in `00_test_prelude.fs`) give every
      test file its own report: "TEST SUMMARY: N run, M failed" plus a
      "STACK IMBALANCE" check. `TEST-REPORT` was removed from
      `ttester.fs`. `ans_test_runner.py` now reads those lines instead of
      sending its own reporting commands. `apply_test_markers.py` adds both
      calls to new section files.
- [x] **Documentation:** ANS Test Suite `README.md` (how to run, edit and
      read the tests, differences from Annex F, known limitations) and
      `bug_fixes.md` (history of the defects above).

## Earlier entries superseded

- Part 2, "`UNLOOP` is now a true no-op": no longer true. `UNLOOP` drops the
  loop frame and `EXIT` does not (see above). The `ClaudeForth` glossary
  entries for `UNLOOP` and `EXIT` need to follow.
- Part 2, "`2@` read order fixed to low-then-high": reversed again (see
  above).
- Part 2, "Software (XON/XOFF) handshaking is still not implemented":
  partly superseded (see below).
- The top-of-file comment in `forth6809.asm` still says "220 entries", still
  says XON/XOFF "remains not implemented", and still describes a 19-byte
  `BASECODE`/`BASEDICT` overlap. All three are stale. The source has 227
  `H_` header labels; the overlap was closed by later `BASECODE`/
  `BASEDICT` moves. Refresh that comment block (see below).

## Documentation to refresh (not started — awaiting go-ahead)

- [ ] `ClaudeForth.docx` / `ClaudeForth preview.pdf`: Memory Map section
      (new `BASEDICT`/`BASECODE`/`INITCODE` values and any changed RAM
      anchors above), the Assembler Source appendix (updated
      `forth6809.asm`), and the `UNLOOP`/`EXIT`/`2@`/`2!`/`ABORT`
      glossary entries. Real byte totals and the unused-ROM figure need a
      fresh `lwasm` listing.
- [ ] `forth6809.asm` top-of-file comment block (items listed above).

## Carried forward from part 2 (still open)

- [ ] **Software flow control is only half in place.** Polling builds now
      transmit XON/XOFF around each line. Nothing recognizes an incoming
      `$11`/`$13` from the host, and interrupt-driven builds still rely on
      hardware RTS/CTS only.
- [ ] **No hard boundary checks** as `DPHERE`/`CODEHERE`/`VARHERE` grow;
      `UNUSED` and `VUNUSED` only report.
- [ ] **`CATCH`-wrapped `QUIT`/`INTERPRET` rollback is scoped to one input
      line**, not back to the opening `:` of a multi-line definition.
- [ ] **`J` does not generalize** past one nesting level; **`LEAVE`** is
      only correct when textually inside its loop.
- [ ] **Search-Order word set not implemented** (documented, Section 4.5).
- [ ] **Duplicated logic:** `NUMBERQ`'s inline 32-bit negation versus
      `MNEG32`; the self-referential PFA fix repeated in `CONSTANT`,
      `DEFER`, `2CONSTANT`, `MARKER`. Part 2 deferred both until automated
      testing existed. That condition is now met (17 ANS sections plus the
      unit tests), so refactoring them is possible and can be checked.
- [ ] **Design questions:** range-checking in `ALLOT`/`VALLOT`/`PICK`/
      `ROLL`/`BASE`; the `TIB`/`SOURCE` distinction; `SWIH`'s placeholder
      `-99`; `REPLACES`/`SUBSTITUTE` single-slot only.
- [ ] **`DUMP` leading-line formatting change** (part 2) was left unchecked
      there; confirm or close.

## New open items

- [ ] **Double-Number word set is partly implemented and has no Annex F
      tests.** Present: `D+ D- DNEGATE DABS DMAX DMIN M+ S>D D>S D= D<
      DU< D. D.R 2ROT 2VARIABLE 2CONSTANT` and `123.` literals. Appear to
      be missing: `D0= D0< D2* D2/ M*/ 2LITERAL 2VALUE`. A double-number test
      file would be the next ANS section, after those words exist.
- [ ] **Facility word set:** only `KEY?` exists; no tests.
- [ ] **`ENVIRONMENT?`:** `X:deferred` answers false (not in `ENVTABLE`)
      although `DEFER`/`IS`/`ACTION-OF` exist. The test accepts either
      answer; answering true would be more accurate.
- [ ] **`ABORT` is silent** (including `-1 THROW` at the top level), and
      `ABORT"` message output at the top level is not covered by any
      test. Decide whether either should print.
- [ ] **Re-assemble and regenerate the listing.** Confirm the current
      `BASEDICT`/`BASECODE`/`INITCODE` boundaries and spare bytes (the
      source comment records a 9-byte margin as of the `[COMPILE]` header,
      never re-verified), then update the docx Memory Map from that
      listing rather than from comments.
- [ ] **Annex F test files that are physical-line sensitive** (sections 19
      and 24) must not be reflowed; any tooling that rewraps test files
      has to respect that (documented in the README).
- [ ] **Page-zero budget is still 256/256.** Any new global (for example,
      for Double-Number work or more error counting) must reuse a cell or
      move one out of page zero.
