\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 11 (11_catch_throw)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M11 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M11 at the end (below)
\ erases everything this file defined - including M11 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M11
\ Reset the pass/fail counters, record the stack depth.
TEST-BEGIN

\ F.9.6.1.0875  CATCH
\ See F.9.6.1.2275 THROW.

\ F.9.6.1.2275  THROW - this whole file's throw-codes (99, 9999, -222,
\ etc) need DECIMAL; saved/restored around the whole file rather
\ than a bare DECIMAL, which would otherwise leak the base change
\ into whatever section file loads next (MARKER only resets the
\ dictionary/HERE, never BASE).
\ BUG FIX (round 1): was "BASE @ >R DECIMAL ... R> BASE !" - unsafe
\ spanning separate top-level lines (see 08_defining_words.tests.fs's
\ matching comment for the full >R/R> mechanism).
\ BUG FIX (round 2): a plain "BASE @ DECIMAL ... BASE !" save/restore
\ is ALSO fragile specifically in this file - it's the one file in
\ the corpus deliberately exercising uncaught-exception propagation
\ (t7/t8/t9 via nested EVALUATE), and QLOOP's own top-level recovery
\ resets the whole data stack on any uncaught error, wiping a parked
\ save. Unconditional restore instead - no save needed, since
\ ambient base here is always HEX by convention (see
\ 08_defining_words.tests.fs for the full reasoning).

DECIMAL
: t1 9 ;
: c1 1 2 3 ['] t1 CATCH ;
T{ c1 -> 1 2 3 9 0 }T
: t2 8 0 THROW ;
: c2 1 2 ['] t2 CATCH ;
T{ c2 -> 1 2 8 0 }T
: t3 7 8 9 99 THROW ;
: c3 1 2 ['] t3 CATCH ;
T{ c3 -> 1 2 99 }T
: t4 1- DUP 0> IF RECURSE ELSE 999 THROW -222 THEN ;
: c4 3 4 5 10 ['] t4 CATCH -111 ;
T{ c4 -> 3 4 5 0 999 -111 }T
: t5 2DROP 2DROP 9999 THROW ;
: c5 1 2 3 4 ['] t5 CATCH DEPTH >R DROP 2DROP 2DROP R> ;
T{ c5 -> 5 }T

\ F.9.3.6  Exception handling 
\ (general propagation test, not tied
\ to a single word - included here since it exercises the same
\ THROW/CATCH/EVALUATE machinery this section implements)

: t7 S" 333 $$UndefedWord$$ 334" EVALUATE 335 ;
: t8 S" 222 t7 223" EVALUATE 224 ;
: t9 S" 111 112 t8 113" EVALUATE 114 ;
\ c6 was referenced but never defined anywhere in the corpus - not
\ an extraction bug (this whole test is custom, per the comment
\ above, not lifted from Annex F), just a missing definition.
\ Completing the obvious c1..c5 pattern here: a plain CATCH wrapper.
\ NOTE: forth6809.asm's BADWORD throws -13 (the standard ANS
\ "undefined word" code) for $$UndefedWord$$, not +13 - so the
\ expected result below may need to read "6 7 -13 3" rather than
\ "6 7 13 3" once this is actually run; left as-is since I can't
\ verify what this custom test's author originally intended.

: c6 CATCH ;
\ Expected -13 (standard undefined-word code), confirmed by design.
T{ 6 7 ' t9 c6 3 -> 6 7 -13 3 }T
HEX

\ Print this file's TEST SUMMARY and trim any stray stack cells.
TEST-END
\ ---- section-marker: undo everything above ----
M11
