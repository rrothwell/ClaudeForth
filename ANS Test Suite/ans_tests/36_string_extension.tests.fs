\ ============================================================
\ ANS test suite - String extension words (STRINGEXT=1 builds
\ only): REPLACES SUBSTITUTE UNESCAPE (and CLR-REPLACES).
\ Independent of the String word set: it uses SCMP, a comparison
\ defined here, instead of COMPARE, so it also runs when
\ STRINGSET=0.
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order. Extracted from the ANS Forth Standard,
\ Annex F (https://forth-standard.org/standard/testsuite).
\ ============================================================
MARKER M36
TEST-BEGIN
DECIMAL

\ SCMP ( c-addr1 u1 c-addr2 u2 -- 0 | 1 )  0 if the strings are equal.
: SCMP
  ROT OVER <> IF 2DROP DROP 1 EXIT THEN
  0 ?DO
    2DUP I + C@ SWAP I + C@ <> IF 2DROP UNLOOP 1 EXIT THEN
  LOOP 2DROP 0 ;

: e1 S" abc" ;
: e2 S" abd" ;
: e3 S" ab" ;
T{ e1 e1 SCMP -> 0 }T
T{ e1 e2 SCMP -> 1 }T
T{ e1 e3 SCMP -> 1 }T

\ F.17.6.2.2141 REPLACES
\ See F.17.6.2.2255 SUBSTITUTE

\ F.17.6.2.2255 SUBSTITUTE
30 CHARS BUFFER: subbuff                \ Destination buffer
: "hi" S" hi" ;
: "wld" S" wld" ;
: "hello" S" hello" ;
: "world" S" world" ;

: sub1 S" Start: %hi%,%wld%! :End" ;    \ Original string
: sub2 S" Start: hello,world! :End" ;   \ First target string
: sub3 S" Start: world,hello! :End" ;   \ Second target string

T{ "hello" "hi"  REPLACES -> }T
T{ "world" "wld" REPLACES -> }T

T{ sub1 subbuff 30 SUBSTITUTE ROT ROT sub2 SCMP -> 2 0 }T

T{ "world" "hi"  REPLACES -> }T
T{ "hello" "wld" REPLACES -> }T

T{ sub1 subbuff 30 SUBSTITUTE ROT ROT sub3 SCMP -> 2 0 }T

\ Where the substitution name is not defined
: sub4 S" aaa%bbb%ccc" ;
T{ sub4 subbuff 30 SUBSTITUTE ROT ROT sub4 SCMP -> 0 0 }T

\ Finally the % character itself
: sub5 S" aaa%%bbb" ;
: sub6 S" aaa%bbb" ;
T{ sub5 subbuff 30 SUBSTITUTE ROT ROT sub6 SCMP -> 0 0 }T

\ F.17.6.2.2375 UNESCAPE
T{ sub6 subbuff UNESCAPE sub5 SCMP -> 0 }T

\ CLR-REPLACES empties the table: the names are no longer replaced.
T{ CLR-REPLACES -> }T
T{ sub1 subbuff 30 SUBSTITUTE ROT ROT sub1 SCMP -> 0 0 }T

\ Restore default base.
HEX

TEST-END
M36
