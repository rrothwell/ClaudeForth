; ============================================================
; 6809 FORTH - 13_compiling_words
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 13: COMPILING WORDS (IMMEDIATE/[/]/'/COMPILE,/
; LITERAL/[']/POSTPONE/>BODY, SLITERAL, ABORT")
; ============================================================
STATEW:     LDD  #STATE
            PSHU D
            RTS

IMMEDIATE:  LDX  LATEST
            LDA  ,X
            ORA  #$80
            STA  ,X
            RTS

LBRACKET: LDD  #0
          STD  STATE
          RTS

RBRACKET: LDD  #-1
          STD  STATE
          RTS

TICK:    LDD  #32
         PSHU D
         JSR  WORD
         JSR  FIND
         PULU D
         CMPD #0
         BNE  TICKOK
         PULU D
         LDD  #-13
         PSHU D
         JSR  THROW
TICKOK:  RTS

COMPILECOMMA: JMP  CCALL

CCALL:   PULU  D
         LDX   CODEHERE
         LDA   #OPJSR
         STA   ,X+
         STD   ,X++
         STX   CODEHERE
         RTS

LITERALW: LDD  #LIT
          PSHU D
          JSR  CCALL
          JSR  CODECOMMA
          RTS

BRACKTICK: LDD  STATE
           BNE  BTSTOK
           LDD  #-14
           PSHU D
           JSR  THROW
BTSTOK:    LDD  #32
           PSHU D
           JSR  WORD
           JSR  FIND
           PULU D
           CMPD #0
           BNE  BTOK
           PULU D
           LDD  #-13
           PSHU D
           JSR  THROW
BTOK:      JSR  LITERALW
           RTS

POSTPONEW: LDD  STATE
           BNE  PPSTOK
           LDD  #-14
           PSHU D
           JSR  THROW
PPSTOK:    LDD  #32
           PSHU D
           JSR  WORD
           JSR  FIND
           PULU D
           CMPD #0
           BNE  PPFOUND
           PULU D
           LDD  #-13
           PSHU D
           JSR  THROW
PPFOUND:   CMPD #1
           BEQ  PPIMM
           JSR  LITERALW
           LDD  #COMPILECOMMA
           PSHU D
           JSR  CCALL
           RTS
PPIMM:     JSR  COMPILECOMMA
           RTS

TOBODY:  PULU D
         ADDD #5
         TFR  D,X
         LDD  ,X
         PSHU D
         RTS

SLITERALW: LDD  STATE
           BNE  SLSTOK
           LDD  #-14
           PSHU D
           JSR  THROW
SLSTOK:    PULU D
           STD  SCNT
           PULU D
           STD  SPTR
           LDD  #DOSTR
           PSHU D
           JSR  CCALL
           LDX  CODEHERE
           LDB  SCNT+1
           STB  ,X+
           LDY  SPTR
           LDB  SCNT+1
           BEQ  SLEND
SLCPY:     LDA  ,Y+
           STA  ,X+
           DECB
           BNE  SLCPY
SLEND:     STX  CODEHERE
           RTS

DOABORTQUOTE: PULS X
              LDB  ,X
              LEAX 1,X
              STX  SPTR
              CLRA
              STD  SCNT
              LDX  SPTR
              LDB  SCNT+1
              LEAX B,X
              PULU D
              CMPD #0
              BNE  AQTHROW
              PSHS X
              RTS
AQTHROW:      LDD  SPTR
              PSHU D
              LDD  SCNT
              PSHU D
              JSR  TYPE
              PSHS X
              LDD  #-2
              PSHU D
              JMP  THROW

ABORTQUOTE: LDD  STATE
            BNE  AQSTOK
            LDD  #-14
            PSHU D
            JSR  THROW
AQSTOK:     LDD  #34
            PSHU D
            JSR  WORD
            PULU X
            LDA  ,X
            STA  SCNT
            LEAX 1,X
            STX  SPTR
            LDD  #DOABORTQUOTE
            PSHU D
            JSR  CCALL
            LDX  CODEHERE
            LDA  SCNT
            STA  ,X+
            LDY  SPTR
            LDB  SCNT
            BEQ  AQEND
AQCPY:      LDA  ,Y+
            STA  ,X+
            DECB
            BNE  AQCPY
AQEND:      STX  CODEHERE
            RTS

BLW:     LDD   #32
         PSHU  D
         RTS

TOINW:   LDD   #TOIN
         PSHU  D
         RTS

SPANW:   LDD   #SPAN
         PSHU  D
         RTS

TIBW:    LDD   #TIBBUF
         PSHU  D
         RTS

NTIBW:   LDD   #NTIB
         PSHU  D
         RTS

; ============================================================
