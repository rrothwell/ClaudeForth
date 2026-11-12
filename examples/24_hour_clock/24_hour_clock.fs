\ Interrupt driven 24 hour clock

\ This Forth application provides the following functions:
\  - time set
\  - message display
\  - continuous versus singular time display.

\ ====== Commands

\ Message entry, overrides the default message.
\ Type: MESSAGE![RETURN] the quick brown fox [RETURN]

\ Current time
\ Type: hours minutes seconds [SPACE]TIME![RETURN]

\ Display current time once
\ Type: ONCE[RETURN]

\ Display current time continuously
\ Type: ALWAYS[RETURN]
\ Terminate the display by pressing any key.

\ ====== Timer Driver Code

\ -------Interrupt Handler

\ Variable space allocation requires long addresses,
\ so using this requires reassembly.
\ VARIABLE TIME 2 VALLOT

\ Zero page allocation instead of variable space.
HEX
F0 CONSTANT TIME

: TENTHS  TIME ;               \ $F0 = 0 - 9  (100 ms increments)
: SECONDS TIME 1+ ;            \ $F1 = 0 - 59
: MINUTES TIME 2+ ;            \ $F2 = 0 - 59
: HOURS   TIME 3 + ;           \ $F3 = 0 - 23

\ Address, 16 bits, split into hi & lo byte and placed in memory,
\ according to Motorola convention.
: ADDR, 
    DUP 
    8 RSHIFT FF AND C, \ MSB at lower memory
    FF AND  C,         \ LSB at higher memory
;

\ Usage: INIT_CLOCK EXECUTE
HEX
HERE
1A C,  50 C,                              \ Disable interrupts
0F C,  TENTHS C,                          \ Clear TIME
0F C,  SECONDS C,  
0F C,  MINUTES C,  
0F C,  HOURS C,       
7F C,  C0 C,  01 C,                       \ Clear PTM_CR2, to access CR3
86 C,  43 C,  B7 C,  C0 C,  00 C,         \ Config CR3
CC C,  61 C,  A7 C,  FD C,  C0 C,  06 C,  \ Load timer
86 C,  01 C,  B7 C,  C0 C,  01 C,         \ Config PTM_CR2, to access CR1
7F C,  C0 C,  00 C,                       \ Start all timers.
1C C,  EF C,  39 C,  \ Enable interrupts & return
  CONSTANT INIT_CLOCK

VARIABLE TIMER3_ISR>                      \ Following ISR in chain uses old terminal ISR
IRQ-CHAIN @ TIMER3_ISR> ! 

HEX
HERE 
B6 C,  C0 C,  01 C,  85 C,  04 C,         \ Identify interrupt source.
27 C,  2C C,                              \ If not here follow the chain.
FC C,  C0 C,  06 C,                       \ Read counter to clear the interrupt flag.
0C C,  TENTHS C,                              \ Count 100ms. 
96 C,  TENTHS C,  81 C,  0A C,  25 C,  20 C,  0F C,  TENTHS C,  \ Handle overflow. 
0C C,  SECONDS C,                              \ Count seconds.
96 C,  SECONDS C,  81 C,  3C C,  25 C,  16 C,  0F C,  SECONDS C,   \ Handle overflow.
0C C,  MINUTES C,                              \ Count minutes.
96 C,  MINUTES C,  81 C,  3C C,  25 C,  0C C,  0F C,  MINUTES C,   \ Handle overflow.
0C C,  HOURS C,                              \ Count hours.
96 C,  HOURS C,  81 C,  18 C,  25 C,  02 C,  0F C,  HOURS C,   \ Handle daily wrap around.
3B C,                                     \ Exit after handling interrupt
6E C,  9F C,  TIMER3_ISR> ADDR,                \ Pass to next handler in chain.
  CONSTANT TIMER3_ISR

TIMER3_ISR IRQ-CHAIN !                    \ This ISR will now be called by serial comms ISR.

\ ------- Userland Code

\ This method uses manipulation of the 
\ interrupt enable/disable bit in CR3 of the 6840 PTM.
\ Slightly slower than manipulating the CPU interrupt mask,
\ but interferes less with serial communications interrupt handling.
\ If other code also uses the 6840 PTM a shadow copy of CR3 
\ needs to be maintained in RAM to allow manipulation of individual bits.

\ TODO generalise allow the timers to be used independently. 

\ Usage: DISABLE_CLK_IRQ EXECUTE
HEX
HERE
7F C,  C0 C,  01 C,                \ Access CR3
86 C,  03 C,  B7 C,  C0 C,  00 C,  \ Disable interrupt, leaving other flags unchanged.
86 C,  01 C,  B7 C,  C0 C,  01 C,  \ Restore access to CR1
39 C,                              \ Return
  CONSTANT DISABLE_CLK_IRQ

\ Usage: ENABLE_CLK_IRQ EXECUTE
HEX
HERE
7F C,  C0 C,  01 C,                       \ Access CR3
86 C,  43 C,  B7 C,  C0 C,  00 C,         \ Enable interrupt, leaving other flags unchanged.  
86 C,  01 C,  B7 C,  C0 C,  01 C,         \ Restore access to CR1 
39 C,                                     \ Return     
  CONSTANT ENABLE_CLK_IRQ

\ This routine resets all times so it that will not work well 
\ if other applications also use the 6840 PTM.

\ Usage: RESET_CLK_TICK EXECUTE
HEX
HERE
0F C,  TENTHS C,                          \ Zero tenths.
B6 C,  C0 C,  01 C,                       \ Clear interrupts by reading status register
FC C,  C0 C,  06 C,                       \ then count register.
39 C,                                     \ Return     
  CONSTANT RESET_CLK_TICK
 
 
\ ====== User Interface Code

: TIME! ( hours minutes seconds   -- )
    DISABLE_CLK_IRQ EXECUTE
    SECONDS C! MINUTES C! HOURS C!
    RESET_CLK_TICK  EXECUTE
    ENABLE_CLK_IRQ EXECUTE
;

: TIME@ ( -- hours minutes seconds )
    DISABLE_CLK_IRQ EXECUTE
    SECONDS C@ MINUTES C@ HOURS C@ 
    ENABLE_CLK_IRQ EXECUTE
;

: SECONDS@ ( -- seconds )
    TIME@
    2DROP
; 

: FORMAT: ( minutes|seconds -- )
    S>D
    <# # # [CHAR] : HOLD #> 
    TYPE 
;

\ Format and print the time with colon separators.
: .TIME  ( -- )
    TIME@
    DECIMAL
    2 .R      \ HH
    FORMAT:   \ :MM
    FORMAT:   \ :SS
;

DECIMAL 
30 CONSTANT #MSG
#MSG BUFFER: (MSG)

: MESSAGE! ( -- )
    CR ." Enter your message (max 30 chars): "
    (MSG) 1+ #MSG 1- ACCEPT  ( -- actual-length )
    (MSG) C!
;

: .MESSAGE 
    (MSG) COUNT TYPE
;

: DISPLAY
    .MESSAGE SPACE .TIME
;

: ONCE 
    CR 
    DISPLAY
;

\ Wait until the seconds change.
: TICK?
    SECONDS@
    BEGIN
        DUP
    SECONDS@ <> UNTIL
    DROP    
;

DECIMAL
: HIDE-CURSOR ( -- )
    27 EMIT ." [?25l" ;

DECIMAL
: SHOW-CURSOR ( -- )
    27 EMIT ." [?25h" ;

DECIMAL
: ALWAYS
    HIDE-CURSOR
    BEGIN 
        TICK?
        13 EMIT
        DISPLAY 
    KEY? UNTIL 
    SHOW-CURSOR
; 

: INIT-MESSAGE ( -- )
    S" The time is: "     \ c-addr u 
    DUP >R                \ Save the character count
    (MSG) 1+              \ c-addr u  dst-addr 
    SWAP                  \ c-addr dst-addr u  
    MOVE                  \ 
    R> (MSG) C!           \ Place the character count
;

: INIT-ALL
    INIT_CLOCK EXECUTE
    INIT-MESSAGE
;  INIT-ALL  
    
DECIMAL