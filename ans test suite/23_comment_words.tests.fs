\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 23 (23_comment_words)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0080  (
\ There is no space either side of the ).  T{ ( A comment)1234 -> }T   T{ : pc1 ( A comment)1234 ; pc1 -> 1234 }T

