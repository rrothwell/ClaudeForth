; ============================================================
; 6809 FORTH - 16_logic_shifts_address_arith
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 16: LOGIC / SHIFTS / ADDRESS ARITHMETIC
; ============================================================
ANDW:    PULU  D
         ANDA  ,U
         ANDB  1,U
         STD   ,U
         RTS

ORW:     PULU  D
         ORA   ,U
         ORB   1,U
         STD   ,U
         RTS

XORW:    PULU  D
         EORA  ,U
         EORB  1,U
         STD   ,U
         RTS

INVERT:  LDD   ,U
         COMA
         COMB
         STD   ,U
         RTS

LSHIFT:  PULU  D
         STB   SHCNT
         LDD   ,U
LSLOOP:  LDB   SHCNT
         BEQ   LSDONE
         ASL   1,U
         ROL   ,U
         DEC   SHCNT
         BRA   LSLOOP
LSDONE:  RTS

RSHIFT:  PULU  D
         STB   SHCNT
RSLOOP:  LDB   SHCNT
         BEQ   RSDONE
         LSR   ,U
         ROR   1,U
         DEC   SHCNT
         BRA   RSLOOP
RSDONE:  RTS

CELLSW:  LDD   ,U
         ASLB
         ROLA
         STD   ,U
         RTS

CELLPLUS: LDD  ,U
          ADDD #2
          STD  ,U
          RTS

CHARSW:  RTS

CHARPLUS: LDD  ,U
          ADDD #1
          STD  ,U
          RTS

ALIGNW:  RTS
ALIGNEDW: RTS

; ============================================================
