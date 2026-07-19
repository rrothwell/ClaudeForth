; ============================================================
; 6809 FORTH - 06_comma_family
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 6: COMMA FAMILY (factored via APPENDCELL/APPENDBYTE)
; ============================================================
APPENDCELL: PULU D
            LDY   ,X
            STD   ,Y++
            STY   ,X
            RTS

APPENDBYTE: PULU D
            LDY   ,X
            STB   ,Y+
            STY   ,X
            RTS

COMMA:      LDX   #CODEHERE
            JMP   APPENDCELL

CODECOMMA:  LDX   #CODEHERE
            JMP   APPENDCELL

CCOMMA:     LDX   #CODEHERE
            JMP   APPENDBYTE

CCOMMA1:    LDX   #CODEHERE
            JMP   APPENDBYTE

VCOMMA:     LDX   #VARHERE
            JMP   APPENDCELL

VCCOMMA:    LDX   #VARHERE
            JMP   APPENDBYTE

ALLOT:   PULU  D
         LDX   CODEHERE
         LEAX  D,X
         STX   CODEHERE
         RTS

VALLOT:  PULU  D
         LDX   VARHERE
         LEAX  D,X
         STX   VARHERE
         RTS

HEREW:   LDD   CODEHERE
         PSHU  D
         RTS

VHEREW:  LDD   VARHERE
         PSHU  D
         RTS

PADW:    LDD   CODEHERE
         ADDD  #84
         PSHU  D
         RTS

UNUSEDW: LDD   #CODETOP
         SUBD  CODEHERE
         PSHU  D
         RTS

VUNUSEDW: LDD  #APPVARSEND    ; was #APPCODE - a real bug, not just a
          SUBD VARHERE        ; missing check: computed a meaningless
          PSHU D              ; distance to an unrelated region instead
          RTS                 ; of remaining APPVARS space

; ============================================================
