\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 13 (13_compiling_words)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0070  '
T{ : GT1 123 ; -> }T   T{ ' GT1 EXECUTE -> 123 }T

\ F.6.1.0190  ."
T{ : pb1 CR ." You should see 2345: " 2345"; pb1 -> }T
See F.6.1.1320 EMIT.

\ F.6.1.0550  >BODY
T{ CREATE CR0 -> }T   T{ ' CR0 >BODY -> HERE }T

\ F.6.1.1370  EXECUTE
See F.6.1.0070 ' and F.6.1.2510 '].

\ F.6.1.1710  IMMEDIATE
T{ 123 CONSTANT iw1 IMMEDIATE iw1 -> 123 }T   T{ : iw2 iw1 LITERAL ; iw2 -> 123 }T
T{ VARIABLE iw3 IMMEDIATE 234 iw3 ! iw3 @ -> 234 }T   T{ : iw4 iw3 [ @ ] LITERAL ; iw4 -> 234 }T
T{ :NONAME [ 345 ] iw3 [ ! ] ; DROP iw3 @ -> 345 }T   T{ CREATE iw5 456 , IMMEDIATE -> }T   T{ :NONAME iw5 [ @ iw3 ! ] ; DROP iw3 @ -> 456 }T
T{ : iw6 CREATE , IMMEDIATE DOES> @ 1+ ; -> }T   T{ 111 iw6 iw7 iw7 -> 112 }T   T{ : iw8 iw7 LITERAL 1+ ; iw8 -> 113 }T
T{ : iw9 CREATE , DOES> @ 2 + IMMEDIATE ; -> }T
: find-iw BL WORD FIND NIP ;   T{ 222 iw9 iw10 find-iw iw10 -> -1 }T \ iw10 is not immediate   T{ iw10 find-iw iw10 -> 224 1 }T \ iw10 becomes immediate

\ F.6.1.1780  LITERAL
T{ : GT3 GT2 LITERAL ; -> }T   T{ GT3 -> ' GT1 }T

\ F.6.1.2033  POSTPONE
T{ : GT4 POSTPONE GT1 ; IMMEDIATE -> }T   T{ : GT5 GT4 ; -> }T   T{ GT5 -> 123 }T
T{ : GT6 345 ; IMMEDIATE -> }T   T{ : GT7 POSTPONE GT6 ; -> }T   T{ GT7 -> 345 }T

\ F.6.1.2165  S"
T{ : GC4 S" XY" ; -> }T   T{ GC4 SWAP DROP -> 2 }T   T{ GC4 DROP DUP C@ SWAP CHAR+ C@ -> 58 59 }T
: GC5 S" A String"2DROP ;   T{ GC5 -> }T

\ F.6.1.2250  STATE
T{ : GT8 STATE @ ; IMMEDIATE -> }T   T{ GT8 -> 0 }T   T{ : GT9 GT8 LITERAL ; -> }T   T{ GT9 0= -> <FALSE> }T

\ F.6.1.2500  [
T{ : GC3 [ GC1 ] LITERAL ; -> }T   T{ GC3 -> 58 }T

\ F.6.1.2510  [']
T{ : GT2 ['] GT1 ; IMMEDIATE -> }T   T{ GT2 EXECUTE -> 123 }T

\ F.6.1.2540  ]
See F.6.1.2500 [.

\ F.6.2.0945  COMPILE,
:NONAME DUP + ; CONSTANT dup+   T{ : q dup+ COMPILE, ; -> }T   T{ : as [ q ] ; -> }T   T{ 123 as -> 246 }T

\ F.6.2.2530  [COMPILE]
T{ : [c1] [COMPILE] DUP ; IMMEDIATE -> }T   T{ 123 [c1] -> 123 123 }T
T{ : [c2] [COMPILE] [c1] ; -> }T   T{ 234 [c2] -> 234 234 }T
T{ : [cif] [COMPILE] IF ; IMMEDIATE -> }T   T{ : [c3] [cif] 111 ELSE 222 THEN ; -> }T   T{ -1 [c3] -> 111 }T   T{ 0 [c3] -> 222 }T

