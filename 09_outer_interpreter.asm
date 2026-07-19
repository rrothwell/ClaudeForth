; ============================================================
; 6809 FORTH - 09_outer_interpreter
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 9: OUTER INTERPRETER (INTERPRET / WORD / FIND / NUMBER?)
; ============================================================
INTERPRET:
ILOOP:   JSR   WORD
         LDX   ,U
         LDA   ,X
         BEQ   IDONE

         JSR   FIND
         PULU  D
         TSTB
         LBEQ  TRYNUM

         LDA   STATE+1
         BEQ   DOEXEC
         TSTB
         BPL   DOEXEC
         JSR   CCALL
         BRA   ILOOP

DOEXEC:  JSR   EXECUTE
         BRA   ILOOP

TRYNUM:  JSR   NUMBERQ
         PULU  D
         CMPD  #0            ; was TSTD (6309-only) - PULU doesn't set CC on
                              ; genuine 6809, so compare D against 0 directly
         BEQ   BADWORD

         LDD   STATE
         BEQ   ILOOP
         LDD   #LIT
         PSHU  D
         JSR   CCALL
         JSR   CODECOMMA
         BRA   ILOOP

BADWORD: JSR   COUNT
         JSR   TYPE
         LDD   #-13
         PSHU  D
         JSR   THROW

IDONE:   RTS

WORD:    PULU  D
         STB   DELIM
         LDD   TOIN
         LDX   SRCADDR
         LEAX  D,X
         LDD   SRCLEN
         SUBD  TOIN
         TFR   D,Y

SKIPLP:  CMPY  #0
         BEQ   EMPTY
         LDA   ,X
         CMPA  DELIM
         BNE   STARTW
         LEAX  1,X
         LEAY  -1,Y
         BRA   SKIPLP

STARTW:  STX   WSTART
         LDB   #0

SCANLP:  CMPY  #0
         BEQ   ENDW
         LDA   ,X
         CMPA  DELIM
         BEQ   CONSUME
         CMPB  #31
         BEQ   ENDW
         LEAX  1,X
         LEAY  -1,Y
         INCB
         BRA   SCANLP

CONSUME: LEAX  1,X
         LEAY  -1,Y
ENDW:    TFR   X,D
         SUBD  SRCADDR
         STD   TOIN

         LDX   #WORDBUF
         STB   ,X+
         LDY   WSTART
COPYLP:  TSTB
         BEQ   COPYDONE
         LDA   ,Y+
         STA   ,X+
         DECB
         BRA   COPYLP
COPYDONE: LDX  #WORDBUF
          PSHU X
          RTS

EMPTY:   LDX   #WORDBUF
         CLR   ,X
         PSHU  X
         RTS

FIND:    PULU  X
         LDA   ,X
         STA   SLEN
         LEAX  1,X
         STX   SNAMEP

         LDD   LATEST
         STD   FNDPTR

FFLOOP:  LDD   FNDPTR
         BEQ   NOTFOUND
         STD   HDRPTR
         TFR   D,X
         LDA   ,X
         STA   HDRFLAGS
         BITA  #$40
         BNE   FNEXT
         ANDA  #$1F
         CMPA  SLEN
         BNE   FNEXT
         LEAX  1,X
         LDY   SNAMEP
         LDB   SLEN
         BEQ   FMATCH
CMPLP:   LDA   ,X+
         CMPA  ,Y+
         BNE   FNEXT
         DECB
         BNE   CMPLP

FMATCH:  LDX   HDRPTR
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LEAX  2,X
         LDD   ,X
         PSHU  D
         LDA   HDRFLAGS
         BITA  #$80
         BEQ   FISNORM
         LDD   #1
         BRA   FPUSH
FISNORM: LDD   #-1
FPUSH:   PSHU  D
         RTS

FNEXT:   LDX   HDRPTR
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LDD   ,X
         STD   FNDPTR
         BRA   FFLOOP

NOTFOUND: LDX  SNAMEP
          LEAX -1,X
          PSHU X
          LDD  #0
          PSHU D
          RTS

UDMULADD: STB  CARRY
          LDA  BASE+1
          STA  MULBASE
          LDA  UDLO+1
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM0
          INCA
UM0:      STB  UDLO+1
          STA  CARRY
          LDA  UDLO
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM1
          INCA
UM1:      STB  UDLO
          STA  CARRY
          LDA  UDHI+1
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM2
          INCA
UM2:      STB  UDHI+1
          STA  CARRY
          LDA  UDHI
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM3
          INCA
UM3:      STB  UDHI
          RTS

NUMLOOP: LDD   NCNT
         BEQ   NLDONE
         LDX   NADDR
         LDA   ,X
         CMPA  #'0'
         BLO   NLDONE
         CMPA  #'9'
         BHI   NLALPHA
         SUBA  #'0'
         BRA   NLGOT
NLALPHA: ANDA  #$DF
         CMPA  #'A'
         BLO   NLDONE
         CMPA  #'Z'
         BHI   NLDONE
         SUBA  #'A'-10
NLGOT:   CMPA  BASE+1
         BHS   NLDONE
         TFR   A,B
         JSR   UDMULADD
         LDX   NADDR
         LEAX  1,X
         STX   NADDR
         LDD   NCNT
         SUBD  #1
         STD   NCNT
         BRA   NUMLOOP
NLDONE:  RTS

TONUMBER: PULU D
          STD  NCNT
          PULU D
          STD  NADDR
          PULU D
          STD  UDHI
          PULU D
          STD  UDLO
          JSR  NUMLOOP
          LDD  UDLO
          PSHU D
          LDD  UDHI
          PSHU D
          LDX  NADDR
          PSHU X
          LDD  NCNT
          PSHU D
          RTS

NUMBERQ: PULU  X
         STX   CADDR
         LDA   ,X
         BEQ   NQBAD
         STA   CNTREM
         LEAX  1,X

         CLR   NUMNEG
         LDA   ,X
         CMPA  #'-'
         BNE   NQNOSIGN
         COM   NUMNEG
         LEAX  1,X
         DEC   CNTREM
         BEQ   NQBAD

NQNOSIGN: STX  NADDR
          CLRA
          LDB   CNTREM
          STD   NCNT
          LDD   #0
          STD   UDHI
          STD   UDLO

          JSR   NUMLOOP

          LDD   NCNT
          BNE   NQBAD

          LDD   UDLO
          TST   NUMNEG
          BEQ   NQPOS
          COMA
          COMB
          ADDD  #1
NQPOS:    PSHU  D
          LDD   #-1
          PSHU  D
          RTS

NQBAD:    LDX   CADDR
          PSHU  X
          LDD   #0
          PSHU  D
          RTS

; ============================================================
