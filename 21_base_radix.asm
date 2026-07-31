; ============================================================
; SECTION 21: BASE / RADIX CONTROL
; ============================================================
BASEW:   LDD  #BASE
         PSHU D
         RTS

DECIMAL: LDD  #10
         STD  BASE
         RTS

HEXW:    LDD  #16
         STD  BASE
         RTS

BINARYW: LDD  #2
         STD  BASE
         RTS

