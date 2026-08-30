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

         LDX   #SERBUF
         CLR   ,X+
         CLR   ,X

         JSR   INITSERIAL

         IFEQ  UNITTESTS  ; >>>>>>>>>>
         JSR   TSTRUNNER
         ELSE  ; <<<<<>>>>>
         NOP             ; BUG FIX: this call site used to emit 0
         NOP             ; bytes when UNITTESTS=1 (excluded), meaning
         NOP             ; COLDSTRT's own size varied by 3 bytes
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

