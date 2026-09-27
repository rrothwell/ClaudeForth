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

\ F.9.6.1.0875  CATCH
See F.9.6.1.2275 THROW.

\ F.9.6.1.2275  THROW
DECIMAL
: t1 9 ;
: c1 1 2 3 ['] t1 CATCH ;   T{ c1 -> 1 2 3 9 0 }T
: t2 8 0 THROW ;
: c2 1 2 ['] t2 CATCH ;   T{ c2 -> 1 2 8 0 }T
: t3 7 8 9 99 THROW ;
: c3 1 2 ['] t3 CATCH ;  T{ c3 -> 1 2 99 }T
: t4 1- DUP 0> IF RECURSE ELSE 999 THROW -222 THEN ;
: c4 3 4 5 10 ['] t4 CATCH -111 ;   T{ c4 -> 3 4 5 0 999 -111 }T
: t5 2DROP 2DROP 9999 THROW ;
: c5 1 2 3 4 ['] t5 CATCH
DEPTH >R DROP 2DROP 2DROP R> ;   T{ c5 -> 5 }T

\ F.9.3.6  Exception handling (general propagation test, not tied
\ to a single word - included here since it exercises the same
\ THROW/CATCH/EVALUATE machinery this section implements)
DECIMAL
: t7 S" 333 $$UndefedWord$$ 334" EVALUATE 335 ;
: t8 S" 222 t7 223" EVALUATE 224 ;
: t9 S" 111 112 t8 113" EVALUATE 114 ;
T{ 6 7 ' t9 c6 3 -> 6 7 13 3 }T
