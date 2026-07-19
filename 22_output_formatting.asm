; ============================================================
; 6809 FORTH - 22_output_formatting
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 22: OUTPUT FORMATTING (CR/SPACE/SPACES)
; ============================================================
CRW:     LDD   #13
         PSHU  D
         JSR   EMIT
         LDD   #10
         PSHU  D
         JSR   EMIT
         RTS

SPACEW:  LDD   #32
         PSHU  D
         JSR   EMIT
         RTS

SPACESW: PULU  D
         STD   SHCNT2
SPLOOP:  LDD   SHCNT2
         BLE   SPDONE
         LDD   #32
         PSHU  D
         JSR   EMIT
         LDD   SHCNT2
         SUBD  #1
         STD   SHCNT2
         BRA   SPLOOP
SPDONE:  RTS

; ============================================================
