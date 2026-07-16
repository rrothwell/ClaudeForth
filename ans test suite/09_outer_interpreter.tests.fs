\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 9 (09_outer_interpreter)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.1550  FIND
HERE 3 C, CHAR G C, CHAR T C, CHAR 1 C, CONSTANT GT1STRING
HERE 3 C, CHAR G C, CHAR T C, CHAR 2 C, CONSTANT GT2STRING   T{ GT1STRING FIND -> ' GT1 -1 }T   T{ GT2STRING FIND -> ' GT2 1 }T

