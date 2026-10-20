\ Defining some constants  
\ as I wish to run the tests without the prelude.

0 CONSTANT 0S
0 INVERT CONSTANT 1S

0S CONSTANT <FALSE>
1S CONSTANT <TRUE>

0 INVERT CONSTANT 1S
0 INVERT 1 RSHIFT CONSTANT MAX-INT
0 INVERT 1 RSHIFT INVERT CONSTANT MIN-INT

0 INVERT CONSTANT MAX-UINT
0 INVERT 1 RSHIFT CONSTANT MID-UINT
0 INVERT 1 RSHIFT INVERT CONSTANT MID-UINT+1

\ Why the test prelude sets this to 24 is unknown.
24 CONSTANT MAX-BASE   

\ Helper comparison words.  

\ Compare two strings.

: S= ( ADDR1 C1 ADDR2 C2 -- T/F ) 
    >R SWAP R@ = \ Do the strings have same length?
    IF 
        R> ?DUP  \ Are the strings non-empty?
        IF 
            0 DO
                OVER C@ OVER C@ - \ Are characters the same?
                IF  
                    2DROP <FALSE> UNLOOP EXIT 
                THEN
                SWAP CHAR+ SWAP CHAR+
            LOOP
        THEN
        2DROP <TRUE> \ Verified that strings match
    ELSE
        R> DROP 2DROP <FALSE> \ Lengths mismatch
    THEN 
;

\ Defining variables for end of test result summary  

VARIABLE TESTCOUNT
VARIABLE FAILCOUNT
0 TESTCOUNT !
0 FAILCOUNT !

VARIABLE START-DEPTH
VARIABLE XCURSOR
VARIABLE ERR-MSG-XT

VARIABLE ACTUAL-DEPTH \ stack record
CREATE ACTUAL-RESULTS 20 CELLS ALLOT
VARIABLE START-DEPTH

\ For vectoring of error reporting
: ERR-MSG ERR-MSG-XT @ EXECUTE ; 


\ Empty the stack; handles underflowed stack too.
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

\ Display an error message
\ on the line that had the error.
\ and clear the stack.
: ERR-MSG-1 \ ( C-ADDR U -- ) 
    TYPE EMPTY-STACK
;

' ERR-MSG-1 ERR-MSG-XT !


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
                    S" INCORRECT RESULT: " ERR-MSG 
                    LEAVE 
                THEN
            LOOP
        THEN
    ELSE \ depth mismatch
        1 FAILCOUNT +!
        S" WRONG NUMBER OF RESULTS: " ERR-MSG
    THEN
;


\ Test SUMMARY

VARIABLE TEST-DEPTH

: TEST-BEGIN ( -- )
    0 TESTCOUNT ! 0 FAILCOUNT !
    DEPTH TEST-DEPTH !
;
       
: TEST-END ( -- )
    BASE @ >R DECIMAL
    CR ." TEST SUMMARY: " TESTCOUNT @ . ." run, "
    FAILCOUNT @ . ." failed" CR
    DEPTH TEST-DEPTH @ > 
    IF
        ." STACK IMBALANCE: " DEPTH TEST-DEPTH @ - .
        ." extra cell(s) dropped" CR
        DEPTH TEST-DEPTH @ DO DROP LOOP
    THEN
    DEPTH TEST-DEPTH @ < 
    IF
        ." STACK IMBALANCE: " TEST-DEPTH @ DEPTH - .
        ." cell(s) missing" CR
    THEN
    R> BASE ! 
;
