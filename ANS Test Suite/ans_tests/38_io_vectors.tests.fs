\ ============================================================
\ ANS test suite - redirectable EMIT/KEY/KEY? and IRQ-CHAIN
\ (EMIT) (KEY) (KEY?) IRQ-CHAIN are ClaudeForth extensions.
\ Each of the first three returns the address of a cell that holds
\ the execution token used by EMIT, KEY and KEY? respectively.
\ Requires ttester.fs then 00_test_prelude.fs to be loaded first.
\ Written for this project (forth6809_stage_6o and later).
\ ============================================================
MARKER M38
TEST-BEGIN
DECIMAL

\ ---- the cells are distinct, in page zero, and hold nonzero xts
T{ (EMIT) 256 U< (KEY) 256 U< (KEY?) 256 U< IRQ-CHAIN 256 U< -> TRUE TRUE TRUE TRUE }T
T{ (EMIT) (KEY) = (EMIT) (KEY?) = (KEY) (KEY?) = -> FALSE FALSE FALSE }T
T{ (EMIT) IRQ-CHAIN = -> FALSE }T
T{ (EMIT) @ 0<> (KEY) @ 0<> (KEY?) @ 0<> -> TRUE TRUE TRUE }T

\ ---- IRQ-CHAIN starts out pointing at an RTI instruction ($3B)
T{ IRQ-CHAIN @ C@ -> 59 }T

\ ---- redirect EMIT into a buffer
(EMIT) @ CONSTANT SAVEEMIT
(KEY) @ CONSTANT SAVEKEY
(KEY?) @ CONSTANT SAVEKEYQ
CREATE OBUF 64 ALLOT
VARIABLE ON
: BUFEMIT ( c -- ) OBUF ON @ + C! 1 ON +! ;
: >BUF ( -- ) 0 ON ! ['] BUFEMIT (EMIT) ! ;
: >TERM ( -- ) SAVEEMIT (EMIT) ! ;

T{ >BUF 65 EMIT 66 EMIT >TERM ON @ OBUF C@ OBUF 1+ C@ -> 2 65 66 }T
T{ >BUF S" Hi" TYPE >TERM ON @ OBUF C@ OBUF 1+ C@ -> 2 72 105 }T
T{ >BUF 123 . >TERM ON @ -> 4 }T
T{ >BUF 123 . >TERM OBUF C@ OBUF 3 + C@ -> 49 32 }T
T{ >BUF SPACE CR >TERM ON @ OBUF C@ -> 3 32 }T
T{ (EMIT) @ SAVEEMIT = -> TRUE }T

\ ---- redirect KEY and KEY?
: FAKEKEY ( -- c ) 88 ;
: FAKEKEYQ ( -- f ) TRUE ;
: KEY>FAKE ['] FAKEKEY (KEY) ! ;
: KEYQ>FAKE ['] FAKEKEYQ (KEY?) ! ;
T{ KEY>FAKE KEY KEY SAVEKEY (KEY) ! -> 88 88 }T
T{ KEYQ>FAKE KEY? SAVEKEYQ (KEY?) ! -> TRUE }T
T{ (KEY) @ SAVEKEY = (KEY?) @ SAVEKEYQ = -> TRUE TRUE }T

\ ---- a word compiled earlier still sees a later redirection
: EMIT3 ( -- ) 51 EMIT ;
T{ >BUF EMIT3 >TERM ON @ OBUF C@ -> 1 51 }T

\ ---- the interpreter's input line and ACCEPT use KEY: feed it text
\ ---- from a string and check that the echo goes through EMIT
CREATE IBUF 8 ALLOT
VARIABLE IP
: SRCKEY ( -- c ) IBUF IP @ + C@ 1 IP +! ;
: PUT-IN ( -- ) 0 IP ! 120 IBUF C! 121 IBUF 1+ C! 13 IBUF 2 + C! ;
CREATE LBUF 8 ALLOT
: >SRC ( -- ) ['] SRCKEY (KEY) ! ;
: GETLINE ( -- n ) PUT-IN >SRC >BUF LBUF 5 ACCEPT >TERM SAVEKEY (KEY) ! ;
T{ GETLINE -> 2 }T
T{ LBUF C@ LBUF 1+ C@ -> 120 121 }T
T{ OBUF C@ OBUF 1+ C@ -> 120 121 }T

HEX
TEST-END
M38
