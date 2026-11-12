; ==============================================================================
; MC6840 PTM 24-Hour Clock Driver for Motorola 6809
; Base Address: $C000 | System Clock: 2 MHz | Interrupt Rate: 100 ms (10 Hz)
; ==============================================================================

PTM_BASE    EQU     $C000
PTM_CR13    EQU     PTM_BASE+0      ; Write: Control Reg 1 or 3 (selected by CR2 bit 0)
PTM_CR2     EQU     PTM_BASE+1      ; Write: Control Reg 2 | Read: Status Register
PTM_T1_MSB  EQU     PTM_BASE+2      ; Timer 1 Latches / Counter
PTM_T1_LSB  EQU     PTM_BASE+3
PTM_T2_MSB  EQU     PTM_BASE+4      ; Timer 2 Latches / Counter
PTM_T2_LSB  EQU     PTM_BASE+5
PTM_T3_MSB  EQU     PTM_BASE+6      ; Timer 3 Latches / Counter
PTM_T3_LSB  EQU     PTM_BASE+7

; Timekeeping Variables (Place in RAM / end of Direct Page to avoid collisions)
            ORG     $00F0
TENTHS      RMB     1               ; 0 - 9  (100 ms increments)
SECONDS     RMB     1               ; 0 - 59
MINUTES     RMB     1               ; 0 - 59
HOURS       RMB     1               ; 0 - 23

; ==============================================================================
; INITIALIZATION ROUTINE
; ==============================================================================
 ; Just under the Forth return stack to avoid collisions.
            ORG     $B800
INIT_CLOCK:
            ORCC    #$50            ; Disable IRQ and FIRQ during setup

            ; 1. Clear time variables
            CLR     TENTHS
            CLR     SECONDS
            CLR     MINUTES
            CLR     HOURS

            ; 2. Configure Control Register 2 (CR2)
            ; Bit 0 = 0: Next write to $C000 accesses Control Register 3 (CR3)
            CLR     PTM_CR2

            ; 3. Configure Control Register 3 (CR3)
            ; Bit 7 = 0 (Output masked)
            ; Bit 6 = 1 (Interrupt enabled)
            ; Bits 5-3 = 000 (Continuous operating mode)
            ; Bit 2 = 0 (16-bit counting mode)
            ; Bit 1 = 1 (Use internal E clock)
            ; Bit 0 = 1 (Enable Divide-by-8 prescaler)
            LDA     #%01000011      ; $43
            STA     PTM_CR13

            ; 4. Load Timer 3 Latch with 24,999 ($61A7)
            ; Note: Must write MSB first, then LSB transfers both into counter
            LDD     #24999          ; $61A7
            STD     PTM_T3_MSB      ; Writes A to $C006, B to $C007

            ; 5. Configure CR2 to point $C000 to Control Register 1 (CR1)
            LDA     #%00000001      ; $01 (Bit 0 = 1 selects CR1)
            STA     PTM_CR2

            ; 6. Start all timers by clearing the internal reset bit in CR1
            ; Bit 0 = 0 (All timers allowed to operate)
            CLR     PTM_CR13

            ANDCC   #$EF            ; Enable IRQ (Clear I flag)
            RTS

; ==============================================================================
; IRQ INTERRUPT SERVICE ROUTINE (100 ms Tick)
; Note: On the 6809, hardware IRQ automatically pushes CC, A, B, DP, X, Y, U, PC
; ==============================================================================
IRQ_ISR:
            LDA     PTM_CR2         ; Read Status Register (Step 1 of clearing IRQ)
            BITA    #$04            ; Check Bit 2 (Timer 3 Interrupt Flag)
            BEQ     NEXT_ISR        ; If not Timer 3, exit (or chain to other IRQ handlers)

            LDD     PTM_T3_MSB      ; Read Timer 3 Counter (Step 2: clears T3 IRQ flag!)

            ; --- Update 24-Hour Clock ---
            INC     TENTHS          ; Increment 100ms counter
            LDA     TENTHS
            CMPA    #10             ; Have 10 tenths (1 second) elapsed?
            BLO     EXIT_ISR
            CLR     TENTHS

            INC     SECONDS         ; Increment seconds
            LDA     SECONDS
            CMPA    #60             ; Have 60 seconds elapsed?
            BLO     EXIT_ISR
            CLR     SECONDS

            INC     MINUTES         ; Increment minutes
            LDA     MINUTES
            CMPA    #60             ; Have 60 minutes elapsed?
            BLO     EXIT_ISR
            CLR     MINUTES

            INC     HOURS           ; Increment hours
            LDA     HOURS
            CMPA    #24             ; Have 24 hours elapsed?
            BLO     EXIT_ISR
            CLR     HOURS           ; Wrap back to 00:00:00.0
            
EXIT_ISR:   RTI

NEXT_ISR    JMP   [$0083]        ; Return from Interrupt (restores all registers)

; ==============================================================================
; FORTH-SAFE INTERRUPT CONTROL ROUTINES
; Note: Uses only Accumulator A. Safe to call from Forth CODE words.
; ==============================================================================

; ------------------------------------------------------------------------------
; DISABLE_CLK_IRQ
; Masks Timer 3 interrupts in CR3 while keeping the hardware counter running.
; Call this before reading or writing HOURS, MINUTES, SECONDS, or TENTHS.
; ------------------------------------------------------------------------------
DISABLE_CLK_IRQ:
            CLR     PTM_CR2         ; Bit 0 = 0: Select CR3 at $C000
            LDA     #%00000011      ; $03: Bit 6 = 0 (IRQ Disabled), Continuous, E-clk, /8
            STA     PTM_CR13
            LDA     #%00000001      ; Bit 0 = 1: Restore $C000 to point to CR1
            STA     PTM_CR2
            RTS

; ------------------------------------------------------------------------------
; ENABLE_CLK_IRQ
; Re-enables Timer 3 interrupts in CR3.
; Note: If a 100ms tick occurred while disabled, the pending flag is still 
; latched and will immediately trigger the ISR upon re-enabling (no lost time).
; ------------------------------------------------------------------------------
ENABLE_CLK_IRQ:
            CLR     PTM_CR2         ; Bit 0 = 0: Select CR3 at $C000
            LDA     #%01000011      ; $43: Bit 6 = 1 (IRQ Enabled), Continuous, E-clk, /8
            STA     PTM_CR13
            LDA     #%00000001      ; Bit 0 = 1: Restore $C000 to point to CR1
            STA     PTM_CR2
            RTS

; ------------------------------------------------------------------------------
; RESET_CLK_TICK (Optional: Call when setting a brand new time)
; Clears any pending Timer 3 IRQ flag and resets the 100ms phase.
; ------------------------------------------------------------------------------
RESET_CLK_TICK:
            CLR     TENTHS          ; Start fresh at .0 seconds
            LDA     PTM_CR2         ; Step 1: Read Status Register
            LDD     PTM_T3_MSB      ; Step 2: Read T3 Counter to clear any pending IRQ flag
            RTS
