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

; ------------------------------------------------------------
; ECHOEMIT - non-blocking echo variant of EMIT, used only by
; ACCEPT's own echo path (below, shared/unconditional code).
; BUG FIX: ACCEPT previously used the real EMIT to echo received
; characters back out - EMIT's own spin-wait (EMITWT, above) can
; block forever if OUTBUF is full while RTS is asserted high,
; since only IRQH's own TX path ever advances OUTTAIL, and that
; path requires TX-interrupt to be enabled - which CR_RTSHI
; (RTSCHECKHI, above) unconditionally disables. Traced precisely:
; ACCEPT's own ALOOP only calls KEY again after EMIT returns, and
; RTSCHECKLO (the only thing that ever clears RTSSTATE and
; restores TX-interrupt-enable) is only ever called from within
; KEY - so a blocked echo call permanently prevents the one thing
; that could unblock it, a genuine deadlock, not just a slow
; path. ECHOEMIT is identical to EMIT except it silently drops
; the character instead of spinning when OUTBUF is full - the
; character itself was already correctly received and stored in
; the input buffer; only its own visual echo is skipped, and only
; under the kind of sustained overload where this would otherwise
; deadlock the whole system. A fixed-retry-count compromise was
; considered and deliberately deferred - not worth the added
; complexity unless a real problem with dropped echoes actually
; shows up in practice.
;
; Deliberately defined here, inside the SERIALPOLL=0 branch only
; (with a separate, trivial pass-through defined in the
; SERIALPOLL=1 branch below) - not as a single, unconditional
; definition. This code directly manipulates OUTHEAD/OUTTAIL/
; RTSSTATE and writes CR_RXTX to ACIACR; under SERIALPOLL=1,
; where IRQH is just an RTI stub, writing CR_RXTX (RX+TX
; interrupt enabled) would start the ACIA generating real
; interrupts that nothing ever services or clears - an interrupt
; storm, not merely a wasted write. ACCEPT's own call site stays
; simple, unconditional code either way, since both branches
; provide a same-named, same-signature routine.
; ------------------------------------------------------------
ECHOEMIT: PULU  D
          STB   EMITCH
          LDB   OUTHEAD
          INCB
          ANDB  #OUTBUFSZ-1
          CMPB  OUTTAIL
          BEQ   ECHOSKIP        ; OUTBUF full - drop this echo
                                ; character rather than spin
          LDX   #OUTBUF
          LDB   OUTHEAD
          LDA   EMITCH
          STA   B,X
          INCB
          ANDB  #OUTBUFSZ-1
          STB   OUTHEAD
          TST   RTSSTATE
          BNE   ECHOSKIP
          LDA   #CR_RXTX
          STA   ACIACR
ECHOSKIP: RTS

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

; ------------------------------------------------------------
; ECHOEMIT - trivial pass-through to EMIT under polling mode.
; The deadlock ECHOEMIT (above, SERIALPOLL=0 branch) guards
; against is specific to interrupt-driven RTS/CTS handshaking,
; which does not exist under SERIALPOLL=1 at all (per this
; flag's own header comment: "no interrupts, no ring buffers, no
; RTS/CTS handshaking") - polling-mode EMIT already cannot
; deadlock this way, so ACCEPT's own call to ECHOEMIT can safely
; just be the real EMIT here.
; ------------------------------------------------------------
ECHOEMIT: JSR   EMIT
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
         JSR   ECHOEMIT
         BRA   ALOOP

ABKSP:   LDD   ACNT
         BEQ   ALOOP
         SUBD  #1
         STD   ACNT
         LDD   #8
         PSHU  D
         JSR   ECHOEMIT
         LDD   #32
         PSHU  D
         JSR   ECHOEMIT
         LDD   #8
         PSHU  D
         JSR   ECHOEMIT
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

