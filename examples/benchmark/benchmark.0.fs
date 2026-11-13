\============================================================
\ Measure execution time of a forth word.
\ Initially using a pure forth implementation.
\
\ Assumptions:
\ Uses timer 2 in an MC6840 PTM.
\ Memory map of an MECB 6809 card with an MECB IO card.
\ Usage:
\ 
\ TODO:
\ Allow timer 2 to be configured & used without affecting
\ use of timers 1 & 3.   
\============================================================

\ Adjust PTM-BASE to match your hardware's memory-mapped I/O address
HEX
C000 CONSTANT PTM-BASE
DECIMAL

PTM-BASE 0 + CONSTANT PTM-CR13
PTM-BASE 1 + CONSTANT PTM-CR2
PTM-BASE 2 + CONSTANT PTM-T1-MSB
PTM-BASE 3 + CONSTANT PTM-T1-LSB

\ Initialize Timer 1 as a free-running E-clock down-counter
: INIT-PTM ( -- )
    1 PTM-CR2 C!          \ Select CR1 at offset 0
    1 PTM-CR13 C!         \ Assert internal reset (CR1 bit 0 = 1)
    255 PTM-T1-MSB C!     \ Load $FFFF reload value (MSB first)
    255 PTM-T1-LSB C!     \ Writing LSB transfers $FFFF into counter
    2 PTM-CR13 C! ;       \ Clear reset, select internal E clock (CR1 bit 1 = 1)

\ Coherently read the 16-bit down-counter (MSB first latches LSB)
: T1@ ( -- u )
    PTM-T1-MSB C@ 8 LSHIFT
    PTM-T1-LSB C@ OR ;

\ Measure execution time of an Execution Token (xt) in E-clock ticks
: MEASURE ( i*x xt -- j*x ticks )
    T1@ >R                \ Capture start count on return stack
    EXECUTE               \ Execute the target Forth word
    T1@                   \ Capture end count
    R> SWAP -             \ Elapsed = Start - End (down-counter)
    65535 AND ;           \ Mask to 16-bit unsigned to handle rollover

\ Measure baseline overhead of EXECUTE + timer reads
: NOOP ( -- ) ;
: OVERHEAD ( -- ticks )
    ['] NOOP MEASURE ;

\ Print net E-clock cycles for a given word
: BENCHMARK ( i*x xt -- j*x )
    MEASURE OVERHEAD -
    CR ." Elapsed E-clock cycles: " U. ;

INIT-PTM