\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 12 (12_control_flow)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0140  +LOOP
T{ : GD2 DO I -1 +LOOP ; -> }T   T{ 1 4 GD2 -> 4 3 2 1 }T   T{ -1 2 GD2 -> 2 1 0 -1 }T   T{ MID-UINT MID-UINT+1 GD2 -> MID-UINT+1 MID-UINT }T
VARIABLE gditerations
VARIABLE gdincrement
: gd7 ( limit start increment -- )
gdincrement !
0 gditerations !
DO
1 gditerations +!
I
gditerations @ 6 = IF LEAVE THEN
gdincrement @
+LOOP gditerations @
;
T{ 4 4 -1 gd7 -> 4 1 }T   T{ 1 4 -1 gd7 -> 4 3 2 1 4 }T   T{ 4 1 -1 gd7 -> 1 0 -1 -2 -3 -4 6 }T   T{ 4 1 0 gd7 -> 1 1 1 1 1 1 6 }T   T{ 0 0 0 gd7 -> 0 0 0 0 0 0 6 }T   T{ 1 4 0 gd7 -> 4 4 4 4 4 4 6 }T   T{ 1 4 1 gd7 -> 4 5 6 7 8 9 6 }T   T{ 4 1 1 gd7 -> 1 2 3 3 }T   T{ 4 4 1 gd7 -> 4 5 6 7 8 9 6 }T   T{ 2 -1 -1 gd7 -> -1 -2 -3 -4 -5 -6 6 }T   T{ -1 2 -1 gd7 -> 2 1 0 -1 4 }T   T{ 2 -1 0 gd7 -> -1 -1 -1 -1 -1 -1 6 }T   T{ -1 2 0 gd7 -> 2 2 2 2 2 2 6 }T   T{ -1 2 1 gd7 -> 2 3 4 5 6 7 6 }T   T{ 2 -1 1 gd7 -> -1 0 1 3 }T   T{ -20 30 -10 gd7 -> 30 20 10 0 -10 -20 6 }T   T{ -20 31 -10 gd7 -> 31 21 11 1 -9 -19 6 }T   T{ -20 29 -10 gd7 -> 29 19 9 -1 -11 5 }T
MAX-UINT 8 RSHIFT 1+ CONSTANT ustep
ustep NEGATE CONSTANT -ustep
MAX-INT 7 RSHIFT 1+ CONSTANT step
step NEGATE CONSTANT -step
VARIABLE bump
T{ : gd8 bump ! DO 1+ bump @ +LOOP ; -> }T
T{ 0 MAX-UINT 0 ustep gd8 -> 256 }T   T{ 0 0 MAX-UINT -ustep gd8 -> 256 }T   T{ 0 MAX-INT MIN-INT step gd8 -> 256 }T   T{ 0 MIN-INT MAX-INT -step gd8 -> 256 }T

\ F.6.1.0760  BEGIN
See F.6.1.2430 WHILE, F.6.1.2390 UNTIL.

\ F.6.1.1240  DO
See F.6.1.1800 LOOP, F.6.1.0140 +LOOP, F.6.1.1730 J, F.6.1.1760 LEAVE, F.6.1.2380 UNLOOP.

\ F.6.1.1310  ELSE
See F.6.1.1700 IF.

\ F.6.1.1380  EXIT
See F.6.1.2380 UNLOOP.

\ F.6.1.1680  I
See F.6.1.1800 LOOP, F.6.1.0140 +LOOP, F.6.1.1730 J, F.6.1.1760 LEAVE, F.6.1.2380 UNLOOP.

\ F.6.1.1700  IF
T{ : GI1 IF 123 THEN ; -> }T   T{ : GI2 IF 123 ELSE 234 THEN ; -> }T   T{ 0 GI1 -> }T   T{ 1 GI1 -> 123 }T   T{ -1 GI1 -> 123 }T   T{ 0 GI2 -> 234 }T   T{ 1 GI2 -> 123 }T   T{ -1 GI1 -> 123 }T
\ Multiple ELSEs in an IF statement
: melse IF 1 ELSE 2 ELSE 3 ELSE 4 ELSE 5 THEN ;   T{ <FALSE> melse -> 2 4 }T   T{ <TRUE> melse -> 1 3 5 }T

\ F.6.1.1730  J
T{ : GD3 DO 1 0 DO J LOOP LOOP ; -> }T   T{ 4 1 GD3 -> 1 2 3 }T   T{ 2 -1 GD3 -> -1 0 1 }T   T{ MID-UINT+1 MID-UINT GD3 -> MID-UINT }T
T{ : GD4 DO 1 0 DO J LOOP -1 +LOOP ; -> }T   T{ 1 4 GD4 -> 4 3 2 1 }T   T{ -1 2 GD4 -> 2 1 0 -1 }T   T{ MID-UINT MID-UINT+1 GD4 -> MID-UINT+1 MID-UINT }T

\ F.6.1.1760  LEAVE
T{ : GD5 123 SWAP 0 DO
I 4 > IF DROP 234 LEAVE THEN
LOOP ; -> }T   T{ 1 GD5 -> 123 }T   T{ 5 GD5 -> 123 }T   T{ 6 GD5 -> 234 }T

\ F.6.1.1800  LOOP
T{ : GD1 DO I LOOP ; -> }T   T{ 4 1 GD1 -> 1 2 3 }T   T{ 2 -1 GD1 -> -1 0 1 }T   T{ MID-UINT+1 MID-UINT GD1 -> MID-UINT }T

\ F.6.1.2120  RECURSE
T{ : GI6 ( N -- 0,1,..N )
DUP IF DUP >R 1- RECURSE R> THEN ; -> }T   T{ 0 GI6 -> 0 }T   T{ 1 GI6 -> 0 1 }T   T{ 2 GI6 -> 0 1 2 }T   T{ 3 GI6 -> 0 1 2 3 }T   T{ 4 GI6 -> 0 1 2 3 4 }T
DECIMAL   T{ :NONAME ( n -- 0, 1, .., n )
DUP IF DUP >R 1- RECURSE R> THEN
;
CONSTANT rn1 -> }T   T{ 0 rn1 EXECUTE -> 0 }T   T{ 4 rn1 EXECUTE -> 0 1 2 3 4 }T
:NONAME ( n -- n1 )
1- DUP
CASE 0 OF EXIT ENDOF
1 OF 11 SWAP RECURSE ENDOF
2 OF 22 SWAP RECURSE ENDOF
3 OF 33 SWAP RECURSE ENDOF
DROP ABS RECURSE EXIT
ENDCASE
; CONSTANT rn2
T{ 1 rn2 EXECUTE -> 0 }T   T{ 2 rn2 EXECUTE -> 11 0 }T   T{ 4 rn2 EXECUTE -> 33 22 11 0 }T   T{ 25 rn2 EXECUTE -> 33 22 11 0 }T

\ F.6.1.2140  REPEAT
See F.6.1.2430 WHILE.

\ F.6.1.2270  THEN
See F.6.1.1700 IF.

\ F.6.1.2380  UNLOOP
T{ : GD6 ( PAT: {0 0},{0 0}{1 0}{1 1},{0 0}{1 0}{1 1}{2 0}{2 1}{2 2} )
0 SWAP 0 DO
I 1+ 0 DO
I J + 3 = IF I UNLOOP I UNLOOP EXIT THEN 1+
LOOP
LOOP ; -> }T   T{ 1 GD6 -> 1 }T   T{ 2 GD6 -> 3 }T   T{ 3 GD6 -> 4 1 2 }T

\ F.6.1.2390  UNTIL
T{ : GI4 BEGIN DUP 1+ DUP 5 > UNTIL ; -> }T   T{ 3 GI4 -> 3 4 5 6 }T   T{ 5 GI4 -> 5 6 }T   T{ 6 GI4 -> 6 7 }T

\ F.6.1.2430  WHILE
T{ : GI3 BEGIN DUP 5 < WHILE DUP 1+ REPEAT ; -> }T   T{ 0 GI3 -> 0 1 2 3 4 5 }T   T{ 4 GI3 -> 4 5 }T   T{ 5 GI3 -> 5 }T   T{ 6 GI3 -> 6 }T
T{ : GI5 BEGIN DUP 2 > WHILE
DUP 5 < WHILE DUP 1+ REPEAT
123 ELSE 345 THEN ; -> }T   T{ 1 GI5 -> 1 345 }T   T{ 2 GI5 -> 2 345 }T   T{ 3 GI5 -> 3 4 5 123 }T   T{ 4 GI5 -> 4 5 123 }T   T{ 5 GI5 -> 5 123 }T

\ F.6.2.0620  ?DO
DECIMAL
: qd ?DO I LOOP ;   T{ 789 789 qd -> }T   T{ -9876 -9876 qd -> }T   T{ 5 0 qd -> 0 1 2 3 4 }T
: qd1 ?DO I 10 +LOOP ;   T{ 50 1 qd1 -> 1 11 21 31 41 }T   T{ 50 0 qd1 -> 0 10 20 30 40 }T
: qd2 ?DO I 3 > IF LEAVE ELSE I THEN LOOP ;   T{ 5 -1 qd2 -> -1 0 1 2 3 }T
: qd3 ?DO I 1 +LOOP ;   T{ 4 4 qd3 -> }T   T{ 4 1 qd3 -> 1 2 3 }T   T{ 2 -1 qd3 -> -1 0 1 }T
: qd4 ?DO I -1 +LOOP ;   T{ 4 4 qd4 -> }T   T{ 1 4 qd4 -> 4 3 2 1 }T   T{ -1 2 qd4 -> 2 1 0 -1 }T
: qd5 ?DO I -10 +LOOP ;   T{ 1 50 qd5 -> 50 40 30 20 10 }T   T{ 0 50 qd5 -> 50 40 30 20 10 0 }T   T{ -25 10 qd5 -> 10 0 -10 -20 }T
VARIABLE qditerations
VARIABLE qdincrement
: qd6 ( limit start increment -- )
qdincrement !
0 qditerations !
?DO
1 qditerations +!
I
qditerations @ 6 = IF LEAVE THEN
qdincrement @
+LOOP qditerations @
;
T{ 4 4 -1 qd6 -> 0 }T   T{ 1 4 -1 qd6 -> 4 3 2 1 4 }T   T{ 4 1 -1 qd6 -> 1 0 -1 -2 -3 -4 6 }T   T{ 4 1 0 qd6 -> 1 1 1 1 1 1 6 }T   T{ 0 0 0 qd6 -> 0 }T   T{ 1 4 0 qd6 -> 4 4 4 4 4 4 6 }T   T{ 1 4 1 qd6 -> 4 5 6 7 8 9 6 }T   T{ 4 1 1 qd6 -> 1 2 3 3 }T   T{ 4 4 1 qd6 -> 0 }T   T{ 2 -1 -1 qd6 -> -1 -2 -3 -4 -5 -6 6 }T   T{ -1 2 -1 qd6 -> 2 1 0 -1 4 }T   T{ 2 -1 0 qd6 -> -1 -1 -1 -1 -1 -1 6 }T   T{ -1 2 0 qd6 -> 2 2 2 2 2 2 6 }T   T{ -1 2 1 qd6 -> 2 3 4 5 6 7 6 }T   T{ 2 -1 1 qd6 -> -1 0 1 3 }T

\ F.6.2.0873  CASE
: cs1 CASE 1 OF 111 ENDOF
2 OF 222 ENDOF
3 OF 333 ENDOF
>R 999 R>
ENDCASE
;
T{ 1 cs1 -> 111 }T   T{ 2 cs1 -> 222 }T   T{ 3 cs1 -> 333 }T   T{ 4 cs1 -> 999 }T
: cs2 >R CASE
-1 OF CASE R@ 1 OF 100 ENDOF
2 OF 200 ENDOF
>R -300 R>
ENDCASE
ENDOF
-2 OF CASE R@ 1 OF -99 ENDOF
>R -199 R>
ENDCASE
ENDOF
>R 299 R>
ENDCASE R> DROP ;
T{ -1 1 cs2 -> 100 }T   T{ -1 2 cs2 -> 200 }T   T{ -1 3 cs2 -> -300 }T   T{ -2 1 cs2 -> -99 }T   T{ -2 2 cs2 -> -199 }T   T{ 0 2 cs2 -> 299 }T

\ F.6.2.1342  ENDCASE
See F.6.2.0873 CASE.

\ F.6.2.1343  ENDOF
See F.6.2.0873 CASE.

\ F.6.2.1950  OF
See F.6.2.0873 CASE.

