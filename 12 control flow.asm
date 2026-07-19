; ============================================================
; 6809 FORTH - 12_control_flow
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 12: CONTROL FLOW (IF/THEN/ELSE, BEGIN family,
; DO/LOOP/+LOOP/I/J/LEAVE/UNLOOP/?DO, EXIT, CASE family)
; ============================================================
PATCH:   PULU  D
         STD   PFIELD
         PULU  D
         STD   PTARGET
         LDD   PTARGET
         SUBD  PFIELD
         LDX   PFIELD
         STD   ,X
         RTS

IF:      LDD   #ZBRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         PSHU  D
         LDD   #TAGFWD
         PSHU  D
         RTS

THEN:    PULU  D
         CMPD  #TAGFWD
         BEQ   THOK
         JSR   CFERR
THOK:    PULU  X
         LDD   CODEHERE
         PSHU  D
         PSHU  X
         JSR   PATCH
         RTS

ELSE:    PULU  D
         CMPD  #TAGFWD
         BEQ   ELOK
         JSR   CFERR
ELOK:    PULU  X
         LDD   #BRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   NEWFLD
         LDD   CODEHERE
         PSHU  D
         PSHU  X
         JSR   PATCH
         LDD   NEWFLD
         PSHU  D
         LDD   #TAGFWD
         PSHU  D
         RTS

BEGIN:   LDD   CODEHERE
         PSHU  D
         LDD   #TAGBACK
         PSHU  D
         RTS

UNTIL:   PULU  D
         CMPD  #TAGBACK
         BEQ   UNOK
         JSR   CFERR
UNOK:    PULU  X
         LDD   #ZBRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         TFR   X,D
         PSHU  D
         LDD   PFIELD
         PSHU  D
         JSR   PATCH
         RTS

AGAIN:   PULU  D
         CMPD  #TAGBACK
         BEQ   AGOK
         JSR   CFERR
AGOK:    PULU  X
         LDD   #BRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         TFR   X,D
         PSHU  D
         LDD   PFIELD
         PSHU  D
         JSR   PATCH
         RTS

WHILE:   LDD   #ZBRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         PSHU  D
         LDD   #TAGFWD
         PSHU  D
         RTS

REPEAT:  PULU  D
         CMPD  #TAGFWD
         BEQ   RPOK1
         JSR   CFERR
RPOK1:   PULU  X
         STX   NEWFLD
         PULU  D
         CMPD  #TAGBACK
         BEQ   RPOK2
         JSR   CFERR
RPOK2:   PULU  X
         LDD   #BRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         TFR   X,D
         PSHU  D
         LDD   PFIELD
         PSHU  D
         JSR   PATCH
         LDD   CODEHERE
         PSHU  D
         LDD   NEWFLD
         PSHU  D
         JSR   PATCH
         RTS

RECURSE: LDX   LATEST
         LDA   ,X
         STA   HDRFLAGS
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LEAX  2,X
         LDD   ,X
         PSHU  D
         JSR   CCALL
         RTS

DO:      LDD   #DOSETUP
         PSHU  D
         JSR   CCALL
         LDD   CODEHERE
         PSHU  D
         LDD   #TAGDO
         PSHU  D
         RTS

DOSETUP: PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULS  X
         LDD   #0
         PSHS  D
         LDD   MSCR2
         PSHS  D
         LDD   MSCR
         PSHS  D
         PSHS  X
         RTS

IWORD:   PULS  X
         LDD   2,S
         PSHS  X
         PSHU  D
         RTS

JWORD:   PULS  X
         LDD   10,S
         PSHS  X
         PSHU  D
         RTS

LEAVE:   PULS  X
         LDD   #TRUEV
         STD   6,S
         PSHS  X
         RTS

LOOP:    PULU  D
         CMPD  #TAGDO
         BEQ   LOOPOK
         JSR   CFERR
LOOPOK:  PULU  X
         LDD   #DOTEST
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         TFR   X,D
         PSHU  D
         LDD   PFIELD
         PSHU  D
         JSR   PATCH

         LDD   ,U
         CMPD  #TAGFWD
         BNE   LOOPDONE
         PULU  D
         PULU  X
         LDD   CODEHERE
         PSHU  D
         PSHU  X
         JSR   PATCH
LOOPDONE: RTS

DOTEST:  PULS  X
         LDD   6,S
         BNE   DTEXIT
         LDD   2,S
         ADDD  #1
         STD   2,S
         CMPD  4,S
         BEQ   DTEXIT
         LDD   ,X
         LEAX  D,X
         PSHS  X
         RTS
DTEXIT:  LEAX  2,X
         LEAS  6,S
         PSHS  X
         RTS

PLUSLOOP: PULU D
          CMPD #TAGDO
          BEQ  PLOOPOK
          JSR  CFERR
PLOOPOK:  PULU X
          LDD  #DOPLUSTEST
          PSHU D
          JSR  CCALL
          LDD  #0
          PSHU D
          JSR  CODECOMMA
          LDD  CODEHERE
          SUBD #2
          STD  PFIELD
          TFR  X,D
          PSHU D
          LDD  PFIELD
          PSHU D
          JSR  PATCH

          LDD  ,U
          CMPD #TAGFWD
          BNE  PLOOPDONE
          PULU D
          PULU X
          LDD  CODEHERE
          PSHU D
          PSHU X
          JSR  PATCH
PLOOPDONE: RTS

DOPLUSTEST: PULS X
            LDD  6,S
            BNE  DPTEXIT
            PULU D
            STD  MSCR
            LDD  2,S
            SUBD 4,S
            STD  MSCR2
            LDD  2,S
            ADDD MSCR
            STD  2,S
            SUBD 4,S
            STD  MSCR3
            LDA  MSCR2
            LDB  MSCR3
            PSHS B
            EORA ,S+          ; was "EORA B" - not valid 6809 syntax (no
                                ; register-to-register EORA); push B, then
                                ; operate through ,S+ - the standard 6809
                                ; idiom for adding/combining two registers
            BMI  DPTEXIT
            LDD  MSCR3
            BEQ  DPTEXIT
            LDD  ,X
            LEAX D,X
            PSHS X
            RTS
DPTEXIT:    LEAX 2,X
            LEAS 6,S
            PSHS X
            RTS

QDO:     LDD   #QDOSETUP
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         PSHU  D
         LDD   #TAGFWD
         PSHU  D
         LDD   CODEHERE
         PSHU  D
         LDD   #TAGDO
         PSHU  D
         RTS

QDOSETUP: PULU D
          STD  MSCR
          PULU D
          STD  MSCR2
          PULS X
          LDD  MSCR2
          CMPD MSCR
          BNE  QDBUILD
          LDD  ,X
          LEAX D,X
          PSHS X
          RTS
QDBUILD:  LEAX 2,X
          LDD  #0
          PSHS D
          LDD  MSCR2
          PSHS D
          LDD  MSCR
          PSHS D
          PSHS X
          RTS

UNLOOP:  PULS  X
         LEAS  6,S
         PSHS  X
         RTS

EXIT:    LDD   #0
         STD   EXITCNT
         TFR   U,D
         STD   EXITPTR
EXSCAN:  LDD   EXITPTR
         CMPD  CSP
         BEQ   EXSCANDONE
         LDX   EXITPTR
         LDD   ,X
         CMPD  #TAGDO
         BNE   EXNOTDO
         LDD   EXITCNT
         ADDD  #1
         STD   EXITCNT
EXNOTDO: LDD   EXITPTR
         ADDD  #4
         STD   EXITPTR
         BRA   EXSCAN
EXSCANDONE:
         LDD   #EXITUNLOOP
         PSHU  D
         JSR   CCALL
         LDD   EXITCNT
         PSHU  D
         JSR   CODECOMMA
         RTS

EXITUNLOOP: PULS X
            LDD  ,X
            TFR  D,Y
EULOOP:     CMPY #0
            BEQ  EUDONE
            LEAS 8,S
            LEAY -1,Y
            BRA  EULOOP
EUDONE:     PULS Y
            JMP  ,Y

CASEW:   LDD   #0
         PSHU  D
         LDD   #TAGCASE
         PSHU  D
         RTS

OF:      LDD   #OVER
         PSHU  D
         JSR   CCALL
         LDD   #EQUALW
         PSHU  D
         JSR   CCALL
         LDD   #ZBRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         PSHU  D
         LDD   #DROP
         PSHU  D
         JSR   CCALL
         LDD   #TAGOF
         PSHU  D
         RTS

ENDOF:   PULU  D
         CMPD  #TAGOF
         BEQ   EOFOK
         JSR   CFERR
EOFOK:   PULU  X
         LDD   #BRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   NEWFLD
         LDD   CODEHERE
         PSHU  D
         PSHU  X
         JSR   PATCH
         LDD   NEWFLD
         PSHU  D
         LDD   #TAGENDOF
         PSHU  D
         RTS

ENDCASE: LDD   #DROP
         PSHU  D
         JSR   CCALL
ECLOOP:  PULU  D
         CMPD  #TAGCASE
         BEQ   ECDONE
         CMPD  #TAGENDOF
         BEQ   ECPATCH
         JSR   CFERR
ECPATCH: PULU  X
         LDD   CODEHERE
         PSHU  D
         PSHU  X
         JSR   PATCH
         BRA   ECLOOP
ECDONE:  RTS

; ============================================================
