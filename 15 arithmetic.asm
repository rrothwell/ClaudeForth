; ============================================================
; 6809 FORTH - 15_arithmetic
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 15: ARITHMETIC (single + double + mixed precision)
; ============================================================
PLUS:    PULU  D
         ADDD  ,U
         STD   ,U
         RTS

; MSCR is declared once in the GLOBALS layout above - no local
; redeclaration needed here.
MINUS:   PULU  D
         STD   MSCR
         LDD   ,U
         SUBD  MSCR
         STD   ,U
         RTS

NEGATE:  LDD   ,U
         COMA
         COMB
         ADDD  #1
         STD   ,U
         RTS

ABSW:    LDD   ,U
         BPL   ABSDONE
         COMA
         COMB
         ADDD  #1
         STD   ,U
ABSDONE: RTS

MIN:     PULU  D
         CMPD  ,U
         BLT   MINISN2
         RTS
MINISN2: STD   ,U
         RTS

MAX:     PULU  D
         CMPD  ,U
         BGT   MAXISN2
         RTS
MAXISN2: STD   ,U
         RTS

ONEPLUS: LDD   ,U
         ADDD  #1
         STD   ,U
         RTS

ONEMINUS: LDD  ,U
          SUBD #1
          STD  ,U
          RTS

TWOPLUS: LDD   ,U
         ADDD  #2
         STD   ,U
         RTS

STAR:    PULU  D
         STD   MSCR
         LDD   ,U
         CLR   MSIGN
         BPL   SNOFLIP1
         COM   MSIGN
         COMA
         COMB
         ADDD  #1
SNOFLIP1: STA  MAHI
          STB  MALO
          LDD  MSCR
          BPL  SNOFLIP2
          COM  MSIGN
          COMA
          COMB
          ADDD #1
SNOFLIP2: STA  MBHI
          STB  MBLO
          LDA  MALO
          LDB  MBLO
          MUL
          STD  MRESULT
          LDA  MAHI
          LDB  MBLO
          MUL
          LDA  MRESULT
          PSHS B
          ADDA ,S+          ; was "ADDA B" - not valid 6809 syntax
          STA  MRESULT
          LDA  MALO
          LDB  MBHI
          MUL
          LDA  MRESULT
          PSHS B
          ADDA ,S+          ; was "ADDA B" - not valid 6809 syntax
          STA  MRESULT
          LDD  MRESULT
          TST  MSIGN
          BEQ  SDONE
          COMA
          COMB
          ADDD #1
SDONE:    STD  ,U
          RTS

TWOSTAR: LDD   ,U
         ASLB
         ROLA
         STD   ,U
         RTS

UDIV16:  CLR   DIVREM
         CLR   DIVREM+1
         LDB   #16
         STB   DIVCNT
UD16LOOP: ASL   DIVNUM+1
         ROL   DIVNUM
         ROL   DIVREM+1
         ROL   DIVREM
         LDD   DIVREM
         SUBD  DIVDEN
         BLO   UDSKIP
         STD   DIVREM
         INC   DIVNUM+1
UDSKIP:  DEC   DIVCNT
         BNE   UD16LOOP
         RTS

DIVCOMMON: PULU  D
           STD   DIVDEN
           CMPD  #0
           BNE   DCOK
           LDD   #-10
           PSHU  D
           JSR   THROW
DCOK:      PULU  D
           STD   DIVNUM
           CLR   DVSIGN
           CLR   DNSIGN
           TST   DIVNUM
           BPL   DNPOS
           COM   DNSIGN
           COM   DVSIGN
           LDD   DIVNUM
           COMA
           COMB
           ADDD  #1
           STD   DIVNUM
DNPOS:     TST   DIVDEN
           BPL   DVPOS
           COM   DVSIGN
           LDD   DIVDEN
           COMA
           COMB
           ADDD  #1
           STD   DIVDEN
DVPOS:     JSR   UDIV16
           LDD   DIVNUM
           TST   DVSIGN
           BEQ   DQPOS
           COMA
           COMB
           ADDD  #1
           STD   DIVNUM
DQPOS:     LDD   DIVREM
           TST   DNSIGN
           BEQ   DCRPOS
           COMA
           COMB
           ADDD  #1
           STD   DIVREM
DCRPOS:    RTS

SLASH:   JSR   DIVCOMMON
         LDD   DIVNUM
         PSHU  D
         RTS

MODW:    JSR   DIVCOMMON
         LDD   DIVREM
         PSHU  D
         RTS

SLASHMOD: JSR  DIVCOMMON
          LDD  DIVREM
          PSHU D
          LDD  DIVNUM
          PSHU D
          RTS

TWOSLASH: LDD  ,U
          ASRA
          RORB
          STD  ,U
          RTS

UMUL32:  LDA   MALO
         LDB   MBLO
         MUL
         STD   PRODLO
         CLR   PRODHI
         CLR   PRODHI+1
         LDA   MAHI
         LDB   MBLO
         MUL
         ADDB  PRODLO
         STB   PRODLO
         ADCA  #0
         ADDA  PRODHI+1
         STA   PRODHI+1
         BCC   UM32A
         INC   PRODHI
UM32A:   LDA   MALO
         LDB   MBHI
         MUL
         ADDB  PRODLO
         STB   PRODLO
         ADCA  #0
         ADDA  PRODHI+1
         STA   PRODHI+1
         BCC   UM32B
         INC   PRODHI
UM32B:   LDA   MAHI
         LDB   MBHI
         MUL
         ADDD  PRODHI
         STD   PRODHI
         RTS

UDIV32:  CLR   DIVREM
         CLR   DIVREM+1
         LDB   #32
         STB   DIVCNT
UD32LP:  ASL   PRODLO+1
         ROL   PRODLO
         ROL   PRODHI+1
         ROL   PRODHI
         ROL   DIVREM+1
         ROL   DIVREM
         LDD   DIVREM
         SUBD  DIVDEN
         BLO   UD32SKIP
         STD   DIVREM
         INC   PRODLO+1
UD32SKIP: DEC  DIVCNT
          BNE  UD32LP
          RTS

MNEG32:  LDD   PRODLO
         COMA
         COMB
         STD   PRODLO
         LDD   PRODHI
         COMA
         COMB
         STD   PRODHI
         LDD   PRODLO
         ADDD  #1
         STD   PRODLO
         BCC   MN32DONE
         LDD   PRODHI
         ADDD  #1
         STD   PRODHI
MN32DONE: RTS

STARSLASHCOMMON:
         PULU  D
         STD   DIVDEN
         CMPD  #0
         BNE   SSOK
         LDD   #-10
         PSHU  D
         JSR   THROW
SSOK:    CLR   PSIGN
         TST   DIVDEN
         BPL   SSN3POS
         COM   PSIGN
         LDD   DIVDEN
         COMA
         COMB
         ADDD  #1
         STD   DIVDEN
SSN3POS: LDA   #0
         STA   PRSIGN
         PULU  D
         STD   MSCR
         TST   MSCR
         BPL   SSN2POS
         COM   PSIGN
         COM   PRSIGN
         LDD   MSCR
         COMA
         COMB
         ADDD  #1
         STD   MSCR
SSN2POS: LDA   MSCR
         STA   MBHI
         LDA   MSCR+1
         STA   MBLO
         PULU  D
         STD   MSCR
         TST   MSCR
         BPL   SSN1POS
         COM   PSIGN
         COM   PRSIGN
         LDD   MSCR
         COMA
         COMB
         ADDD  #1
         STD   MSCR
SSN1POS: LDA   MSCR
         STA   MAHI
         LDA   MSCR+1
         STA   MALO
         JSR   UMUL32
         JSR   UDIV32
         LDD   PRODLO
         TST   PSIGN
         BEQ   SSQPOS
         COMA
         COMB
         ADDD  #1
         STD   PRODLO
SSQPOS:  LDD   DIVREM
         TST   PRSIGN
         BEQ   SSRPOS
         COMA
         COMB
         ADDD  #1
         STD   DIVREM
SSRPOS:  RTS

STARSLASH: JSR  STARSLASHCOMMON
           LDD  PRODLO
           PSHU D
           RTS

STARSLASHMOD: JSR  STARSLASHCOMMON
              LDD  DIVREM
              PSHU D
              LDD  PRODLO
              PSHU D
              RTS

UMSTAR:  PULU  D
         STD   MSCR
         PULU  D
         STA   MAHI
         STB   MALO
         LDD   MSCR
         STA   MBHI
         STB   MBLO
         JSR   UMUL32
         LDD   PRODLO
         PSHU  D
         LDD   PRODHI
         PSHU  D
         RTS

UMSLASHMOD: PULU D
            STD  DIVDEN
            CMPD #0
            BNE  UMOK
            LDD  #-10
            PSHU D
            JSR  THROW
UMOK:       PULU D
            STD  PRODHI
            PULU D
            STD  PRODLO
            JSR  UDIV32
            LDD  DIVREM
            PSHU D
            LDD  PRODLO
            PSHU D
            RTS

MSTAR:   PULU  D
         STD   MSCR
         PULU  D
         CLR   MSIGN
         BPL   MSN1POS
         COM   MSIGN
         COMA
         COMB
         ADDD  #1
MSN1POS: STA   MAHI
         STB   MALO
         LDD   MSCR
         BPL   MSN2POS
         COM   MSIGN
         COMA
         COMB
         ADDD  #1
MSN2POS: STA   MBHI
         STB   MBLO
         JSR   UMUL32
         TST   MSIGN
         BEQ   MSDONE
         JSR   MNEG32
MSDONE:  LDD   PRODLO
         PSHU  D
         LDD   PRODHI
         PSHU  D
         RTS

SMSLASHREM: PULU D
            STD  DIVDEN
            CMPD #0
            BNE  SMOK
            LDD  #-10
            PSHU D
            JSR  THROW
SMOK:       PULU D
            STD  PRODHI
            PULU D
            STD  PRODLO
            CLR  DNSIGN
            CLR  DVSIGN
            TST  PRODHI
            BPL  SMDPOS
            COM  DNSIGN
            COM  DVSIGN
            JSR  MNEG32
SMDPOS:     LDD  DIVDEN
            BPL  SMDVPOS
            COM  DVSIGN
            LDD  DIVDEN
            COMA
            COMB
            ADDD #1
            STD  DIVDEN
SMDVPOS:    JSR  UDIV32
            LDD  DIVREM
            TST  DNSIGN
            BEQ  SMRPOS
            COMA
            COMB
            ADDD #1
SMRPOS:     PSHU D
            LDD  PRODLO
            TST  DVSIGN
            BEQ  SMQPOS
            COMA
            COMB
            ADDD #1
SMQPOS:     PSHU D
            RTS

FMSLASHMOD: PULU D
            STD  DIVDEN
            CMPD #0
            BNE  FMOK
            LDD  #-10
            PSHU D
            JSR  THROW
FMOK:       PULU D
            STD  PRODHI
            PULU D
            STD  PRODLO
            CLR  DNSIGN
            CLR  DVSIGN
            CLR  DVOWNSIGN
            TST  PRODHI
            BPL  FMDPOS
            COM  DNSIGN
            COM  DVSIGN
            JSR  MNEG32
FMDPOS:     LDD  DIVDEN
            BPL  FMDVPOS
            COM  DVSIGN
            COM  DVOWNSIGN
            LDD  DIVDEN
            COMA
            COMB
            ADDD #1
            STD  DIVDEN
FMDVPOS:    JSR  UDIV32
            TST  DVSIGN
            BEQ  FMNOFLOOR
            LDD  DIVREM
            BEQ  FMNOFLOOR
            LDD  PRODLO
            ADDD #1
            STD  PRODLO
            LDD  DIVDEN
            SUBD DIVREM
            STD  DIVREM
FMNOFLOOR:  LDD  DIVREM
            TST  DVOWNSIGN
            BEQ  FMRPOS
            COMA
            COMB
            ADDD #1
FMRPOS:     PSHU D
            LDD  PRODLO
            TST  DVSIGN
            BEQ  FMQPOS
            COMA
            COMB
            ADDD #1
FMQPOS:     PSHU D
            RTS

DPLUS:   PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         ADDD  MSCR2
         STD   MSCR4
         BCC   DPNOCY
         LDD   MSCR3
         ADDD  MSCR
         ADDD  #1
         BRA   DPHIDONE
DPNOCY:  LDD   MSCR3
         ADDD  MSCR
DPHIDONE: STD  MSCR3
         LDD   MSCR4
         PSHU  D
         LDD   MSCR3
         PSHU  D
         RTS

DMINUS:  PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         SUBD  MSCR2
         STD   MSCR4
         BCC   DMNOBOR
         LDD   MSCR3
         SUBD  MSCR
         SUBD  #1
         BRA   DMHIDONE
DMNOBOR: LDD   MSCR3
         SUBD  MSCR
DMHIDONE: STD  MSCR3
         LDD   MSCR4
         PSHU  D
         LDD   MSCR3
         PSHU  D
         RTS

DNEGATEW: PULU D
          STD  PRODHI
          PULU D
          STD  PRODLO
          JSR  MNEG32
          LDD  PRODLO
          PSHU D
          LDD  PRODHI
          PSHU D
          RTS

DABSW:   PULU  D
         STD   PRODHI
         PULU  D
         STD   PRODLO
         TST   PRODHI
         BPL   DABSDONE
         JSR   MNEG32
DABSDONE: LDD  PRODLO
          PSHU D
          LDD  PRODHI
          PSHU D
          RTS

MPLUS:   PULU  D
         STD   MSCR2
         BPL   MPPOSN
         LDD   #-1
         BRA   MPSIGNED
MPPOSN:  LDD   #0
MPSIGNED: STD  MSCR
          PULU D
          STD  MSCR3
          PULU D
          ADDD MSCR2
          STD  MSCR4
          BCC  MPNOCY
          LDD  MSCR3
          ADDD MSCR
          ADDD #1
          BRA  MPHIDONE
MPNOCY:   LDD  MSCR3
          ADDD MSCR
MPHIDONE: STD MSCR3
          LDD  MSCR4
          PSHU D
          LDD  MSCR3
          PSHU D
          RTS

STOD:    PULU  D
         PSHU  D
         BPL   SDPOS
         LDD   #-1
         BRA   SDPUSH
SDPOS:   LDD   #0
SDPUSH:  PSHU  D
         RTS

DTOS:    PULU  D
         RTS

DMAXW:   PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         STD   MSCR4
         LDD   MSCR3
         CMPD  MSCR
         BGT   DMXD1
         BLT   DMXD2
         LDD   MSCR4
         CMPD  MSCR2
         BHS   DMXD1
DMXD2:   LDD   MSCR2
         PSHU  D
         LDD   MSCR
         PSHU  D
         RTS
DMXD1:   LDD   MSCR4
         PSHU  D
         LDD   MSCR3
         PSHU  D
         RTS

DMINW:   PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         STD   MSCR4
         LDD   MSCR3
         CMPD  MSCR
         BLT   DMND1
         BGT   DMND2
         LDD   MSCR4
         CMPD  MSCR2
         BLS   DMND1
DMND2:   LDD   MSCR2
         PSHU  D
         LDD   MSCR
         PSHU  D
         RTS
DMND1:   LDD   MSCR4
         PSHU  D
         LDD   MSCR3
         PSHU  D
         RTS

; ============================================================
