\ ============================================================
\ ANS test suite - String word set (STRINGSET=1 builds only):
\ -TRAILING /STRING BLANK CMOVE CMOVE> COMPARE SEARCH SLITERAL.
\ The String extension words (REPLACES SUBSTITUTE UNESCAPE) are
\ in 36_string_extension.tests.fs.
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order. Extracted from the ANS Forth Standard,
\ Annex F (https://forth-standard.org/standard/testsuite).
\ ============================================================
MARKER M27
TEST-BEGIN
DECIMAL

\ String constant setup.
: s1 S" abcdefghijklmnopqrstuvwxyz" ;
T{ : s2  S" abc"   ; -> }T
T{ : s3  S" jklmn" ; -> }T
T{ : s4  S" z"     ; -> }T
T{ : s5  S" mnoq"  ; -> }T
T{ : s6  S" 12345" ; -> }T
T{ : s7  S" "      ; -> }T
T{ : s8  S" abc  " ; -> }T
T{ : s9  S"      " ; -> }T
T{ : s10 S"    a " ; -> }T
: s11 S" 0abc" ;
: s12 S" 0aBc" ;
: s13 S" aaaaa      a" ;                 \ Six spaces

\ F.17.6.1.0780 BLANK
T{ PAD 25 CHAR a FILL -> }T
T{ PAD 5 CHARS + 6 BLANK -> }T
T{ PAD 12 s13 COMPARE -> 0 }T

\ F.17.6.1.0910 CMOVE
T{ S" ABCD" PAD SWAP CMOVE -> }T
T{ PAD DUP CHAR+ 3 CMOVE -> }T
T{ PAD 4 S" AAAA" COMPARE -> 0 }T

\ F.17.6.1.0920 CMOVE>
T{ S" ABCD" PAD SWAP CMOVE -> }T
T{ PAD DUP CHAR+ 3 CMOVE> -> }T
T{ PAD 4 S" AAAB" COMPARE -> 0 }T

\ 17.6.1.0935 COMPARE
T{ s1        s1 COMPARE ->  0  }T
T{ s1  PAD SWAP CMOVE   ->     }T
T{ s1  PAD OVER COMPARE ->  0  }T
T{ s1     PAD 6 COMPARE ->  1  }T
T{ PAD 10    s1 COMPARE -> -1  }T
T{ s1     PAD 0 COMPARE ->  1  }T
T{ PAD  0    s1 COMPARE -> -1  }T
T{ s1        s6 COMPARE ->  1  }T
T{ s6        s1 COMPARE -> -1  }T

: "abdde" S" abdde" ;
: "abbde" S" abbde" ;
: "abcdf" S" abcdf" ;
: "abcdee" S" abcdee" ;

T{ s1 "abdde"  COMPARE -> -1 }T
T{ s1 "abbde"  COMPARE ->  1 }T
T{ s1 "abcdf"  COMPARE -> -1 }T
T{ s1 "abcdee" COMPARE ->  1 }T

T{ s11 s12 COMPARE ->  1 }T
T{ s12 s11 COMPARE -> -1 }T

\ F.17.6.1.0245 /STRING
T{ s1  5 /STRING -> s1 SWAP 5 + SWAP 5 - }T
T{ s1 10 /STRING -4 /STRING -> s1 6 /STRING }T
T{ s1  0 /STRING -> s1 }T

\ F.17.6.1.0170 -TRAILING
T{  s1 -TRAILING -> s1 }T
T{  s8 -TRAILING -> s8 2 - }T
T{  s7 -TRAILING -> s7 }T
T{  s9 -TRAILING -> s9 DROP 0 }T
T{ s10 -TRAILING -> s10 1- }T

\ F.17.6.1.2191 SEARCH
T{ s1 s2 SEARCH -> s1 <TRUE>  }T
T{ s1 s3 SEARCH -> s1  9 /STRING <TRUE>  }T
T{ s1 s4 SEARCH -> s1 25 /STRING <TRUE>  }T
T{ s1 s5 SEARCH -> s1 <FALSE> }T
T{ s1 s6 SEARCH -> s1 <FALSE> }T
T{ s1 s7 SEARCH -> s1 <TRUE>  }T

\ F.17.6.1.2212 SLITERAL
T{ : s14 [ s1 ] SLITERAL ; -> }T
T{ s1 s14 COMPARE -> 0 }T
T{ s1 s14 ROT = ROT ROT = -> <TRUE> <FALSE> }T

\ Restore default base.
HEX

TEST-END
M27
