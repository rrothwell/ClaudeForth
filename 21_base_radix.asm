; ============================================================
; 6809 FORTH - 21_base_radix
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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

; ============================================================
