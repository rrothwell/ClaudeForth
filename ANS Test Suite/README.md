# ANS Forth Test Suite, Organized by forth6809.asm Section

Source: https://forth-standard.org/standard/testsuite (Annex F), fetched
2026-07-15. Explicitly redistributable per the test harness's own header:
"(C) 1995 JOHNS HOPKINS UNIVERSITY / APPLIED PHYSICS LABORATORY - MAY BE
DISTRIBUTED FREELY AS LONG AS THIS COPYRIGHT NOTICE REMAINS."

## What's here

- `ttester.fs` — the test harness itself (ANS Forth Standard, Annex F,
  Section F.2.3), reorganized here into its own file rather than left
  bundled inline with anything else. Defines `T{`/`->`/`}T` and every
  supporting word (`ERROR`, `EMPTY-STACK`, the `HAS-FLOATING`/
  `HAS-FLOATING-STACK` detection, and the `X}T`/`R}T`-family closing
  words for mixed cell/float stack pictures). Load this first, before
  the prelude or any section file. Verified after transcription: `[IF]`
  and `[THEN]` counts match exactly (8/8), and `:`/`;` counts match
  exactly (63/63) — no unbalanced conditional-compilation or colon
  definition introduced while extracting it from the fetched page.
- `00_test_prelude.fs` — shared setup every section depends on: the basic
  two's-complement assumptions (BITSSET?), the bound constants (MAX-UINT,
  MAX-INT, MIN-INT, MID-UINT, MID-UINT+1, MSB), the boolean constants
  (0S/1S via <FALSE>/<TRUE>), the floored-vs-symmetric division helpers
  (IFFLOORED/IFSYM), the string-compare helper (S=), and the shared memory
  buffers used by the FILL/MOVE tests (FBUF/SBUF/SEEBUF). Load this after
  `ttester.fs`, before any section file.
- `NN_name.tests.fs` — one file per forth6809.asm section (matching the
  exact same numbering and filenames as `forth6809_split/`), containing
  every ANS test block for the words that section implements.

153 test blocks placed across 17 section files (sections that implement
no words with an official ANS test — e.g. section 5's inner-interpreter
primitives like LIT/BRANCH, which have no directly-callable ANS name —
have no file, since there was nothing to place there).

## Load order — this matters, not just cosmetic

The original ANS suite is one continuous stream where later tests reuse
words and constants defined by earlier ones (this is explicit in the
standard's own F.3 narrative: "these are included in the appropriate
test"). Splitting it by forth6809.asm section preserves the *word
groupings* but not the full original ordering — a few cross-section
dependencies remain and must be respected:

- `09_outer_interpreter.tests.fs` (FIND) uses `GT1`/`GT2`, which are
  defined by the `'`/`[']` tests in `13_compiling_words.tests.fs`. Load
  13 before 9, even though forth6809.asm's own section numbering runs
  the other way.
- Several `20_numeric_output.tests.fs` tests use `MAX-BASE`, `#BITS-UD`,
  and `S=`, already provided by `00_test_prelude.fs`.
- `18_memory.tests.fs`'s `MOVE` test depends on the `FBUF`/`SEEBUF` state
  left behind by the immediately preceding `FILL` test in the same file
  — this dependency stayed intact since both are in the same section.

If you want a single flat run, the safe order is: `ttester.fs`, then
`00_test_prelude.fs`, then sections in this sequence: 21, 17, 16, 14,
15, 18, 19, 20, 13, 9, 8, 12, 24, 10, 11, 26, 23 (roughly the original
F.3 progression, adapted to where each word actually landed after the
split).

## Two real gaps this exercise surfaced — one still open, one since resolved

- **`TRUE` and `FALSE` were not implemented as dictionary words** when
  this test suite was first organized — checked directly against
  `forth6809.asm`'s dictionary section at the time: only the internal
  assembler constants `TRUEV`/`FALSEV` existed, never exposed as
  `CONSTANT TRUE` / `CONSTANT FALSE` a running program could call. This
  has since been resolved: both are now real dictionary words
  (`CONSTANT TRUE -1` / `CONSTANT FALSE 0`), and their tests
  (`F.6.2.1485 FALSE`, `F.6.2.2298 TRUE`) are now included at the end of
  `26_abort_quit_headers.tests.fs`, alongside that section's other
  ROM-resident, hand-built words.
- Everything else in Core (F.6.1) and the Core Extension subset this
  system implements (F.6.2) mapped cleanly to exactly one section.

## Not included

Double-Number, Facility, File-Access, Floating-Point, Memory-Allocation,
and Search-Order word-set tests are all omitted — forth6809 implements
none of those word sets (Search-Order's absence is documented explicitly
in the ClaudeForth documentation, Section 4.5). Most of the Programming-
Tools word set is also omitted (AHEAD, CS-PICK, CS-ROLL, N>R, [THEN],
etc. have no ANS test coverage relevant here since this system's own
Tools word set — `.S`, `WORDS`, `DUMP` — are non-standard extensions
with no official ANS test cases to begin with).
