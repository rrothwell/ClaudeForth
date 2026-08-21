; ============================================================
; SECTION 20: NUMERIC OUTPUT (pictured + direct)
; ============================================================
LTNUM:   JSR   PADW
         PULU  D
         STD   HLD
         RTS

HOLD:    PULU  D
         LDX   HLD
         LEAX  -1,X
         STX   HLD
         STB   ,X
         RTS

HOLDS:   PULU  D
         STD   HSLEN
         PULU  D
         STD   HSADDR
HSLOOP:  LDD   HSLEN
         BEQ   HSDONE
         SUBD  #1
         STD   HSLEN
         LDX   HSADDR
         LDD   HSLEN
         LEAX  D,X
         LDA   ,X
         TFR   A,B
         CLRA
         PSHU  D
         JSR   HOLD
         BRA   HSLOOP
HSDONE:  RTS

NUMSIGN: PULU  D
         STD   UDHI
         PULU  D
         STD   UDLO
         JSR   UDDIGIT
         LDA   REM
         CMPA  #10
         BLO   NDIGIT
         ADDA  #'A'-10
         BRA   NHOLD
NDIGIT:  ADDA  #'0'
NHOLD:   TFR   A,B
         CLRA
         PSHU  D
         JSR   HOLD
         LDD   UDLO
         PSHU  D
         LDD   UDHI
         PSHU  D
         RTS

UDDIGIT: CLR   REM
         LDB   #32
         STB   DCNT
UDDLOOP: ASL   UDLO+1
         ROL   UDLO
         ROL   UDHI+1
         ROL   UDHI
         ROL   REM
         LDA   REM
         CMPA  BASE+1
         BLO   UDNEXT
         SUBA  BASE+1
         STA   REM
         INC   UDLO+1
UDNEXT:  DEC   DCNT
         BNE   UDDLOOP
         RTS

NUMSIGNS: JSR  NUMSIGN
          LDD  UDHI
          BNE  NUMSIGNS
          LDD  UDLO
          BNE  NUMSIGNS
          RTS

SIGN:    PULU  D
         TSTA          ; BUG FIX: was a bare "BPL SIGNDONE" right
                         ; after PULU - PULU doesn't affect condition
                         ; codes on genuine 6809 (same class as STOD's
                         ; own fix elsewhere in this file), so BPL was
                         ; testing whatever flags an unrelated, earlier
                         ; instruction happened to leave set, not the
                         ; sign of the value just popped. TSTA
                         ; explicitly tests D's high byte immediately
                         ; before the branch that depends on it. The
                         ; four existing internal callers (DOT/DOTR/
                         ; DDOT/DDOTR, i.e. . / .R / D. / D.R) were
                         ; accidentally unaffected - each happens to
                         ; run "LDD SAVEN" (a flag-setting load of the
                         ; true signed value) immediately before PSHU
                         ; D/JSR SIGN, and PSHU doesn't disturb flags -
                         ; but this was fragile, caller-side luck, not
                         ; SIGN being correct on its own. Confirmed via
                         ; MAME: a direct, standalone use of SIGN (not
                         ; preceded by an unrelated flag-setting
                         ; instruction) never added the minus sign for
                         ; either sign of input.
         BPL   SIGNDONE
         LDD   #'-'
         PSHU  D
         JSR   HOLD
SIGNDONE: RTS

NUMGT:   PULU  D
         PULU  D
         LDX   HLD
         PSHU  X
         JSR   PADW
         PULU  D
         SUBD  HLD
         PSHU  D
         RTS

DOT:     PULU  D
         STD   SAVEN
         BPL   DABSOK
         COMA
         COMB
         ADDD  #1
DABSOK:  PSHU  D
         LDD   #0
         PSHU  D
         JSR   LTNUM
         JSR   NUMSIGNS
         LDD   SAVEN
         PSHU  D
         JSR   SIGN
         JSR   NUMGT
         JSR   TYPE
         LDD   #32
         PSHU  D
         JSR   EMIT
         RTS

UDOT:    LDD   #0        ; SIMPLIFICATION: was PULU D/PSHU D here first -
                          ; a literal no-op (pop the value, immediately
                          ; push it back, nothing in between), leftover
                          ; rather than functional. The value being
                          ; formatted was never actually consumed here;
                          ; this line already pushes 0 on top of it
                          ; unchanged either way. Removed per the
                          ; parallel 68000 port's observation, confirmed
                          ; by inspection.
         PSHU  D
         JSR   LTNUM
         JSR   NUMSIGNS
         JSR   NUMGT
         JSR   TYPE
         LDD   #32
         PSHU  D
         JSR   EMIT
         RTS

DOTR:    PULU  D
         STD   DRWIDTH
         PULU  D
         STD   SAVEN
         BPL   DRABSOK
         COMA
         COMB
         ADDD  #1
DRABSOK: PSHU  D
         LDD   #0
         PSHU  D
         JSR   LTNUM
         JSR   NUMSIGNS
         LDD   SAVEN
         PSHU  D
         JSR   SIGN
         JSR   NUMGT
         PULU  D
         STD   DRLEN
         PULU  D
         STD   DRADDR
         LDD   DRWIDTH
         SUBD  DRLEN
         BLE   DRNOPAD
         STD   DRPAD
DRPADLP: LDD   DRPAD
         BEQ   DRNOPAD
         SUBD  #1
         STD   DRPAD
         LDD   #32
         PSHU  D
         JSR   EMIT
         BRA   DRPADLP
DRNOPAD: LDX   DRADDR
         PSHU  X
         LDD   DRLEN
         PSHU  D
         JSR   TYPE
         RTS

UDOTR:   PULU  D
         STD   DRWIDTH
         LDD   #0        ; SIMPLIFICATION: was PULU D/PSHU D here first -
                          ; a literal no-op on the value being formatted
                          ; (the width above is a real, separate pop -
                          ; unaffected). Removed per the parallel 68000
                          ; port's observation, confirmed by inspection.
         PSHU  D
         JSR   LTNUM
         JSR   NUMSIGNS
         JSR   NUMGT
         PULU  D
         STD   DRLEN
         PULU  D
         STD   DRADDR
         LDD   DRWIDTH
         SUBD  DRLEN
         BLE   UDRNOPAD
         STD   DRPAD
UDRPADLP: LDD  DRPAD
          BEQ  UDRNOPAD
          SUBD #1
          STD  DRPAD
          LDD  #32
          PSHU D
          JSR  EMIT
          BRA  UDRPADLP
UDRNOPAD: LDX  DRADDR
          PSHU X
          LDD  DRLEN
          PSHU D
          JSR  TYPE
          RTS

QMARK:   PULU  X
         LDD   ,X
         PSHU  D
         JSR   DOT
         RTS

DDOT:    PULU  D
         STD   PRODHI
         PULU  D
         STD   PRODLO
         LDD   PRODHI
         STD   SAVEN
         BPL   DDPOS
         JSR   MNEG32
DDPOS:   LDD   PRODLO
         PSHU  D
         LDD   PRODHI
         PSHU  D
         JSR   LTNUM
         JSR   NUMSIGNS
         LDD   SAVEN
         PSHU  D
         JSR   SIGN
         JSR   NUMGT
         JSR   TYPE
         LDD   #32
         PSHU  D
         JSR   EMIT
         RTS

DDOTR:   PULU  D
         STD   DRWIDTH
         PULU  D
         STD   PRODHI
         PULU  D
         STD   PRODLO
         LDD   PRODHI
         STD   SAVEN
         BPL   DDRPOS
         JSR   MNEG32
DDRPOS:  LDD   PRODLO
         PSHU  D
         LDD   PRODHI
         PSHU  D
         JSR   LTNUM
         JSR   NUMSIGNS
         LDD   SAVEN
         PSHU  D
         JSR   SIGN
         JSR   NUMGT
         PULU  D
         STD   DRLEN
         PULU  D
         STD   DRADDR
         LDD   DRWIDTH
         SUBD  DRLEN
         BLE   DRDNOPAD
         STD   DRPAD
DRDPADLP: LDD  DRPAD
          BEQ  DRDNOPAD
          SUBD #1
          STD  DRPAD
          LDD  #32
          PSHU D
          JSR  EMIT
          BRA  DRDPADLP
DRDNOPAD: LDX  DRADDR
          PSHU X
          LDD  DRLEN
          PSHU D
          JSR  TYPE
          RTS

