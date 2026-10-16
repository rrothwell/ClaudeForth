\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 08 (08_defining_words)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M28 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M28 at the end (below)
\ erases everything this file defined - including M28 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M28
\ Reset the pass/fail counters, record the stack depth.
TEST-BEGIN

\ Default base is HEX.
DECIMAL

\ ---- 8.6.1 Double-Number words ----


\ Double number constant setup.
\ TODO Define these in the dictionary.
\ or maybe not.

HEX

7FFF CONSTANT MAX-INT
8000 CONSTANT MIN-INT
MAX-INT 2/ CONSTANT HI-INT
MIN-INT 2/ CONSTANT LO-INT

FFFF 7FFF 2CONSTANT MAX-2INT
0000 8000 2CONSTANT MIN-2INT
MAX-2INT 2CONSTANT max-2INT
MIN-2INT 2CONSTANT min-2INT
MAX-2INT 2CONSTANT max-2int
MIN-2INT 2CONSTANT min-2int

\ MAX-2INT D2/ 2CONSTANT HI-2INT
\ MIN-2INT D2/ 2CONSTANT LO-2INT
FFFF 3FFF 2CONSTANT HI-2INT
0000 C000 2CONSTANT LO-2INT
HI-2INT 2CONSTANT hi-2INT
LO-2INT 2CONSTANT lo-2INT

\ Depends on M*/ which is not implemented.
\ MAX-2INT 71 73 M*/ 2CONSTANT dbl1
\ MIN-2INT 73 79 M*/ 2CONSTANT dbl2

DECIMAL

\ F.8.6.1.0360 2CONSTANT

T{ 1 2 2CONSTANT 2c1 -> }T
T{ 2c1 -> 1 2 }T
T{ : cd1 2c1 ; -> }T
T{ cd1 -> 1 2 }T

T{ : cd2 2CONSTANT ; -> }T
T{ -1 -2 cd2 2c2 -> }T
T{ 2c2 -> -1 -2 }T

T{ 4 5 2CONSTANT 2c3 IMMEDIATE 2c3 -> 4 5 }T
T{ : cd6 2c3 2LITERAL ; cd6 -> 4 5 }T

\ F.8.6.1.0390 2LITERAL (Not implemented)

\ T{ : cd1 [ MAX-2INT ] 2LITERAL ; -> }T
\ T{ cd1 -> MAX-2INT }T
\ T{ 2VARIABLE 2v4 IMMEDIATE 5 6 2v4 2! -> }T
\ T{ : cd7 2v4 [ 2@ ] 2LITERAL ; cd7 -> 5 6 }T
\ T{ : cd8 [ 6 7 ] 2v4 [ 2! ] ; 2v4 2@ -> 6 7 }T

\ F.8.6.1.0440 2VARIABLE

T{ 2VARIABLE 2v1 -> }T
T{ 0. 2v1 2! ->    }T
T{    2v1 2@ -> 0. }T
T{ -1 -2 2v1 2! ->       }T
T{       2v1 2@ -> -1 -2 }T
T{ : cd2 2VARIABLE ; -> }T
T{ cd2 2v2 -> }T
T{ : cd3 2v2 2! ; -> }T
T{ -2 -1 cd3 -> }T
T{ 2v2 2@ -> -2 -1 }T

T{ 2VARIABLE 2v3 IMMEDIATE 5 6 2v3 2! -> }T
T{ 2v3 2@ -> 5 6 }T

\ F.8.6.1.1040 D+

T{  0.  5. D+ ->  5. }T                         \ small integers
T{ -5.  0. D+ -> -5. }T
T{  1.  2. D+ ->  3. }T
T{  1. -2. D+ -> -1. }T
T{ -1.  2. D+ ->  1. }T
T{ -1. -2. D+ -> -3. }T
T{ -1.  1. D+ ->  0. }T
T{  0  0  0  5 D+ ->  0  5 }T                  \ mid range integers
T{ -1  5  0  0 D+ -> -1  5 }T
T{  0  0  0 -5 D+ ->  0 -5 }T
T{  0 -5 -1  0 D+ -> -1 -5 }T
T{  0  1  0  2 D+ ->  0  3 }T
T{ -1  1  0 -2 D+ -> -1 -1 }T
T{  0 -1  0  2 D+ ->  0  1 }T
T{  0 -1 -1 -2 D+ -> -1 -3 }T
T{ -1 -1  0  1 D+ -> -1  0 }T

T{ MIN-INT 0 2DUP D+ -> 0 1 }T
T{ MIN-INT S>D MIN-INT 0 D+ -> 0 0 }T

T{  HI-2INT       1. D+ -> 0 HI-INT 1+ }T    \ large double integers
T{  HI-2INT     2DUP D+ -> 1S 1- MAX-INT }T
T{ MAX-2INT MIN-2INT D+ -> -1. }T
T{ MAX-2INT  LO-2INT D+ -> HI-2INT }T
T{  LO-2INT     2DUP D+ -> MIN-2INT }T
T{  HI-2INT MIN-2INT D+ 1. D+ -> LO-2INT }T


\ F.8.6.1.1050 D-

T{  0.  5. D- -> -5. }T              \ small integers
T{  5.  0. D- ->  5. }T
T{  0. -5. D- ->  5. }T
T{  1.  2. D- -> -1. }T
T{  1. -2. D- ->  3. }T
T{ -1.  2. D- -> -3. }T
T{ -1. -2. D- ->  1. }T
T{ -1. -1. D- ->  0. }T
T{  0  0  0  5 D- ->  0 -5 }T       \ mid-range integers
T{ -1  5  0  0 D- -> -1  5 }T
T{  0  0 -1 -5 D- ->  1  4 }T
T{  0 -5  0  0 D- ->  0 -5 }T
T{ -1  1  0  2 D- -> -1 -1 }T
T{  0  1 -1 -2 D- ->  1  2 }T
T{  0 -1  0  2 D- ->  0 -3 }T
T{  0 -1  0 -2 D- ->  0  1 }T
T{  0  0  0  1 D- ->  0 -1 }T
T{ MIN-INT 0 2DUP D- -> 0. }T
T{ MIN-INT S>D MAX-INT 0D- -> 1 1s }T
T{ MAX-2INT max-2INT D- -> 0. }T    \ large integers
T{ MIN-2INT min-2INT D- -> 0. }T
T{ MAX-2INT  hi-2INT D- -> lo-2INT DNEGATE }T
T{  HI-2INT  lo-2INT D- -> max-2INT }T
T{  LO-2INT  hi-2INT D- -> min-2INT 1. D+ }T
T{ MIN-2INT min-2INT D- -> 0. }T
T{ MIN-2INT  lo-2INT D- -> lo-2INT }T


\ F.8.6.1.1060 D. (Not tested) 

\ F.8.6.1.1070 D.R 
(has a dependency on M*/ which is not implemented)

MAX-2INT 71 73 M*/ 2CONSTANT dbl1
MIN-2INT 73 79 M*/ 2CONSTANT dbl2
: d>ascii ( d -- caddr u )
   DUP >R <# DABS #S R> SIGN #>    ( -- caddr1 u )
   HERE SWAP 2DUP 2>R CHARS DUP ALLOT MOVE 2R>
;

dbl1 d>ascii 2CONSTANT "dbl1"
dbl2 d>ascii 2CONSTANT "dbl2"

: DoubleOutput
   CR ." You should see lines duplicated:" CR
   5 SPACES "dbl1" TYPE CR
   5 SPACES dbl1 D. CR
   8 SPACES "dbl1" DUP >R TYPE CR
   5 SPACES dbl1 R> 3 + D.R CR
   5 SPACES "dbl2" TYPE CR
   5 SPACES dbl2 D. CR
   10 SPACES "dbl2" DUP >R TYPE CR
   5 SPACES dbl2 R> 5 + D.R CR
;

T{ DoubleOutput -> }T


\ F.8.6.1.1075 D0< (Not implemented)

\ T{                0. D0< -> <FALSE> }T
\ T{                1. D0< -> <FALSE> }T
\ T{  MIN-INT        0 D0< -> <FALSE> }T
\ T{        0  MAX-INT D0< -> <FALSE> }T
\ T{          MAX-2INT D0< -> <FALSE> }T
\ T{               -1. D0< -> <TRUE>  }T
\ T{          MIN-2INT D0< -> <TRUE>  }T


\ F.8.6.1.1080 D0= (Not implemented)

\ T{               1. D0= -> <FALSE> }T
\ T{ MIN-INT        0 D0= -> <FALSE> }T
\ T{         MAX-2INT D0= -> <FALSE> }T
\ T{      -1  MAX-INT D0= -> <FALSE> }T
\ T{               0. D0= -> <TRUE>  }T
\ T{              -1. D0= -> <FALSE> }T
\ T{       0  MIN-INT D0= -> <FALSE> }T


\ F.8.6.1.1090 D2* (Not implemented)

\ T{              0. D2* -> 0. D2* }T
\ T{ MIN-INT       0 D2* -> 0 1 }T
\ T{         HI-2INT D2* -> MAX-2INT 1. D- }T
\ T{         LO-2INT D2* -> MIN-2INT }T


\ F.8.6.1.1100 D2/ (Not implemented)

\ T{       0. D2/ -> 0.        }T
\ T{       1. D2/ -> 0.        }T
\ T{      0 1 D2/ -> MIN-INT 0 }T
\ T{ MAX-2INT D2/ -> HI-2INT   }T
\ T{      -1. D2/ -> -1.       }T
\ T{ MIN-2INT D2/ -> LO-2INT   }T

\ F.8.6.1.1110 D<

T{       0.       1. D< -> <TRUE>  }T
T{       0.       0. D< -> <FALSE> }T
T{       1.       0. D< -> <FALSE> }T
T{      -1.       1. D< -> <TRUE>  }T
T{      -1.       0. D< -> <TRUE>  }T
T{      -2.      -1. D< -> <TRUE>  }T
T{      -1.      -2. D< -> <FALSE> }T
T{      -1. MAX-2INT D< -> <TRUE>  }T
T{ MIN-2INT MAX-2INT D< -> <TRUE>  }T
T{ MAX-2INT      -1. D< -> <FALSE> }T
T{ MAX-2INT MIN-2INT D< -> <FALSE> }T
T{ MAX-2INT 2DUP -1. D+ D< -> <FALSE> }T
T{ MIN-2INT 2DUP  1. D+ D< -> <TRUE>  }T


\ F.8.6.1.1120 D=

T{      -1.      -1. D= -> <TRUE>  }T
T{      -1.       0. D= -> <FALSE> }T
T{      -1.       1. D= -> <FALSE> }T
T{       0.      -1. D= -> <FALSE> }T
T{       0.       0. D= -> <TRUE>  }T
T{       0.       1. D= -> <FALSE> }T
T{       1.      -1. D= -> <FALSE> }T
T{       1.       0. D= -> <FALSE> }T
T{       1.       1. D= -> <TRUE>  }T
T{   0   -1    0  -1 D= -> <TRUE>  }T
T{   0   -1    0   0 D= -> <FALSE> }T
T{   0   -1    0   1 D= -> <FALSE> }T
T{   0    0    0  -1 D= -> <FALSE> }T
T{   0    0    0   0 D= -> <TRUE>  }T
T{   0    0    0   1 D= -> <FALSE> }T
T{   0    1    0  -1 D= -> <FALSE> }T
T{   0    1    0   0 D= -> <FALSE> }T
T{   0    1    0   1 D= -> <TRUE>  }T

T{ MAX-2INT MIN-2INT D= -> <FALSE> }T
T{ MAX-2INT       0. D= -> <FALSE> }T
T{ MAX-2INT MAX-2INT D= -> <TRUE>  }T
T{ MAX-2INT HI-2INT  D= -> <FALSE> }T
T{ MAX-2INT MIN-2INT D= -> <FALSE> }T
T{ MIN-2INT MIN-2INT D= -> <TRUE>  }T
T{ MIN-2INT LO-2INT  D= -> <FALSE> }T
T{ MIN-2INT MAX-2INT D= -> <FALSE> }T

\ F.8.6.1.1140 D>S

T{    1234  0 D>S ->  1234   }T
T{   -1234 -1 D>S -> -1234   }T
T{ MAX-INT  0 D>S -> MAX-INT }T
T{ MIN-INT -1 D>S -> MIN-INT }T


\ F.8.6.1.1160 DABS

T{       1. DABS -> 1.       }T
T{      -1. DABS -> 1.       }T
T{ MAX-2INT DABS -> MAX-2INT }T
T{ MIN-2INT 1. D+ DABS -> MAX-2INT }T


\ F.8.6.1.1210 DMAX

T{       1.       2. DMAX ->  2.      }T
T{       1.       0. DMAX ->  1.      }T
T{       1.      -1. DMAX ->  1.      }T
T{       1.       1. DMAX ->  1.      }T
T{       0.       1. DMAX ->  1.      }T
T{       0.      -1. DMAX ->  0.      }T
T{      -1.       1. DMAX ->  1.      }T
T{      -1.      -2. DMAX -> -1.      }T
T{ MAX-2INT  HI-2INT DMAX -> MAX-2INT }T
T{ MAX-2INT MIN-2INT DMAX -> MAX-2INT }T
T{ MIN-2INT MAX-2INT DMAX -> MAX-2INT }T
T{ MIN-2INT  LO-2INT DMAX -> LO-2INT  }T

T{ MAX-2INT       1. DMAX -> MAX-2INT }T
T{ MAX-2INT      -1. DMAX -> MAX-2INT }T
T{ MIN-2INT       1. DMAX ->  1.      }T
T{ MIN-2INT      -1. DMAX -> -1.      }T

\ F.8.6.1.1220 DMIN

T{       1.       2. DMIN ->  1.      }T
T{       1.       0. DMIN ->  0.      }T
T{       1.      -1. DMIN -> -1.      }T
T{       1.       1. DMIN ->  1.      }T
T{       0.       1. DMIN ->  0.      }T
T{       0.      -1. DMIN -> -1.      }T
T{      -1.       1. DMIN -> -1.      }T
T{      -1.      -2. DMIN -> -2.      }T
T{ MAX-2INT  HI-2INT DMIN -> HI-2INT  }T
T{ MAX-2INT MIN-2INT DMIN -> MIN-2INT }T
T{ MIN-2INT MAX-2INT DMIN -> MIN-2INT }T
T{ MIN-2INT  LO-2INT DMIN -> MIN-2INT }T

T{ MAX-2INT       1. DMIN ->  1.      }T
T{ MAX-2INT      -1. DMIN -> -1.      }T
T{ MIN-2INT       1. DMIN -> MIN-2INT }T
T{ MIN-2INT      -1. DMIN -> MIN-2INT }T


\ F.8.6.1.1230 DNEGATE

T{   0. DNEGATE ->  0. }T
T{   1. DNEGATE -> -1. }T
T{  -1. DNEGATE ->  1. }T
T{ max-2int DNEGATE -> min-2int SWAP 1+ SWAP }T
T{ min-2int SWAP 1+ SWAP DNEGATE -> max-2int }T

\ F.8.6.1.1820 M*/ (Not implemented)

\ : ?floored [ -3 2 / -2 = ] LITERAL IF 1. D- THEN ;
\ 
\ T{       5.       7             11 M*/ ->  3. }T
\ T{       5.      -7             11 M*/ -> -3. ?floored }T
\ T{      -5.       7             11 M*/ -> -3. ?floored }T
\ T{      -5.      -7             11 M*/ ->  3. }T
\ T{ MAX-2INT       8             16 M*/ -> HI-2INT }T
\ T{ MAX-2INT      -8             16 M*/ -> HI-2INT DNEGATE ?floored }T
\ T{ MIN-2INT       8             16 M*/ -> LO-2INT }T
\ T{ MIN-2INT      -8             16 M*/ -> LO-2INT DNEGATE }T
\ 
\ T{ MAX-2INT MAX-INT        MAX-INT M*/ -> MAX-2INT }T
\ T{ MAX-2INT MAX-INT 2/     MAX-INT M*/ -> MAX-INT 1- HI-2INT NIP }T
\ T{ MIN-2INT LO-2INT NIP DUP NEGATE M*/ -> MIN-2INT }T
\ T{ MIN-2INT LO-2INT NIP 1- MAX-INT M*/ -> MIN-INT 3 + HI-2INT NIP 2 + }T
\ T{ MAX-2INT LO-2INT NIP DUP NEGATE M*/ -> MAX-2INT DNEGATE }T
\ T{ MIN-2INT MAX-INT            DUP M*/ -> MIN-2INT }T


\ F.8.6.1.1830 M+

T{ HI-2INT   1 M+ -> HI-2INT   1. D+ }T
T{ MAX-2INT -1 M+ -> MAX-2INT -1. D+ }T
T{ MIN-2INT  1 M+ -> MIN-2INT  1. D+ }T
T{ LO-2INT  -1 M+ -> LO-2INT  -1. D+ }T

\ ---- 8.6.2 Double-Number extension words ----

\ F.8.6.2.0420 2ROT 

T{       1.       2. 3. 2ROT ->       2. 3.       1. }T
T{ MAX-2INT MIN-2INT 1. 2ROT -> MIN-2INT 1. MAX-2INT }T


\ F.8.6.2.0435 2VALUE (Not implemented)

\ T{ 1 2 2VALUE t2val -> }T
\ T{ t2val -> 1 2 }T
\ T{ 3 4 TO t2val -> }T
\ T{ t2val -> 3 4 }T
\ : sett2val t2val 2SWAP TO t2val ;
\ T{ 5 6 sett2val t2val -> 3 4 5 6 }T

\ F.8.6.2.1270 DU<

T{       1.       1. DU< -> <FALSE> }T
T{       1.      -1. DU< -> <TRUE>  }T
T{      -1.       1. DU< -> <FALSE> }T
T{      -1.      -2. DU< -> <FALSE> }T
T{ MAX-2INT  HI-2INT DU< -> <FALSE> }T
T{  HI-2INT MAX-2INT DU< -> <TRUE>  }T
T{ MAX-2INT MIN-2INT DU< -> <TRUE>  }T
T{ MIN-2INT MAX-2INT DU< -> <FALSE> }T
T{ MIN-2INT  LO-2INT DU< -> <TRUE>  }T



\ Restore default base.
HEX

\ Print this file's TEST SUMMARY and trim any stray stack cells.
TEST-END
\ ---- section-marker: undo everything above ----
M28
