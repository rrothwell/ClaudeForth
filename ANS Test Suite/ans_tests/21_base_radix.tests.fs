\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 21 (21_base_radix)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M21 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M21 at the end (below)
\ erases everything this file defined - including M21 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M21

\ F.6.1.0750  BASE
: GN2 ( -- 16 10 )
BASE @ >R HEX BASE @ DECIMAL BASE @ R> BASE ! ;   T{ GN2 -> 10 A }T

\ F.6.1.1170  DECIMAL
\ See F.6.1.0750 BASE.

\ F.6.2.1660  HEX
\ See F.6.1.0750 BASE.

\ ---- section-marker: undo everything above ----
M21
