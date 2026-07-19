; ============================================================
; 6809 FORTH - 03_irqh
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 3: ACIA INTERRUPT HANDLER
; ============================================================
         ORG   BASECODE       ; BASECODE is $E800. This ORG was missing
                               ; entirely - every routine from here through
                               ; SECTION 26 (IRQH, COLD/ABORT/QUIT, and
                               ; every primitive) would otherwise have
                               ; continued growing from wherever SECTION 2's
                               ; WARM message left the location counter,
                               ; inside INIT's 48-byte $FFC0-$FFEF budget,
                               ; overflowing directly into VECTORS ($FFF0)
                               ; instead of landing in BASECODE at all

; ------------------------------------------------------------
; INFILL - ( -- A=fill level, 0-63 ) input ring's current fill
; level. INBUFSZ is a power of two, and both indices are always
; kept in 0..INBUFSZ-1, so a plain masked subtraction gives the
; true mod-64 distance even across the wrap point.
; ------------------------------------------------------------
INFILL:  LDA   INHEAD
         SUBA  INTAIL
         ANDA  #INBUFSZ-1
         RTS

; ------------------------------------------------------------
; RTSCHECKHI - called from IRQH's own RX path (interrupts
; already masked by hardware during ISR execution, so no
; explicit masking needed here). If the input ring has reached
; INHIWATER and RTS is not already asserted high, assert it -
; telling the remote device to pause sending. Per the 6850, RTS
; has no automatic tie to reception; this is ordinary firmware
; flow control, not a chip feature.
; ------------------------------------------------------------
RTSCHECKHI: JSR  INFILL
            CMPA #INHIWATER
            BLO  RTSCHIDONE
            TST  RTSSTATE
            BNE  RTSCHIDONE       ; already high - nothing to do
            LDA  #CR_RTSHI
            STA  ACIACR
            LDA  #1
            STA  RTSSTATE
RTSCHIDONE: RTS

; ------------------------------------------------------------
; RTSCHECKLO - called from mainline code (KEY), NOT from the
; ISR, so it must mask IRQ around its critical section: IRQH's
; own TXOFF path also writes ACIACR, and an interrupt landing
; mid-decision here could otherwise race it. If the ring has
; drained to INLOWATER or below and RTS is currently high,
; reassert RTS low - restoring TX-interrupt-enable too if
; output happens to be queued, since the ACIA has no control
; byte combination offering RTS-high with TX-interrupt-enabled
; simultaneously (see CR_RTSHI's comment).
; ------------------------------------------------------------
RTSCHECKLO: JSR  INFILL
            CMPA #INLOWATER
            BHI  RTSCLODONE
            TST  RTSSTATE
            BEQ  RTSCLODONE       ; already low - nothing to do
            ORCC #$10              ; mask IRQ for the critical section
            CLR  RTSSTATE
            LDB  OUTTAIL
            CMPB OUTHEAD
            BEQ  RTSCLONOTX
            LDA  #CR_RXTX
            STA  ACIACR
            BRA  RTSCLOUNMASK
RTSCLONOTX: LDA  #CR_RXON
            STA  ACIACR
RTSCLOUNMASK: ANDCC #$EF
RTSCLODONE: RTS

IRQH:    LDA   ACIASR
         BITA  #SR_IRQ
         BEQ   IRQDONE

         BITA  #SR_RDRF
         BEQ   TXCHK

         LDB   INHEAD
         LDA   ACIADR
         LDX   #INBUF
         STA   B,X
         INCB
         ANDB  #INBUFSZ-1
         CMPB  INTAIL
         BEQ   IRQDONE
         STB   INHEAD
         JSR   RTSCHECKHI
         BRA   IRQDONE

TXCHK:   LDB   OUTTAIL
         CMPB  OUTHEAD
         BEQ   TXOFF
         LDX   #OUTBUF
         LDA   B,X
         STA   ACIADR
         INCB
         ANDB  #OUTBUFSZ-1
         STB   OUTTAIL
         BRA   IRQDONE

TXOFF:   TST   RTSSTATE
         BNE   IRQDONE         ; RTS is asserted high - leave ACIACR alone,
                                ; or this would incorrectly drop it back low
         LDA   #CR_RXON
         STA   ACIACR

IRQDONE: RTI

SWI3H:   RTI
SWI2H:   RTI
FIRQH:   RTI
NMIH:    RTI                   ; unused now that NMI -> WARM
SWIH:    LDD   #-99             ; placeholder hardware-trap code; push and
         PSHU  D                 ; JMP THROW, per the CATCH/THROW turn
         JMP   THROW

; ============================================================
