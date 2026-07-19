; ============================================================
; 6809 FORTH - 17_comparison
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 17: COMPARISON
; ============================================================
EQUALW:  PULU  D
         CMPD  ,U
         BEQ   EQTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
EQTRUE:  LDD   #TRUEV
         STD   ,U
         RTS

LESSW:   PULU  D
         STD   MSCR
         LDD   ,U
         CMPD  MSCR
         BLT   LTTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
LTTRUE:  LDD   #TRUEV
         STD   ,U
         RTS

GREATERW: PULU D
          STD  MSCR
          LDD  ,U
          CMPD MSCR
          BGT  GTTRUE
          LDD  #FALSEV
          STD  ,U
          RTS
GTTRUE:   LDD  #TRUEV
          STD  ,U
          RTS

ZEROEQ:  LDD   ,U
         BEQ   ZEQTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
ZEQTRUE: LDD   #TRUEV
         STD   ,U
         RTS

ZEROLT:  LDD   ,U
         BMI   ZLTTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
ZLTTRUE: LDD   #TRUEV
         STD   ,U
         RTS

ULESSW:  PULU  D
         STD   MSCR
         LDD   ,U
         CMPD  MSCR
         BLO   ULTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
ULTRUE:  LDD   #TRUEV
         STD   ,U
         RTS

NOTEQUAL: JSR  EQUALW
          LDD  ,U
          COMA
          COMB
          STD  ,U
          RTS

ZERONE:  JSR   ZEROEQ
         LDD   ,U
         COMA
         COMB
         STD   ,U
         RTS

ZEROGT:  LDD   ,U
         BEQ   ZGTFALSE
         BMI   ZGTFALSE
         LDD   #TRUEV
         STD   ,U
         RTS
ZGTFALSE: LDD  #FALSEV
          STD  ,U
          RTS

UGREATER: PULU D
          STD  MSCR
          LDD  ,U
          CMPD MSCR
          BLO  UGFALSE
          BEQ  UGFALSE
          LDD  #TRUEV
          STD  ,U
          RTS
UGFALSE:  LDD  #FALSEV
          STD  ,U
          RTS

WITHINW: PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         LDD   ,U
         SUBD  MSCR2
         STD   MSCR3
         LDD   MSCR
         SUBD  MSCR2
         STD   MSCR
         LDD   MSCR3
         CMPD  MSCR
         BLO   WITHTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
WITHTRUE: LDD  #TRUEV
          STD  ,U
          RTS

DEQUAL:  PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         CMPD  MSCR2
         BNE   DEQFALSE
         LDD   MSCR3
         CMPD  MSCR
         BNE   DEQFALSE
         LDD   #TRUEV
         PSHU  D
         RTS
DEQFALSE: LDD  #FALSEV
          PSHU D
          RTS

DLESSW:  PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         STD   MSCR4
         LDD   MSCR3
         CMPD  MSCR
         BLT   DLTRUE
         BGT   DLFALSE
         LDD   MSCR4
         CMPD  MSCR2
         BLO   DLTRUE
DLFALSE: LDD   #FALSEV
         PSHU  D
         RTS
DLTRUE:  LDD   #TRUEV
         PSHU  D
         RTS

DULESSW: PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         STD   MSCR4
         LDD   MSCR3
         CMPD  MSCR
         BLO   DULTRUE
         BHI   DULFALSE
         LDD   MSCR4
         CMPD  MSCR2
         BLO   DULTRUE
DULFALSE: LDD  #FALSEV
          PSHU D
          RTS
DULTRUE:  LDD  #TRUEV
          PSHU D
          RTS

; ============================================================
