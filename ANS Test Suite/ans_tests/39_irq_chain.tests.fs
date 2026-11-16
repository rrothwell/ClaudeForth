\ ============================================================
\ ANS test suite - IRQ-CHAIN with a real interrupt source
\ BOARD TEST: needs the MC6840 PTM at $C000-$C007 (MECB layout).
\ Do not include it in a run on a machine without that PTM.
\ Requires ttester.fs then 00_test_prelude.fs to be loaded first.
\ Based on the interrupt-chaining technique of 24_hour_clock.fs.
\ Written for this project (forth6809_stage_6o and later).
\
\ Waits are bounded loop counts, never elapsed time, so the test
\ gives the same verdict on real hardware and in an emulator whose
\ PTM clock runs slow.  If the interrupt never arrives the wait
\ gives up and the test reports a failure instead of hanging.
\
\ Handlers follow the chain rules: test the PTM status for our own
\ flag, if it is not ours JMP [next]; if ours clear it (read the
\ status, then the timer counter), count it and RTI.
\ ============================================================
MARKER M39
TEST-BEGIN
HEX

\ ---- PTM register addresses
C000 CONSTANT PTM-CR13      \ CR1 or CR3, selected by CR2 bit 0
C001 CONSTANT PTM-CR2       \ CR2 (write) / status (read)
C004 CONSTANT PTM-T2        \ timer 2 data
C006 CONSTANT PTM-T3        \ timer 3 data

\ ---- put the PTM in a known quiet state: all timers held in
\ ---- reset, all interrupt enables off
: PTM-STOP ( -- )
   00 PTM-CR2 C!  02 PTM-CR13 C!      \ CR3: no interrupt
   01 PTM-CR2 C!  01 PTM-CR13 C! ;    \ CR2 no interrupt, CR1 = reset

: LATCH! ( n addr -- ) >R DUP 8 RSHIFT R@ C! FF AND R> 1+ C! ;

\ ---- start timer 3 (interrupt, internal clock, /8) and optionally
\ ---- timer 2 (interrupt, internal clock); both run in continuous mode
: PTM-GO ( latch3 latch2 use2? -- )
   >R  PTM-T2 LATCH!  PTM-T3 LATCH!
   00 PTM-CR2 C!  43 PTM-CR13 C!               \ CR3
   R> IF 43 ELSE 01 THEN PTM-CR2 C!            \ CR2, selects CR1
   00 PTM-CR13 C! ;                            \ CR1: release reset

\ ---- build a chain handler: ( mask counter-reg count-var next-var -- xt )
VARIABLE I-CNT  VARIABLE I-NXT
: ADDR, ( u -- ) DUP 8 RSHIFT C, FF AND C, ;
: MKISR ( mask ctr cnt next -- xt )
   I-NXT !  I-CNT !
   HERE >R
   B6 C, PTM-CR2 ADDR,                     \ LDA status
   SWAP 85 C, C,                           \ BITA #mask
   27 C, 0D C,                             \ BEQ not ours
   FC C, ( ctr) ADDR,                      \ LDD counter: clears flag
   FC C, I-CNT @ ADDR,                     \ LDD count
   C3 C, 00 C, 01 C,                       \ ADDD #1
   FD C, I-CNT @ ADDR,                     \ STD count
   3B C,                                   \ RTI
   6E C, 9F C, I-NXT @ ADDR,               \ JMP [next]
   R> ;

VARIABLE COUNT2  VARIABLE COUNT3
VARIABLE NEXT2   VARIABLE NEXT3
IRQ-CHAIN @ CONSTANT OLD-CHAIN

\ ---- wait (bounded) until a count reaches n; returns true if it did
: DELAY ( -- ) 2710 0 DO LOOP ;
: WAIT-FOR ( addr n -- flag )
   >R  0
   BEGIN  1+  DUP 186A0 =  2 PICK @ R@ U< INVERT  OR  UNTIL
   DROP  @ R> U< INVERT ;

\ ---- timer 3 alone
PTM-STOP
0 COUNT3 !
OLD-CHAIN NEXT3 !
04 PTM-T3 COUNT3 NEXT3 MKISR CONSTANT ISR3
ISR3 IRQ-CHAIN !
T{ IRQ-CHAIN @ ISR3 = -> TRUE }T
T{ COUNT3 @ -> 0 }T
7D0 0 FALSE PTM-GO
T{ COUNT3 5 WAIT-FOR -> TRUE }T

\ ---- stopping the source stops the count
PTM-STOP
COUNT3 @ CONSTANT FROZEN
T{ FROZEN 5 U< INVERT -> TRUE }T
T{ DELAY COUNT3 @ FROZEN = -> TRUE }T

\ ---- two handlers, chained: timer 2 first, then timer 3, then the old chain
\ The timers are started and checked inside ONE definition, so the CPU
\ never sits idle at the prompt while they tick.  (On the board that
\ makes no difference, but MAME's PTM does not deliver interrupts
\ reliably across an idle prompt, so the test avoids depending on it.)
0 COUNT2 !  0 COUNT3 !
IRQ-CHAIN @ NEXT2 !
02 PTM-T2 COUNT2 NEXT2 MKISR CONSTANT ISR2
ISR2 IRQ-CHAIN !
T{ NEXT2 @ ISR3 = -> TRUE }T
: BOTH ( -- f3 f2 )
   7D0 7D0 TRUE PTM-GO
   COUNT3 4 WAIT-FOR  COUNT2 4 WAIT-FOR
   PTM-STOP ;
T{ BOTH -> TRUE TRUE }T

\ ---- both sources keep running while the terminal is in use
: WITH-TEXT ( -- f )
   0 COUNT2 !  0 COUNT3 !
   7D0 7D0 TRUE PTM-GO
   CR ." chain test: 0123456789 ABCDEFGHIJ klmnopqrst UVWXYZ"
   COUNT3 4 WAIT-FOR  COUNT2 4 WAIT-FOR AND
   PTM-STOP ;
T{ WITH-TEXT -> TRUE }T
T{ COUNT3 @ 0 U> COUNT2 @ 0 U> -> TRUE TRUE }T

\ ---- tear down: source off first, then restore the chain
PTM-STOP
OLD-CHAIN IRQ-CHAIN !
T{ IRQ-CHAIN @ OLD-CHAIN = -> TRUE }T
T{ IRQ-CHAIN @ C@ -> 3B }T
COUNT2 @ COUNT3 @ 2CONSTANT FINAL
T{ DELAY COUNT2 @ COUNT3 @ FINAL D= -> TRUE }T

DECIMAL
TEST-END
M39
