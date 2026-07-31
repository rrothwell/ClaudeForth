; ============================================================
; SECTION 10: QUERY / ACCEPT / EXPECT / KEY / KEY? / EMIT
; ============================================================
         IFEQ SERIALPOLL  ; >>>>>>>>>>
KEY:     LDA   INHEAD
         CMPA  INTAIL
         BEQ   KEY
         LDX   #INBUF
         LDB   INTAIL
         LDA   B,X
         INCB
         ANDB  #INBUFSZ-1
         STB   INTAIL
         PSHS  A               ; stash the char on the return stack across
                                ; the call - JSR/RTS is self-balancing, so
                                ; this needs no dedicated scratch global
         JSR   RTSCHECKLO
         PULS  A
         TFR   A,B
         CLRA
         PSHU  D
         RTS

KEYQ:    LDA   INHEAD
         CMPA  INTAIL
         BNE   KQTRUE
         LDD   #FALSEV
         PSHU  D
         RTS
KQTRUE:  LDD   #TRUEV
         PSHU  D
         RTS

EMIT:    PULU  D
         STB   EMITCH
EMITWT:  LDB   OUTHEAD
         INCB
         ANDB  #OUTBUFSZ-1
         CMPB  OUTTAIL
         BEQ   EMITWT
         LDX   #OUTBUF
         LDB   OUTHEAD
         LDA   EMITCH
         STA   B,X
         INCB
         ANDB  #OUTBUFSZ-1
         STB   OUTHEAD
         TST   RTSSTATE
         BNE   EMITNORTS       ; RTS is asserted high - leave ACIACR alone;
                                ; output stays queued until RTS drops low,
                                ; at which point RTSCHECKLO re-enables TX
                                ; interrupt itself if OUTBUF still has data
         LDA   #CR_RXTX
         STA   ACIACR
EMITNORTS: RTS

         ELSE  ; <<<<<>>>>>
; ------------------------------------------------------------
; Polling versions of KEY/KEYQ/EMIT (SERIALPOLL=1) - no ring
; buffers, no interrupts, no RTS/CTS handshaking. Each blocks
; (KEY, EMIT) or checks once (KEYQ) directly against ACIASR.
; ------------------------------------------------------------
KEY:     LDA   ACIASR
         BITA  #SR_RDRF
         BEQ   KEY
         LDA   ACIADR
         TFR   A,B
         CLRA
         PSHU  D
         RTS

KEYQ:    LDA   ACIASR
         BITA  #SR_RDRF
         BEQ   KQFALSE
         LDD   #TRUEV
         PSHU  D
         RTS
KQFALSE: LDD   #FALSEV
         PSHU  D
         RTS

EMIT:    PULU  D
         STB   EMITCH
EMITWT:  LDA   ACIASR
         BITA  #SR_TDRE
         BEQ   EMITWT
         LDA   EMITCH
         STA   ACIADR
         RTS
         ENDC  ; <<<<<<<<<<

ACCEPT:  PULU  D
         STD   AMAX
         PULU  D
         STD   ABUFP
         LDD   #0
         STD   ACNT

ALOOP:   JSR   KEY
         PULU  D
         STB   ACH

         CMPB  #13
         BEQ   ADONE
         CMPB  #10
         BEQ   ALOOP
         CMPB  #8
         BEQ   ABKSP
         CMPB  #127
         BEQ   ABKSP

         LDD   ACNT
         CMPD  AMAX
         BEQ   ALOOP

         LDX   ABUFP
         LEAX  D,X
         LDA   ACH
         STA   ,X
         LDD   ACNT
         ADDD  #1
         STD   ACNT

         CLRA
         LDB   ACH
         PSHU  D
         JSR   EMIT
         BRA   ALOOP

ABKSP:   LDD   ACNT
         BEQ   ALOOP
         SUBD  #1
         STD   ACNT
         LDD   #8
         PSHU  D
         JSR   EMIT
         LDD   #32
         PSHU  D
         JSR   EMIT
         LDD   #8
         PSHU  D
         JSR   EMIT
         BRA   ALOOP

ADONE:   LDD   ACNT
         PSHU  D
         RTS

EXPECTW: JSR   ACCEPT
         PULU  D
         STD   SPAN
         RTS

QUERY:   LDX   #TIBBUF
         PSHU  X
         LDD   #TIBBUFL
         PSHU  D
         JSR   ACCEPT
         PULU  D
         STD   NTIB
         STD   SRCLEN
         LDD   #TIBBUF
         STD   SRCADDR
         LDD   #0
         STD   SRCID
         STD   TOIN
         RTS

