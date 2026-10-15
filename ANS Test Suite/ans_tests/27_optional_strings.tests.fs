\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 19 (19_string_words)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M27 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M27 at the end (below)
\ erases everything this file defined - including M27 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M27
\ Reset the pass/fail counters, record the stack depth.
TEST-BEGIN

\ Default base is HEX.
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


\ F.17.6.1.0780 BLANK

: s13 S" aaaaa      a" ;                \ Six spaces between the a's
T{ PAD 25 CHAR a FILL -> }T             \ Fill PAD with 25 'a's
T{ PAD 5 CHARS + 6 BLANK -> }T          \ Put 6 spaces from character 5
T{ PAD 12 s13 COMPARE -> 0 }T           \ PAD should now be same as s13
T{ PAD 5 CHARS + 0 BLANK -> }T          \ A zero count changes nothing
T{ PAD 12 s13 COMPARE -> 0 }T


\ F.17.6.1.0910 CMOVE

\ Assume a character string at address 100: "ABCD".
\ Then after
\ 100 DUP CHAR+ 3 CMOVE
\ the string at address 100 is "AAAA".

: s15 S" ABCD" ;
: s16 S" AAAA" ;
T{ s15 PAD SWAP CMOVE -> }T
T{ PAD DUP CHAR+ 3 CMOVE -> }T
T{ PAD 4 s16 COMPARE -> 0 }T
T{ PAD DUP CHAR+ 0 CMOVE -> }T          \ A zero count changes nothing
T{ PAD 4 s16 COMPARE -> 0 }T

\ Copying down by one is the direction CMOVE is meant for
: s17 S" ABCDE" ;
: s18 S" BCDEE" ;
T{ s17 PAD SWAP CMOVE -> }T
T{ PAD CHAR+ PAD 4 CMOVE -> }T
T{ PAD 5 s18 COMPARE -> 0 }T


\ F.17.6.1.0920 CMOVE>

\ Assume a character string at address 100: "ABCD".
\ Then after
\ 100 DUP CHAR+ SWAP 3 CMOVE>
\ the string at address 100 is "DDDD".

: s19 S" DDDD" ;
T{ s15 PAD SWAP CMOVE -> }T
T{ PAD DUP CHAR+ SWAP 3 CMOVE> -> }T
T{ PAD 4 s19 COMPARE -> 0 }T
T{ PAD DUP CHAR+ SWAP 0 CMOVE> -> }T    \ A zero count changes nothing
T{ PAD 4 s19 COMPARE -> 0 }T

\ Copying up by one is the direction CMOVE> is meant for
: s20 S" AABCD" ;
T{ s17 PAD SWAP CMOVE -> }T
T{ PAD PAD CHAR+ 4 CMOVE> -> }T
T{ PAD 5 s20 COMPARE -> 0 }T


\ 17.6.1.0935 COMPARE

T{ s1        s1 COMPARE ->  0  }T
T{ s1  PAD SWAP CMOVE   ->     }T    \ Copy s1 to PAD
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

T{  s1 -TRAILING -> s1 }T               \ "abcdefghijklmnopqrstuvwxyz"
T{  s8 -TRAILING -> s8 2 - }T           \ "abc "
T{  s7 -TRAILING -> s7 }T               \ " "
T{  s9 -TRAILING -> s9 DROP 0 }T        \ " "
T{ s10 -TRAILING -> s10 1- }T           \ " a "


\ F.17.6.2.2141 REPLACES
\ See F.17.6.2.2255 SUBSTITUTE


\ F.17.6.1.2191 SEARCH

T{ s1 s2 SEARCH -> s1 <TRUE>  }T
T{ s1 s3 SEARCH -> s1  9 /STRING <TRUE>  }T
T{ s1 s4 SEARCH -> s1 25 /STRING <TRUE>  }T
T{ s1 s5 SEARCH -> s1 <FALSE> }T
T{ s1 s6 SEARCH -> s1 <FALSE> }T
T{ s1 s7 SEARCH -> s1 <TRUE>  }T

\ u3 is the length remaining from the match, not the needle's length
T{ s1 s3 SEARCH ROT DROP -> 17 <TRUE> }T
T{ s1 s4 SEARCH ROT DROP ->  1 <TRUE> }T


\ F.17.6.1.2212 SLITERAL

T{ : s14 [ s1 ] SLITERAL ; -> }T
T{ s1 s14 COMPARE -> 0 }T
T{ s1 s14 ROT = ROT ROT = -> <TRUE> <FALSE> }T


\ F.17.6.2.2255 SUBSTITUTE

30 CHARS BUFFER: subbuff \ Destination buffer
\ Define a few string constants
: "hi" S" hi" ;
: "wld" S" wld" ;
: "hello" S" hello" ;
: "world" S" world" ;

\ Define a few test strings
: sub1 S" Start: %hi%,%wld%! :End" ;    \ Original string
: sub2 S" Start: hello,world! :End" ;   \ First target string
: sub3 S" Start: world,hello! :End" ;   \ Second target string

\ Define the hi and wld substitutions
T{ "hello" "hi"  REPLACES -> }T          \ Replace "%hi%" with "hello"
T{ "world" "wld" REPLACES -> }T          \ Replace "%wld%" with "world"

\ "%hi%,%wld%" changed to "hello,world"
T{ sub1 subbuff 30 SUBSTITUTE ROT ROT sub2 COMPARE -> 2 0 }T

\ Change the hi and wld substitutions
T{ "world" "hi"  REPLACES -> }T
T{ "hello" "wld" REPLACES -> }T

\ Now "%hi%,%wld%" should be changed to "world,hello"
T{ sub1 subbuff 30 SUBSTITUTE ROT ROT sub3 COMPARE -> 2 0 }T

\ Where the subsitution name is not defined
: sub4 S" aaa%bbb%ccc" ;
T{ sub4 subbuff 30 SUBSTITUTE ROT ROT sub4 COMPARE -> 0 0 }T

\ Finally the % character itself
: sub5 S" aaa%%bbb" ;
: sub6 S" aaa%bbb" ;
T{ sub5 subbuff 30 SUBSTITUTE ROT ROT sub6 COMPARE -> 0 0 }T

\ Output too small for the result: n is negative
T{ sub1 subbuff 5 SUBSTITUTE ROT DROP SWAP DROP 0< -> <TRUE> }T

\ Source and destination the same buffer: n is negative
T{ sub1 subbuff SWAP CMOVE -> }T
T{ subbuff 6 subbuff 30 SUBSTITUTE ROT DROP SWAP DROP 0< -> <TRUE> }T


\ CLR-REPLACES (not a standard word) forgets all the substitutions
T{ CLR-REPLACES -> }T
T{ sub1 subbuff 30 SUBSTITUTE ROT ROT sub1 COMPARE -> 0 0 }T


\ F.17.6.2.2375 UNESCAPE

\ Using subbuff, sub5 and sub6 from F.17.6.2.2255 SUBSTITUTE.
T{ sub6 subbuff UNESCAPE sub5 COMPARE -> 0 }T

\ Restore default base.
HEX

\ Print this file's TEST SUMMARY and trim any stray stack cells.
TEST-END
\ ---- section-marker: undo everything above ----
M27
