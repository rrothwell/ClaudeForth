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

\ F.9.6.2.0670  ABORT
See F.9.6.2.0680 ABORT".

\ F.9.6.2.0680  ABORT"
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


\ F.6.2.1485  FALSE
\ Added after these tests were first organized: TRUE/FALSE were
\ not yet implemented as dictionary words at that point (see
\ README and the open-items checklist). Now resolved.
T{ FALSE -> 0 }T   T{ FALSE -> <FALSE> }T

\ F.6.2.2298  TRUE
T{ TRUE -> <TRUE> }T   T{ TRUE -> 0 INVERT }T
