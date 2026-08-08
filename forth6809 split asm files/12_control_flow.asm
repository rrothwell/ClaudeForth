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
ELOK:    PULU  D          ; BUG FIX: same class as LOOP/EOFOK - was PULU X
         STD   MSCR       ; then used via PSHU X after CCALL/CODECOMMA
                          ; below, both of which clobber X internally.
                          ; Saved to scratch (not parked on U, since
                          ; CODEHERE gets pushed onto U further down,
                          ; between the save and the retrieve).
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
         LDD   MSCR
         PSHU  D
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
UNOK:    PULU  D          ; BUG FIX: same class as LOOP - was PULU X then
         PSHU  D          ; TFR X,D after CCALL/CODECOMMA, both of which
                          ; clobber X internally. Parked on U instead.
         LDD   #ZBRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         PULU  D
         PSHU  D
         LDD   PFIELD
         PSHU  D
         JSR   PATCH
         RTS

AGAIN:   PULU  D
         CMPD  #TAGBACK
         BEQ   AGOK
         JSR   CFERR
AGOK:    PULU  D          ; BUG FIX: same class as LOOP - was PULU X then
         PSHU  D          ; TFR X,D after CCALL/CODECOMMA, both of which
                          ; clobber X internally. Parked on U instead.
         LDD   #BRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         PULU  D
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
RPOK2:   PULU  D          ; BUG FIX: same class as LOOP - was PULU X then
         PSHU  D          ; TFR X,D after CCALL/CODECOMMA, both of which
                          ; clobber X internally. Parked on U instead.
         LDD   #BRANCH
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         PULU  D
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

IWORD:   LDD   2,S        ; BUG FIX: PULS X/PSHS X used to bracket this
         PSHU  D          ; read, shifting S by 2 first - so "2,S" landed
         RTS              ; on the limit (what's really at 4,S unshifted)
                          ; instead of the index. The pair served no
                          ; purpose (nothing needed offset 0 for anything
                          ; here) - removed, so 2,S directly and
                          ; correctly targets the index DOSETUP pushed
                          ; there. Confirmed via MAME debugger: "I"
                          ; returned the loop limit on every iteration.

JWORD:   LDD   10,S       ; BUG FIX: same class as IWORD above - the
         PSHU  D          ; PULS X/PSHS X pair shifted S by 2 first, so
         RTS              ; "10,S" landed on the outer loop's limit
                          ; instead of its index. Removed for the same
                          ; reason - 10,S unshifted already correctly
                          ; targets the outer index across a nested nest
                          ; of nested DOSETUP frames.

LEAVE:   LDD   #TRUEV    ; BUG FIX: same class as DOTEST above - PULS X
         STD   6,S       ; used to run first, shifting S by 2 before this
         PULS  X         ; write, landing 2 bytes past the LEAVE flag
         PSHS  X         ; DOSETUP actually pushed. Deferred PULS X to
         RTS             ; after the write, matching DOTEST's fix.

LOOP:    PULU  D
         CMPD  #TAGDO
         BEQ   LOOPOK
         JSR   CFERR
LOOPOK:  PULU  D          ; BUG FIX: was PULU X, then TFR X,D to retrieve
         PSHU  D          ; it after CCALL/CODECOMMA below - but both of
                          ; those clobber X internally (CCALL's own LDX
                          ; CODEHERE, CODECOMMA's LDX #CODEHERE via
                          ; APPENDCELL), so X no longer held the target
                          ; by the time TFR X,D ran - it held the address
                          ; of the CODEHERE variable itself, corrupting
                          ; the branch displacement PATCH computed.
                          ; Parking the target on U instead (untouched by
                          ; CCALL/CODECOMMA, which only use D/X/A) keeps
                          ; it safe across both calls; retrieved below via
                          ; PULU D in place of the old TFR X,D. Confirmed
                          ; via MAME debugger: the compiled displacement
                          ; came out as +8, executing DOTEST's return to
                          ; a near-zero, invalid address.
         LDD   #DOTEST
         PSHU  D
         JSR   CCALL
         LDD   #0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         SUBD  #2
         STD   PFIELD
         PULU  D
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

DOTEST:  LDD   6,S       ; BUG FIX: PULS X used to run FIRST, shifting S
         BNE   DTEXIT    ; by 2 before these offset reads - "6,S" ended
         LDD   2,S       ; up reading past the 3 cells DOSETUP pushed,
         ADDD  #1        ; into whatever return address was already on
         STD   2,S       ; S below them (e.g. EXECUTE's own), which is
         CMPD  4,S       ; almost always nonzero - so BNE DTEXIT fired
         BEQ   DTEXIT    ; on the very first pass, exiting immediately.
         PULS  X         ; X (the return address to the FDB <offset>
         LDD   ,X        ; field, needed for the back-branch) is only
         LEAX  D,X       ; actually needed here and in DTEXIT below -
         PSHS  X         ; deferred to each path separately instead of
         RTS             ; popped once up front. Confirmed via MAME
                          ; debugger: DOTEST was tested at $E184, a
                          ; leftover EXECUTE return address, instead of
                          ; the intended $0000 LEAVE flag.
DTEXIT:  PULS  X
         LEAX  2,X
         LEAS  6,S
         PSHS  X
         RTS

PLUSLOOP: PULU D
          CMPD #TAGDO
          BEQ  PLOOPOK
          JSR  CFERR
PLOOPOK:  PULU D          ; BUG FIX: same class as LOOP above - was PULU X
          PSHU D          ; then TFR X,D after CCALL/CODECOMMA, both of
                          ; which clobber X internally. Parked on U
                          ; instead, retrieved below via PULU D.
          LDD  #DOPLUSTEST
          PSHU D
          JSR  CCALL
          LDD  #0
          PSHU D
          JSR  CODECOMMA
          LDD  CODEHERE
          SUBD #2
          STD  PFIELD
          PULU D
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

DOPLUSTEST: LDD  6,S      ; BUG FIX: same class as DOTEST - PULS X used to
            BNE  DPTEXIT  ; run first, shifting S by 2 before every one of
            PULU D        ; these offset reads (6,S/2,S/4,S), landing past
            STD  MSCR     ; the 3 cells DOSETUP pushed. Deferred PULS X to
            LDD  2,S      ; each path separately below, same fix as DOTEST.
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
            PULS X
            LDD  ,X
            LEAX D,X
            PSHS X
            RTS
DPTEXIT:    PULS X
            LEAX 2,X
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
EOFOK:   PULU  D          ; BUG FIX: same class as LOOP - was PULU X then
         STD   MSCR       ; used via PSHU X after CCALL/CODECOMMA below,
                          ; both of which clobber X internally. Saved to
                          ; scratch instead (not parked on U, since
                          ; CODEHERE gets pushed onto U further down,
                          ; between the save and the retrieve below -
                          ; parking on U would retrieve that instead).
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
         LDD   MSCR
         PSHU  D
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

