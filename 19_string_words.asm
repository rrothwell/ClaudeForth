; ============================================================
; 6809 FORTH - 19_string_words
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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
         JSR   WORD
         PULU  X
         LDA   ,X
         STA   SCNT
         LEAX  1,X
         STX   SPTR
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

SQINTERP: LDY  SPTR
          LDB  SCNT
          LDX  #SIBUF
          BEQ  SQIEND
SQICPY:   LDA  ,Y+
          STA  ,X+
          DECB
          BNE  SQICPY
SQIEND:   LDX  #SIBUF
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
          JSR  WORD
          PULU X
          LDA  ,X
          STA  SCNT
          LEAX 1,X
          STX  SPTR
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

UNESCAPEW: PULU D
           STD  UESRCLEN
           LDD  ,U
           STD  UEADDR
           STD  UEDST
           LDD  #0
           STD  UEOUTLEN
           LDX  UEADDR
           LDY  UEDST
UELOOP:    LDD  UESRCLEN
           BEQ  UEDONE
           LDA  ,X+
           CMPA #'\'
           BNE  UEPLAIN
           LDD  UESRCLEN
           SUBD #1
           STD  UESRCLEN
           BEQ  UEPLAIN
           LDA  ,X+
           CMPA #'n'
           BNE  UECKT
           LDA  #10
           BRA  UEEMIT
UECKT:     CMPA #'t'
           BNE  UECKBS
           LDA  #9
           BRA  UEEMIT
UECKBS:    CMPA #'\'
           BEQ  UEEMIT
           CMPA #'"'
           BEQ  UEEMIT
           PSHS A
           LDA  #'\'
           STA  ,Y+
           LDD  UEOUTLEN
           ADDD #1
           STD  UEOUTLEN
           PULS A
UEEMIT:    STA  ,Y+
           LDD  UEOUTLEN
           ADDD #1
           STD  UEOUTLEN
           LDD  UESRCLEN
           SUBD #1
           STD  UESRCLEN
           BRA  UELOOP
UEPLAIN:   STA  ,Y+
           LDD  UEOUTLEN
           ADDD #1
           STD  UEOUTLEN
           LDD  UESRCLEN
           SUBD #1
           STD  UESRCLEN
           BRA  UELOOP
UEDONE:    LDD  UEOUTLEN
           STD  ,U
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

SUBSTITUTEW: PULU D
             STD  SUBDESTCAP
             PULU D
             STD  SUBDESTADR
             PULU D
             STD  SUBSRCLEN
             PULU D
             STD  SUBSRCADR

             LDD  SUBSRCADR
             PSHU D
             LDD  SUBSRCLEN
             PSHU D
             LDD  REPLNAME
             PSHU D
             LDD  REPLNLEN
             PSHU D
             JSR  SEARCHW
             PULU D
             CMPD #0
             BEQ  SUBNOTFOUND
             PULU D
             PULU D
             STD  MSCR4

             LDY  SUBDESTADR
             STY  SUBWPTR
             LDD  #0
             STD  SUBOUTLEN

             LDD  MSCR4
             SUBD SUBSRCADR
             STD  MSCR3
             LDX  SUBSRCADR
             LDD  MSCR3
             JSR  SUBCOPY

             LDX  REPLVAL
             LDD  REPLVLEN
             JSR  SUBCOPY

             LDD  MSCR4
             ADDD REPLNLEN
             STD  MSCR2
             LDD  SUBSRCLEN
             SUBD MSCR3
             SUBD REPLNLEN
             STD  MSCR
             LDX  MSCR2
             LDD  MSCR
             JSR  SUBCOPY

             LDX  SUBDESTADR
             PSHU X
             LDD  SUBOUTLEN
             PSHU D
             RTS

SUBNOTFOUND: LDY SUBDESTADR
             STY SUBWPTR
             LDD #0
             STD SUBOUTLEN
             LDX SUBSRCADR
             LDD SUBSRCLEN
             JSR SUBCOPY
             LDX SUBDESTADR
             PSHU X
             LDD SUBOUTLEN
             PSHU D
             RTS

SUBOVERFLOW: LDD #-1
             PSHU D
             JSR  THROW

; ============================================================
