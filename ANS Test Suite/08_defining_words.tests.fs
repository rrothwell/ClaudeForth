\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 8 (08_defining_words)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0450  :
T{ : NOP : POSTPONE ; ; -> }T   T{ NOP NOP1 NOP NOP2 -> }T   T{ NOP1 -> }T   T{ NOP2 -> }T
The following tests the dictionary search order:
T{ : GDX 123 ; : GDX GDX 234 ; -> }T   T{ GDX -> 123 234 }T

\ F.6.1.0460  ;
See F.6.1.0450 :.

\ F.6.1.0950  CONSTANT
T{ 123 CONSTANT X123 -> }T   T{ X123 -> 123 }T
T{ : EQU CONSTANT ; -> }T   T{ X123 EQU Y123 -> }T   T{ Y123 -> 123 }T

\ F.6.1.1000  CREATE
See F.6.1.0550 >BODY and F.6.1.1250 DOES>.

\ F.6.1.1250  DOES>
T{ : DOES1 DOES> @ 1 + ; -> }T   T{ : DOES2 DOES> @ 2 + ; -> }T   T{ CREATE CR1 -> }T   T{ CR1 -> HERE }T   T{ 1 , -> }T   T{ CR1 @ -> 1 }T   T{ DOES1 -> }T   T{ CR1 -> 2 }T   T{ DOES2 -> }T   T{ CR1 -> 3 }T
T{ : WEIRD: CREATE DOES> 1 + DOES> 2 + ; -> }T   T{ WEIRD: W1 -> }T   T{ ' W1 >BODY -> HERE }T   T{ W1 -> HERE 1 + }T   T{ W1 -> HERE 2 + }T

\ F.6.1.2410  VARIABLE
T{ VARIABLE V1 -> }T   T{ 123 V1 ! -> }T   T{ V1 @ -> 123 }T

\ F.6.2.0455  :NONAME
VARIABLE nn1
VARIABLE nn2   T{ :NONAME 1234 ; nn1 ! -> }T   T{ :NONAME 9876 ; nn2 ! -> }T   T{ nn1 @ EXECUTE -> 1234 }T   T{ nn2 @ EXECUTE -> 9876 }T

\ F.6.2.0698  ACTION-OF
T{ DEFER defer1 -> }T   T{ : action-defer1 ACTION-OF defer1 ; -> }T
T{ ' * ' defer1 DEFER! -> }T   T{ 2 3 defer1 -> 6 }T   T{ ACTION-OF defer1 -> ' * }T   T{ action-defer1 -> ' * }T
T{ ' + IS defer1 -> }T   T{ 1 2 defer1 -> 3 }T   T{ ACTION-OF defer1 -> ' + }T   T{ action-defer1 -> ' + }T

\ F.6.2.0825  BUFFER:
DECIMAL   T{ 127 CHARS BUFFER: TBUF1 -> }T   T{ 127 CHARS BUFFER: TBUF2 -> }T
\ Buffer is aligned   T{ TBUF1 ALIGNED -> TBUF1 }T
\ Buffers do not overlap   T{ TBUF2 TBUF1 - ABS 127 CHARS < -> <FALSE> }T
\ Buffer can be written to
1 CHARS CONSTANT /CHAR
: TFULL? ( c-addr n char -- flag )
TRUE 2SWAP CHARS OVER + SWAP ?DO
OVER I C@ = AND
/CHAR +LOOP NIP
;
T{ TBUF1 127 CHAR * FILL -> }T   T{ TBUF1 127 CHAR * TFULL? -> <TRUE> }T
T{ TBUF1 127 0 FILL -> }T   T{ TBUF1 127 0 TFULL? -> <TRUE> }T

\ F.6.2.1173  DEFER
T{ DEFER defer2 -> }T   T{ ' * ' defer2 DEFER! -> }T   T{ 2 3 defer2 -> 6 }T
T{ ' + IS defer2 -> }T   T{ 1 2 defer2 -> 3 }T

\ F.6.2.1175  DEFER!
T{ DEFER defer3 -> }T
T{ ' * ' defer3 DEFER! -> }T   T{ 2 3 defer3 -> 6 }T
T{ ' + ' defer3 DEFER! -> }T   T{ 1 2 defer3 -> 3 }T

\ F.6.2.1177  DEFER@
T{ DEFER defer4 -> }T
T{ ' * ' defer4 DEFER! -> }T   T{ 2 3 defer4 -> 6 }T   T{ ' defer4 DEFER@ -> ' * }T
T{ ' + IS defer4 -> }T   T{ 1 2 defer4 -> 3 }T   T{ ' defer4 DEFER@ -> ' + }T

\ F.6.2.1725  IS
T{ DEFER defer5 -> }T   T{ : is-defer5 IS defer5 ; -> }T
T{ ' * IS defer5 -> }T   T{ 2 3 defer5 -> 6 }T
T{ ' + is-defer5 -> }T   T{ 1 2 defer5 -> 3 }T

\ F.6.2.2295  TO
See F.6.2.2405 VALUE.

\ F.6.2.2405  VALUE
T{ 111 VALUE v1 -> }T   T{ -999 VALUE v2 -> }T   T{ v1 -> 111 }T   T{ v2 -> -999 }T   T{ 222 TO v1 -> }T   T{ v1 -> 222 }T
T{ : vd1 v1 ; -> }T   T{ vd1 -> 222 }T
T{ : vd2 TO v2 ; -> }T   T{ v2 -> -999 }T   T{ -333 vd2 -> }T   T{ v2 -> -333 }T   T{ v1 -> 222 }T

