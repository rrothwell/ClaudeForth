\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 18 (18_memory)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0010  !
See F.6.1.0150 ,.

\ F.6.1.0130  +!
T{ 0 1ST ! -> }T   T{ 1 1ST +! -> }T   T{ 1ST @ -> 1 }T   T{ -1 1ST +! 1ST @ -> 0 }T

\ F.6.1.0150  ,
HERE 1 ,
HERE 2 ,
CONSTANT 2ND
CONSTANT 1ST
T{ 1ST 2ND U< -> <TRUE> }T \ HERE MUST GROW WITH ALLOT   T{ 1ST CELL+ -> 2ND }T \ ... BY ONE CELL   T{ 1ST 1 CELLS + -> 2ND }T   T{ 1ST @ 2ND @ -> 1 2 }T   T{ 5 1ST ! -> }T   T{ 1ST @ 2ND @ -> 5 2 }T   T{ 6 2ND ! -> }T   T{ 1ST @ 2ND @ -> 5 6 }T   T{ 1ST 2@ -> 6 5 }T   T{ 2 1 1ST 2! -> }T   T{ 1ST 2@ -> 2 1 }T   T{ 1S 1ST ! 1ST @ -> 1S }T \ CAN STORE CELL-WIDE VALUE

\ F.6.1.0310  2!
See F.6.1.0150 ,.

\ F.6.1.0350  2@
See F.6.1.0150 ,.

\ F.6.1.0650  @
See F.6.1.0150 ,.

\ F.6.1.0710  ALLOT
HERE 1 ALLOT
HERE
CONSTANT 2NDA
CONSTANT 1STA   T{ 1STA 2NDA U< -> <TRUE> }T \ HERE MUST GROW WITH ALLOT   T{ 1STA 1+ -> 2NDA }T \ ... BY ONE ADDRESS UNIT

\ F.6.1.0850  C!
See F.6.1.0860 C,.

\ F.6.1.0860  C,
HERE 1 C,
HERE 2 C,
CONSTANT 2NDC
CONSTANT 1STC
T{ 1STC 2NDC U< -> <TRUE> }T \ HERE MUST GROW WITH ALLOT   T{ 1STC CHAR+ -> 2NDC }T \ ... BY ONE CHAR   T{ 1STC 1 CHARS + -> 2NDC }T   T{ 1STC C@ 2NDC C@ -> 1 2 }T   T{ 3 1STC C! -> }T   T{ 1STC C@ 2NDC C@ -> 3 2 }T   T{ 4 2NDC C! -> }T   T{ 1STC C@ 2NDC C@ -> 3 4 }T

\ F.6.1.0870  C@
See F.6.1.0860 C,.

\ F.6.1.1540  FILL
T{ FBUF 0 20 FILL -> }T   T{ SEEBUF -> 00 00 00 }T
T{ FBUF 1 20 FILL -> }T   T{ SEEBUF -> 20 00 00 }T
T{ FBUF 3 20 FILL -> }T   T{ SEEBUF -> 20 20 20 }T

\ F.6.1.1650  HERE
See F.6.1.0150 ,, F.6.1.0710 ALLOT, F.6.1.0860 C,.

\ F.6.1.1900  MOVE
T{ FBUF FBUF 3 CHARS MOVE -> }T   T{ SEEBUF -> 20 20 20 }T
T{ SBUF FBUF 0 CHARS MOVE -> }T   T{ SEEBUF -> 20 20 20 }T
T{ SBUF FBUF 1 CHARS MOVE -> }T   T{ SEEBUF -> 12 20 20 }T
T{ SBUF FBUF 3 CHARS MOVE -> }T   T{ SEEBUF -> 12 34 56 }T
T{ FBUF FBUF CHAR+ 2 CHARS MOVE -> }T   T{ SEEBUF -> 12 12 34 }T
T{ FBUF CHAR+ FBUF 2 CHARS MOVE -> }T   T{ SEEBUF -> 12 34 34 }T

