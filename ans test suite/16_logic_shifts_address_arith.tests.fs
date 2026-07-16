\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 16 (16_logic_shifts_address_arith)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0705  ALIGN
ALIGN 1 ALLOT HERE ALIGN HERE 3 CELLS ALLOT
CONSTANT A-ADDR CONSTANT UA-ADDR   T{ UA-ADDR ALIGNED -> A-ADDR }T   T{ 1 A-ADDR C! A-ADDR C@ -> 1 }T   T{ 1234 A-ADDR ! A-ADDR @ -> 1234 }T   T{ 123 456 A-ADDR 2! A-ADDR 2@ -> 123 456 }T   T{ 2 A-ADDR CHAR+ C! A-ADDR CHAR+ C@ -> 2 }T   T{ 3 A-ADDR CELL+ C! A-ADDR CELL+ C@ -> 3 }T   T{ 1234 A-ADDR CELL+ ! A-ADDR CELL+ @ -> 1234 }T   T{ 123 456 A-ADDR CELL+ 2! A-ADDR CELL+ 2@ -> 123 456 }T

\ F.6.1.0720  AND
T{ 0 0 AND -> 0 }T   T{ 0 1 AND -> 0 }T   T{ 1 0 AND -> 0 }T   T{ 1 1 AND -> 1 }T
T{ 0 INVERT 1 AND -> 1 }T   T{ 1 INVERT 1 AND -> 0 }T
T{ 0S 0S AND -> 0S }T   T{ 0S 1S AND -> 0S }T   T{ 1S 0S AND -> 0S }T   T{ 1S 1S AND -> 1S }T

\ F.6.1.0880  CELL+
See F.6.1.0150 ,.

\ F.6.1.0890  CELLS
: BITS ( X -- U )
0 SWAP BEGIN DUP WHILE
DUP MSB AND IF >R 1+ R> THEN 2*
REPEAT DROP ;
T{ 1 CELLS 1 < -> <FALSE> }T   T{ 1 CELLS 1 CHARS MOD -> 0 }T   T{ 1S BITS 10 < -> <FALSE> }T

\ F.6.1.0897  CHAR+
See F.6.1.0860 C,.

\ F.6.1.0898  CHARS
T{ 1 CHARS 1 < -> <FALSE> }T   T{ 1 CHARS 1 CELLS > -> <FALSE> }T

\ F.6.1.1720  INVERT
T{ 0S INVERT -> 1S }T   T{ 1S INVERT -> 0S }T

\ F.6.1.1805  LSHIFT
T{ 1 0 LSHIFT -> 1 }T   T{ 1 1 LSHIFT -> 2 }T   T{ 1 2 LSHIFT -> 4 }T   T{ 1 F LSHIFT -> 8000 }T   T{ 1S 1 LSHIFT 1 XOR -> 1S }T   T{ MSB 1 LSHIFT -> 0 }T

\ F.6.1.1980  OR
T{ 0S 0S OR -> 0S }T   T{ 0S 1S OR -> 1S }T   T{ 1S 0S OR -> 1S }T   T{ 1S 1S OR -> 1S }T

\ F.6.1.2162  RSHIFT
T{ 1 0 RSHIFT -> 1 }T   T{ 1 1 RSHIFT -> 0 }T   T{ 2 1 RSHIFT -> 1 }T   T{ 4 2 RSHIFT -> 1 }T   T{ 8000 F RSHIFT -> 1 }T   T{ MSB 1 RSHIFT MSB AND -> 0 }T   T{ MSB 1 RSHIFT 2* -> MSB }T

\ F.6.1.2490  XOR
T{ 0S 0S XOR -> 0S }T   T{ 0S 1S XOR -> 1S }T   T{ 1S 0S XOR -> 1S }T   T{ 1S 1S XOR -> 0S }T

