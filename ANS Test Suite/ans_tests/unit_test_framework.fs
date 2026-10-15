0 CONSTANT 0S
0 INVERT CONSTANT 1S

0S CONSTANT <FALSE>
1S CONSTANT <TRUE>

VARIABLE TESTCOUNT
VARIABLE FAILCOUNT
0 TESTCOUNT !
0 FAILCOUNT !

VARIABLE START-DEPTH
VARIABLE XCURSOR
VARIABLE ERROR-XT

VARIABLE ACTUAL-DEPTH \ stack record
CREATE ACTUAL-RESULTS 20 CELLS ALLOT
VARIABLE START-DEPTH

\ For vectoring of error reporting
: ERROR ERROR-XT @ EXECUTE ; 


\ Empty stack; handles underflowed stack too.
: EMPTY-STACK \ ( ... -- ) 
    DEPTH START-DEPTH @ < 
    IF
        DEPTH START-DEPTH @ SWAP 
        DO 
            0 
        LOOP
    THEN
    DEPTH START-DEPTH @ > 
    IF
        DEPTH START-DEPTH @ 
        DO 
            DROP 
        LOOP
    THEN
;

: ERROR1 \ ( C-ADDR U -- ) display an error message
\ followed by the line that had the error.
TYPE SOURCE TYPE CR \ display line corresponding to error
EMPTY-STACK \ throw away everything else
;

' ERROR1 ERROR-XT !


\ Record the pre-test depth.
: T{ \ ( -- ) 
    DEPTH START-DEPTH ! 0 XCURSOR ! ;


\ Record depth and contents of stack.
: -> \ ( ... -- ) 
    DEPTH DUP ACTUAL-DEPTH ! \ record depth
    START-DEPTH @ > 
    IF \ if there is something on the stack
        DEPTH START-DEPTH @ - 0 
        DO \ save them
            ACTUAL-RESULTS I CELLS + !
        LOOP
    THEN
;


\ Compare stack (expected) contents with saved
\ (actual) contents.
: }T \ ( ... -- ) 
    1 TESTCOUNT +!
    DEPTH ACTUAL-DEPTH @ = 
    IF \ if depths match
        DEPTH START-DEPTH @ > 
        IF \ if something on the stack
            2 SPACES ." Actual:Expected "
            DEPTH START-DEPTH @ - 0 
            DO \ for each stack item
                ACTUAL-RESULTS I CELLS + @ \ compare actual with expected
                2DUP . ." =?= " .
                <> 
                IF 
                    1 FAILCOUNT +! 
                    S" INCORRECT RESULT: " ERROR 
                    LEAVE 
                THEN
            LOOP
        THEN
    ELSE \ depth mismatch
        1 FAILCOUNT +!
        S" WRONG NUMBER OF RESULTS: " ERROR
    THEN
;
