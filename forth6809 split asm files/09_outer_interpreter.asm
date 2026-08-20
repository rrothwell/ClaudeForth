; ============================================================
; SECTION 9: OUTER INTERPRETER (INTERPRET / WORD / FIND / NUMBER?)
; ============================================================
INTERPRET:
ILOOP:   LDD   #32            ; BUG FIX: WORD expects a delimiter char
         PSHU  D              ; pushed by its caller (PULU D/STB DELIM)
                               ; - nothing pushed one here before, so
                               ; WORD pulled from an empty U stack,
                               ; landing on live RSTACK content (SP0 is
                               ; RSTACK's own first byte) instead of a
                               ; real delimiter. Confirmed present in
                               ; both SERIALPOLL branches - IRQH never
                               ; touches U, so interrupt-driven mode
                               ; had no incidental workaround either.
         JSR   WORD
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

IDONE:   PULU  X         ; BUG FIX: WORD always pushes a c-addr (WORDBUF),
                          ; even via its EMPTY branch - this path used to
                          ; branch straight here via a bare peek (LDX ,U,
                          ; never popped), stranding that address on U.
                          ; JSR FIND (the other path) consumes it via its
                          ; own PULU X; this does the same here, matching
                          ; that same convention rather than inventing a
                          ; different one. Confirmed via MAME debugger:
                          ; a spurious WORDBUF address was found sitting
                          ; on top of otherwise-correct stack contents.
         RTS

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
         CMPB  #WORDMAXCHARS  ; REDESIGN: was "CMPB #31", capping WORD
                          ; at 31 characters regardless of what it was
                          ; parsing - a plain word, a defined name, or
                          ; the text of a compiled/interpreted S"
                          ; string, all fed through the same scan.
                          ; That cap came from WORDBUF's own fixed
                          ; 33-byte allocation (1 count byte + 32 data
                          ; bytes, with 1 byte of that never actually
                          ; used by this check), entirely unrelated to
                          ; CODEHERE or PAD. Traced via MAME: a longer
                          ; S" string was truncated during WORD's own
                          ; scan, before either S"'s interpreted-mode
                          ; (PAD) or compiled-mode (CODEHERE) storage
                          ; path ever got a chance to matter - the
                          ; PAD-based S" redesign a few turns ago
                          ; didn't help here because this is an
                          ; earlier stage entirely. Now uses the
                          ; CODEHERE-to-PAD gap directly, matching the
                          ; traditional fig-Forth layout (WORD's own
                          ; buffer at HERE, growing toward PAD, with
                          ; the pictured numeric output buffer at the
                          ; opposite end growing back toward HERE) -
                          ; WORDMAXCHARS reserves HOLDMINSIZE bytes at
                          ; the PAD end for that buffer, so the two
                          ; don't collide even though ANS itself would
                          ; permit them to (3.3.3.6: "the regions
                          ; returned by WORD and #> may overlap in
                          ; memory"). Confirmed via MAME debugger.
         BEQ   ENDW
         LEAX  1,X
         LEAY  -1,Y
         INCB
         BRA   SCANLP

CONSUME: LEAX  1,X
         LEAY  -1,Y
ENDW:    PSHS  B          ; BUG FIX: B holds the true character count from
                          ; SCANLP's own INCB loop, but B is D's low byte -
                          ; TFR X,D below would silently destroy it before
                          ; it's stored as the length byte. Save it here,
                          ; restore it right before STB ,X+. Affects every
                          ; token followed by more input on the same line
                          ; (terminated via CONSUME, not by running out of
                          ; buffer) - the stored length was TOIN's delta
                          ; instead of the true count, one too many (the
                          ; consumed delimiter), so the copy loop below
                          ; would also copy one byte past the token's real
                          ; end. Confirmed via MAME debugger.
         TFR   X,D
         SUBD  SRCADDR
         STD   TOIN
         PULS  B

         LDX   CODEHERE   ; REDESIGN: was "LDX #WORDBUF" - now writes
                          ; at CODEHERE directly (see SCANLP above for
                          ; the full reasoning). CODEHERE itself is
                          ; NOT advanced by this - matches the ANS
                          ; transient-region contract, where WORD's
                          ; region is expected to be overwritten by
                          ; whatever gets compiled/allocated next.
         STB   ,X+
         LDY   WSTART
COPYLP:  TSTB
         BEQ   COPYDONE
         LDA   ,Y+
         STA   ,X+
         DECB
         BRA   COPYLP
COPYDONE: LDX  CODEHERE   ; REDESIGN: was "LDX #WORDBUF", matching
                          ; the copy destination above.
          PSHU X
          RTS

EMPTY:   LDX   CODEHERE   ; REDESIGN: was "LDX #WORDBUF" - same reason.
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

