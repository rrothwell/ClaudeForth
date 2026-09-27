\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 17 (17_comparison)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0250  0<
T{ 0 0< -> <FALSE> }T   T{ -1 0< -> <TRUE> }T   T{ MIN-INT 0< -> <TRUE> }T   T{ 1 0< -> <FALSE> }T   T{ MAX-INT 0< -> <FALSE> }T

\ F.6.1.0270  0=
T{ 0 0= -> <TRUE> }T   T{ 1 0= -> <FALSE> }T   T{ 2 0= -> <FALSE> }T   T{ -1 0= -> <FALSE> }T   T{ MAX-UINT 0= -> <FALSE> }T   T{ MIN-INT 0= -> <FALSE> }T   T{ MAX-INT 0= -> <FALSE> }T

\ F.6.1.0480  <
T{ 0 1 < -> <TRUE> }T   T{ 1 2 < -> <TRUE> }T   T{ -1 0 < -> <TRUE> }T   T{ -1 1 < -> <TRUE> }T   T{ MIN-INT 0 < -> <TRUE> }T   T{ MIN-INT MAX-INT < -> <TRUE> }T   T{ 0 MAX-INT < -> <TRUE> }T   T{ 0 0 < -> <FALSE> }T   T{ 1 1 < -> <FALSE> }T   T{ 1 0 < -> <FALSE> }T   T{ 2 1 < -> <FALSE> }T   T{ 0 -1 < -> <FALSE> }T   T{ 1 -1 < -> <FALSE> }T   T{ 0 MIN-INT < -> <FALSE> }T   T{ MAX-INT MIN-INT < -> <FALSE> }T   T{ MAX-INT 0 < -> <FALSE> }T

\ F.6.1.0530  =
T{ 0 0 = -> <TRUE> }T   T{ 1 1 = -> <TRUE> }T   T{ -1 -1 = -> <TRUE> }T   T{ 1 0 = -> <FALSE> }T   T{ -1 0 = -> <FALSE> }T   T{ 0 1 = -> <FALSE> }T   T{ 0 -1 = -> <FALSE> }T

\ F.6.1.0540  >
T{ 0 1 > -> <FALSE> }T   T{ 1 2 > -> <FALSE> }T   T{ -1 0 > -> <FALSE> }T   T{ -1 1 > -> <FALSE> }T   T{ MIN-INT 0 > -> <FALSE> }T   T{ MIN-INT MAX-INT > -> <FALSE> }T   T{ 0 MAX-INT > -> <FALSE> }T   T{ 0 0 > -> <FALSE> }T   T{ 1 1 > -> <FALSE> }T   T{ 1 0 > -> <TRUE> }T   T{ 2 1 > -> <TRUE> }T   T{ 0 -1 > -> <TRUE> }T   T{ 1 -1 > -> <TRUE> }T   T{ 0 MIN-INT > -> <TRUE> }T   T{ MAX-INT MIN-INT > -> <TRUE> }T   T{ MAX-INT 0 > -> <TRUE> }T

\ F.6.1.2340  U<
T{ 0 1 U< -> <TRUE> }T   T{ 1 2 U< -> <TRUE> }T   T{ 0 MID-UINT U< -> <TRUE> }T   T{ 0 MAX-UINT U< -> <TRUE> }T   T{ MID-UINT MAX-UINT U< -> <TRUE> }T   T{ 0 0 U< -> <FALSE> }T   T{ 1 1 U< -> <FALSE> }T   T{ 1 0 U< -> <FALSE> }T   T{ 2 1 U< -> <FALSE> }T   T{ MID-UINT 0 U< -> <FALSE> }T   T{ MAX-UINT 0 U< -> <FALSE> }T   T{ MAX-UINT MID-UINT U< -> <FALSE> }T

