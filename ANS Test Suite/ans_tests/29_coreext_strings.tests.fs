\ ============================================================
\ ANS test suite - CORE-EXT words added in stage 6b:
\ .(  C"  SAVE-INPUT  RESTORE-INPUT  and ENVIRONMENT? CORE-EXT
\ Requires ttester.fs then 00_test_prelude.fs first.
\ ============================================================
MARKER M29
TEST-BEGIN

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
T{ dp1 -> }T  \ XXX 


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

TEST-END
M29
