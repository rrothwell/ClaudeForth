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

