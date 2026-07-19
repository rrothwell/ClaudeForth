; ============================================================
; 6809 FORTH - 18_memory
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 18: MEMORY (fetch/store, block ops)
; ============================================================
STOREW:  PULU  X
         PULU  D
         STD   ,X
         RTS

CFETCH:  PULU  X
         LDB   ,X
         CLRA
         PSHU  D
         RTS

CSTOREW: PULU  X
         PULU  D
         STB   ,X
         RTS

PLUSSTORE: PULU X
           PULU D
           ADDD ,X
           STD  ,X
           RTS

DFETCH:  PULU  X
         LDD   2,X
         PSHU  D
         LDD   ,X
         PSHU  D
         RTS

DSTORE:  PULU  X
         PULU  D
         STD   2,X
         PULU  D
         STD   ,X
         RTS

CMOVEW:  PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDX   MVSRC
         LDY   MVDST
CMVLOOP: LDD   MVCNT
         BEQ   CMDONE
         LDA   ,X+
         STA   ,Y+
         SUBD  #1
         STD   MVCNT
         BRA   CMVLOOP
CMDONE:  RTS

CMOVEGT: PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDD   MVCNT
         BEQ   CGDONE
         LDX   MVSRC
         LEAX  D,X
         LEAX  -1,X
         LDY   MVDST
         LEAY  D,Y
         LEAY  -1,Y
CGLOOP:  LDA   ,X
         STA   ,Y
         LEAX  -1,X
         LEAY  -1,Y
         LDD   MVCNT
         SUBD  #1
         STD   MVCNT
         BNE   CGLOOP
CGDONE:  RTS

MOVEW:   PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDD   MVDST
         CMPD  MVSRC
         BLS   MVLOW
         LDD   MVSRC
         PSHU  D
         LDD   MVDST
         PSHU  D
         LDD   MVCNT
         PSHU  D
         JMP   CMOVEGT
MVLOW:   LDD   MVSRC
         PSHU  D
         LDD   MVDST
         PSHU  D
         LDD   MVCNT
         PSHU  D
         JMP   CMOVEW

FILLW:   PULU  D
         STB   FILLCHR
         PULU  D
         STD   FILLCNT
         PULU  D
         STD   FILLADDR
         LDX   FILLADDR
FILLOOP: LDD   FILLCNT
         BEQ   FDONE
         LDA   FILLCHR
         STA   ,X+
         SUBD  #1
         STD   FILLCNT
         BRA   FILLOOP
FDONE:   RTS

ERASEW:  LDD   #0
         PSHU  D
         JMP   FILLW

; ============================================================
