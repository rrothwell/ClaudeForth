; ============================================================
; SECTION 2: INIT CODE (COLDSTRT / WARM)
; ============================================================
         ORG   INITCODE       ; INITCODE is $FFA9 (was $FFA2, before that $FFA0, before that literal $FFC0)
COLDSTRT:
         ORCC  #$50
         LDS   #RSTACK+1
         LDU   #DSTACK+1
         CLRA
         TFR   A,DP

         LDX   #GLOBALS
         LDB   #0
CLRGLOB: CLR   ,X+
         DECB
         BNE   CLRGLOB

         JSR   INITSERIAL

         ANDCC #$AF      ; BUG FIX: confirmed via MAME - COLDSTRT's own
                         ; ORCC #$50 above (masking IRQ+FIRQ during the
                         ; critical early setup: stack pointers, DP,
                         ; GLOBALS, SERBUF) was never paired with a
                         ; matching unmask anywhere on this path - only
                         ; WARM (below) had one, on its own, separate
                         ; entry point. Under SERIALPOLL=1 (the
                         ; longstanding default) this never mattered,
                         ; since IRQH is just an RTI stub and nothing
                         ; on that path ever depends on interrupts
                         ; actually firing. It surfaced only once
                         ; SERIALPOLL=0 (interrupt-driven ACIA I/O) was
                         ; actually selected and tested: with IRQ left
                         ; permanently masked, the ACIA's own interrupt
                         ; (now correctly wired to the CPU - see the
                         ; MAME driver's own irq_handler fix) could
                         ; never actually be serviced, regardless of
                         ; how correctly it reached the CPU pin -
                         ; keystrokes were silently dropped and the
                         ; warm-boot message never got typed out.
                         ; Confirmed directly: manually clearing the I
                         ; bit via the MAME debugger (cc=EF) mid-
                         ; session immediately unblocked both. Placed
                         ; here, right after INITSERIAL returns (the
                         ; ACIA is configured and every piece of ring-
                         ; buffer state IRQH depends on is already
                         ; zeroed by CLRGLOB above), and before
                         ; TSTRUNNER runs, so the unit test framework's
                         ; own interrupt-driven output works correctly
                         ; too, not just the eventual interactive
                         ; session. Matches WARM's own, already-correct
                         ; ANDCC #$AF exactly, for consistency - FIRQ
                         ; is harmless to unmask alongside IRQ, since
                         ; nothing on this system ever drives it
                         ; (FIRQH is an RTI stub, same as the other
                         ; unused vectors).

         IFNE  UNITTESTS  ; >>>>>>>>>>
         JSR   TSTRUNNER
         ELSE  ; <<<<<>>>>>
         NOP             ; BUG FIX (see the historical note above this
         NOP             ; call site's own comment, describing the
         NOP             ; original bug): this call site used to emit
                         ; 0 bytes when UNITTESTS' flag meaning
                         ; excluded the test framework, meaning
                         ; COLDSTRT's own size varied by 3 bytes
                         ; depending on UNITTESTS - with INITCODE's
                         ; own position fixed regardless, that risked
                         ; the code overflowing into VECTORS whenever
                         ; UNITTESTS was toggled on. Three NOPs here
                         ; are byte-for-byte the same size as the
                         ; JSR TSTRUNNER they replace, so this block
                         ; now always contributes exactly 3 bytes to
                         ; COLDSTRT either way - COLDSTRT's total size
                         ; no longer depends on UNITTESTS at all.
         ENDC  ; <<<<<<<<<<

         JMP   COLD

WARM:    ORCC  #$50
         CLRA
         TFR   A,DP
         LDU   #SP0
         LDS   #RP0

         JSR   INITSERIAL       ; BUG FIX: previously WARM never re-ran
                                ; this at all, meaning a warm reboot never
                                ; reset the ring buffer pointers (only
                                ; COLDSTRT's own, separate path did, and
                                ; only partially - see SERBUFCLR's own
                                ; comment) nor re-issued the ACIA's own
                                ; master-reset sequence. If a lockup or
                                ; stuck-overrun condition (observed and
                                ; reported separately) left either side
                                ; in a corrupted state, a warm reboot
                                ; would previously have inherited it
                                ; unchanged rather than genuinely
                                ; recovering. Placed here, matching
                                ; COLDSTRT's own established ordering
                                ; exactly: while IRQ is still masked,
                                ; with the later ANDCC #$AF unmasking
                                ; only once setup is complete.

         LDX   #WARMMSG
         PSHU  X
         LDD   #WARMMSGL
         PSHU  D
         JSR   TYPE
         ANDCC #$AF
         JMP   ABORT

WARMMSG: FCC   "  warm"
WARMMSGL EQU   *-WARMMSG

INITEND  EQU   *          ; Verify no collision with vectors, value should match vector ORG
INITSIZE EQU   INITEND-INITCODE

