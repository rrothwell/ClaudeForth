\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 14 (14_stack_manipulation)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0370  2DROP
T{ 1 2 2DROP -> }T

\ F.6.1.0380  2DUP
T{ 1 2 2DUP -> 1 2 1 2 }T

\ F.6.1.0400  2OVER
T{ 1 2 3 4 2OVER -> 1 2 3 4 1 2 }T

\ F.6.1.0430  2SWAP
T{ 1 2 3 4 2SWAP -> 3 4 1 2 }T

\ F.6.1.0580  >R
T{ : GR1 >R R> ; -> }T   T{ : GR2 >R R@ R> DROP ; -> }T   T{ 123 GR1 -> 123 }T   T{ 123 GR2 -> 123 }T   T{ 1S GR1 -> 1S }T

\ F.6.1.0630  ?DUP
T{ -1 ?DUP -> -1 -1 }T   T{ 0 ?DUP -> 0 }T   T{ 1 ?DUP -> 1 1 }T

\ F.6.1.1200  DEPTH
T{ 0 1 DEPTH -> 0 1 2 }T   T{ 0 DEPTH -> 0 1 }T   T{ DEPTH -> 0 }T

\ F.6.1.1260  DROP
T{ 1 2 DROP -> 1 }T   T{ 0 DROP -> }T

\ F.6.1.1290  DUP
T{ 1 DUP -> 1 1 }T

\ F.6.1.1990  OVER
T{ 1 2 OVER -> 1 2 1 }T

\ F.6.1.2060  R>
See F.6.1.0580 >R.

\ F.6.1.2070  R@
See F.6.1.0580 >R.

\ F.6.1.2160  ROT
T{ 1 2 3 ROT -> 2 3 1 }T

\ F.6.1.2260  SWAP
T{ 1 2 SWAP -> 2 1 }T

