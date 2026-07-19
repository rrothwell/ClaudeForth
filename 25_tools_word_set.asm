; ============================================================
; 6809 FORTH - 25_tools_word_set
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 25: TOOLS WORD SET (.S / WORDS / DUMP)
; ============================================================
DOTS:    TFR   U,D
         STD   DSPTMP
DSLOOP:  LDD   DSPTMP
         CMPD  #SP0
         BEQ   DSDONE
         LDX   DSPTMP
         LDD   ,X
         PSHU  D
         JSR   DOT
         LDD   DSPTMP
         ADDD  #2
         STD   DSPTMP
         BRA   DSLOOP
DSDONE:  RTS

WORDSW:  LDD   LATEST
         STD   WWALK
WWLOOP:  LDD   WWALK
         BEQ   WWDONE
         LDX   WWALK
         LDA   ,X
         STA   HDRFLAGS
         LEAX  1,X
         PSHU  X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         PSHU  D
         JSR   TYPE
         JSR   SPACEW
         LDX   WWALK
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LDD   ,X
         STD   WWALK
         BRA   WWLOOP
WWDONE:  JSR   CRW
         RTS

HEXDIGIT: PULU D
          CMPD #10
          BLO  HDDIGIT
          ADDD #'A'-10
          BRA  HDEMIT
HDDIGIT:  ADDD #'0'
HDEMIT:   PSHU D
          JSR  EMIT
          RTS

HEXBYTE: PULU  D
         STB   MSCR
         LDB   MSCR+1
         LSRB
         LSRB
         LSRB
         LSRB
         CLRA
         PSHU  D
         JSR   HEXDIGIT
         LDB   MSCR+1
         ANDB  #$0F
         CLRA
         PSHU  D
         JSR   HEXDIGIT
         RTS

; DUMP - includes the partial-final-line ASCII fix
DUMPW:   PULU  D
         STD   DUMPCNT
         PULU  D
         STD   DUMPADDR
DULINE:  LDD   DUMPCNT
         LBEQ  DUDONE          ; was BEQ - out of short-branch range
         LDD   DUMPADDR
         STD   HEXBUF
         CLR   DUMPCOL
         LDA   #16
         STA   DUVALID
DUHEX:   LDB   DUMPCOL
         CMPB  #16
         BEQ   DUASCII
         LDD   DUMPCNT
         BNE   DUHEXBYTE
         LDA   DUMPCOL
         STA   DUVALID
         BRA   DUHEXPAD
DUHEXBYTE: LDX  DUMPADDR
           LDB  ,X
           CLRA
           PSHU D
           JSR  HEXBYTE
           LDD  #32
           PSHU D
           JSR  EMIT
           LDX  DUMPADDR
           LEAX 1,X
           STX  DUMPADDR
           LDD  DUMPCNT
           SUBD #1
           STD  DUMPCNT
           INC  DUMPCOL
           BRA  DUHEX
DUHEXPAD: LDD  #32
          PSHU D
          JSR  EMIT
          PSHU D
          JSR  EMIT
          PSHU D
          JSR  EMIT
          INC  DUMPCOL
          LDB  DUMPCOL
          CMPB #16
          BNE  DUHEXPAD
          BRA  DUASCII
DUASCII: LDD  #32
         PSHU D
         JSR  EMIT
         CLR  DUMPCOL
DUACHAR: LDB  DUMPCOL
         CMPB #16
         BEQ  DULEND
         CMPB DUVALID
         BHS  DUABLANK
         LDX  HEXBUF
         LDB  DUMPCOL
         CLRA
         LEAX D,X
         LDA  ,X
         CMPA #32
         BLO  DUDOT
         CMPA #127
         BHS  DUDOT
         BRA  DUPRINT
DUDOT:   LDA  #'.'
DUPRINT: TFR  A,B
         CLRA
         PSHU D
         JSR  EMIT
         INC  DUMPCOL
         BRA  DUACHAR
DUABLANK: LDD #32
          PSHU D
          JSR EMIT
          INC DUMPCOL
          BRA DUACHAR
DULEND:  JSR  CRW
         LDD  DUMPCNT
         LBNE DULINE           ; was BNE - out of short-branch range
DUDONE:  RTS

; ============================================================
