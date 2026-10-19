\ ============================================================
\ ANS test suite - words that had no test in sections 08 to 29:
\   Group 1 (standard words): PICK ROLL 2R@ <> 0<> U> WITHIN
\     AGAIN ERASE PARSE SOURCE-ID REFILL TIB #TIB .R U.R
\   Group 2 (ClaudeForth extensions): 2+ BINARY SNAME
\     VHERE V, VC, VALLOT UNUSED VUNUSED
\ Requires ttester.fs then 00_test_prelude.fs first, in that
\ order. The tests for the standard words follow the forth-
\ standard.org Core and Core-Ext test suites, with the values
\ chosen for 16-bit cells. Base is HEX throughout.
\ ============================================================
MARKER M30
TEST-BEGIN

HEX

\ ============ Group 1: standard words ============

\ F.6.2.2030 PICK

T{ 1 2 3 0 PICK -> 1 2 3 3 }T
T{ 1 2 3 1 PICK -> 1 2 3 2 }T
T{ 1 2 3 2 PICK -> 1 2 3 1 }T


\ F.6.2.2150 ROLL

T{ 1 2 3 0 ROLL -> 1 2 3 }T
T{ 1 2 3 1 ROLL -> 1 3 2 }T
T{ 1 2 3 2 ROLL -> 2 3 1 }T
T{ 1 2 3 4 3 ROLL -> 2 3 4 1 }T


\ F.6.2.0415 2R@ 

\ Return-stack words can only be used inside definitions.
: g2r1 2>R 2R@ 2R> ;
T{ 1 2 g2r1 -> 1 2 1 2 }T
: g2r2 2>R 2R@ 2R> 2DROP ;
T{ 3 4 g2r2 -> 3 4 }T
T{ : g2r3 2>R 2R@ R> R> ; -> }T
T{ 5 6 g2r3 -> 5 6 6 5 }T


\ F.6.2.0500 <>

T{  0  0 <> -> <FALSE> }T
T{  1  1 <> -> <FALSE> }T
T{ -1 -1 <> -> <FALSE> }T
T{  1  0 <> -> <TRUE>  }T
T{ -1  0 <> -> <TRUE>  }T
T{  0  1 <> -> <TRUE>  }T
T{  0 -1 <> -> <TRUE>  }T
T{ MIN-INT MAX-INT <> -> <TRUE> }T


\ F.6.2.0260 0<>

T{        0 0<> -> <FALSE> }T
T{        1 0<> -> <TRUE>  }T
T{        2 0<> -> <TRUE>  }T
T{       -1 0<> -> <TRUE>  }T
T{ MAX-UINT 0<> -> <TRUE>  }T
T{  MIN-INT 0<> -> <TRUE>  }T
T{  MAX-INT 0<> -> <TRUE>  }T


\ F.6.2.2350 U>

T{        0        1 U> -> <FALSE> }T
T{        1        2 U> -> <FALSE> }T
T{        0 MID-UINT U> -> <FALSE> }T
T{        0 MAX-UINT U> -> <FALSE> }T
T{ MID-UINT MAX-UINT U> -> <FALSE> }T
T{        0        0 U> -> <FALSE> }T
T{        1        1 U> -> <FALSE> }T
T{        1        0 U> -> <TRUE>  }T
T{        2        1 U> -> <TRUE>  }T
T{ MID-UINT        0 U> -> <TRUE>  }T
T{ MAX-UINT        0 U> -> <TRUE>  }T
T{ MAX-UINT MID-UINT U> -> <TRUE>  }T
T{ MID-UINT+1 MID-UINT U> -> <TRUE> }T


\ F.6.2.2440 WITHIN

\ n1 is in the range n2 <= n1 < n3, and the range may wrap.
T{ 0 0 0 WITHIN -> <FALSE> }T
T{ 0 0 1 WITHIN -> <TRUE>  }T
T{ 1 0 1 WITHIN -> <FALSE> }T
T{ 5 3 8 WITHIN -> <TRUE>  }T
T{ 3 3 8 WITHIN -> <TRUE>  }T
T{ 8 3 8 WITHIN -> <FALSE> }T
T{ 2 3 8 WITHIN -> <FALSE> }T
T{ 7 3 8 WITHIN -> <TRUE>  }T
T{ 0 MIN-INT MAX-INT WITHIN -> <TRUE>  }T
T{ MIN-INT MIN-INT MAX-INT WITHIN -> <TRUE>  }T
T{ MAX-INT MIN-INT MAX-INT WITHIN -> <FALSE> }T
\ A range that wraps through zero: -1 up to (not including) 1.
T{ -2 -1 1 WITHIN -> <FALSE> }T
T{ -1 -1 1 WITHIN -> <TRUE>  }T
T{  0 -1 1 WITHIN -> <TRUE>  }T
T{  1 -1 1 WITHIN -> <FALSE> }T
T{  2 -1 1 WITHIN -> <FALSE> }T
\ n2 above n3: the range runs from n2 up through MAX-UINT, then 0 up to n3.
T{ -1 3 1 WITHIN -> <TRUE>  }T
T{  0 3 1 WITHIN -> <TRUE>  }T
T{  1 3 1 WITHIN -> <FALSE> }T
T{  2 3 1 WITHIN -> <FALSE> }T
T{  3 3 1 WITHIN -> <TRUE>  }T


\ F.6.2.0700 AGAIN

T{ : gi4 BEGIN DUP 1+ DUP 5 > IF EXIT THEN AGAIN ; -> }T
T{ 1 gi4 -> 1 2 3 4 5 6 }T
T{ 4 gi4 -> 4 5 6 }T
T{ 3 gi4 -> 3 4 5 6 }T
\ Counting up on the data stack until the loop leaves.
T{ : gi5 0 BEGIN 1+ DUP 7 = IF EXIT THEN AGAIN ; -> }T
T{ gi5 -> 7 }T


\ F.6.2.1350 ERASE

CREATE eb 4 ALLOT
: ebfill eb 4 FF FILL ;
: ebsee eb C@ eb 1+ C@ eb 2 + C@ eb 3 + C@ ;
T{ ebfill ebsee -> FF FF FF FF }T
T{ ebfill eb 2 ERASE ebsee -> 0 0 FF FF }T
T{ ebfill eb 1+ 2 ERASE ebsee -> FF 0 0 FF }T
T{ ebfill eb 4 ERASE ebsee -> 0 0 0 0 }T
\ A count of zero changes nothing.
T{ ebfill eb 0 ERASE ebsee -> FF FF FF FF }T


\ F.6.2.2008 PARSE

\ The delimiter is not skipped at the start, so an empty string is
\ possible; the length comes back with the address.
T{ CHAR | PARSE 1234| DUP ROT ROT EVALUATE -> 4 1234 }T
T{ CHAR ^ PARSE  23 123 ^ DUP ROT ROT EVALUATE -> 8 23 123 }T
T{ CHAR | PARSE |  NIP -> 0 }T
T{ CHAR , PARSE abc, NIP -> 3 }T
T{ BL PARSE xyz  NIP -> 3 }T


\ F.6.2.2218 SOURCE-ID
\ F.6.2.2125 REFILL

\ Both tests run from the terminal, which is source 0; an EVALUATEd
\ string is source -1 and cannot be refilled.
T{ SOURCE-ID -> 0 }T
: sid1 S" SOURCE-ID" EVALUATE ;
T{ sid1 -> -1 }T
: rf1 S" REFILL" EVALUATE ;
T{ rf1 -> <FALSE> }T


\ F.XXXX TIB
\ F.XXXX #TIB
\ Removed from ANS Forth.

\ TIB is the fixed terminal buffer ($0106, TIBBUF), #TIB its character
\ count. 0106 is hex, so the base must be HEX here.
T{ TIB 0106 = -> <TRUE> }T
T{ SOURCE DROP TIB = -> <TRUE> }T
: tb1 S" TIB" EVALUATE ;
T{ tb1 TIB = -> <TRUE> }T
T{ #TIB @ SOURCE NIP = -> <TRUE> }T
T{ #TIB @ >IN @ U> -> <TRUE> }T


\ F.6.2.0210 .R
\ F.6.2.2330 U.R 

\ Visual test.
\ The two lines of each pair must be identical. The values are
\ shown in hex (the base here): 123 is $123 and so on.
: RJOutput
   CR ." You should see lines duplicated:" CR
   S"  123" TYPE CR    123 4 .R CR
   S"   -7B" TYPE CR   -7B 5 .R CR
   S" 0" TYPE CR       0 1 .R CR
   S" -123" TYPE CR    -123 2 .R CR
   S"      FFFF" TYPE CR   MAX-UINT 9 U.R CR
   S" 8000" TYPE CR    MIN-INT 4 U.R CR
   S"    1F" TYPE CR   1F 5 U.R CR
   S" 12345" TYPE CR   12345 3 U.R CR
;
T{ RJOutput -> }T


\ ============ Group 2: ClaudeForth extensions ============

\ CF 2+

T{        0 2+ -> 2 }T
T{        1 2+ -> 3 }T
T{       -2 2+ -> 0 }T
T{       -3 2+ -> -1 }T
T{  MAX-INT 2+ -> MIN-INT 1+ }T
T{ MAX-UINT 2+ -> 1 }T


\ CF BINARY

: bn1 BASE @ BINARY BASE @ SWAP BASE ! ;
T{ bn1 BASE @ 10 = -> 2 <TRUE> }T
\ The digits after BINARY are read in base 2 and HEX restores base 16.
T{ BINARY 101 HEX -> 5 }T
T{ BINARY 1111 1111 HEX -> F F }T
T{ BASE @ -> 10 }T


\ CF SNAME

T{ ' DUP SNAME S" DUP" S= -> <TRUE> }T
T{ ' SWAP SNAME S" SWAP" S= -> <TRUE> }T
T{ ' SNAME SNAME S" SNAME" S= -> <TRUE> }T
: SN1 ;
T{ ' SN1 SNAME S" SN1" S= -> <TRUE> }T
CREATE SN2
T{ ' SN2 SNAME S" SN2" S= -> <TRUE> }T
\ An address that is not an execution token gives a zero length.
T{ 1 SNAME NIP -> 0 }T


\ CF VHERE
\ CF V,
\ CF VC,

\ VSTART remembers where the variable region stood, so that the
\ tests below can hand back everything they allocate.
CREATE VSTART VHERE ,
T{ VHERE VSTART @ = -> <TRUE> }T
T{ VHERE 1 V, VHERE SWAP - -> 2 }T
T{ VHERE 1234 V, @ -> 1234 }T
T{ VHERE 5A VC, VHERE OVER - SWAP C@ -> 1 5A }T

\ CF VALLOT

T{ VHERE 10 VALLOT VHERE SWAP - -> 10 }T
\ A negative count gives the space back.
T{ VHERE 8 VALLOT -8 VALLOT VHERE = -> <TRUE> }T
\ Hand back everything allocated above (2 + 2 + 1 + 16 bytes).
: vrestore VHERE VSTART @ - NEGATE VALLOT ;
vrestore
T{ VHERE VSTART @ = -> <TRUE> }T


\ CF UNUSED

\ UNUSED shrinks by the amount ALLOTted, VUNUSED by the amount VALLOTted.
T{ UNUSED 0<> -> <TRUE> }T
T{ UNUSED 10 ALLOT UNUSED - -10 ALLOT -> 10 }T

\ CF VUNUSED


T{ VUNUSED 0<> -> <TRUE> }T
T{ VUNUSED 8 VALLOT VUNUSED - -8 VALLOT -> 8 }T
T{ VHERE VSTART @ = -> <TRUE> }T


\ Print this file's TEST SUMMARY and trim any stray stack cells.
TEST-END
\ ---- section-marker: undo everything above ----
M30
