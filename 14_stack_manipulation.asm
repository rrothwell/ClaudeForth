; ============================================================
; 6809 FORTH - 14_stack_manipulation
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 14: STACK MANIPULATION (Core + Core Ext + return stack)
; ============================================================
DUP:     LDD   ,U
         PSHU  D
         RTS

DROP:    LEAU  2,U
         RTS

SWAP:    LDD   ,U
         LDX   2,U
         STX   ,U
         STD   2,U
         RTS

OVER:    LDD   2,U
         PSHU  D
         RTS

ROT:     LDD   ,U
         LDX   2,U
         LDY   4,U
         STY   ,U
         STD   2,U
         STX   4,U
         RTS

QDUP:    LDD   ,U
         CMPD  #0
         BEQ   QDUPDONE
         PSHU  D
QDUPDONE: RTS

DEPTH:   TFR   U,D
         STD   DEPTHTMP
         LDD   #SP0
         SUBD  DEPTHTMP
         LSRA
         RORB
         PSHU  D
         RTS

DDUP:    LDD   2,U
         LDX   ,U
         PSHU  D
         PSHU  X
         RTS

DDROP:   LEAU  4,U
         RTS

DSWAP:   LDD   ,U
         STD   MSCR
         LDD   2,U
         LDX   4,U
         LDY   6,U
         STD   6,U
         STX   ,U
         STY   2,U
         LDD   MSCR
         STD   4,U
         RTS

DOVER:   LDD   6,U
         LDX   4,U
         PSHU  D
         PSHU  X
         RTS

NIP:     LDD   ,U
         STD   2,U
         LEAU  2,U
         RTS

TUCK:    LDD   ,U
         LDX   2,U
         PSHU  D
         STX   2,U
         STD   4,U
         RTS

PICK:    PULU  D
         LSLB
         ROLA
         LDD   D,U
         PSHU  D
         RTS

ROLL:    PULU  D
         CMPD  #0
         BEQ   ROLLDONE
         LSLB
         ROLA
         STD   RDST
         LEAX  D,U
         LDD   ,X
         STD   RVAL
RLOOP:   LDD   RDST
         CMPD  #2
         BLT   RSTORE
         LEAY  D,U
         SUBD  #2
         LEAX  D,U
         LDD   ,X
         STD   ,Y
         LDD   RDST
         SUBD  #2
         STD   RDST
         BRA   RLOOP
RSTORE:  LDD   RVAL
         STD   ,U
ROLLDONE: RTS

DROT:    LDD   10,U
         STD   TR1
         LDD   8,U
         STD   TR2
         LDD   6,U
         STD   10,U
         LDD   4,U
         STD   8,U
         LDD   2,U
         STD   6,U
         LDD   0,U
         STD   4,U
         LDD   TR2
         STD   ,U
         LDD   TR1
         STD   2,U
         RTS

TOR:     PULU  D
         PULS  X
         PSHS  D
         PSHS  X
         RTS

FROMR:   PULS  X
         PULS  D
         PSHS  X
         PSHU  D
         RTS

RFETCH:  PULS  X
         LDD   ,S
         PSHS  X
         PSHU  D
         RTS

TWOTOR:  PULU  D
         STD   R2A
         PULU  D
         STD   R2B
         PULS  X
         LDD   R2B
         PSHS  D
         LDD   R2A
         PSHS  D
         PSHS  X
         RTS

TWOFROMR: PULS X
          PULS D
          STD  R2A
          PULS D
          STD  R2B
          PSHS X
          LDD  R2B
          PSHU D
          LDD  R2A
          PSHU D
          RTS

TWORFETCH: PULS X
           LDD  ,S
           STD  R2A
           LDD  2,S
           STD  R2B
           PSHS X
           LDD  R2B
           PSHU D
           LDD  R2A
           PSHU D
           RTS

; ============================================================
