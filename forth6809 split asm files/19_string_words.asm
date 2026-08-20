; ============================================================
; SECTION 19: STRING WORDS
; ============================================================
DOSTR:   PULS  X
         LDB   ,X
         LEAX  1,X
         PSHU  X
         CLRA
         PSHU  D
         LEAX  B,X
         PSHS  X
         RTS

SQUOTE:  LDD   #34
         PSHU  D
         LDD   CODEHERE   ; BUG FIX (caught while verifying the WORD
         ADDD  #3         ; redesign above): reserve 3 bytes ahead of
         STD   CODEHERE   ; where WORD is about to write its parsed
                          ; text. Without this, the compiled path
                          ; below would compile "JSR DOSTR" (3 bytes)
                          ; directly at CODEHERE - the same address
                          ; WORD just used - overwriting the first 2
                          ; characters of the very text being staged,
                          ; before the copy loop even runs. Reserving
                          ; the gap first means the text lands exactly
                          ; where it needs to end up, and the trampoline
                          ; safely goes in front of it instead of on
                          ; top of it.
         JSR   WORD
         PULU  X
         LDA   ,X
         STA   SCNT
         LEAX  1,X
         STX   SPTR
         LDD   CODEHERE   ; restore - undo the temporary reserve
         SUBD  #3
         STD   CODEHERE
         LDD   STATE
         BEQ   SQINTERP

         LDD   #DOSTR
         PSHU  D
         JSR   CCALL
         LDX   CODEHERE
         LDA   SCNT
         STA   ,X+
         LDY   SPTR
         LDB   SCNT
         BEQ   SQEND
SQCPY:   LDA   ,Y+
         STA   ,X+
         DECB
         BNE   SQCPY
SQEND:   STX   CODEHERE
         RTS

SQINTERP: ; REDESIGN: was a fixed "LDX #SIBUF" here and at SQIEND -
                          ; SIBUF was a dedicated, fixed 32-byte buffer,
                          ; capping every interpreted S" string at 32
                          ; characters and (worse) shared identically
                          ; by every S" call, so a second S" call before
                          ; the first string was actually used (e.g.
                          ; registering two REPLACES strings, or a
                          ; SUBSTITUTE template argument) silently
                          ; overwrote the first - confirmed via MAME
                          ; testing and traced precisely earlier this
                          ; session. Retired per user's own follow-up
                          ; testing/design decision: rather than give
                          ; REPLACES its own dedicated copy-on-register
                          ; storage, wrap each string in its own colon
                          ; definition for stable storage instead - but
                          ; that still leaves interpreted S" itself
                          ; capped at SIBUF's 32 characters for any
                          ; single string. Now computes PAD's current
                          ; address fresh via PADW (dynamic - depends
                          ; on CODEHERE, per ANS's own transient-region
                          ; semantics) and writes there instead, giving
                          ; interpreted S" access to PAD's full
                          ; PADMINSIZE-character region (84, comfortably
                          ; above the old 32-character SIBUF limit) -
                          ; SIBUF itself is now unused and retired (see
                          ; the GLOBALS layout notes above).
          JSR  PADW
          PULU X
          STX  MSCR4        ; save PAD's own address - X gets advanced
                             ; by the copy loop below, need the
                             ; original back for the return value
          LDY  SPTR
          LDB  SCNT
          BEQ  SQIEND
SQICPY:   LDA  ,Y+
          STA  ,X+
          DECB
          BNE  SQICPY
SQIEND:   LDX  MSCR4
          PSHU X
          CLRA
          LDB  SCNT
          PSHU D
          RTS

DOTSTR:  PULS  X
         LDB   ,X
         LEAX  1,X
         STX   SPTR
         CLRA
         STD   SCNT
         LEAX  B,X
         PSHS  X
         LDX   SPTR
         PSHU  X
         LDD   SCNT
         PSHU  D
         JSR   TYPE
         RTS

DOTQUOTE: LDD  #34
          PSHU D
          LDD  CODEHERE   ; BUG FIX: same class as SQUOTE above -
          ADDD #3         ; reserve 3 bytes ahead of WORD's write so
          STD  CODEHERE   ; the trampoline compiled below doesn't
                          ; overwrite the text it's about to stage.
          JSR  WORD
          PULU X
          LDA  ,X
          STA  SCNT
          LEAX 1,X
          STX  SPTR
          LDD  CODEHERE   ; restore
          SUBD #3
          STD  CODEHERE
          LDD  #DOTSTR
          PSHU D
          JSR  CCALL
          LDX  CODEHERE
          LDA  SCNT
          STA  ,X+
          LDY  SPTR
          LDB  SCNT
          BEQ  DQEND
DQCPY:    LDA  ,Y+
          STA  ,X+
          DECB
          BNE  DQCPY
DQEND:    STX  CODEHERE
          RTS

TYPE:    PULU  D
         STD   TYPECNT
         PULU  D
         STD   TYPEADDR
TYLOOP:  LDD   TYPECNT
         BEQ   TYDONE
         LDX   TYPEADDR
         LDA   ,X+
         STX   TYPEADDR
         TFR   A,B
         CLRA
         PSHU  D
         JSR   EMIT
         LDD   TYPECNT
         SUBD  #1
         STD   TYPECNT
         BRA   TYLOOP
TYDONE:  RTS

COUNT:   PULU  X
         LDB   ,X
         CLRA
         STD   MSCR
         LEAX  1,X
         PSHU  X
         LDD   MSCR
         PSHU  D
         RTS

CHARW:   LDD   #32
         PSHU  D
         JSR   WORD
         PULU  X
         LDB   1,X
         CLRA
         PSHU  D
         RTS

BRACKCHAR: LDD  STATE
           BNE  BCSTOK
           LDD  #-14
           PSHU D
           JSR  THROW
BCSTOK:    LDD  #32
           PSHU D
           JSR  WORD
           PULU X
           LDB  1,X
           CLRA
           PSHU D
           JSR  LITERALW
           RTS

PARSEW:  PULU  D
         STB   PDELIM
         LDD   TOIN
         LDX   SRCADDR
         LEAX  D,X
         STX   PSTART
         LDD   SRCLEN
         SUBD  TOIN
         TFR   D,Y
         LDD   #0
         STD   PLEN
PSCAN:   CMPY  #0
         BEQ   PDONE
         LDA   ,X
         CMPA  PDELIM
         BEQ   PFOUND
         LEAX  1,X
         LEAY  -1,Y
         LDD   PLEN
         ADDD  #1
         STD   PLEN
         BRA   PSCAN
PFOUND:  LEAX  1,X
         LEAY  -1,Y
PDONE:   TFR   X,D
         SUBD  SRCADDR
         STD   TOIN
         LDX   PSTART
         PSHU  X
         LDD   PLEN
         PSHU  D
         RTS

PARSENAME: LDD  TOIN
           LDX  SRCADDR
           LEAX D,X
           LDD  SRCLEN
           SUBD TOIN
           TFR  D,Y
PNSKIP:    CMPY #0
           BEQ  PNEMPTY
           LDA  ,X
           CMPA #32
           BNE  PNSTART
           LEAX 1,X
           LEAY -1,Y
           BRA  PNSKIP
PNSTART:   STX  PSTART
           LDD  #0
           STD  PLEN
PNSCAN:    CMPY #0
           BEQ  PNDONE
           LDA  ,X
           CMPA #32
           BEQ  PNFOUND
           LEAX 1,X
           LEAY -1,Y
           LDD  PLEN
           ADDD #1
           STD  PLEN
           BRA  PNSCAN
PNFOUND:   LEAX 1,X
           LEAY -1,Y
PNDONE:    TFR  X,D
           SUBD SRCADDR
           STD  TOIN
           LDX  PSTART
           PSHU X
           LDD  PLEN
           PSHU D
           RTS
PNEMPTY:   LDD  SRCLEN
           LDX  SRCADDR
           LEAX D,X
           STD  TOIN
           PSHU X
           LDD  #0
           PSHU D
           RTS

SLASHSTRING: PULU D
             STD  MSCR
             PULU D
             SUBD MSCR
             STD  MSCR2
             PULU D
             ADDD MSCR
             PSHU D
             LDD  MSCR2
             PSHU D
             RTS

DASHTRAILING: LDD  ,U
              STD  PLEN
DTLOOP:       LDD  PLEN
              BEQ  DTDONE
              LDX  2,U
              LEAX D,X
              LEAX -1,X
              LDA  ,X
              CMPA #32
              BNE  DTDONE
              LDD  PLEN
              SUBD #1
              STD  PLEN
              BRA  DTLOOP
DTDONE:       LDD  PLEN
              STD  ,U
              RTS

COMPAREW: PULU D
          STD  CMPL2
          PULU D
          STD  CMPA2
          PULU D
          STD  CMPL1
          PULU D
          STD  CMPA1
          LDD  CMPL1
          CMPD CMPL2
          BLS  CMMINIS1
          LDD  CMPL2
          BRA  CMMINSET
CMMINIS1: LDD  CMPL1
CMMINSET: STD  CMPMIN
          LDX  CMPA1
          LDY  CMPA2
CMPLOOP:  LDD  CMPMIN
          BEQ  CMTIEBREAK
          LDA  ,X+
          CMPA ,Y
          BLO  CMLT
          BHI  CMGT
          LEAY 1,Y
          LDD  CMPMIN
          SUBD #1
          STD  CMPMIN
          BRA  CMPLOOP
CMTIEBREAK: LDD CMPL1
            CMPD CMPL2
            BLO  CMLT
            BHI  CMGT
            LDD  #0
            PSHU D
            RTS
CMLT:     LDD  #-1
          PSHU D
          RTS
CMGT:     LDD  #1
          PSHU D
          RTS

SEARCHW: PULU  D
         STD   SRCH2L
         PULU  D
         STD   SRCH2
         PULU  D
         STD   SRCH1L
         PULU  D
         STD   SRCH1
         LDD   SRCH2L
         BEQ   SRCHNOTFOUND
         LDD   SRCH1L
         SUBD  SRCH2L
         BLT   SRCHNOTFOUND
         ADDD  #1
         STD   SRCHPOS
         LDD   #0
         STD   SRCHI
SPOSLOOP: LDD  SRCHI
          CMPD SRCHPOS
          BEQ  SRCHNOTFOUND
          LDX  SRCH1
          LDD  SRCHI
          LEAX D,X
          LDY  SRCH2
          LDD  SRCH2L
          STD  MSCR3
SMATCH:   LDD  MSCR3
          BEQ  SFOUND
          LDA  ,X+
          CMPA ,Y+
          BNE  SNOMATCH
          LDD  MSCR3
          SUBD #1
          STD  MSCR3
          BRA  SMATCH
SNOMATCH: LDD  SRCHI
          ADDD #1
          STD  SRCHI
          BRA  SPOSLOOP
SFOUND:   LDX  SRCH1
          LDD  SRCHI
          LEAX D,X
          PSHU X
          LDD  SRCH2L
          PSHU D
          LDD  #TRUEV
          PSHU D
          RTS
SRCHNOTFOUND: LDD SRCH1
              PSHU D
              LDD  SRCH1L
              PSHU D
              LDD  #FALSEV
              PSHU D
              RTS

SNAMEW:  PULU  D
         STD   SNTARGET
         LDD   LATEST
         STD   SNXT
SNLOOP:  LDD   SNXT
         BEQ   SNNOTFOUND
         LDX   SNXT
         LDA   ,X
         STA   HDRFLAGS
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LEAX  2,X
         LDD   ,X
         CMPD  SNTARGET
         BEQ   SNFOUND
         LDX   SNXT
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LDD   ,X
         STD   SNXT
         BRA   SNLOOP
SNFOUND: LDX   SNXT
         LEAX  1,X
         PSHU  X
         LDX   SNXT
         LDA   ,X
         ANDA  #$1F
         CLRB
         TFR   A,B
         CLRA
         PSHU  D
         RTS
SNNOTFOUND: LDD #0
            PSHU D
            PSHU D
            RTS

UNESCAPEW: PULU D        ; BUG FIX: was PULU D/STD UESRCLEN (storing
           STD  UEDST     ; the popped dest-addr into the SOURCE-
                          ; length variable), then LDD ,U (a PEEK, not
                          ; a pop) into BOTH UEADDR and UEDST - so the
                          ; real source length was misread as an
                          ; address, the real source address was never
                          ; popped at all, and the true destination
                          ; address never reached UEDST. Correct
                          ; ANS order is ( c-addr1 u1 c-addr2 -- ):
                          ; c-addr2 (dest) is on top, popped first.
           PULU D         ; next: u1 (source length)
           STD  UESRCLEN
           PULU D         ; next: c-addr1 (source address)
           STD  UEADDR
           LDD  #0
           STD  UEOUTLEN
           LDX  UEADDR
           LDY  UEDST

           ; ALGORITHM REPLACED (caught by MAME testing after the
           ; argument-order fix above): the entire body below used
           ; to decode backslash escape sequences (\n, \t, \\, \") -
           ; a plausible-looking but entirely wrong reading of what
           ; ANS UNESCAPE does. Confirmed against the actual spec and
           ; its canonical reference implementation (forth-standard.
           ; org/standard/string/UNESCAPE and complang.tuwien.ac.at's
           ; ANS Forth reference text): UNESCAPE has nothing to do
           ; with backslash sequences at all - it replaces every '%'
           ; character with two '%' characters, and nothing else, so
           ; that a literal '%' in text survives an eventual
           ; SUBSTITUTE pass unchanged ("If you pass a string through
           ; UNESCAPE and then SUBSTITUTE, you get the original
           ; string"). Every character that ISN'T '%' passes straight
           ; through, one-for-one. Confirmed via MAME: doubling a
           ; single '%' wasn't happening at all, and the returned
           ; count didn't grow to reflect the added characters -
           ; both are direct, expected consequences of this being the
           ; wrong algorithm entirely, not a smaller bug within it.
UELOOP:    LDD  UESRCLEN
           BEQ  UEDONE
           LDA  ,X+
           CMPA #'%'
           BNE  UENOTPCT
           LDB  #'%'      ; write the extra '%' first - the character
           STB  ,Y+       ; itself still gets written once more below,
                          ; giving two '%' total for each one in the
                          ; source. Handles multiple '%' characters in
                          ; the same string correctly, since this runs
                          ; independently for each one the loop visits.
UENOTPCT:  STA  ,Y+       ; write the actual character - always, for
                          ; every character, '%' or not
           LDD  UESRCLEN
           SUBD #1
           STD  UESRCLEN
           BRA  UELOOP
UEDONE:    TFR  Y,D       ; BUG FIX: was "LDD UEOUTLEN / STD ,U" -
           SUBD UEDST     ; overwriting whatever was left on top of
           STD  UEOUTLEN  ; the stack rather than pushing both
                          ; required return values, and separately,
                          ; UEOUTLEN itself was never correctly
                          ; tracked by the old backslash-decoding
                          ; loop's own per-character bookkeeping in a
                          ; way that accounted for doubled '%'
                          ; characters. Now computed directly as the
                          ; final write pointer (Y) minus the
                          ; original destination address (UEDST) -
                          ; correct regardless of how many characters
                          ; were doubled, since it's derived from
                          ; where writing actually stopped rather than
                          ; incremented alongside it.
           LDD  UEDST
           PSHU D         ; push c-addr2 (destination address)
           LDD  UEOUTLEN
           PSHU D         ; push u2 (actual unescaped length)
           RTS

; REPLACES/SUBSTITUTE - single-slot simplified version, per
; the explicit scoping-down discussed in the source conversation
REPLACESW: PULU D
           STD  REPLNLEN
           PULU D
           STD  REPLNAME
           PULU D
           STD  REPLVLEN
           PULU D
           STD  REPLVAL
           RTS

SUBCOPY: STD  SUBCOPYCNT
         STX  SUBCOPYSRC
SUBCPLP: LDD  SUBCOPYCNT
         BEQ  SUBCPDONE
         LDD  SUBOUTLEN
         CMPD SUBDESTCAP
         LBHS SUBOVERFLOW      ; was BHS - out of short-branch range
         LDX  SUBCOPYSRC
         LDA  ,X+
         STX  SUBCOPYSRC
         LDY  SUBWPTR
         STA  ,Y+
         STY  SUBWPTR
         LDD  SUBOUTLEN
         ADDD #1
         STD  SUBOUTLEN
         LDD  SUBCOPYCNT
         SUBD #1
         STD  SUBCOPYCNT
         BRA  SUBCPLP
SUBCPDONE: RTS

SUBSTITUTEW: ; REWRITE: was a plain substring search-and-replace on
             ; the bare registered name (via SEARCHW), which found
             ; "girl" and replaced only that span, leaving surrounding
             ; "%...%" delimiters untouched in the output - and never
             ; returned the substitution count ANS requires as a
             ; third stack item. Per the ANS spec (forth-standard.org/
             ; standard/string/SUBSTITUTE), SUBSTITUTE must scan for
             ; text between '%' (ASCII $25) delimiter pairs
             ; specifically: "%%" collapses to a single '%' (count
             ; unchanged); a name matching the REPLACES registration
             ; has the ENTIRE "%name%" span - delimiters included -
             ; replaced by the substitution text (count incremented);
             ; a non-matching name is passed through unchanged,
             ; delimiters and all (count unchanged); an unpaired
             ; trailing '%' with no closing delimiter passes the
             ; residue through unchanged. Confirmed via MAME testing
             ; against a real template. GLOBALS is fully packed
             ; (256/256), so this reuses MSCR/MSCR2/MSCR3/MSCR4
             ; (confirmed untouched by SUBCOPY) rather than adding
             ; dedicated cells: MSCR = current read position, MSCR2 =
             ; running substitution count, MSCR3/MSCR4 = local scratch
             ; per %-pair found. Reuses the existing COMPAREW for name
             ; matching rather than a new comparison loop.
             PULU D
             STD  SUBDESTCAP
             PULU D
             STD  SUBDESTADR
             PULU D
             STD  SUBSRCLEN
             PULU D
             STD  SUBSRCADR

             LDY  SUBDESTADR
             STY  SUBWPTR
             LDD  #0
             STD  SUBOUTLEN
             STD  MSCR        ; read position, starts at 0
             STD  MSCR2       ; substitution count, starts at 0

SUBSCAN:     LDD  MSCR
             CMPD SUBSRCLEN
             LBHS SUBSDONE
             LDX  SUBSRCADR
             LEAX D,X
             LDA  ,X
             CMPA #$25         ; '%' delimiter
             BEQ  SUBPCT
             LDD  #1
             JSR  SUBCOPY
             LDD  MSCR
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBPCT:      LDD  MSCR
             ADDD #1
             STD  MSCR3        ; scan for the closing '%'
SUBFINDCL:   LDD  MSCR3
             CMPD SUBSRCLEN
             BLO  SUBFC2
             ; no closing delimiter found - residue passed unchanged
             LDD  MSCR
             LDX  SUBSRCADR
             LEAX D,X
             LDD  SUBSRCLEN
             SUBD MSCR
             JSR  SUBCOPY
             LDD  SUBSRCLEN
             STD  MSCR
             LBRA SUBSCAN
SUBFC2:      LDD  MSCR3
             LDX  SUBSRCADR
             LEAX D,X
             LDA  ,X
             CMPA #$25
             BEQ  SUBFOUNDCL
             LDD  MSCR3
             ADDD #1
             STD  MSCR3
             LBRA SUBFINDCL

SUBFOUNDCL:  LDD  MSCR3
             SUBD MSCR
             SUBD #1
             STD  MSCR4         ; enclosed name length
             LBNE SUBHASNAME
             ; namelen 0: "%%" -> single '%' to output, count unchanged
             LDD  MSCR
             LDX  SUBSRCADR
             LEAX D,X
             LDD  #1
             JSR  SUBCOPY
             LDD  MSCR3
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBHASNAME:  LDD  MSCR
             ADDD #1
             LDX  SUBSRCADR
             LEAX D,X
             PSHU X
             LDD  MSCR4
             PSHU D
             LDD  REPLNAME
             PSHU D
             LDD  REPLNLEN
             PSHU D
             JSR  COMPAREW
             PULU D
             CMPD #0
             BNE  SUBNOMATCH
             ; valid name - replace the whole %name% span
             LDX  REPLVAL
             LDD  REPLVLEN
             JSR  SUBCOPY
             LDD  MSCR2
             ADDD #1
             STD  MSCR2
             LDD  MSCR3
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBNOMATCH:  ; not a registered name - pass %name% through unchanged
             LDD  MSCR
             LDX  SUBSRCADR
             LEAX D,X
             LDD  MSCR3
             SUBD MSCR
             ADDD #1
             JSR  SUBCOPY
             LDD  MSCR3
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBSDONE:    LDX  SUBDESTADR
             PSHU X
             LDD  SUBOUTLEN
             PSHU D
             LDD  MSCR2
             PSHU D
             RTS

SUBOVERFLOW: LDD #-1
             PSHU D
             JSR  THROW

