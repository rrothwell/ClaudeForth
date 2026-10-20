\ ============================================================
\ ANS test suite - CORE-EXT words added in stage 6b:
\ .(  C"  SAVE-INPUT  RESTORE-INPUT  and ENVIRONMENT? CORE-EXT
\ Requires ttester.fs then 00_test_prelude.fs first.
\ ============================================================
MARKER M29
TEST-BEGIN

HEX

\ F.6.1.1345  ENVIRONMENT? CORE-EXT

: ENV-COREEXT S" CORE-EXT" ENVIRONMENT? ;
\ Returns the value flag, then the "recognised" flag, 
T{ ENV-COREEXT -> <TRUE> <TRUE> }T


\ F.6.2.0200 .(  

\ Display is visual: a line saying "visible-1" must appear. 
T{ .( visible-1) -> }T  \ --> 
\ Display is visual: a line saying "visible-2" 
\ must appear at compile time, not when run. 
T{ : dp1 .( visible-2) ; -> }T   \ --> 
T{ dp1 -> }T  \ --> ____ 


\ F.6.2.0855  C"

T{ : cq1 C" 123" ; -> }T
T{ cq1 COUNT SWAP C@ -> 3 CHAR 1 }T
T{ : cq2 C" " ; cq2 C@ -> 0 }T
T{ : cq3 C" GLORP" ; cq3 COUNT NIP -> 5 }T


\ F.6.2.2182 SAVE-INPUT 
\ F.6.2.2148 RESTORE-INPUT 

\ For SAVE-INPUT 3 cells are returned with a count of 3.
\ >R and R> are used inside a definition: 
\ because their interpretation semantics are undefined.
\ At top level they put the value
\ under the interpreter's own return address - bad!.
: SI-SHAPE SAVE-INPUT 3 = >R 2DROP DROP R> ;
T{ SI-SHAPE -> <TRUE> }T

\ For RESTORE-INPUT a count other than 3 cannot be restored:
\ the cells are dropped
\ and true (failure) is returned.
T{ 5 6 2 RESTORE-INPUT -> <TRUE> }T
T{ 0 RESTORE-INPUT -> <TRUE> }T
\ A state saved from a different source is refused, 
\ since the EVALUATEd string has another address and length.
: ri1 S" SAVE-INPUT" EVALUATE ;
T{ ri1 RESTORE-INPUT -> <TRUE> }T


\ F.6.2.2266 S\" 

\ Build a string from a quoted string 
\ containing the escape characters:
\      \a 7  \b 8  \e 1B  \f C  \l A  \m 0D 0A  \n A  \q 22
\     \r D  \t 9  \v B  \z 0  \" 22  \\ 5C  \xhh

: SQ1 S\" abc" ;
T{ SQ1 NIP -> 3 }T
T{ SQ1 DROP C@ -> 61 }T
: SQ2 S\" a\qb\\c" ;
T{ SQ2 NIP -> 5 }T
T{ SQ2 DROP 1+ C@ -> 22 }T
T{ SQ2 DROP 3 + C@ -> 5C }T
: SQ3 S\" \a\b\e\f\l\n\r\t\v\z" ;
T{ SQ3 NIP -> A }T
T{ SQ3 DROP C@ -> 7 }T
T{ SQ3 DROP 2 + C@ -> 1B }T
T{ SQ3 DROP 8 + C@ -> B }T
T{ SQ3 DROP 9 + C@ -> 0 }T
: SQ4 S\" \m" ;
T{ SQ4 NIP -> 2 }T
T{ SQ4 DROP C@ -> D }T
T{ SQ4 DROP 1+ C@ -> A }T
\ \" does not end the string
: SQ5 S\" x\"y" ;
T{ SQ5 NIP -> 3 }T
T{ SQ5 DROP 1+ C@ -> 22 }T
\ Hex escapes: upper or lower case, two digits
: SQ6 S\" \x41\x7a!" ;
T{ SQ6 NIP -> 3 }T
T{ SQ6 DROP C@ -> 41 }T
T{ SQ6 DROP 1+ C@ -> 7A }T
T{ SQ6 DROP 2 + C@ -> 21 }T
\ Interpreted S\" gives the same result
T{ S\" a\tb" NIP -> 3 }T
T{ S\" a\tb" DROP 1+ C@ -> 9 }T
\ The text after the closing quote is still interpreted
T{ S\" \q" NIP 5 -> 1 5 }T


\ F.0000 CONVERT
\ Obsolescent, removed from ANS Forth 2012.
\ Use >NUMBER instead.

CREATE CVB 20 C, 31 C, 32 C, 33 C, 0 C,
\ The test base is HEX, so "123" converts to 123 hex.
T{ 0 0 CVB CONVERT CVB 4 + = -> 123 0 <TRUE> }T
T{ 5 0 CVB CONVERT DROP -> 5123 0 }T


TEST-END
M29
