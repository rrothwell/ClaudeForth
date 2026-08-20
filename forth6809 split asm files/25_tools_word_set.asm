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
         STB   MSCR      ; BUG FIX: STB writes ONE byte, at MSCR
         LDB   MSCR      ; itself - both reads below used to read
         LSRB             ; MSCR+1 instead, a byte this routine never
         LSRB             ; writes at all, so both the high and low
         LSRB             ; nibble extraction ran on whatever stale
         LSRB             ; value happened to be sitting there, not
         CLRA             ; the byte actually passed in. Now reads
         PSHU  D           ; from MSCR, where STB actually put it.
         JSR   HEXDIGIT    ; Confirmed via MAME debugger: DUMP showed
         LDB   MSCR        ; $03 instead of $7B for a memory fill
         ANDB  #$0F        ; character, with the ASCII column (a
         CLRA              ; separate code path) correctly showing
         PSHU  D           ; "}".
         JSR   HEXDIGIT
         RTS

; DUMP - includes the partial-final-line ASCII fix
DUMPW:   PULU  D
         STD   DUMPCNT
         PULU  D
         STD   DUMPADDR
         JSR   CRW        ; FORMATTING: leading CR, so the first line
                          ; starts on its own fresh line - matches
                          ; DULEND's existing trailing CR after every
                          ; line (including the last), giving
                          ; consistent vertical alignment from the
                          ; first line to the last regardless of
                          ; where the cursor was when DUMP was called.
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

