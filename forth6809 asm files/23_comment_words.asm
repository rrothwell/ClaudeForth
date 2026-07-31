; ============================================================
; SECTION 23: COMMENT WORDS
; ============================================================
LPAREN:  LDD   #')'
         PSHU  D
         JSR   WORD
         RTS

BACKSLASH: LDD  SRCLEN
           STD  TOIN
           RTS

