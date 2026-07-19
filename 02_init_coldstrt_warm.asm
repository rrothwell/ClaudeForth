; ============================================================
; 6809 FORTH - 02_init_coldstrt_warm
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 2: INIT CODE (COLDSTRT / WARM)
; ============================================================
         ORG   INITCODE       ; INITCODE is $FFA2 (was INIT/$FFA0, before that literal $FFC0)
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

         LDA   #$03
         STA   ACIACR         ; was "STA ACIA" - only correct by
                               ; coincidence while ACIA and ACIACR were
                               ; the same address; now genuinely distinct
         LDA   #CR_RXON
         STA   ACIACR         ; was "STA ACIA" - same fix

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

; ============================================================
