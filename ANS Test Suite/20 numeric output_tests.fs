\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 20 (20_numeric_output)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M20 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M20 at the end (below)
\ erases everything this file defined - including M20 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M20

\ F.6.1.0030  #
: GP3  <# 1 0 # # #> S" 01" S= ;   T{ GP3 -> <TRUE> }T

\ F.6.1.0040  #>
\ See F.6.1.0030 #, F.6.1.0050 #S, F.6.1.1670 HOLD and F.6.1.2210 SIGN.

\ F.6.1.0050  #S
: GP4  <# 1 0 #S #> S" 1" S= ;   T{ GP4 -> <TRUE> }T

\ F.6.1.0180  .
\ See F.6.1.1320 EMIT.

\ F.6.1.0490  <#
\ See F.6.1.0030 #, F.6.1.0050 #S, F.6.1.1670 HOLD, F.6.1.2210 SIGN.

\ F.6.1.1670  HOLD
: GP1 <# 41 HOLD 42 HOLD 0 0 #> S" BA" S= ;   T{ GP1 -> <TRUE> }T

\ F.6.1.2210  SIGN
: GP2 <# -1 SIGN 0 SIGN -1 SIGN 0 0 #> S" --" S= ;   T{ GP2 -> <TRUE> }T

\ F.6.1.2320  U.
\ See F.6.1.1320 EMIT.

\ F.6.2.1675  HOLDS
T{ 0. <# S" Test" HOLDS #> S" Test" COMPARE -> 0 }T

\ ---- section-marker: undo everything above ----
M20
