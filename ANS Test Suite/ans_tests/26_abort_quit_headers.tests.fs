\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 26 (26_abort_quit_headers)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M26 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M26 at the end (below)
\ erases everything this file defined - including M26 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M26
\ Reset the pass/fail counters, record the stack depth.
TEST-BEGIN

\ F.9.6.2.0670  ABORT
\ See F.9.6.2.0680 ABORT".

\ F.9.6.2.0680  ABORT" - exc_undef (-13) and the OF branch values need
\ DECIMAL; saved/restored locally rather than a bare DECIMAL, for
\ the same reason as the other files this round (this one happens
\ to be last in load order, so nothing downstream is affected
\ today, but there's no guarantee it stays last).
\ BUG FIX (round 1): was "BASE @ >R DECIMAL ... R> BASE !" - unsafe
\ spanning separate top-level lines (see 08_defining_words.tests.fs's
\ matching comment for the full >R/R> mechanism).
\ BUG FIX (round 2): plain "BASE @ DECIMAL ... BASE !" is also
\ fragile here - this file tests ABORT/ABORT"/CATCH directly, a
\ plausible source of an uncaught error that would wipe a parked
\ stack value via QLOOP's top-level recovery. Unconditional restore
\ instead - see 08_defining_words.tests.fs for the full reasoning.

DECIMAL
-1 CONSTANT exc_abort
-2 CONSTANT exc_abort"
-13 CONSTANT exc_undef
: t6 ABORT ;
: t10 77 SWAP ABORT" This should not be displayed" ;
: c6 CATCH
CASE exc_abort OF 11 ENDOF
exc_abort" OF 12 ENDOF
exc_undef OF 13 ENDOF
ENDCASE
;
T{ 1 2 ' t6 c6 -> 1 2 11 }T
T{ 3 0 ' t10 c6 -> 3 77 }T
T{ 4 5 ' t10 c6 -> 4 77 12 }T
HEX

\ F.6.2.1485  FALSE

\ Added after these tests were first organized: TRUE/FALSE were
\ not yet implemented as dictionary words at that point (see
\ README and the open-items checklist). Now resolved.
T{ FALSE -> 0 }T
T{ FALSE -> <FALSE> }T
\ F.6.2.2298  TRUE

T{ TRUE -> <TRUE> }T
T{ TRUE -> 0 INVERT }T
\ Print this file's TEST SUMMARY and trim any stray stack cells.
TEST-END
\ ---- section-marker: undo everything above ----
M26
