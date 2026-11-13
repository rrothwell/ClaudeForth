\ =========================================================
\ Measure execution time of a forth word.
\ Initially using a pure forth implementation.

\ Usage: 
\    INIT-PTM
\    ' MY-WORD BENCHMARK
\ Example: 234 5678 0987 ' */ BENCHMARK    
\ =========================================================
\ Verified:  
\ 1. the PTM GT2 is floating and sits at 0V.
\  Counting is not inhibited.
\ 2. The shadow locations at $F0 etc are unused & not in conflict.


: CODE ( "name" -- )
    -1 HEADER
;

: END-CODE ( -- )
    SMUDGE       
; IMMEDIATE

\ Incompatible with interrupt-driven serial comms.
HEX
CODE DI-SAVE ( -- )   \ Push CC onto return stack and mask IRQ + FIRQ
    ( PSHS A)    1F C,  A8 C,  
    ( TFR  CC,A) 34 C,  02 C,  
    ( ORCC #$50) 1A C,  50 C,   \ Set I (bit 4) and F (bit 6)
    ( RTS )      39 C,    
END-CODE

\ Incompatible with interrupt-driven serial comms.
HEX
CODE RESTORE-CC ( -- ) \ Restore original CC from return stack
    ( PULS A )     35 C,  02 C,
    ( TFR  A,CC )  1F C,  8A C,
    ( RTS )        39 C,
END-CODE

\ Memory map.
HEX
C000 CONSTANT PTM-BASE

\ Hardware registers
PTM-BASE 0 + CONSTANT PTM-CR13
PTM-BASE 1 + CONSTANT PTM-CR2
PTM-BASE 4 + CONSTANT PTM-T2-MSB
PTM-BASE 5 + CONSTANT PTM-T2-LSB

\ Page zero (Direct Page) shadow registers (adjust addresses if needed)

\ These registers are copies of the write-only PTM configuration registers. 
\ They are used to allow changes to individual config bits for
\ a timer, without affecting the other timers.
\ In other words they are shared by applications, just like the PTM itself.

00F0 CONSTANT SHAD-CR1
00F1 CONSTANT SHAD-CR2
00F2 CONSTANT SHAD-CR3

: SELECT-CR1
    SHAD-CR2 C@ 01 OR DUP     \ Set CR2 bit 0 = 1 in shadow
    SHAD-CR2 C! PTM-CR2 C!    \ Send to PTM - selects CR1.
;

: SELECT-CR3
    SHAD-CR2 C@ FE AND DUP    \ Clear CR2 bit 0 = 0 in shadow.
    SHAD-CR2 C! PTM-CR2 C!    \ Send to PTM - selects CR3.
;

\ Write shadow values to hardware without disturbing other timers

: FLUSH-CR1 ( -- )
    SELECT-CR1
    SHAD-CR1 C@  PTM-CR13 C!  \ Copy CR1 shadow to CR13.
;

: FLUSH-CR2 ( -- )
    SHAD-CR2 C@  PTM-CR2 C!   \ Copy CR2 shadow to CR12.
;

: FLUSH-CR3 ( -- )
    SELECT-CR3
    SHAD-CR3 C@  PTM-CR13 C! \ Copy CR3 shadow to CR13.
;

\ Initialize Timer 2 only (preserves CR1 and CR3 shadow states)
    \ Bit 7=0 (IRQ masked), 
    \ Bit 6=0 (O2 disabled), 
    \ Bits 5-3=000 (continuous),
    \ Bit 2=0 (16-bit mode), 
    \ Bit 1=1 (internal E clock), 
    \ Bit 0=1 (keep CR1 selected)
    \ = $03
3 CONSTANT 16-CONTINUOUS-E-CLK

: RESET-CR1
    \ Assert internal reset of timer 2
    \ via CR1 bit 0 without altering other CR1 bits
    SHAD-CR1 C@ 01 OR SHAD-CR1 C!
    FLUSH-CR1
;

: UNRESET-CR1
    \ Release internal reset via CR1 bit 0 = 0 (starts all enabled timers)
    SHAD-CR1 C@ FE AND SHAD-CR1 C!
    FLUSH-CR1 ;
;

: LOAD-COUNTER-T2
    \ Load Timer 2 16-bit counter with $FFFF (MSB first, then LSB)
    FF PTM-T2-MSB C!
    FF PTM-T2-LSB C!
;

: CONFIGURE-T2
    \ Configure Timer 2 in CR2:
    16-CONTINUOUS-E-CLK SHAD-CR2 C!
    FLUSH-CR2
;

: INIT-T2 ( -- )
    RESET-CR1
    LOAD-COUNTER-T2
    CONFIGURE-T2
    UNRESET-CR1
;

\ Coherently read Timer 2 (reading MSB latches LSB into PTM buffer)
: T2@ ( -- u )
    PTM-T2-MSB C@ 8 LSHIFT
    PTM-T2-LSB C@ OR 
;

\ Measure execution time of xt in 2 MHz E-clock ticks with interrupts disabled
: MEASURE-T2 ( i*x xt -- j*x ticks )
    \ DI-SAVE             \ Mask IRQ and FIRQ, saving CC
    T2@ >R                \ Read start count onto return stack
    EXECUTE               \ Run target word
    T2@                   \ Read end count
    \ RESTORE-CC          \ Restore previous interrupt state
    R> SWAP -             \ Elapsed = Start - End (16-bit down-counter)
    FFFF AND             \ Mask to 16-bit unsigned for single rollover
;

\ Calibration word to subtract EXECUTE and timer read overhead
: NOOP ( -- ) ;
: T2-OVERHEAD ( -- ticks )
    ['] NOOP MEASURE-T2 ;

\ Run word and display net ticks and microseconds (at 2 MHz, 1 us = 2 ticks)
: BENCHMARK ( i*x xt -- j*x )
    MEASURE-T2 T2-OVERHEAD -
    DECIMAL
    CR ." Net E-clock cycles (0.5 us each): " DUP U.
    CR ." Execution duration: "
    DUP 2 / U. ." ." 1 AND 5 * 0 .R ."  us" ;

INIT-T2