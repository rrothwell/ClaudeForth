\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 24 (24_environmental_query)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0560  >IN
VARIABLE SCANS
: RESCAN? -1 SCANS +! SCANS @ IF 0 >IN ! THEN ;
T{ 2 SCANS !
345 RESCAN?
-> 345 345 }T
: GS2 5 SCANS ! S" 123 RESCAN?" EVALUATE ;   T{ GS2 -> 123 123 123 123 123 }T
\ These tests must start on a new line
DECIMAL
T{ 123456 DEPTH OVER 9 < 35 AND + 3 + >IN !
-> 123456 23456 3456 456 56 6 }T
T{ 14145 8115 ?DUP 0= 34 AND >IN +! TUCK MOD 14 >IN ! -> 15 }T

\ F.6.1.0570  >NUMBER
CREATE GN-BUF 0 C,
: GN-STRING GN-BUF 1 ;
: GN-CONSUMED GN-BUF CHAR+ 0 ;
: GN' [CHAR] ' WORD CHAR+ C@ GN-BUF C! GN-STRING ;
T{ 0 0 GN' 0' >NUMBER -> 0 0 GN-CONSUMED }T   T{ 0 0 GN' 1' >NUMBER -> 1 0 GN-CONSUMED }T   T{ 1 0 GN' 1' >NUMBER -> BASE @ 1+ 0 GN-CONSUMED }T
\ FOLLOWING SHOULD FAIL TO CONVERT   T{ 0 0 GN' -' >NUMBER -> 0 0 GN-STRING }T   T{ 0 0 GN' +' >NUMBER -> 0 0 GN-STRING }T   T{ 0 0 GN' .' >NUMBER -> 0 0 GN-STRING }T
: >NUMBER-BASED
BASE @ >R BASE ! >NUMBER R> BASE ! ;
T{ 0 0 GN' 2' 10 >NUMBER-BASED -> 2 0 GN-CONSUMED }T   T{ 0 0 GN' 2' 2 >NUMBER-BASED -> 0 0 GN-STRING }T   T{ 0 0 GN' F' 10 >NUMBER-BASED -> F 0 GN-CONSUMED }T   T{ 0 0 GN' G' 10 >NUMBER-BASED -> 0 0 GN-STRING }T   T{ 0 0 GN' G' MAX-BASE >NUMBER-BASED -> 10 0 GN-CONSUMED }T   T{ 0 0 GN' Z' MAX-BASE >NUMBER-BASED -> 23 0 GN-CONSUMED }T
: GN1 ( UD BASE -- UD' LEN )
BASE @ >R BASE !
<# #S #>
0 0 2SWAP >NUMBER SWAP DROP
R> BASE ! ;
T{ 0 0 2 GN1 -> 0 0 0 }T   T{ MAX-UINT 0 2 GN1 -> MAX-UINT 0 0 }T   T{ MAX-UINT DUP 2 GN1 -> MAX-UINT DUP 0 }T   T{ 0 0 MAX-BASE GN1 -> 0 0 0 }T   T{ MAX-UINT 0 MAX-BASE GN1 -> MAX-UINT 0 0 }T   T{ MAX-UINT DUP MAX-BASE GN1 -> MAX-UINT DUP 0 }T

\ F.6.1.0770  BL
T{ BL -> 20 }T

\ F.6.1.1345  ENVIRONMENT?
T{ S" X:deferred" ENVIRONMENT? DUP 0= XOR INVERT -> <TRUE> }T   T{ S" X:notfound" ENVIRONMENT? DUP 0= XOR INVERT -> <FALSE> }T

\ F.6.1.1360  EVALUATE
: GE1 S" 123" ; IMMEDIATE
: GE2 S" 123 1+" ; IMMEDIATE
: GE3 S" : GE4 345 ;" ;
: GE5 EVALUATE ; IMMEDIATE
T{ GE1 EVALUATE -> 123 }T   T{ GE2 EVALUATE -> 124 }T   T{ GE3 EVALUATE -> }T   T{ GE4 -> 345 }T
T{ : GE6 GE1 GE5 ; -> }T   T{ GE6 -> 123 }T   T{ : GE7 GE2 GE5 ; -> }T   T{ GE7 -> 124 }T

\ F.6.1.2216  SOURCE
: GS1 S" SOURCE" 2DUP EVALUATE >R SWAP >R = R> R> = ;   T{ GS1 -> <TRUE> <TRUE> }T
: GS4 SOURCE >IN ! DROP ;   T{ GS4 123 456
-> }T

