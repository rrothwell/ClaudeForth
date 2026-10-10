; ============================================================
; UNIT TEST FRAMEWORK
;
; Self-checking assembly-level tests of this ROM's primitives. Built
; in when UNITTESTS is 1; run once at cold boot, after INITSERIAL and
; before COLD (U and S are valid, but nothing else is initialised).
;
; Each test saves U on entry and restores it on exit, so one test's
; failure cannot disturb the next. Scratch variables live at the
; start of APPVARS (safe: COLD re-purposes that space afterwards).
; Each test reports its name and OK or FAIL through TSTREPORT.
;
; TSTSELECTOR picks one test group per build, because all groups
; together do not fit in the unused ROM. Example, group 2:
;
;   lwasm --6809 --format=raw \
;   --output=forth6809.bin --list=forth6809.lst \
;   --define=UNITTESTS --define=TSTSELECTOR=2 \
;   forth6809.asm
;
; The original header comment is shadow UNITTEST.0.
; ============================================================

TSTU0       EQU   APPVARS           ; saved U, before a test touches it
TSTUB4      EQU   APPVARS+2         ; U immediately before the op under test
TSTUAF      EQU   APPVARS+4         ; U immediately after the op under test
TSTFLAG     EQU   APPVARS+6         ; scratch for TSTREPORT's pass/fail arg

TSTGUARD    EQU   $3C7A             ; sentinel beneath the value under test
TSTVAL1     EQU   $59E1             ; the value under test (non-trivial)
TSTVAL2     EQU   $2468             ; additional distinct, non-trivial
TSTVAL3     EQU   $7B3D             ; values for multi-item tests (SWAP,
TSTVAL4     EQU   $4E2C             ; OVER, ROT, 2DUP, 2ROT, etc) - none are
TSTVAL5     EQU   $19A7             ; 0, 1, -1, TSTGUARD, or any of each
TSTVAL6     EQU   $6D95             ; other

TSTSCR      EQU   APPVARS+8         ; extra scratch cell (DEPTH test)

TSTCBUF     EQU   APPVARS+10        ; 80-byte compile target buffer
TSTCSAV     EQU   APPVARS+90        ; saved CODEHERE
TSTCSPS     EQU   APPVARS+92        ; saved CSP
TSTLSAV     EQU   APPVARS+94        ; saved LATEST (RECURSE test)
TSTFHDR     EQU   APPVARS+96        ; 16-byte fake dictionary header

TSTDBUF     EQU   APPVARS+112       ; 40-byte scratch dictionary buffer
TSTDSAV     EQU   APPVARS+152       ; saved DPHERE
TSTVBUF     EQU   APPVARS+154       ; 20-byte scratch VARHERE buffer
TSTVSAV     EQU   APPVARS+174       ; saved VARHERE
TSTNAMEB    EQU   APPVARS+176       ; 16-byte fake source text for name parsing
TSTSASAV    EQU   APPVARS+192       ; saved SRCADDR
TSTSLSAV    EQU   APPVARS+194       ; saved SRCLEN
TSTTISAV    EQU   APPVARS+196       ; saved TOIN
TSTWCFA     EQU   APPVARS+198       ; CFA of the newly defined test word
TSTSTSAV    EQU   APPVARS+200       ; saved STATE, across a :/; test
TSTSMFLG    EQU   APPVARS+202       ; scratch: header SMUDGE-bit check result
TSTDOESA    EQU   APPVARS+204       ; address of a compiled JSR SETDOES
TSTCSAV2    EQU   APPVARS+212       ; MARKER test: CODEHERE after marker ran
TSTDSAV2    EQU   APPVARS+214       ; same, DPHERE
TSTVSAV2    EQU   APPVARS+216       ; same, VARHERE
TSTLSAV2    EQU   APPVARS+218       ; same, LATEST
TSTCBUF2    EQU   APPVARS+220       ; second 20-byte CODEHERE redirect target
                                    ; See bugfix: TSTCBUF2.1
TSTUMID     EQU   APPVARS+240       ; U captured mid round trip (>R, 2>R)

TSTOHSAV    EQU   APPVARS+242       ; saved OUTHEAD (EMIT-family tests)

TSTBASAV    EQU   APPVARS+243       ; saved BASE. See bugfix: TSTBASAV.1

TSTHANDSAV  EQU   APPVARS+245       ; saved HANDLER (CATCH test)

TSTSISAV    EQU   APPVARS+247       ; saved SRCID (SOURCE-ID, REFILL tests)

TSTNEG1     EQU   $CFC7             ; -12345: a non-trivial negative value
TSTNEG2     EQU   $FEBF             ; -321

TSTD1HI     EQU   $0001             ; TSTDBL1 = 70000 (positive, exceeds 16
TSTD1LO     EQU   $1170             ; bits - exercises real double-cell width,
                                    ; not just a sign-extended single)
TSTD2HI     EQU   $FFFE             ; TSTDBL2 = -70000
TSTD2LO     EQU   $EE90
TSTD3HI     EQU   $00BC             ; TSTDBL3 = 12345678
TSTD3LO     EQU   $614E
TSTDSHI     EQU   $0000             ; TSTDBLSMALL = 500 - small enough to fit
TSTDSLO     EQU   $01F4             ; in a single cell, for D>S

; ------------------------------------------------------------
; Report one test result: print the test name, then OK or FAIL,
; then a CR.
; TSTREPORT
;    Inputs:
;        data stack: passflag (TRUEV = pass), testname-caddr
;        beneath it (counted string)
;    Outputs:
;        name, then " OK" or " FAIL", then CR, queued for output
;    Registers: all changed.
; Original comment: shadow TSTREPORT.0.
; ------------------------------------------------------------
TSTREPORT:  PULU  D
            STD   TSTFLAG
            JSR   COUNTW
            JSR   TYPEW
            LDD   TSTFLAG
            BEQ   TSTFAILR
            LDD   #TSTOKMSG
            PSHU  D
            LDD   #TSTOKMSGL
            PSHU  D
            BRA   TSTPRINT
TSTFAILR:   LDD   #TSTFAILMSG
            PSHU  D
            LDD   #TSTFAILMSGL
            PSHU  D
TSTPRINT:   JSR   TYPEW
            JSR   CRW
            RTS

TSTOKMSG:   FCC   " OK"
TSTOKMSGL   EQU   *-TSTOKMSG
TSTFAILMSG: FCC   " FAIL"
TSTFAILMSGL EQU   *-TSTFAILMSG

; ------------------------------------------------------------
; Run each test group in turn.
; TSTRUNNER
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTRUNNER.0.
; ------------------------------------------------------------
TSTRUNNER:  JSR   TSTSYSIO
            JSR   TSTSTACK
            JSR   TSTRETSTACK
            JSR   TSTSARITH
            JSR   TSTDARITH
            JSR   TSTLOGIC
            JSR   TSTCOMPARE
            JSR   TSTCTRLFLOW
            JSR   TSTDEFWORDS
            JSR   TSTCOMPWORDS
            JSR   TSTMEMORY
            JSR   TSTSTRPARSE
            JSR   TSTNUMOUT
            JSR   TSTBASERADIX
            JSR   TSTEXCEPTION
            JSR   TSTCOMMENTS
            JSR   TSTENVSYS
            JSR   TSTTOOLS
            RTS

; ------------------------------------------------------------
; System/Console I/O tests (glossary section 3.1, 12 words,
; 7 tests).
; TSTSYSIO
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTSYSIO.0.
; ------------------------------------------------------------
TSTSYSIO:   JSR   CRW
            LDX   #TSTSYSIOMSG
            PSHU  X
            LDD   #5
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-0     ; >>>>

            JSR   TSTKEYQ
            JSR   TSTEMIT
            JSR   TSTCR
            JSR   TSTSPACE
            JSR   TSTSPACES
            JSR   TSTSPACESZ
            JSR   TSTTYPE

            ENDC                    ; <<<<

            RTS

TSTSYSIOMSG:
            FCC   "SysIO"

            IFEQ  TSTSELECTOR-0     ; >>>>

; ------------------------------------------------------------
; System/Console I/O test harness (glossary section 3.1).
; Original comment: shadow TSTSYSIO.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for KEY?. With no real input pending during
; automated boot-time testing, expects FALSE - the normal,
; expected case for this kind of test run.
; TSTKEYQ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTKEYQ OK" or "TSTKEYQ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTKEYQ:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   KEYQW

            STU   TSTUAF

            PULU  D
            CMPD  #FALSEV
            BNE   KYFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   KYFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   KYFAIL

            LDD   #TRUEV
            BRA   KYDONE
KYFAIL:     LDD   #FALSEV
KYDONE:     LDX   #TSTKEYQNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTKEYQNAME:
            FCB   7
            FCC   "TSTKEYQ"

; ------------------------------------------------------------
; unit test for EMIT. Verifies the actual queuing mechanism:
; saves OUTHEAD before the call, then confirms it advanced
; by exactly one (wrapping correctly via OUTBUFSZ, a power
; of two) and that the queued byte at the old OUTHEAD
; position genuinely matches the character emitted - not
; just that the call returned.
; TSTEMIT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTEMIT OK" or "TSTEMIT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTEMIT:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #65
            PSHU  D
            STU   TSTUB4

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            JSR   EMITW

            STU   TSTUAF

            IFEQ  SERIALPOLL        ; >>>> ring check: interrupt-driven EMIT
            LDA   TSTOHSAV
            INCA
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   EMFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #65
            BNE   EMFAIL
            ELSE                    ; <<<<>>>> See bugfix: TSTEMIT.2
            LDA   EMITCH            ; See bugfix: TSTEMIT.1
            CMPA  #65
            BNE   EMFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   EMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   EMFAIL

            LDD   #TRUEV
            BRA   EMDONE
EMFAIL:     LDD   #FALSEV
EMDONE:     LDX   #TSTEMITNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEMITNAME:
            FCB   7
            FCC   "TSTEMIT"

; ------------------------------------------------------------
; unit test for CR. Verifies both queued bytes (13 then 10,
; CR then LF, matching the documented "CR then LF") land
; correctly in the output ring buffer, in order.
; TSTCR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCR OK" or "TSTCR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCR:      STU   TSTU0

            IFEQ  SERIALPOLL        ; >>>> full check: interrupt-driven EMIT
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<


            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   CRW

            STU   TSTUAF

            IFEQ  SERIALPOLL        ; >>>> full check: interrupt-driven EMIT
            LDA   TSTOHSAV
            ADDA  #2
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   CRFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #13
            BNE   CRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #10
            BNE   CRFAIL
            ELSE                    ; <<<<>>>> See bugfix: TSTCR.3
            LDA   EMITCH
            CMPA  #10
            BNE   CRFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   CRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   CRFAIL

            LDD   #TRUEV
            BRA   CRDONE
CRFAIL:     LDD   #FALSEV
CRDONE:     LDX   #TSTCRNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCRNAME:  FCB   5
            FCC   "TSTCR"

; ------------------------------------------------------------
; unit test for SPACE. Verifies one space (32) is genuinely
; queued.
; TSTSPACE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSPACE OK" or "TSTSPACE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSPACE:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            JSR   SPACEW

            STU   TSTUAF

            IFEQ  SERIALPOLL        ; >>>> ring check: interrupt-driven EMIT
            LDA   TSTOHSAV
            INCA
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   SCFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #32
            BNE   SCFAIL
            ELSE                    ; <<<<>>>> See bugfix: TSTSPACE.2
            LDA   EMITCH            ; See bugfix: TSTSPACE.1
            CMPA  #32
            BNE   SCFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   SCFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   SCFAIL

            LDD   #TRUEV
            BRA   SCDONE
SCFAIL:     LDD   #FALSEV
SCDONE:     LDX   #TSTSPACENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSPACENAME:
            FCB   8
            FCC   "TSTSPACE"

; ------------------------------------------------------------
; unit test for SPACES, normal (n=3) case. Verifies all
; three queued bytes are genuinely spaces (32), not just
; that OUTHEAD advanced by the right count.
; TSTSPACES
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSPACES OK" or "TSTSPACES FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSPACES:  STU   TSTU0

            IFEQ  SERIALPOLL        ; >>>> full check: interrupt-driven EMIT
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            LDD   #TSTGUARD
            PSHU  D
            LDD   #3
            PSHU  D
            STU   TSTUB4

            JSR   SPACESW

            STU   TSTUAF

            IFEQ  SERIALPOLL        ; >>>> full check: interrupt-driven EMIT
                                    ; queues all three bytes into OUTBUF,
                                    ; verifiable individually
            LDA   TSTOHSAV
            ADDA  #3
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   SSFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #32
            BNE   SSFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   SSFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   SSFAIL
            ELSE                    ; <<<<>>>> See bugfix: TSTSPACES.2
            LDA   EMITCH
            CMPA  #32
            BNE   SSFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   SSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   SSFAIL

            LDD   #TRUEV
            BRA   SSDONE
SSFAIL:     LDD   #FALSEV
SSDONE:     LDX   #TSTSPACESNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSPACESNAME:
            FCB   9
            FCC   "TSTSPACES"

; ------------------------------------------------------------
; unit test for SPACES, n<=0 case. Documented behavior is
; "no output if n <= 0" - verifies OUTHEAD genuinely doesn't
; advance at all, not just that the call didn't crash.
; TSTSPACESZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSPACESZ OK" or "TSTSPACESZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSPACESZ: LDA   OUTHEAD
            STA   TSTOHSAV

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   SPACESW

            STU   TSTUAF

            LDA   TSTOHSAV
            CMPA  OUTHEAD
            BNE   S0FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   S0FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   S0FAIL

            LDD   #TRUEV
            BRA   S0DONE
S0FAIL:     LDD   #FALSEV
S0DONE:     LDX   #TSTSPACESZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSPACESZNAME:
            FCB   10
            FCC   "TSTSPACESZ"

; ------------------------------------------------------------
; unit test for TYPE. Writes a known 2-character string into
; scratch, calls TYPE on it, and verifies both queued bytes
; genuinely match the source string, in order - not just
; that OUTHEAD advanced by the right count.
; TSTTYPE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTYPE OK" or "TSTTYPE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTYPE:    LDA   #'A'
            STA   TSTNAMEB
            LDA   #'B'
            STA   TSTNAMEB+1

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNAMEB
            PSHU  D
            LDD   #2
            PSHU  D
            STU   TSTUB4

            JSR   TYPEW

            STU   TSTUAF

            IFEQ  SERIALPOLL        ; >>>> full check: interrupt-driven EMIT
                                    ; (called internally by TYPE for each
                                    ; character) queues both bytes into OUTBUF,
                                    ; verifiable in order
            LDA   TSTOHSAV
            ADDA  #2
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   TEFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'A'
            BNE   TEFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'B'
            BNE   TEFAIL
            ELSE                    ; <<<<>>>> See bugfix: TSTTYPE.1
            LDA   EMITCH
            CMPA  #'B'
            BNE   TEFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   TEFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   TEFAIL

            LDD   #TRUEV
            BRA   TEDONE
TEFAIL:     LDD   #FALSEV
TEDONE:     LDX   #TSTTYPENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTYPENAME:
            FCB   7
            FCC   "TSTTYPE"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; data stack operation tests.
; TSTSTACK
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTSTACK.0.
; ------------------------------------------------------------
TSTSTACK:   JSR   CRW
            LDX   #TSTSTACKMSG
            PSHU  X
            LDD   #5
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-1     ; >>>>

            JSR   TSTDUP
            JSR   TSTDROP
            JSR   TSTSWAP
            JSR   TSTOVER
            JSR   TSTROT
            JSR   TSTQDUPNZ
            JSR   TSTQDUPZ
            JSR   TSTDEPTH
            JSR   TSTDDUP
            JSR   TSTDDROP
            JSR   TSTDSWAP
            JSR   TSTDOVER
            JSR   TSTNIP
            JSR   TSTTUCK
            JSR   TSTPICK
            JSR   TSTROLL
            JSR   TSTDROT

            ENDC                    ; <<<<

            RTS

TSTSTACKMSG:
            FCC   "Stack"

            IFEQ  TSTSELECTOR-1     ; >>>>

; ------------------------------------------------------------
; unit test for DUP ( x -- x x ). Verifies both the stack's
; contents (the duplicate and the original both equal the
; pushed test value, and the guard beneath is undisturbed)
; and the data stack pointer's movement (exactly one cell, 2
; bytes - DUP's own net effect, not conflated with the two
; pushes that set the test up).
; TSTDUP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDUP OK" or "TSTDUP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDUP:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   DUPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   TDFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   TDFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   TDFAIL

            LDD   #TRUEV
            BRA   TDDONE
TDFAIL:     LDD   #FALSEV
TDDONE:     LDX   #TSTDUPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDUPNAME: FCB   6
            FCC   "TSTDUP"

; ------------------------------------------------------------
; unit test for DROP ( x -- ). Verifies both the stack's
; contents (the guard beneath the dropped value is left
; undisturbed, and is now the new top) and the data stack
; pointer's movement (exactly one cell, 2 bytes, freed -
; DROP's own net effect, not conflated with the two pushes
; that set the test up).
; TSTDROP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDROP OK" or "TSTDROP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDROP:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   DROPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   DPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   DPFAIL

            LDD   #TRUEV
            BRA   DPDONE
DPFAIL:     LDD   #FALSEV
DPDONE:     LDX   #TSTDROPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDROPNAME:
            FCB   7
            FCC   "TSTDROP"

; ------------------------------------------------------------
; unit test for SWAP ( n1 n2 -- n2 n1 ). Verifies the two
; items exchange places, the guard beneath is undisturbed,
; and the net stack depth is unchanged.
; TSTSWAP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSWAP OK" or "TSTSWAP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSWAP:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   SWAPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   SWFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   SWFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SWFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   SWFAIL

            LDD   #TRUEV
            BRA   SWDONE
SWFAIL:     LDD   #FALSEV
SWDONE:     LDX   #TSTSWAPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSWAPNAME:
            FCB   7
            FCC   "TSTSWAP"

; ------------------------------------------------------------
; unit test for OVER ( n1 n2 -- n1 n2 n1 ). Verifies the
; copy of n1 is correct, the originals and guard are
; undisturbed, and exactly one cell was added.
; TSTOVER
;    Inputs:
;        none
;    Outputs:
;        prints "TSTOVER OK" or "TSTOVER FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTOVER:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   OVERW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   OVFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   OVFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   OVFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   OVFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   OVFAIL

            LDD   #TRUEV
            BRA   OVDONE
OVFAIL:     LDD   #FALSEV
OVDONE:     LDX   #TSTOVERNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTOVERNAME:
            FCB   7
            FCC   "TSTOVER"

; ------------------------------------------------------------
; unit test for ROT ( n1 n2 n3 -- n2 n3 n1 ). Verifies the
; rotation order, the guard beneath is undisturbed, and the
; net stack depth is unchanged.
; TSTROT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTROT OK" or "TSTROT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTROT:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            STU   TSTUB4

            JSR   ROTW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   RTFAIL
            PULU  D
            CMPD  #TSTVAL3
            BNE   RTFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   RTFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   RTFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   RTFAIL

            LDD   #TRUEV
            BRA   RTDONE
RTFAIL:     LDD   #FALSEV
RTDONE:     LDX   #TSTROTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTROTNAME: FCB   6
            FCC   "TSTROT"

; ------------------------------------------------------------
; unit test for ?DUP ( n -- n n | 0 ), nonzero case.
; Verifies the nonzero value is duplicated, the guard
; beneath is undisturbed, and exactly one cell was added -
; same as DUP's own behavior for this case. ?DUP needs two
; tests, one per condition, since DUP-like and no-op are
; genuinely different code paths (QDUP branches on the
; popped value).
; TSTQDUPNZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTQDUPNZ OK" or "TSTQDUPNZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTQDUPNZ:  STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   QDUPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   QNFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   QNFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   QNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   QNFAIL

            LDD   #TRUEV
            BRA   QNDONE
QNFAIL:     LDD   #FALSEV
QNDONE:     LDX   #TSTQNNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTQNNAME:  FCB   9
            FCC   "TSTQDUPNZ"

; ------------------------------------------------------------
; unit test for ?DUP ( n -- n n | 0 ), zero case. Verifies
; zero is left alone - no duplicate is pushed - the guard
; beneath is undisturbed, and the net stack depth is
; unchanged.
; TSTQDUPZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTQDUPZ OK" or "TSTQDUPZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTQDUPZ:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   QDUPW

            STU   TSTUAF

            PULU  D
            CMPD  #0
            BNE   QZFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   QZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   QZFAIL

            LDD   #TRUEV
            BRA   QZDONE
QZFAIL:     LDD   #FALSEV
QZDONE:     LDX   #TSTQZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTQZNAME:  FCB   8
            FCC   "TSTQDUPZ"

; ------------------------------------------------------------
; unit test for DEPTH ( -- n ).
; TSTDEPTH
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDEPTH OK" or "TSTDEPTH FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTDEPTH.0.
; ------------------------------------------------------------
TSTDEPTH:   STU   TSTU0

            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            STU   TSTUB4

            JSR   DEPTHW

            STU   TSTUAF

            LDD   #SP0
            SUBD  TSTUB4
            LSRA
            RORB
            STD   TSTSCR

            PULU  D
            CMPD  TSTSCR
            BNE   DHFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   DHFAIL

            PULU  D
            CMPD  #TSTVAL3
            BNE   DHFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   DHFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   DHFAIL

            LDD   #TRUEV
            BRA   DHDONE
DHFAIL:     LDD   #FALSEV
DHDONE:     LDX   #TSTDEPTHNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDEPTHNAME:
            FCB   8
            FCC   "TSTDEPTH"

; ------------------------------------------------------------
; unit test for 2DUP ( x1 x2 -- x1 x2 x1 x2 ). Verifies the
; duplicated pair, the originals and guard are undisturbed,
; and exactly two cells were added.
; TSTDDUP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDDUP OK" or "TSTDDUP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDDUP:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   DDUPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   DU2FAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   DU2FAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   DU2FAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   DU2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DU2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   DU2FAIL

            LDD   #TRUEV
            BRA   DU2DONE
DU2FAIL:    LDD   #FALSEV
DU2DONE:    LDX   #TSTDDUPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDDUPNAME:
            FCB   7
            FCC   "TSTDDUP"

; ------------------------------------------------------------
; unit test for 2DROP ( x1 x2 -- ). Verifies both items are
; removed, the guard beneath is undisturbed, and exactly two
; cells were freed.
; TSTDDROP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDDROP OK" or "TSTDDROP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDDROP:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   DDROPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   DR2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   DR2FAIL

            LDD   #TRUEV
            BRA   DR2DONE
DR2FAIL:    LDD   #FALSEV
DR2DONE:    LDX   #TSTDDROPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDDROPNAME:
            FCB   8
            FCC   "TSTDDROP"

; ------------------------------------------------------------
; unit test for 2SWAP ( x1 x2 x3 x4 -- x3 x4 x1 x2 ).
; Verifies the two pairs exchange places, the guard beneath
; is undisturbed, and the net stack depth is unchanged.
; TSTDSWAP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDSWAP OK" or "TSTDSWAP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDSWAP:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            LDD   #TSTVAL4
            PSHU  D
            STU   TSTUB4

            JSR   DSWAPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   SW2FAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   SW2FAIL
            PULU  D
            CMPD  #TSTVAL4
            BNE   SW2FAIL
            PULU  D
            CMPD  #TSTVAL3
            BNE   SW2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SW2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   SW2FAIL

            LDD   #TRUEV
            BRA   SW2DONE
SW2FAIL:    LDD   #FALSEV
SW2DONE:    LDX   #TSTDSWAPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDSWAPNAME:
            FCB   8
            FCC   "TSTDSWAP"

; ------------------------------------------------------------
; unit test for 2OVER ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 ).
; Verifies the copied pair, the originals and guard are
; undisturbed, and exactly two cells were added.
; TSTDOVER
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDOVER OK" or "TSTDOVER FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDOVER:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            LDD   #TSTVAL4
            PSHU  D
            STU   TSTUB4

            JSR   DOVERW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   OV2FAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   OV2FAIL
            PULU  D
            CMPD  #TSTVAL4
            BNE   OV2FAIL
            PULU  D
            CMPD  #TSTVAL3
            BNE   OV2FAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   OV2FAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   OV2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   OV2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   OV2FAIL

            LDD   #TRUEV
            BRA   OV2DONE
OV2FAIL:    LDD   #FALSEV
OV2DONE:    LDX   #TSTDOVERNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDOVERNAME:
            FCB   8
            FCC   "TSTDOVER"

; ------------------------------------------------------------
; unit test for NIP ( x1 x2 -- x2 ). Verifies the second
; item is discarded, x2 is left on top, the guard beneath is
; undisturbed, and exactly one cell was freed.
; TSTNIP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTNIP OK" or "TSTNIP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTNIP:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   NIPW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   NPFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   NPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   NPFAIL

            LDD   #TRUEV
            BRA   NPDONE
NPFAIL:     LDD   #FALSEV
NPDONE:     LDX   #TSTNIPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTNIPNAME: FCB   6
            FCC   "TSTNIP"

; ------------------------------------------------------------
; unit test for TUCK ( x1 x2 -- x2 x1 x2 ). Verifies the
; copy of x2 is tucked correctly beneath x1, the guard
; beneath is undisturbed, and exactly one cell was added.
; TSTTUCK
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTUCK OK" or "TSTTUCK FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTUCK:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   TUCKW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   TKFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   TKFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   TKFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TKFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   TKFAIL

            LDD   #TRUEV
            BRA   TKDONE
TKFAIL:     LDD   #FALSEV
TKDONE:     LDX   #TSTTUCKNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTUCKNAME:
            FCB   7
            FCC   "TSTTUCK"

; ------------------------------------------------------------
; unit test for PICK ( xu ... x0 u -- xu ... x0 xu ), using
; u=2 as a concrete representative case (0 PICK is DUP, 1
; PICK is OVER; 2 PICK is the first case distinct from
; both).
; TSTPICK
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPICK OK" or "TSTPICK FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTPICK.0.
; ------------------------------------------------------------
TSTPICK:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            LDD   #2
            PSHU  D
            STU   TSTUB4

            JSR   PICKW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   PKFAIL
            PULU  D
            CMPD  #TSTVAL3
            BNE   PKFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   PKFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   PKFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   PKFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   PKFAIL

            LDD   #TRUEV
            BRA   PKDONE
PKFAIL:     LDD   #FALSEV
PKDONE:     LDX   #TSTPICKNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPICKNAME:
            FCB   7
            FCC   "TSTPICK"

; ------------------------------------------------------------
; unit test for ROLL ( xu ... x0 u -- xu-1 ... x0 xu ),
; using u=2 as a concrete representative case (matches
; TSTPICK's own choice of u, so the two tests are directly
; comparable).
; TSTROLL
;    Inputs:
;        none
;    Outputs:
;        prints "TSTROLL OK" or "TSTROLL FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTROLL.0.
; ------------------------------------------------------------
TSTROLL:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            LDD   #2
            PSHU  D
            STU   TSTUB4

            JSR   ROLLW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   RLFAIL
            PULU  D
            CMPD  #TSTVAL3
            BNE   RLFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   RLFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   RLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   RLFAIL

            LDD   #TRUEV
            BRA   RLDONE
RLFAIL:     LDD   #FALSEV
RLDONE:     LDX   #TSTROLLNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTROLLNAME:
            FCB   7
            FCC   "TSTROLL"

; ------------------------------------------------------------
; unit test for 2ROT ( x1 x2 x3 x4 x5 x6 -- x3 x4 x5 x6 x1
; x2 ). Verifies the rotation order of all three cell pairs,
; the guard beneath is undisturbed, and the net stack depth
; is unchanged.
; TSTDROT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDROT OK" or "TSTDROT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDROT:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            LDD   #TSTVAL4
            PSHU  D
            LDD   #TSTVAL5
            PSHU  D
            LDD   #TSTVAL6
            PSHU  D
            STU   TSTUB4

            JSR   DROTW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   RO2FAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   RO2FAIL
            PULU  D
            CMPD  #TSTVAL6
            BNE   RO2FAIL
            PULU  D
            CMPD  #TSTVAL5
            BNE   RO2FAIL
            PULU  D
            CMPD  #TSTVAL4
            BNE   RO2FAIL
            PULU  D
            CMPD  #TSTVAL3
            BNE   RO2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   RO2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   RO2FAIL

            LDD   #TRUEV
            BRA   RO2DONE
RO2FAIL:    LDD   #FALSEV
RO2DONE:    LDX   #TSTDROTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDROTNAME:
            FCB   7
            FCC   "TSTDROT"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; return-stack tests (glossary section 3.3, 6 words, 4 tests
; since >R/R> and 2>R/2R> are each combined into one
; round-trip test, matching how they can only be
; meaningfully tested together - the "must be balanced
; within the same definition" constraint each word's own
; glossary entry documents).
; TSTRETSTACK
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTRETSTACK.0.
; ------------------------------------------------------------
TSTRETSTACK:
            JSR   CRW
            LDX   #TSTRETMSG
            PSHU  X
            LDD   #8
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-2     ; >>>>

            JSR   TSTTOR
            JSR   TSTRFETCH
            JSR   TSTTWOTOR
            JSR   TSTTWORFETCH

            ENDC                    ; <<<<

            RTS

TSTRETMSG:  FCC   "RetStack"

            IFEQ  TSTSELECTOR-2     ; >>>>

; ------------------------------------------------------------
; Return-stack test harness (glossary section 3.3).
; Original comment: shadow TSTRETSTACK.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for >R and R> together. Includes an intermediate
; check (right after >R, before R>) confirming the value
; genuinely left the data stack - a pure round-trip check
; could pass even if both words were broken no-ops, since
; the value would never actually have left.
; TSTTOR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTOR OK" or "TSTTOR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTOR:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   TORW

            STU   TSTUMID

            LDD   TSTUB4
            SUBD  TSTUMID
            CMPD  #-2
            BNE   TRFAIL

            JSR   FROMRW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   TRFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   TRFAIL

            LDD   #TRUEV
            BRA   TRDONE
TRFAIL:     LDD   #FALSEV
TRDONE:     LDX   #TSTTORNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTORNAME: FCB   6
            FCC   "TSTTOR"

; ------------------------------------------------------------
; unit test for R@. Moves a value to the return stack via
; >R, peeks it via R@ (verifying the copy matches), then
; retrieves the original via R> (verifying R@ genuinely left
; it there undisturbed, not just that R@ itself returned the
; right value once) - confirming "non-destructive" for real,
; not assumed from the name.
; TSTRFETCH
;    Inputs:
;        none
;    Outputs:
;        prints "TSTRFETCH OK" or "TSTRFETCH FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTRFETCH:  STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   TORW
            JSR   RFETCHW
            JSR   FROMRW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   RFFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   RFFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   RFFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   RFFAIL

            LDD   #TRUEV
            BRA   RFDONE
RFFAIL:     LDD   #FALSEV
RFDONE:     LDX   #TSTRFETCHNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTRFETCHNAME:
            FCB   9
            FCC   "TSTRFETCH"

; ------------------------------------------------------------
; unit test for 2>R and 2R> together. Same
; intermediate-check reasoning as TSTTOR, applied to the
; pair - confirms both cells genuinely left the data stack
; before verifying the round trip.
; TSTTWOTOR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTWOTOR OK" or "TSTTWOTOR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTWOTOR:  STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   TWOTORW

            STU   TSTUMID

            LDD   TSTUB4
            SUBD  TSTUMID
            CMPD  #-4
            BNE   T2RFAIL

            JSR   TWOFROMRW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   T2RFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   T2RFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   T2RFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   T2RFAIL

            LDD   #TRUEV
            BRA   T2RDONE
T2RFAIL:    LDD   #FALSEV
T2RDONE:    LDX   #TSTTWOTORNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTWOTORNAME:
            FCB   9
            FCC   "TSTTWOTOR"

; ------------------------------------------------------------
; unit test for 2R@. Same reasoning as TSTRFETCH, applied to
; the pair: moves x1,x2 to the return stack via 2>R, peeks
; via 2R@ (verifying both cells, correctly ordered), then
; retrieves the originals via 2R> (verifying 2R@ genuinely
; left them there undisturbed).
; TSTTWORFETCH
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTWORFETCH OK" or "TSTTWORFETCH FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTWORFETCH:
            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   TWOTORW
            JSR   TWORFETCHW
            JSR   TWOFROMRW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   T2FFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   T2FFAIL
            PULU  D
            CMPD  #TSTVAL2
            BNE   T2FFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   T2FFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   T2FFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   T2FFAIL

            LDD   #TRUEV
            BRA   T2FDONE
T2FFAIL:    LDD   #FALSEV
T2FDONE:    LDX   #TSTTWORFETCHNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTWORFETCHNAME:
            FCB   12
            FCC   "TSTTWORFETCH"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; single-cell arithmetic tests (glossary section 3.4).
; TSTSARITH
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTSARITH.0.
; ------------------------------------------------------------
TSTSARITH:  JSR   CRW
            LDX   #TSTSARITHMSG
            PSHU  X
            LDD   #11
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-3     ; >>>>

            JSR   TSTPLUS
            JSR   TSTMINUS
            JSR   TSTSTAR1
            JSR   TSTSTAR2
            JSR   TSTSLASH1
            JSR   TSTSLASH2
            JSR   TSTSLASHZ
            JSR   TSTMODW
            JSR   TSTMODZ
            JSR   TSTSLMOD
            JSR   TSTSLMODZ
            JSR   TSTNEGATE
            JSR   TSTABS1
            JSR   TSTABS2
            JSR   TSTMIN1
            JSR   TSTMIN2
            JSR   TSTMAX1
            JSR   TSTMAX2
            JSR   TSTONEP
            JSR   TSTONEM
            JSR   TSTTWOP
            JSR   TSTTWOS
            JSR   TSTTWOD1
            JSR   TSTTWOD2
            JSR   TSTSTSL
            JSR   TSTSTSLZ
            JSR   TSTSTSM
            JSR   TSTSTSMZ

            ENDC                    ; <<<<

            RTS

TSTSARITHMSG:
            FCC   "SArithmetic"

            IFEQ  TSTSELECTOR-3     ; >>>>

; ------------------------------------------------------------
; unit test for PLUS. n1 + n2, mixed signs.
; TSTPLUS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPLUS OK" or "TSTPLUS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTPLUS:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   PLUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$29A8
            BNE   PLFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   PLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   PLFAIL

            LDD   #TRUEV
            BRA   PLDONE
PLFAIL:     LDD   #FALSEV
PLDONE:     LDX   #TSTPLUSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPLUSNAME:
            FCB   7
            FCC   "TSTPLUS"

; ------------------------------------------------------------
; unit test for MINUS. n1 - n2 (operand order matters).
; TSTMINUS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMINUS OK" or "TSTMINUS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMINUS:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   MINUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$3579
            BNE   MNFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   MNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   MNFAIL

            LDD   #TRUEV
            BRA   MNDONE
MNFAIL:     LDD   #FALSEV
MNDONE:     LDX   #TSTMINUSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMINUSNAME:
            FCB   8
            FCC   "TSTMINUS"

; ------------------------------------------------------------
; unit test for STAR. normal signed multiply.
; TSTSTAR1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTAR1 OK" or "TSTSTAR1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSTAR1:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTNEG2
            PSHU  D
            STU   TSTUB4

            JSR   STARW

            STU   TSTUAF

            PULU  D
            CMPD  #$5998
            BNE   S1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   S1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   S1FAIL

            LDD   #TRUEV
            BRA   S1DONE
S1FAIL:     LDD   #FALSEV
S1DONE:     LDX   #TSTSTAR1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTAR1NAME:
            FCB   8
            FCC   "TSTSTAR1"

; ------------------------------------------------------------
; unit test for STAR. overflow case - product exceeds 16-bit
; range; ANS defines * as truncating, not erroring.
; TSTSTAR2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTAR2 OK" or "TSTSTAR2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSTAR2:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$03E8
            PSHU  D
            LDD   #$03E8
            PSHU  D
            STU   TSTUB4

            JSR   STARW

            STU   TSTUAF

            PULU  D
            CMPD  #$4240
            BNE   S2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   S2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   S2FAIL

            LDD   #TRUEV
            BRA   S2DONE
S2FAIL:     LDD   #FALSEV
S2DONE:     LDX   #TSTSTAR2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTAR2NAME:
            FCB   8
            FCC   "TSTSTAR2"

; ------------------------------------------------------------
; unit test for SLASH. normal signed symmetric division
; (quotient only - SLASH pushes DIVNUM, not the remainder
; too).
; TSTSLASH1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLASH1 OK" or "TSTSLASH1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSLASH1:  STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   SLASHW

            STU   TSTUAF

            PULU  D
            CMPD  #$0002
            BNE   SLFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   SLFAIL

            LDD   #TRUEV
            BRA   SLDONE
SLFAIL:     LDD   #FALSEV
SLDONE:     LDX   #TSTSLASH1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSLASH1NAME:
            FCB   9
            FCC   "TSTSLASH1"

; ------------------------------------------------------------
; unit test for SLASH. negative dividend, symmetric
; division.
; TSTSLASH2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLASH2 OK" or "TSTSLASH2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSLASH2:  STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   SLASHW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   SNFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   SNFAIL

            LDD   #TRUEV
            BRA   SNDONE
SNFAIL:     LDD   #FALSEV
SNDONE:     LDX   #TSTSLASH2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSLASH2NAME:
            FCB   9
            FCC   "TSTSLASH2"

; ------------------------------------------------------------
; unit test for SLASH, divide-by-zero case. n2 = 0.
; TSTSLASHZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLASHZ OK" or "TSTSLASHZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSLASHZ.0.
; ------------------------------------------------------------
TSTSLASHZ:  STU   TSTU0

            LDD   #TSTVAL1
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #SLASHW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   SZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   SZFAIL

            LDD   #TRUEV
            BRA   SZDONE
SZFAIL:     LDD   #FALSEV
SZDONE:     LDX   #TSTSLASHZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSLASHZNAME:
            FCB   9
            FCC   "TSTSLASHZ"

; ------------------------------------------------------------
; unit test for MODW. negative dividend, symmetric
; remainder.
; TSTMODW
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMODW OK" or "TSTMODW FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMODW:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   MODW

            STU   TSTUAF

            PULU  D
            CMPD  #$F42F
            BNE   MDFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   MDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   MDFAIL

            LDD   #TRUEV
            BRA   MDDONE
MDFAIL:     LDD   #FALSEV
MDDONE:     LDX   #TSTMODWNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMODWNAME:
            FCB   7
            FCC   "TSTMODW"

; ------------------------------------------------------------
; unit test for MODW, divide-by-zero case. n2 = 0.
; TSTMODZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMODZ OK" or "TSTMODZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTMODZ.0.
; ------------------------------------------------------------
TSTMODZ:    STU   TSTU0

            LDD   #TSTVAL1
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #MODW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   MZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   MZFAIL

            LDD   #TRUEV
            BRA   MZDONE
MZFAIL:     LDD   #FALSEV
MZDONE:     LDX   #TSTMODZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMODZNAME:
            FCB   7
            FCC   "TSTMODZ"

; ------------------------------------------------------------
; unit test for SLASHMOD. /MOD together - both remainder and
; quotient.
; TSTSLMOD
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLMOD OK" or "TSTSLMOD FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSLMOD:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTNEG2
            PSHU  D
            STU   TSTUB4

            JSR   SLASHMODW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFB9
            BNE   SMFAIL
            PULU  D
            CMPD  #$00DA
            BNE   SMFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   SMFAIL

            LDD   #TRUEV
            BRA   SMDONE
SMFAIL:     LDD   #FALSEV
SMDONE:     LDX   #TSTSLMODNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSLMODNAME:
            FCB   8
            FCC   "TSTSLMOD"

; ------------------------------------------------------------
; unit test for SLASHMOD, divide-by-zero case. n2 = 0.
; TSTSLMODZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLMODZ OK" or "TSTSLMODZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSLMODZ.0.
; ------------------------------------------------------------
TSTSLMODZ:  STU   TSTU0

            LDD   #TSTVAL1
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #SLASHMODW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   MXFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   MXFAIL

            LDD   #TRUEV
            BRA   MXDONE
MXFAIL:     LDD   #FALSEV
MXDONE:     LDX   #TSTSLMODZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSLMODZNAME:
            FCB   9
            FCC   "TSTSLMODZ"

; ------------------------------------------------------------
; unit test for NEGATE. two's-complement negate.
; TSTNEGATE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTNEGATE OK" or "TSTNEGATE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTNEGATE:  STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   NEGATEW

            STU   TSTUAF

            PULU  D
            CMPD  #$A61F
            BNE   NGFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   NGFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   NGFAIL

            LDD   #TRUEV
            BRA   NGDONE
NGFAIL:     LDD   #FALSEV
NGDONE:     LDX   #TSTNEGATENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTNEGATENAME:
            FCB   9
            FCC   "TSTNEGATE"

; ------------------------------------------------------------
; unit test for ABSW. positive input - already non-negative,
; unchanged.
; TSTABS1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTABS1 OK" or "TSTABS1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTABS1:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   ABSW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   A1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   A1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   A1FAIL

            LDD   #TRUEV
            BRA   A1DONE
A1FAIL:     LDD   #FALSEV
A1DONE:     LDX   #TSTABS1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTABS1NAME:
            FCB   7
            FCC   "TSTABS1"

; ------------------------------------------------------------
; unit test for ABSW. negative input - the branch that
; actually negates.
; TSTABS2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTABS2 OK" or "TSTABS2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTABS2:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   ABSW

            STU   TSTUAF

            PULU  D
            CMPD  #$3039
            BNE   A2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   A2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   A2FAIL

            LDD   #TRUEV
            BRA   A2DONE
A2FAIL:     LDD   #FALSEV
A2DONE:     LDX   #TSTABS2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTABS2NAME:
            FCB   7
            FCC   "TSTABS2"

; ------------------------------------------------------------
; unit test for MIN. n1 < n2 - n1 is the min, left
; unchanged.
; TSTMIN1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMIN1 OK" or "TSTMIN1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMIN1:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   MINW

            STU   TSTUAF

            PULU  D
            CMPD  #$CFC7
            BNE   N1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   N1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   N1FAIL

            LDD   #TRUEV
            BRA   N1DONE
N1FAIL:     LDD   #FALSEV
N1DONE:     LDX   #TSTMIN1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMIN1NAME:
            FCB   7
            FCC   "TSTMIN1"

; ------------------------------------------------------------
; unit test for MIN. n1 > n2 - n2 is the min, replaces n1.
; TSTMIN2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMIN2 OK" or "TSTMIN2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMIN2:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   MINW

            STU   TSTUAF

            PULU  D
            CMPD  #$CFC7
            BNE   N2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   N2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   N2FAIL

            LDD   #TRUEV
            BRA   N2DONE
N2FAIL:     LDD   #FALSEV
N2DONE:     LDX   #TSTMIN2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMIN2NAME:
            FCB   7
            FCC   "TSTMIN2"

; ------------------------------------------------------------
; unit test for MAX. n1 < n2 - n2 is the max, replaces n1.
; TSTMAX1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMAX1 OK" or "TSTMAX1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMAX1:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   MAXW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   X1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   X1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   X1FAIL

            LDD   #TRUEV
            BRA   X1DONE
X1FAIL:     LDD   #FALSEV
X1DONE:     LDX   #TSTMAX1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMAX1NAME:
            FCB   7
            FCC   "TSTMAX1"

; ------------------------------------------------------------
; unit test for MAX. n1 > n2 - n1 is the max, left
; unchanged.
; TSTMAX2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMAX2 OK" or "TSTMAX2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMAX2:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   MAXW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   X2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   X2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   X2FAIL

            LDD   #TRUEV
            BRA   X2DONE
X2FAIL:     LDD   #FALSEV
X2DONE:     LDX   #TSTMAX2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMAX2NAME:
            FCB   7
            FCC   "TSTMAX2"

; ------------------------------------------------------------
; unit test for ONEPLUS. add one.
; TSTONEP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTONEP OK" or "TSTONEP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTONEP:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   ONEPLUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$59E2
            BNE   OPFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   OPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   OPFAIL

            LDD   #TRUEV
            BRA   OPDONE
OPFAIL:     LDD   #FALSEV
OPDONE:     LDX   #TSTONEPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTONEPNAME:
            FCB   7
            FCC   "TSTONEP"

; ------------------------------------------------------------
; unit test for ONEMINUS. subtract one.
; TSTONEM
;    Inputs:
;        none
;    Outputs:
;        prints "TSTONEM OK" or "TSTONEM FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTONEM:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   ONEMINUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$59E0
            BNE   OMFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   OMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   OMFAIL

            LDD   #TRUEV
            BRA   OMDONE
OMFAIL:     LDD   #FALSEV
OMDONE:     LDX   #TSTONEMNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTONEMNAME:
            FCB   7
            FCC   "TSTONEM"

; ------------------------------------------------------------
; unit test for TWOPLUS. add two (not ANS-standard).
; TSTTWOP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTWOP OK" or "TSTTWOP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTWOP:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   TWOPLUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$59E3
            BNE   TPFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   TPFAIL

            LDD   #TRUEV
            BRA   TPDONE
TPFAIL:     LDD   #FALSEV
TPDONE:     LDX   #TSTTWOPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTWOPNAME:
            FCB   7
            FCC   "TSTTWOP"

; ------------------------------------------------------------
; unit test for TWOSTAR. arithmetic shift left one bit.
; TSTTWOS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTWOS OK" or "TSTTWOS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTWOS:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   TWOSTARW

            STU   TSTUAF

            PULU  D
            CMPD  #$48D0
            BNE   TWFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TWFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   TWFAIL

            LDD   #TRUEV
            BRA   TWDONE
TWFAIL:     LDD   #FALSEV
TWDONE:     LDX   #TSTTWOSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTWOSNAME:
            FCB   7
            FCC   "TSTTWOS"

; ------------------------------------------------------------
; unit test for TWOSLASH. positive input, arithmetic shift
; right.
; TSTTWOD1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTWOD1 OK" or "TSTTWOD1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTWOD1:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   TWOSLASHW

            STU   TSTUAF

            PULU  D
            CMPD  #$1234
            BNE   D1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   D1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   D1FAIL

            LDD   #TRUEV
            BRA   D1DONE
D1FAIL:     LDD   #FALSEV
D1DONE:     LDX   #TSTTWOD1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTWOD1NAME:
            FCB   8
            FCC   "TSTTWOD1"

; ------------------------------------------------------------
; unit test for TWOSLASH. negative input - the case that
; actually tests sign-preservation.
; TSTTWOD2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTWOD2 OK" or "TSTTWOD2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTWOD2:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   TWOSLASHW

            STU   TSTUAF

            PULU  D
            CMPD  #$E7E3
            BNE   D2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   D2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   D2FAIL

            LDD   #TRUEV
            BRA   D2DONE
D2FAIL:     LDD   #FALSEV
D2DONE:     LDX   #TSTTWOD2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTWOD2NAME:
            FCB   8
            FCC   "TSTTWOD2"

; ------------------------------------------------------------
; unit test for STARSLASH. n1*n2/n3 via double-cell
; intermediate, no truncation until final divide.
; TSTSTSL
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTSL OK" or "TSTSTSL FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSTSL:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            STU   TSTUB4

            JSR   STARSLASHW

            STU   TSTUAF

            PULU  D
            CMPD  #$1A8D
            BNE   TSFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   TSFAIL

            LDD   #TRUEV
            BRA   TSDONE
TSFAIL:     LDD   #FALSEV
TSDONE:     LDX   #TSTSTSLNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTSLNAME:
            FCB   7
            FCC   "TSTSTSL"

; ------------------------------------------------------------
; unit test for STARSLASH, divide-by-zero case. n3 = 0.
; TSTSTSLZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTSLZ OK" or "TSTSTSLZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSTSLZ.0.
; ------------------------------------------------------------
TSTSTSLZ:   STU   TSTU0

            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #STARSLASHW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   TZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   TZFAIL

            LDD   #TRUEV
            BRA   TZDONE
TZFAIL:     LDD   #FALSEV
TZDONE:     LDX   #TSTSTSLZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTSLZNAME:
            FCB   8
            FCC   "TSTSTSLZ"

; ------------------------------------------------------------
; unit test for STARSLASHMOD. */MOD together - remainder and
; quotient.
; TSTSTSM
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTSM OK" or "TSTSTSM FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSTSM:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTVAL3
            PSHU  D
            STU   TSTUB4

            JSR   STARSLASHMODW

            STU   TSTUAF

            PULU  D
            CMPD  #$F1C2
            BNE   TMFAIL
            PULU  D
            CMPD  #$939E
            BNE   TMFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   TMFAIL

            LDD   #TRUEV
            BRA   TMDONE
TMFAIL:     LDD   #FALSEV
TMDONE:     LDX   #TSTSTSMNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTSMNAME:
            FCB   7
            FCC   "TSTSTSM"

; ------------------------------------------------------------
; unit test for STARSLASHMOD, divide-by-zero case. n3 = 0.
; TSTSTSMZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTSMZ OK" or "TSTSTSMZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSTSMZ.0.
; ------------------------------------------------------------
TSTSTSMZ:   STU   TSTU0

            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #STARSLASHMODW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   TXFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   TXFAIL

            LDD   #TRUEV
            BRA   TXDONE
TXFAIL:     LDD   #FALSEV
TXDONE:     LDX   #TSTSTSMZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTSMZNAME:
            FCB   8
            FCC   "TSTSTSMZ"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; mixed & double-precision arithmetic tests (glossary
; section 3.5).
; TSTDARITH
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTDARITH.0.
; ------------------------------------------------------------
TSTDARITH:  JSR   CRW
            LDX   #TSTDARITHMSG
            PSHU  X
            LDD   #11
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-4     ; >>>>

            JSR   TSTUMST
            JSR   TSTUMSM
            JSR   TSTUMSM2
            JSR   TSTUMSZ
            JSR   TSTMSTAR
            JSR   TSTFMSM
            JSR   TSTFMSZ
            JSR   TSTSMRM
            JSR   TSTSMRZ
            JSR   TSTDPLUS
            JSR   TSTDMIN2
            JSR   TSTDNEG
            JSR   TSTDABS1
            JSR   TSTDABS2
            JSR   TSTMPLUS
            JSR   TSTSTOD
            JSR   TSTDTOS
            JSR   TSTDMAX
            JSR   TSTDMIN

            ENDC                    ; <<<<

            RTS

TSTDARITHMSG:
            FCC   "DArithmetic"

            IFEQ  TSTSELECTOR-4     ; >>>>

; ------------------------------------------------------------
; unit test for UMSTAR. unsigned single*single->double.
; TSTUMST
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUMST OK" or "TSTUMST FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUMST:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   UMSTARW

            STU   TSTUAF

            PULU  D
            CMPD  #$0CC8
            BNE   UMFAIL
            PULU  D
            CMPD  #$2768
            BNE   UMFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   UMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   UMFAIL

            LDD   #TRUEV
            BRA   UMDONE
UMFAIL:     LDD   #FALSEV
UMDONE:     LDX   #TSTUMSTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUMSTNAME:
            FCB   7
            FCC   "TSTUMST"

; ------------------------------------------------------------
; unit test for UMSLASHMOD. unsigned double/single ->
; remainder, quotient.
; TSTUMSM
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUMSM OK" or "TSTUMSM FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUMSM:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   UMSLASHMODW

            STU   TSTUAF

            PULU  D
            CMPD  #$0007
            BNE   UDFAIL
            PULU  D
            CMPD  #$1298
            BNE   UDFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   UDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   UDFAIL

            LDD   #TRUEV
            BRA   UDDONE
UDFAIL:     LDD   #FALSEV
UDDONE:     LDX   #TSTUMSMNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUMSMNAME:
            FCB   7
            FCC   "TSTUMSM"

; ------------------------------------------------------------
; unit test for UMSLASHMOD, MAX-UINT/MAX-UINT boundary case
; (ANS Annex F F.6.1.2370: "MAX-UINT MAX-UINT UM* MAX-UINT
; UM/MOD -> 0 MAX-UINT").
; TSTUMSM2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUMSM2 OK" or "TSTUMSM2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTUMSM2.0.
; ------------------------------------------------------------
TSTUMSM2:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$0001
            PSHU  D
            LDD   #$FFFE
            PSHU  D
            LDD   #$FFFF
            PSHU  D
            STU   TSTUB4

            JSR   UMSLASHMODW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   UM2FAIL
            PULU  D
            CMPD  #$0000
            BNE   UM2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   UM2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   UM2FAIL

            LDD   #TRUEV
            BRA   UM2DONE
UM2FAIL:    LDD   #FALSEV
UM2DONE:    LDX   #TSTUMSM2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUMSM2NAME:
            FCB   8
            FCC   "TSTUMSM2"

; ------------------------------------------------------------
; unit test for MSTAR. signed single*single->double.
; TSTMSTAR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMSTAR OK" or "TSTMSTAR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMSTAR:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   MSTARW

            STU   TSTUAF

            PULU  D
            CMPD  #$F924
            BNE   MCFAIL
            PULU  D
            CMPD  #$64D8
            BNE   MCFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   MCFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   MCFAIL

            LDD   #TRUEV
            BRA   MCDONE
MCFAIL:     LDD   #FALSEV
MCDONE:     LDX   #TSTMSTARNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMSTARNAME:
            FCB   8
            FCC   "TSTMSTAR"

; ------------------------------------------------------------
; unit test for FMSLASHMOD. floored double/single division.
; TSTFMSM
;    Inputs:
;        none
;    Outputs:
;        prints "TSTFMSM OK" or "TSTFMSM FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTFMSM:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD2LO
            PSHU  D
            LDD   #TSTD2HI
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   FMSLASHMODW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFF8
            BNE   FMFAIL
            PULU  D
            CMPD  #$11D0
            BNE   FMFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   FMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   FMFAIL

            LDD   #TRUEV
            BRA   FMDONE
FMFAIL:     LDD   #FALSEV
FMDONE:     LDX   #TSTFMSMNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTFMSMNAME:
            FCB   7
            FCC   "TSTFMSM"

; ------------------------------------------------------------
; unit test for SMSLASHREM. symmetric double/single
; division.
; TSTSMRM
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSMRM OK" or "TSTSMRM FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSMRM:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD2LO
            PSHU  D
            LDD   #TSTD2HI
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   SMSLASHREMW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFF9
            BNE   SRFAIL
            PULU  D
            CMPD  #$ED68
            BNE   SRFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   SRFAIL

            LDD   #TRUEV
            BRA   SRDONE
SRFAIL:     LDD   #FALSEV
SRDONE:     LDX   #TSTSMRMNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSMRMNAME:
            FCB   7
            FCC   "TSTSMRM"

; ------------------------------------------------------------
; unit test for DPLUS. double-cell add, with carry
; propagation.
; TSTDPLUS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDPLUS OK" or "TSTDPLUS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDPLUS:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            LDD   #TSTD3LO
            PSHU  D
            LDD   #TSTD3HI
            PSHU  D
            STU   TSTUB4

            JSR   DPLUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$00BD
            BNE   PDFAIL
            PULU  D
            CMPD  #$72BE
            BNE   PDFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   PDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   PDFAIL

            LDD   #TRUEV
            BRA   PDDONE
PDFAIL:     LDD   #FALSEV
PDDONE:     LDX   #TSTDPLUSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDPLUSNAME:
            FCB   8
            FCC   "TSTDPLUS"

; ------------------------------------------------------------
; unit test for DMINUS. double-cell subtract, with borrow
; propagation.
; TSTDMIN2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDMIN2 OK" or "TSTDMIN2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDMIN2:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD3LO
            PSHU  D
            LDD   #TSTD3HI
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            STU   TSTUB4

            JSR   DMINUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$00BB
            BNE   BDFAIL
            PULU  D
            CMPD  #$4FDE
            BNE   BDFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   BDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   BDFAIL

            LDD   #TRUEV
            BRA   BDDONE
BDFAIL:     LDD   #FALSEV
BDDONE:     LDX   #TSTDMIN2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDMIN2NAME:
            FCB   8
            FCC   "TSTDMIN2"

; ------------------------------------------------------------
; unit test for DNEGATEW. double-cell two's-complement
; negate.
; TSTDNEG
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDNEG OK" or "TSTDNEG FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDNEG:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD3LO
            PSHU  D
            LDD   #TSTD3HI
            PSHU  D
            STU   TSTUB4

            JSR   DNEGATEW

            STU   TSTUAF

            PULU  D
            CMPD  #$FF43
            BNE   DNFAIL
            PULU  D
            CMPD  #$9EB2
            BNE   DNFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   DNFAIL

            LDD   #TRUEV
            BRA   DNDONE
DNFAIL:     LDD   #FALSEV
DNDONE:     LDX   #TSTDNEGNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDNEGNAME:
            FCB   7
            FCC   "TSTDNEG"

; ------------------------------------------------------------
; unit test for DABSW. positive double - already
; non-negative, unchanged.
; TSTDABS1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDABS1 OK" or "TSTDABS1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDABS1:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD3LO
            PSHU  D
            LDD   #TSTD3HI
            PSHU  D
            STU   TSTUB4

            JSR   DABSW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTD3HI
            BNE   DAFAIL
            PULU  D
            CMPD  #TSTD3LO
            BNE   DAFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DAFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   DAFAIL

            LDD   #TRUEV
            BRA   DADONE
DAFAIL:     LDD   #FALSEV
DADONE:     LDX   #TSTDABS1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDABS1NAME:
            FCB   8
            FCC   "TSTDABS1"

; ------------------------------------------------------------
; unit test for DABSW. negative double - the branch that
; actually negates.
; TSTDABS2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDABS2 OK" or "TSTDABS2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDABS2:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD2LO
            PSHU  D
            LDD   #TSTD2HI
            PSHU  D
            STU   TSTUB4

            JSR   DABSW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTD1HI
            BNE   DBFAIL
            PULU  D
            CMPD  #TSTD1LO
            BNE   DBFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DBFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   DBFAIL

            LDD   #TRUEV
            BRA   DBDONE
DBFAIL:     LDD   #FALSEV
DBDONE:     LDX   #TSTDABS2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDABS2NAME:
            FCB   8
            FCC   "TSTDABS2"

; ------------------------------------------------------------
; unit test for MPLUS. add a single-cell value into a
; double.
; TSTMPLUS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMPLUS OK" or "TSTMPLUS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMPLUS:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            LDD   #TSTNEG2
            PSHU  D
            STU   TSTUB4

            JSR   MPLUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$0001
            BNE   MPFAIL
            PULU  D
            CMPD  #$102F
            BNE   MPFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   MPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   MPFAIL

            LDD   #TRUEV
            BRA   MPDONE
MPFAIL:     LDD   #FALSEV
MPDONE:     LDX   #TSTMPLUSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMPLUSNAME:
            FCB   8
            FCC   "TSTMPLUS"

; ------------------------------------------------------------
; unit test for STOD. sign-extend a negative single to
; double (this word's own documented bug history was in this
; exact case).
; TSTSTOD
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTOD OK" or "TSTSTOD FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSTOD:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   STODW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   SDFAIL
            PULU  D
            CMPD  #TSTNEG1
            BNE   SDFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   SDFAIL

            LDD   #TRUEV
            BRA   SDDONE
SDFAIL:     LDD   #FALSEV
SDDONE:     LDX   #TSTSTODNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTODNAME:
            FCB   7
            FCC   "TSTSTOD"

; ------------------------------------------------------------
; unit test for DTOS. narrow a double that fits to a single
; cell.
; TSTDTOS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDTOS OK" or "TSTDTOS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDTOS:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTDSLO
            PSHU  D
            LDD   #TSTDSHI
            PSHU  D
            STU   TSTUB4

            JSR   DTOSW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTDSLO
            BNE   NSFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   NSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   NSFAIL

            LDD   #TRUEV
            BRA   NSDONE
NSFAIL:     LDD   #FALSEV
NSDONE:     LDX   #TSTDTOSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDTOSNAME:
            FCB   7
            FCC   "TSTDTOS"

; ------------------------------------------------------------
; unit test for DMAXW. double-cell signed maximum,
; cross-sign case.
; TSTDMAX
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDMAX OK" or "TSTDMAX FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDMAX:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            LDD   #TSTD2LO
            PSHU  D
            LDD   #TSTD2HI
            PSHU  D
            STU   TSTUB4

            JSR   DMAXW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTD1HI
            BNE   XMFAIL
            PULU  D
            CMPD  #TSTD1LO
            BNE   XMFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   XMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   XMFAIL

            LDD   #TRUEV
            BRA   XMDONE
XMFAIL:     LDD   #FALSEV
XMDONE:     LDX   #TSTDMAXNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDMAXNAME:
            FCB   7
            FCC   "TSTDMAX"

; ------------------------------------------------------------
; unit test for DMINW. double-cell signed minimum,
; cross-sign case.
; TSTDMIN
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDMIN OK" or "TSTDMIN FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDMIN:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            LDD   #TSTD2LO
            PSHU  D
            LDD   #TSTD2HI
            PSHU  D
            STU   TSTUB4

            JSR   DMINW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTD2HI
            BNE   NMFAIL
            PULU  D
            CMPD  #TSTD2LO
            BNE   NMFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   NMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   NMFAIL

            LDD   #TRUEV
            BRA   NMDONE
NMFAIL:     LDD   #FALSEV
NMDONE:     LDX   #TSTDMINNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDMINNAME:
            FCB   7
            FCC   "TSTDMIN"

; ------------------------------------------------------------
; unit test for UMSLASHMOD, divide-by-zero case. u1 = 0.
; Verifies THROW -10 and CATCH's own depth-restoration
; contract (net 0 change across the JSR CATCH) - same
; pattern established in the section 3.4 tests.
; TSTUMSZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUMSZ OK" or "TSTUMSZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUMSZ:    STU   TSTU0

            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #UMSLASHMODW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   UZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   UZFAIL

            LDD   #TRUEV
            BRA   UZDONE
UZFAIL:     LDD   #FALSEV
UZDONE:     LDX   #TSTUMSZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUMSZNAME:
            FCB   7
            FCC   "TSTUMSZ"

; ------------------------------------------------------------
; unit test for FMSLASHMOD, divide-by-zero case. n1 = 0.
; Verifies THROW -10 and CATCH's own depth-restoration
; contract (net 0 change across the JSR CATCH) - same
; pattern established in the section 3.4 tests.
; TSTFMSZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTFMSZ OK" or "TSTFMSZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTFMSZ:    STU   TSTU0

            LDD   #TSTD2LO
            PSHU  D
            LDD   #TSTD2HI
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #FMSLASHMODW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   FZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   FZFAIL

            LDD   #TRUEV
            BRA   FZDONE
FZFAIL:     LDD   #FALSEV
FZDONE:     LDX   #TSTFMSZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTFMSZNAME:
            FCB   7
            FCC   "TSTFMSZ"

; ------------------------------------------------------------
; unit test for SMSLASHREM, divide-by-zero case. n1 = 0.
; Verifies THROW -10 and CATCH's own depth-restoration
; contract (net 0 change across the JSR CATCH) - same
; pattern established in the section 3.4 tests.
; TSTSMRZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSMRZ OK" or "TSTSMRZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSMRZ:    STU   TSTU0

            LDD   #TSTD2LO
            PSHU  D
            LDD   #TSTD2HI
            PSHU  D
            LDD   #$0000
            PSHU  D
            LDX   #SMSLASHREMW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-10
            BNE   RZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   RZFAIL

            LDD   #TRUEV
            BRA   RZDONE
RZFAIL:     LDD   #FALSEV
RZDONE:     LDX   #TSTSMRZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSMRZNAME:
            FCB   7
            FCC   "TSTSMRZ"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; logic, shift, and address-arithmetic tests (glossary
; section 3.6).
; TSTLOGIC
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTLOGIC.0.
; ------------------------------------------------------------
TSTLOGIC:   JSR   CRW
            LDX   #TSTLOGICMSG
            PSHU  X
            LDD   #5
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-5     ; >>>>

            JSR   TSTAND
            JSR   TSTOR
            JSR   TSTXOR
            JSR   TSTINV
            JSR   TSTLSH
            JSR   TSTRSH
            JSR   TSTCELS
            JSR   TSTCELP
            JSR   TSTCHRS
            JSR   TSTCHRP
            JSR   TSTALGD
            JSR   TSTALGN

            ENDC                    ; <<<<

            RTS

TSTLOGICMSG:
            FCC   "Logic"

            IFEQ  TSTSELECTOR-5     ; >>>>

; ------------------------------------------------------------
; unit test for ANDW. bitwise AND.
; TSTAND
;    Inputs:
;        none
;    Outputs:
;        prints "TSTAND OK" or "TSTAND FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTAND:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   ANDW

            STU   TSTUAF

            PULU  D
            CMPD  #$0060
            BNE   ANFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ANFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   ANFAIL

            LDD   #TRUEV
            BRA   ANDONE
ANFAIL:     LDD   #FALSEV
ANDONE:     LDX   #TSTANDNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTANDNAME: FCB   6
            FCC   "TSTAND"

; ------------------------------------------------------------
; unit test for ORW. bitwise OR.
; TSTOR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTOR OK" or "TSTOR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTOR:      STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   ORW

            STU   TSTUAF

            PULU  D
            CMPD  #$7DE9
            BNE   ORFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ORFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   ORFAIL

            LDD   #TRUEV
            BRA   ORDONE
ORFAIL:     LDD   #FALSEV
ORDONE:     LDX   #TSTORNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTORNAME:  FCB   5
            FCC   "TSTOR"

; ------------------------------------------------------------
; unit test for XORW. bitwise exclusive OR.
; TSTXOR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTXOR OK" or "TSTXOR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTXOR:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   XORW

            STU   TSTUAF

            PULU  D
            CMPD  #$7D89
            BNE   XRFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   XRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   XRFAIL

            LDD   #TRUEV
            BRA   XRDONE
XRFAIL:     LDD   #FALSEV
XRDONE:     LDX   #TSTXORNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTXORNAME: FCB   6
            FCC   "TSTXOR"

; ------------------------------------------------------------
; unit test for INVERT. one's-complement, in-place (never
; touches U itself, unlike most words - the test only cares
; what's observable via the stack, not how the
; implementation gets there).
; TSTINV
;    Inputs:
;        none
;    Outputs:
;        prints "TSTINV OK" or "TSTINV FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTINV:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   INVERTW

            STU   TSTUAF

            PULU  D
            CMPD  #$A61E
            BNE   IVFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   IVFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   IVFAIL

            LDD   #TRUEV
            BRA   IVDONE
IVFAIL:     LDD   #FALSEV
IVDONE:     LDX   #TSTINVNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTINVNAME: FCB   6
            FCC   "TSTINV"

; ------------------------------------------------------------
; unit test for LSHIFT. logical shift left, zero-fill,
; truncated to 16 bits.
; TSTLSH
;    Inputs:
;        none
;    Outputs:
;        prints "TSTLSH OK" or "TSTLSH FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTLSH:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #$0004
            PSHU  D
            STU   TSTUB4

            JSR   LSHIFTW

            STU   TSTUAF

            PULU  D
            CMPD  #$4680
            BNE   L2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   L2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   L2FAIL

            LDD   #TRUEV
            BRA   L2DONE
L2FAIL:     LDD   #FALSEV
L2DONE:     LDX   #TSTLSHNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTLSHNAME: FCB   6
            FCC   "TSTLSH"

; ------------------------------------------------------------
; unit test for RSHIFT. logical shift right, zero-fill (not
; arithmetic/sign-preserving) - negative input is the case
; that actually distinguishes this from an arithmetic shift.
; TSTRSH
;    Inputs:
;        none
;    Outputs:
;        prints "TSTRSH OK" or "TSTRSH FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTRSH:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #$0004
            PSHU  D
            STU   TSTUB4

            JSR   RSHIFTW

            STU   TSTUAF

            PULU  D
            CMPD  #$0CFC
            BNE   R2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   R2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   R2FAIL

            LDD   #TRUEV
            BRA   R2DONE
R2FAIL:     LDD   #FALSEV
R2DONE:     LDX   #TSTRSHNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTRSHNAME: FCB   6
            FCC   "TSTRSH"

; ------------------------------------------------------------
; unit test for CELLSW. convert a cell count to a byte
; offset (x2, this system's cell size).
; TSTCELS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCELS OK" or "TSTCELS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCELS:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   CELLSW

            STU   TSTUAF

            PULU  D
            CMPD  #$48D0
            BNE   CSFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   CSFAIL

            LDD   #TRUEV
            BRA   CSDONE
CSFAIL:     LDD   #FALSEV
CSDONE:     LDX   #TSTCELSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCELSNAME:
            FCB   7
            FCC   "TSTCELS"

; ------------------------------------------------------------
; unit test for CELLPLUS. add one cell's size (2 bytes).
; TSTCELP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCELP OK" or "TSTCELP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCELP:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   CELLPLUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$59E3
            BNE   CPFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   CPFAIL

            LDD   #TRUEV
            BRA   CPDONE
CPFAIL:     LDD   #FALSEV
CPDONE:     LDX   #TSTCELPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCELPNAME:
            FCB   7
            FCC   "TSTCELP"

; ------------------------------------------------------------
; unit test for CHARSW. convert a character count to a byte
; offset - documented no-op on this system (1 byte per
; character already).
; TSTCHRS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCHRS OK" or "TSTCHRS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCHRS:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   CHARSW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   C3FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   C3FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   C3FAIL

            LDD   #TRUEV
            BRA   C3DONE
C3FAIL:     LDD   #FALSEV
C3DONE:     LDX   #TSTCHRSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCHRSNAME:
            FCB   7
            FCC   "TSTCHRS"

; ------------------------------------------------------------
; unit test for CHARPLUS. add one character's size (1 byte).
; TSTCHRP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCHRP OK" or "TSTCHRP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCHRP:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   CHARPLUSW

            STU   TSTUAF

            PULU  D
            CMPD  #$59E2
            BNE   HPFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   HPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   HPFAIL

            LDD   #TRUEV
            BRA   HPDONE
HPFAIL:     LDD   #FALSEV
HPDONE:     LDX   #TSTCHRPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCHRPNAME:
            FCB   7
            FCC   "TSTCHRP"

; ------------------------------------------------------------
; unit test for ALIGNEDW. align a given address - documented
; no-op on the 6809 (no alignment restrictions to enforce).
; TSTALGD
;    Inputs:
;        none
;    Outputs:
;        prints "TSTALGD OK" or "TSTALGD FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTALGD:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   ALIGNEDW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   ADFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ADFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   ADFAIL

            LDD   #TRUEV
            BRA   ADDONE
ADFAIL:     LDD   #FALSEV
ADDONE:     LDX   #TSTALGDNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTALGDNAME:
            FCB   7
            FCC   "TSTALGD"

; ------------------------------------------------------------
; unit test for ALIGNW. align HERE to a cell boundary -
; documented no-op on the 6809, and takes no stack arguments
; at all. Verifies pushed decoy values are entirely
; undisturbed, not just a single value's persistence.
; TSTALGN
;    Inputs:
;        none
;    Outputs:
;        prints "TSTALGN OK" or "TSTALGN FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTALGN:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   ALIGNW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   AGFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   AGFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   AGFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   AGFAIL

            LDD   #TRUEV
            BRA   AGDONE
AGFAIL:     LDD   #FALSEV
AGDONE:     LDX   #TSTALGNNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTALGNNAME:
            FCB   7
            FCC   "TSTALGN"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; comparison tests (glossary section 3.7).
; TSTCOMPARE
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTCOMPARE.0.
; ------------------------------------------------------------
TSTCOMPARE: JSR   CRW
            LDX   #TSTCOMPMSG
            PSHU  X
            LDD   #7
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-6     ; >>>>

            JSR   TSTEQ
            JSR   TSTLT
            JSR   TSTGT
            JSR   TSTZEQ
            JSR   TSTZLT
            JSR   TSTULT
            JSR   TSTNE
            JSR   TSTZNE
            JSR   TSTZGT
            JSR   TSTUGT
            JSR   TSTWI1
            JSR   TSTWI2
            JSR   TSTDEQ
            JSR   TSTDLT
            JSR   TSTDULT

            ENDC                    ; <<<<

            RTS

TSTCOMPMSG: FCC   "Compare"

            IFEQ  TSTSELECTOR-6     ; >>>>

; ------------------------------------------------------------
; unit test for EQUALW. true if equal - tested with matching
; values, the case that actually exercises the true branch.
; TSTEQ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTEQ OK" or "TSTEQ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTEQ:      STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   EQUALW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   EQFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   EQFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   EQFAIL

            LDD   #TRUEV
            BRA   EQDONE
EQFAIL:     LDD   #FALSEV
EQDONE:     LDX   #TSTEQNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEQNAME:  FCB   5
            FCC   "TSTEQ"

; ------------------------------------------------------------
; unit test for LESSW. true if n1 signed less than n2 -
; tested with a negative n1 and positive n2, the case that
; distinguishes signed from unsigned comparison.
; TSTLT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTLT OK" or "TSTLT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTLT:      STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   LESSW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   LTFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   LTFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   LTFAIL

            LDD   #TRUEV
            BRA   LTDONE
LTFAIL:     LDD   #FALSEV
LTDONE:     LDX   #TSTLTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTLTNAME:  FCB   5
            FCC   "TSTLT"

; ------------------------------------------------------------
; unit test for GREATERW. true if n1 signed greater than n2
; - same reasoning as < , reversed operands.
; TSTGT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTGT OK" or "TSTGT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTGT:      STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   GREATERW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   GTFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   GTFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   GTFAIL

            LDD   #TRUEV
            BRA   GTDONE
GTFAIL:     LDD   #FALSEV
GTDONE:     LDX   #TSTGTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTGTNAME:  FCB   5
            FCC   "TSTGT"

; ------------------------------------------------------------
; unit test for ZEROEQ. true if n is zero - tested with a
; nonzero value, confirming false is genuinely reachable,
; not just the trivial zero case.
; TSTZEQ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTZEQ OK" or "TSTZEQ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTZEQ:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   ZEROEQW

            STU   TSTUAF

            PULU  D
            CMPD  #$0000
            BNE   ZEFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ZEFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   ZEFAIL

            LDD   #TRUEV
            BRA   ZEDONE
ZEFAIL:     LDD   #FALSEV
ZEDONE:     LDX   #TSTZEQNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTZEQNAME: FCB   6
            FCC   "TSTZEQ"

; ------------------------------------------------------------
; unit test for ZEROLT. true if n is negative.
; TSTZLT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTZLT OK" or "TSTZLT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTZLT:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   ZEROLTW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   ZLFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ZLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   ZLFAIL

            LDD   #TRUEV
            BRA   ZLDONE
ZLFAIL:     LDD   #FALSEV
ZLDONE:     LDX   #TSTZLTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTZLTNAME: FCB   6
            FCC   "TSTZLT"

; ------------------------------------------------------------
; unit test for ULESSW. true if u1 unsigned less than u2 -
; tested with TSTVAL1 vs TSTNEG1's raw bit pattern (a large
; unsigned magnitude), the case that would invert under
; signed comparison, confirming this is genuinely unsigned.
; TSTULT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTULT OK" or "TSTULT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTULT:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   ULESSW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   ULFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ULFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   ULFAIL

            LDD   #TRUEV
            BRA   ULDONE
ULFAIL:     LDD   #FALSEV
ULDONE:     LDX   #TSTULTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTULTNAME: FCB   6
            FCC   "TSTULT"

; ------------------------------------------------------------
; unit test for NOTEQUAL. true if not equal.
; TSTNE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTNE OK" or "TSTNE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTNE:      STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            STU   TSTUB4

            JSR   NOTEQUALW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   NEFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   NEFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   NEFAIL

            LDD   #TRUEV
            BRA   NEDONE
NEFAIL:     LDD   #FALSEV
NEDONE:     LDX   #TSTNENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTNENAME:  FCB   5
            FCC   "TSTNE"

; ------------------------------------------------------------
; unit test for ZERONE. true if n is not zero.
; TSTZNE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTZNE OK" or "TSTZNE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTZNE:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   ZERONEW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   ZNFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ZNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   ZNFAIL

            LDD   #TRUEV
            BRA   ZNDONE
ZNFAIL:     LDD   #FALSEV
ZNDONE:     LDX   #TSTZNENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTZNENAME: FCB   6
            FCC   "TSTZNE"

; ------------------------------------------------------------
; unit test for ZEROGT. true if n is greater than zero -
; tested with a negative value, confirming the comparison
; correctly excludes negatives (not just zero).
; TSTZGT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTZGT OK" or "TSTZGT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTZGT:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            STU   TSTUB4

            JSR   ZEROGTW

            STU   TSTUAF

            PULU  D
            CMPD  #$0000
            BNE   ZGFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ZGFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   ZGFAIL

            LDD   #TRUEV
            BRA   ZGDONE
ZGFAIL:     LDD   #FALSEV
ZGDONE:     LDX   #TSTZGTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTZGTNAME: FCB   6
            FCC   "TSTZGT"

; ------------------------------------------------------------
; unit test for UGREATER. true if u1 unsigned greater than
; u2 - same reasoning as U< : TSTNEG1's raw bit pattern is a
; large unsigned magnitude, genuinely greater than TSTVAL1's
; here.
; TSTUGT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUGT OK" or "TSTUGT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUGT:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   UGREATERW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   UGFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   UGFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   UGFAIL

            LDD   #TRUEV
            BRA   UGDONE
UGFAIL:     LDD   #FALSEV
UGDONE:     LDX   #TSTUGTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUGTNAME: FCB   6
            FCC   "TSTUGT"

; ------------------------------------------------------------
; unit test for WITHINW. true if n2<=n1<n3 - tested with a
; wraparound range (n2 near $FFFF, n3 wrapped past $0000),
; the documented special case this word's own
; unsigned-offset implementation exists to handle correctly,
; with n1 inside the wrapped range.
; TSTWI1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTWI1 OK" or "TSTWI1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTWI1:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$FFFA
            PSHU  D
            LDD   #$FFF0
            PSHU  D
            LDD   #$0010
            PSHU  D
            STU   TSTUB4

            JSR   WITHINW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   W1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   W1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   W1FAIL

            LDD   #TRUEV
            BRA   W1DONE
W1FAIL:     LDD   #FALSEV
W1DONE:     LDX   #TSTWI1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTWI1NAME: FCB   6
            FCC   "TSTWI1"

; ------------------------------------------------------------
; unit test for WITHINW. same wraparound range as TSTWI1,
; with n1 genuinely outside it - confirms the wraparound
; handling correctly excludes as well as includes.
; TSTWI2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTWI2 OK" or "TSTWI2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTWI2:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$0020
            PSHU  D
            LDD   #$FFF0
            PSHU  D
            LDD   #$0010
            PSHU  D
            STU   TSTUB4

            JSR   WITHINW

            STU   TSTUAF

            PULU  D
            CMPD  #$0000
            BNE   W2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   W2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   W2FAIL

            LDD   #TRUEV
            BRA   W2DONE
W2FAIL:     LDD   #FALSEV
W2DONE:     LDX   #TSTWI2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTWI2NAME: FCB   6
            FCC   "TSTWI2"

; ------------------------------------------------------------
; unit test for DEQUAL. double-cell equal - tested with
; matching double values.
; TSTDEQ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDEQ OK" or "TSTDEQ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDEQ:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            LDD   #TSTD1LO
            PSHU  D
            LDD   #TSTD1HI
            PSHU  D
            STU   TSTUB4

            JSR   DEQUALW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   DQFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DQFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   DQFAIL

            LDD   #TRUEV
            BRA   DQDONE
DQFAIL:     LDD   #FALSEV
DQDONE:     LDX   #TSTDEQNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDEQNAME: FCB   6
            FCC   "TSTDEQ"

; ------------------------------------------------------------
; unit test for DLESSW. double-cell signed less than -
; tested with equal high cells and different low cells, the
; tie-break case this word's own documented behavior
; specifically calls out (compares low cells unsigned only
; when the high cells are equal).
; TSTDLT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDLT OK" or "TSTDLT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDLT:     STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$1000
            PSHU  D
            LDD   #$0005
            PSHU  D
            LDD   #$2000
            PSHU  D
            LDD   #$0005
            PSHU  D
            STU   TSTUB4

            JSR   DLESSW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   DLFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   DLFAIL

            LDD   #TRUEV
            BRA   DLDONE
DLFAIL:     LDD   #FALSEV
DLDONE:     LDX   #TSTDLTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDLTNAME: FCB   6
            FCC   "TSTDLT"

; ------------------------------------------------------------
; unit test for DULESSW. double-cell unsigned less than -
; same tie-break reasoning as D<, both tiers compared
; unsigned.
; TSTDULT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDULT OK" or "TSTDULT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDULT:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$1000
            PSHU  D
            LDD   #$0005
            PSHU  D
            LDD   #$2000
            PSHU  D
            LDD   #$0005
            PSHU  D
            STU   TSTUB4

            JSR   DULESSW

            STU   TSTUAF

            PULU  D
            CMPD  #$FFFF
            BNE   DZFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   DZFAIL

            LDD   #TRUEV
            BRA   DZDONE
DZFAIL:     LDD   #FALSEV
DZDONE:     LDX   #TSTDULTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDULTNAME:
            FCB   7
            FCC   "TSTDULT"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; control-flow tests (glossary section 3.8, 22 words - all
; except UNLOOP, which is a genuine runtime no-op and tested
; directly like ALIGN's own test, needing none of this
; section's compile-time harness).
; TSTCTRLFLOW
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTCTRLFLOW.0.
; ------------------------------------------------------------
TSTCTRLFLOW:
            JSR   CRW
            LDX   #TSTCTRLMSG
            PSHU  X
            LDD   #8
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-7     ; >>>>

            JSR   TSTIFT1
            JSR   TSTIFT2
            JSR   TSTIET1
            JSR   TSTIET2
            JSR   TSTBGU
            JSR   TSTBWR
            JSR   TSTRECUR
            JSR   TSTDOLP
            JSR   TSTQDOLP
            JSR   TSTQDOLPEQ
            JSR   TSTPLOOP
            JSR   TSTJIDX
            JSR   TSTLEAVE
            JSR   TSTEXIT
            JSR   TSTUNLOOP
            JSR   TSTCASE1
            JSR   TSTCASE2
            JSR   TSTTHENZ
            JSR   TSTUNTILZ
            JSR   TSTENDOFZ

            ENDC                    ; <<<<

            RTS

TSTCTRLMSG: FCC   "CtrlFlow"

            IFEQ  TSTSELECTOR-7     ; >>>>

; ------------------------------------------------------------
; Control-flow test harness (glossary section 3.8).
; Original comment: shadow TSTCTRLFLOW.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for IF/THEN, true case.
; TSTIFT1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTIFT1 OK" or "TSTIFT1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTIFT1.0.
; ------------------------------------------------------------
TSTIFT1:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   IFW

            LDD   #111
            PSHU  D
            JSR   LITERALW

            JSR   THENW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TRUEV
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #111
            BNE   T1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   T1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   T1FAIL

            LDD   #TRUEV
            BRA   T1DONE
T1FAIL:     LDD   #FALSEV
T1DONE:     LDX   #TSTIFT1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTIFT1NAME:
            FCB   7
            FCC   "TSTIFT1"

; ------------------------------------------------------------
; unit test for IF/THEN, false case. Same compiled snippet
; as TSTIFT1, run with a false flag instead - the branch IS
; taken, jumping straight past the LIT+111, so 111 should
; NOT appear; only the guard remains.
; TSTIFT2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTIFT2 OK" or "TSTIFT2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTIFT2:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   IFW

            LDD   #111
            PSHU  D
            JSR   LITERALW

            JSR   THENW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #FALSEV
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   T2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   T2FAIL

            LDD   #TRUEV
            BRA   T2DONE
T2FAIL:     LDD   #FALSEV
T2DONE:     LDX   #TSTIFT2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTIFT2NAME:
            FCB   7
            FCC   "TSTIFT2"

; ------------------------------------------------------------
; unit test for IF/ELSE/THEN, true case. Compiles "IF <lit
; 111> ELSE <lit 222> THEN" into scratch. True flag should
; take the IF-body (111) and skip the ELSE-body (222) via
; ELSE's own unconditional branch. Verified by hand-trace:
; IF's patched offset (12) lands exactly at the ELSE-body's
; start; ELSE's own patched offset (7) lands exactly past
; it.
; TSTIET1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTIET1 OK" or "TSTIET1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTIET1:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   IFW

            LDD   #111
            PSHU  D
            JSR   LITERALW

            JSR   ELSEW

            LDD   #222
            PSHU  D
            JSR   LITERALW

            JSR   THENW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TRUEV
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #111
            BNE   E1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   E1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   E1FAIL

            LDD   #TRUEV
            BRA   E1DONE
E1FAIL:     LDD   #FALSEV
E1DONE:     LDX   #TSTIET1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTIET1NAME:
            FCB   7
            FCC   "TSTIET1"

; ------------------------------------------------------------
; unit test for IF/ELSE/THEN, false case. Same compiled
; snippet as TSTIET1, run with a false flag - should take
; the ELSE-body (222) instead, IF-body (111) skipped.
; TSTIET2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTIET2 OK" or "TSTIET2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTIET2:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   IFW

            LDD   #111
            PSHU  D
            JSR   LITERALW

            JSR   ELSEW

            LDD   #222
            PSHU  D
            JSR   LITERALW

            JSR   THENW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #FALSEV
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #222
            BNE   E2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   E2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   E2FAIL

            LDD   #TRUEV
            BRA   E2DONE
E2FAIL:     LDD   #FALSEV
E2DONE:     LDX   #TSTIET2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTIET2NAME:
            FCB   7
            FCC   "TSTIET2"

; ------------------------------------------------------------
; unit test for BEGIN/UNTIL.
; TSTBGU
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBGU OK" or "TSTBGU FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTBGU.0.
; ------------------------------------------------------------
TSTBGU:     LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   BEGINW

            LDD   #ONEPLUSW
            PSHU  D
            JSR   CCALL

            LDD   #DUPW
            PSHU  D
            JSR   CCALL

            LDD   #5
            PSHU  D
            JSR   LITERALW

            LDD   #EQUALW
            PSHU  D
            JSR   CCALL

            JSR   UNTILW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #5
            BNE   BUFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   BUFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   BUFAIL

            LDD   #TRUEV
            BRA   BUDONE
BUFAIL:     LDD   #FALSEV
BUDONE:     LDX   #TSTBGUNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBGUNAME: FCB   6
            FCC   "TSTBGU"

; ------------------------------------------------------------
; unit test for BEGIN/WHILE/REPEAT.
; TSTBWR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBWR OK" or "TSTBWR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTBWR.0.
; ------------------------------------------------------------
TSTBWR:     LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   BEGINW

            LDD   #DUPW
            PSHU  D
            JSR   CCALL

            LDD   #5
            PSHU  D
            JSR   LITERALW

            LDD   #LESSW
            PSHU  D
            JSR   CCALL

            JSR   WHILEW

            LDD   #ONEPLUSW
            PSHU  D
            JSR   CCALL

            JSR   REPEATW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #5
            BNE   BWFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   BWFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   BWFAIL

            LDD   #TRUEV
            BRA   BWDONE
BWFAIL:     LDD   #FALSEV
BWDONE:     LDX   #TSTBWRNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBWRNAME: FCB   6
            FCC   "TSTBWR"

; ------------------------------------------------------------
; unit test for RECURSE.
; TSTRECUR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTRECUR OK" or "TSTRECUR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTRECUR.0.
; ------------------------------------------------------------
TSTRECUR:   LDD   CURXT
            STD   TSTLSAV
            LDD   CODEHERE
            STD   TSTCSAV

            LDD   #DUPW
            STD   CURXT

            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   RECURSEW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   CURXT

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   RCFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   RCFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   RCFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   RCFAIL

            LDD   #TRUEV
            BRA   RCDONE
RCFAIL:     LDD   #FALSEV
RCDONE:     LDX   #TSTRECURNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTRECURNAME:
            FCB   8
            FCC   "TSTRECUR"

; ------------------------------------------------------------
; unit test for DO/LOOP.
; TSTDOLP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDOLP OK" or "TSTDOLP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTDOLP.0.
; ------------------------------------------------------------
TSTDOLP:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   DOW

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            JSR   LOOPW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            LDD   #5
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #10
            BNE   DWFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DWFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   DWFAIL

            LDD   #TRUEV
            BRA   DWDONE
DWFAIL:     LDD   #FALSEV
DWDONE:     LDX   #TSTDOLPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDOLPNAME:
            FCB   7
            FCC   "TSTDOLP"

; ------------------------------------------------------------
; unit test for ?DO/LOOP, normal (non-skip) case. Same "?DO
; I + LOOP" structure and I-sum verification as TSTDOLP,
; confirming ?DO behaves like DO when index != limit.
; TSTQDOLP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTQDOLP OK" or "TSTQDOLP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTQDOLP:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   QDOW

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            JSR   LOOPW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            LDD   #5
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #10
            BNE   QLFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   QLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   QLFAIL

            LDD   #TRUEV
            BRA   QLDONE
QLFAIL:     LDD   #FALSEV
QLDONE:     LDX   #TSTQDOLPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTQDOLPNAME:
            FCB   8
            FCC   "TSTQDOLP"

; ------------------------------------------------------------
; unit test for ?DO/LOOP, limit=index case - the documented
; case that DISTINGUISHES ?DO from plain DO: skips the loop
; entirely, unlike DO's own limit=index behavior (confirmed
; separately to take a full 65536-iteration wraparound, not
; tested here - see TSTDOLP's own notes).
; TSTQDOLPEQ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTQDOLPEQ OK" or "TSTQDOLPEQ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTQDOLPEQ.0.
; ------------------------------------------------------------
TSTQDOLPEQ: LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   QDOW

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            JSR   LOOPW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            LDD   #5
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #0
            BNE   QEFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   QEFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   QEFAIL

            LDD   #TRUEV
            BRA   QEDONE
QEFAIL:     LDD   #FALSEV
QEDONE:     LDX   #TSTQDOLPEQNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTQDOLPEQNAME:
            FCB   10
            FCC   "TSTQDOLPEQ"

; ------------------------------------------------------------
; unit test for DO/+LOOP.
; TSTPLOOP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPLOOP OK" or "TSTPLOOP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTPLOOP.0.
; ------------------------------------------------------------
TSTPLOOP:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   DOW

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            LDD   #3
            PSHU  D
            JSR   LITERALW

            JSR   PLUSLOOPW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            LDD   #10
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #18
            BNE   POFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   POFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   POFAIL

            LDD   #TRUEV
            BRA   PODONE
POFAIL:     LDD   #FALSEV
PODONE:     LDX   #TSTPLOOPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPLOOPNAME:
            FCB   8
            FCC   "TSTPLOOP"

; ------------------------------------------------------------
; unit test for J.
; TSTJIDX
;    Inputs:
;        none
;    Outputs:
;        prints "TSTJIDX OK" or "TSTJIDX FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTJIDX.0.
; ------------------------------------------------------------
TSTJIDX:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   DOW

            LDD   #2
            PSHU  D
            JSR   LITERALW
            LDD   #0
            PSHU  D
            JSR   LITERALW

            JSR   DOW

            LDD   #JWORDW
            PSHU  D
            JSR   CCALL

            LDD   #10
            PSHU  D
            JSR   LITERALW

            LDD   #STARW
            PSHU  D
            JSR   CCALL

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            JSR   LOOPW

            JSR   LOOPW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            LDD   #3
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #63
            BNE   JIFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   JIFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   JIFAIL

            LDD   #TRUEV
            BRA   JIDONE
JIFAIL:     LDD   #FALSEV
JIDONE:     LDX   #TSTJIDXNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTJIDXNAME:
            FCB   7
            FCC   "TSTJIDX"

; ------------------------------------------------------------
; unit test for LEAVE.
; TSTLEAVE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTLEAVE OK" or "TSTLEAVE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTLEAVE.0.
; ------------------------------------------------------------
TSTLEAVE:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   DOW

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #DUPW
            PSHU  D
            JSR   CCALL

            LDD   #3
            PSHU  D
            JSR   LITERALW

            LDD   #EQUALW
            PSHU  D
            JSR   CCALL

            JSR   IFW

            LDD   #LEAVEW
            PSHU  D
            JSR   CCALL

            JSR   THENW

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            JSR   LOOPW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            LDD   #10
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #6
            BNE   LVFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   LVFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   LVFAIL

            LDD   #TRUEV
            BRA   LVDONE
LVFAIL:     LDD   #FALSEV
LVDONE:     LDX   #TSTLEAVENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTLEAVENAME:
            FCB   8
            FCC   "TSTLEAVE"

; ------------------------------------------------------------
; unit test for EXIT.
; TSTEXIT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTEXIT OK" or "TSTEXIT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTEXIT.0.
; ------------------------------------------------------------
TSTEXIT:    LDD   CSP
            STD   TSTCSPS
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            TFR   U,D
            STD   CSP

            JSR   DOW

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #3
            PSHU  D
            JSR   LITERALW

            LDD   #EQUALW
            PSHU  D
            JSR   CCALL

            JSR   IFW

            LDD   #UNLOOPW
            PSHU  D
            JSR   CCALL

            JSR   EXITW

            JSR   THENW

            LDD   #IWORDW
            PSHU  D
            JSR   CCALL

            LDD   #PLUSW
            PSHU  D
            JSR   CCALL

            JSR   LOOPW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTCSPS
            STD   CSP

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            LDD   #10
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #3
            BNE   EXFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   EXFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   EXFAIL

            LDD   #TRUEV
            BRA   EXDONE
EXFAIL:     LDD   #FALSEV
EXDONE:     LDX   #TSTEXITNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEXITNAME:
            FCB   7
            FCC   "TSTEXIT"

; ------------------------------------------------------------
; unit test for UNLOOP.
; TSTUNLOOP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUNLOOP OK" or "TSTUNLOOP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTUNLOOP.0.
; ------------------------------------------------------------
TSTUNLOOP:  STU   TSTU0

            LDD   #TSTVAL1
            PSHS  D                 ; fake frame: LEAVE flag
            LDD   #TSTVAL2
            PSHS  D                 ;             limit
            LDD   #TSTVAL1
            PSHS  D                 ;             index
            STS   TSTUB4            ; S with the fake frame in place
            STU   TSTSCR            ; U before

            JSR   UNLOOPW

            STS   TSTUAF            ; S after

            LDD   TSTUAF
            SUBD  TSTUB4
            CMPD  #6
            BNE   UOFAIL
            CMPU  TSTSCR
            BNE   UOFAIL

            LDD   #TRUEV
            BRA   UODONE
UOFAIL:     LDD   #FALSEV
UODONE:     LDX   #TSTUNLOOPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUNLOOPNAME:
            FCB   9
            FCC   "TSTUNLOOP"

; ------------------------------------------------------------
; unit test for CASE/OF/ENDOF/ENDCASE, matching clause.
; TSTCASE1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCASE1 OK" or "TSTCASE1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCASE1.0.
; ------------------------------------------------------------
TSTCASE1:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   CASEW

            LDD   #1
            PSHU  D
            JSR   LITERALW
            JSR   OFW
            LDD   #111
            PSHU  D
            JSR   LITERALW
            JSR   ENDOFW

            LDD   #2
            PSHU  D
            JSR   LITERALW
            JSR   OFW
            LDD   #222
            PSHU  D
            JSR   LITERALW
            JSR   ENDOFW

            JSR   ENDCASEW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #2
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #222
            BNE   C1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   C1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   C1FAIL

            LDD   #TRUEV
            BRA   C1DONE
C1FAIL:     LDD   #FALSEV
C1DONE:     LDX   #TSTCASE1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCASE1NAME:
            FCB   9
            FCC   "TSTCASE1"

; ------------------------------------------------------------
; unit test for CASE/OF/ENDOF/ENDCASE, no-match case.
; TSTCASE2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCASE2 OK" or "TSTCASE2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCASE2.0.
; ------------------------------------------------------------
TSTCASE2:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   #TSTCBUF
            STD   CODEHERE

            JSR   CASEW

            LDD   #1
            PSHU  D
            JSR   LITERALW
            JSR   OFW
            LDD   #111
            PSHU  D
            JSR   LITERALW
            JSR   ENDOFW

            LDD   #2
            PSHU  D
            JSR   LITERALW
            JSR   OFW
            LDD   #222
            PSHU  D
            JSR   LITERALW
            JSR   ENDOFW

            JSR   ENDCASEW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #99
            PSHU  D
            STU   TSTUB4

            JSR   TSTCBUF

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   C2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   C2FAIL

            LDD   #TRUEV
            BRA   C2DONE
C2FAIL:     LDD   #FALSEV
C2DONE:     LDX   #TSTCASE2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCASE2NAME:
            FCB   9
            FCC   "TSTCASE2"

; ------------------------------------------------------------
; unit test for THEN, tag-mismatch case.
; TSTTHENZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTHENZ OK" or "TSTTHENZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTTHENZ.0.
; ------------------------------------------------------------
TSTTHENZ:   STU   TSTU0

            LDD   #0
            PSHU  D
            LDD   #0
            PSHU  D
            LDX   #THENW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-22
            BNE   T3FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   T3FAIL

            LDD   #TRUEV
            BRA   T3DONE
T3FAIL:     LDD   #FALSEV
T3DONE:     LDX   #TSTTHENZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTHENZNAME:
            FCB   8
            FCC   "TSTTHENZ"

; ------------------------------------------------------------
; unit test for UNTIL, tag-mismatch case. Same pattern as
; TSTTHENZ - wrong value in place of TAGBACK.
; TSTUNTILZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUNTILZ OK" or "TSTUNTILZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUNTILZ:  STU   TSTU0

            LDD   #0
            PSHU  D
            LDD   #0
            PSHU  D
            LDX   #UNTILW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-22
            BNE   U3FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   U3FAIL

            LDD   #TRUEV
            BRA   U3DONE
U3FAIL:     LDD   #FALSEV
U3DONE:     LDX   #TSTUNTLZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUNTLZNAME:
            FCB   9
            FCC   "TSTUNTILZ"

; ------------------------------------------------------------
; unit test for ENDOF, tag-mismatch case. Same pattern -
; wrong value in place of TAGOF.
; TSTENDOFZ
;    Inputs:
;        none
;    Outputs:
;        prints "TSTENDOFZ OK" or "TSTENDOFZ FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTENDOFZ:  STU   TSTU0

            LDD   #0
            PSHU  D
            LDD   #0
            PSHU  D
            LDX   #ENDOFW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-22
            BNE   EOFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   EOFAIL

            LDD   #TRUEV
            BRA   EODONE
EOFAIL:     LDD   #FALSEV
EODONE:     LDX   #TSTENDFZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTENDFZNAME:
            FCB   9
            FCC   "TSTENDOFZ"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; defining-words tests (glossary section 3.9, 17 words, 12
; tests since VALUE/TO and IS/ACTION-OF are each combined
; into one test).
; TSTDEFWORDS
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTDEFWORDS.0.
; ------------------------------------------------------------
TSTDEFWORDS:
            JSR   CRW
            LDX   #TSTDEFMSG
            PSHU  X
            LDD   #8
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-8     ; >>>>

            JSR   TSTVAR
            JSR   TSTCONST
            JSR   TSTCOLON
            JSR   TSTCRDOES
            JSR   TST2VAR
            JSR   TST2CONST
            JSR   TSTBUFC
            JSR   TSTVALTO
            JSR   TSTDEFER1
            JSR   TSTDEFER2
            JSR   TSTISOF
            JSR   TSTMARKER

            ENDC                    ; <<<<

            RTS

TSTDEFMSG:  FCC   "DefWords"

            IFEQ  TSTSELECTOR-8     ; >>>>

; ------------------------------------------------------------
; Defining-words test harness (glossary section 3.9).
; Original comment: shadow TSTDEFWORDS.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for VARIABLE. Compiles "VARIABLE TESTWD" into
; scratch, then executes the result. Verifies it pushes its
; own PFA address (TSTVBUF, since VARHERE was redirected
; there) and that the cell there was correctly initialized
; to zero - VARIABLE's own documented behavior, not assumed.
; TSTVAR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTVAR OK" or "TSTVAR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTVAR:     LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   VARIABLEW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVBUF
            BNE   VRFAIL

            LDX   TSTVBUF
            LDD   ,X
            CMPD  #0
            BNE   VRFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   VRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   VRFAIL

            LDD   #TRUEV
            BRA   VRDONE
VRFAIL:     LDD   #FALSEV
VRDONE:     LDX   #TSTVARNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTVARNAME: FCB   6
            FCC   "TSTVAR"

; ------------------------------------------------------------
; unit test for CONSTANT.
; TSTCONST
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCONST OK" or "TSTCONST FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCONST.0.
; ------------------------------------------------------------
TSTCONST:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            LDD   #5
            PSHU  D
            JSR   CONSTANTW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #5
            BNE   CNFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   CNFAIL

            LDD   #TRUEV
            BRA   CNDONE
CNFAIL:     LDD   #FALSEV
CNDONE:     LDX   #TSTCONSTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCONSTNAME:
            FCB   8
            FCC   "TSTCONST"

; ------------------------------------------------------------
; unit test for : and ; together.
; TSTCOLON
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCOLON OK" or "TSTCOLON FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCOLON.0.
; ------------------------------------------------------------
TSTCOLON:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   CSP
            STD   TSTCSPS
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   COLONW

            LDD   #111
            PSHU  D
            JSR   LITERALW

            JSR   SEMIW

            LDA   TSTDBUF
            ANDA  #$40
            STA   TSTSMFLG

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTCSPS
            STD   CSP
            LDD   TSTSTSAV
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #111
            BNE   CLFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   CLFAIL

            TST   TSTSMFLG
            BNE   CLFAIL

            LDD   #TRUEV
            BRA   CLDONE
CLFAIL:     LDD   #FALSEV
CLDONE:     LDX   #TSTCOLONNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCOLONNAME:
            FCB   8
            FCC   "TSTCOLON"

; ------------------------------------------------------------
; unit test for CREATE/DOES> together.
; TSTCRDOES
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCRDOES OK" or "TSTCRDOES FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCRDOES.0.
; ------------------------------------------------------------
TSTCRDOES:  LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   CREATEW

            LDD   #5
            PSHU  D
            JSR   COMMAW

            LDD   CODEHERE
            STD   TSTDOESA

            JSR   DOESGTW

            LDD   #ATSIGNW
            PSHU  D
            JSR   CCALL

            LDD   #ONEPLUSW
            PSHU  D
            JSR   CCALL

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            LDX   TSTDOESA          ; See bugfix: TSTCRDOES.1
            JSR   ,X

            LDD   TSTLSAV
            STD   LATEST

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #6
            BNE   CDFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   CDFAIL

            LDD   #TRUEV
            BRA   CDDONE
CDFAIL:     LDD   #FALSEV
CDDONE:     LDX   #TSTCRDOESNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCRDOESNAME:
            FCB   9
            FCC   "TSTCRDOES"

; ------------------------------------------------------------
; unit test for 2VARIABLE. Compiles "2VARIABLE TESTWD" into
; scratch, then executes the result. Verifies it pushes its
; own PFA address (TSTVBUF) and that BOTH cells there were
; correctly initialized to zero.
; TST2VAR
;    Inputs:
;        none
;    Outputs:
;        prints "TST2VAR OK" or "TST2VAR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TST2VAR:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   TWOVARIABLEW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVBUF
            BNE   T2VFAIL

            LDX   TSTVBUF
            LDD   ,X
            CMPD  #0
            BNE   T2VFAIL
            LDD   2,X
            CMPD  #0
            BNE   T2VFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   T2VFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   T2VFAIL

            LDD   #TRUEV
            BRA   T2VDONE
T2VFAIL:    LDD   #FALSEV
T2VDONE:    LDX   #TST2VARNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TST2VARNAME:
            FCB   7
            FCC   "TST2VAR"

; ------------------------------------------------------------
; unit test for 2CONSTANT. Compiles "100 200 2CONSTANT
; TESTWD" into scratch (x1=100 stored at the lower address,
; x2=200 at the higher, matching 2@/2!'s own convention),
; then executes the result. Verifies it pushes both cells
; correctly ordered (200 on top/popped first, 100 deeper -
; matching 2@'s own documented behavior), not their own
; address.
; TST2CONST
;    Inputs:
;        none
;    Outputs:
;        prints "TST2CONST OK" or "TST2CONST FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TST2CONST:  LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            LDD   #100
            PSHU  D
            LDD   #200
            PSHU  D
            JSR   TWOCONSTANTW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #200
            BNE   T2CFAIL
            PULU  D
            CMPD  #100
            BNE   T2CFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   T2CFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   T2CFAIL

            LDD   #TRUEV
            BRA   T2CDONE
T2CFAIL:    LDD   #FALSEV
T2CDONE:    LDX   #TST2CONSTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TST2CONSTNAME:
            FCB   9
            FCC   "TST2CONST"

; ------------------------------------------------------------
; unit test for BUFFER:.
; TSTBUFC
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBUFC OK" or "TSTBUFC FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTBUFC.0.
; ------------------------------------------------------------
TSTBUFC:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            LDD   #10
            PSHU  D
            JSR   BUFFERCOLONW

            LDD   VARHERE
            SUBD  #TSTVBUF
            STD   TSTSCR

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVBUF
            BNE   BFFAIL

            LDD   TSTSCR
            CMPD  #10
            BNE   BFFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   BFFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   BFFAIL

            LDD   #TRUEV
            BRA   BFDONE
BFFAIL:     LDD   #FALSEV
BFDONE:     LDX   #TSTBUFCNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBUFCNAME:
            FCB   7
            FCC   "TSTBUFC"

; ------------------------------------------------------------
; unit test for VALUE and TO together.
; TSTVALTO
;    Inputs:
;        none
;    Outputs:
;        prints "TSTVALTO OK" or "TSTVALTO FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTVALTO.0.
; ------------------------------------------------------------
TSTVALTO:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            LDD   #42
            PSHU  D
            JSR   VALUEW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #42
            LBNE  VTFAIL            ; was BNE: VTFAIL out of short range
            PULU  D
            CMPD  #TSTGUARD
            LBNE  VTFAIL            ; was BNE - same reason

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            LBNE  VTFAIL            ; was BNE - same reason

            LDD   #TSTCBUF2         ; See bugfix: TSTVALTO.2
            STD   CODEHERE
            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #0
            STD   STATE

            LDD   #99
            PSHU  D
            JSR   TOW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE
            LDD   TSTLSAV
            STD   LATEST

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #99
            BNE   VTFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   VTFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   VTFAIL

            LDD   #TRUEV
            BRA   VTDONE
VTFAIL:     LDD   #FALSEV
VTDONE:     LDX   #TSTVALTONAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTVALTONAME:
            FCB   8
            FCC   "TSTVALTO"

; ------------------------------------------------------------
; unit test for DEFER, default-action case. Compiles "DEFER
; TESTWD" into scratch, then executes it via CATCH. Verifies
; the default action throws -21 (per DEFER's own documented
; behavior before IS/DEFER! sets a real target) and that
; CATCH's own depth-restoration contract holds - same
; pattern as the divide-by-zero tests in earlier sections.
; TSTDEFER1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDEFER1 OK" or "TSTDEFER1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDEFER1:  LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   DEFERW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST

            STU   TSTU0

            LDX   TSTWCFA
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-21
            BNE   DF1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   DF1FAIL

            LDD   #TRUEV
            BRA   DF1DONE
DF1FAIL:    LDD   #FALSEV
DF1DONE:    LDX   #TSTDEF1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDEF1NAME:
            FCB   9
            FCC   "TSTDEFER1"

; ------------------------------------------------------------
; unit test for DEFER together with DEFER!/DEFER@. Compiles
; "DEFER TESTWD", sets its target to DUP's own xt via DEFER!
; (an ordinary runtime word - unlike DEFER's own name-
; parsing, DEFER!/DEFER@ take an xt-defer directly, no
; WORD/FIND needed), executes TESTWD (should now behave like
; DUP), then reads the target back via DEFER@ to confirm it
; matches.
; TSTDEFER2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDEFER2 OK" or "TSTDEFER2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDEFER2:  LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   DEFERW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTLSAV
            STD   LATEST

            LDD   #DUPW
            PSHU  D
            LDX   TSTWCFA
            PSHU  X
            JSR   DEFERSTOREW

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   DF2FAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   DF2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DF2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   DF2FAIL

            LDX   TSTWCFA
            PSHU  X
            JSR   DEFERFETCHW

            PULU  D
            CMPD  #DUPW
            BNE   DF2FAIL

            LDD   #TRUEV
            BRA   DF2DONE
DF2FAIL:    LDD   #FALSEV
DF2DONE:    LDX   #TSTDEF2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDEF2NAME:
            FCB   9
            FCC   "TSTDEFER2"

; ------------------------------------------------------------
; unit test for IS and ACTION-OF together.
; TSTISOF
;    Inputs:
;        none
;    Outputs:
;        prints "TSTISOF OK" or "TSTISOF FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTISOF.0.
; ------------------------------------------------------------
TSTISOF:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   DEFERW

            LDD   TSTCSAV
            STD   CODEHERE

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #0
            STD   STATE

            LDD   #TSTCBUF2         ; See bugfix: TSTISOF.1
            STD   CODEHERE

            LDD   #DUPW
            PSHU  D
            JSR   ISW

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            LBNE  ISFAIL            ; was BNE: ISFAIL out of short range
            PULU  D
            CMPD  #TSTVAL1
            BNE   ISFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ISFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   ISFAIL

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   #TSTCBUF2         ; See bugfix: TSTISOF.3
            STD   CODEHERE

            JSR   ACTIONOFW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE
            LDD   TSTLSAV
            STD   LATEST

            PULU  D
            CMPD  #DUPW
            BNE   ISFAIL

            LDD   #TRUEV
            BRA   ISDONE
ISFAIL:     LDD   #FALSEV
ISDONE:     LDX   #TSTISOFNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTISOFNAME:
            FCB   7
            FCC   "TSTISOF"

; ------------------------------------------------------------
; unit test for MARKER.
; TSTMARKER
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMARKER OK" or "TSTMARKER FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTMARKER.0.
; ------------------------------------------------------------
TSTMARKER:  LDD   CODEHERE
            STD   TSTCSAV
            LDD   DPHERE
            STD   TSTDSAV
            LDD   VARHERE
            STD   TSTVSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   LATEST
            STD   TSTLSAV

            LDA   #'T'
            STA   TSTNAMEB
            LDA   #'E'
            STA   TSTNAMEB+1
            LDA   #'S'
            STA   TSTNAMEB+2
            LDA   #'T'
            STA   TSTNAMEB+3
            LDA   #'W'
            STA   TSTNAMEB+4
            LDA   #'D'
            STA   TSTNAMEB+5

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTDBUF
            STD   DPHERE
            LDD   #TSTVBUF
            STD   VARHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #6
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            LDD   CODEHERE
            STD   TSTWCFA

            JSR   MARKERW

            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   CODEHERE
            ADDD  #30
            STD   CODEHERE
            LDD   DPHERE
            ADDD  #30
            STD   DPHERE
            LDD   VARHERE
            ADDD  #30
            STD   VARHERE
            LDD   #TSTFHDR
            STD   LATEST

            LDX   TSTWCFA
            JSR   ,X

            STU   TSTUAF

            LDD   CODEHERE
            STD   TSTCSAV2
            LDD   DPHERE
            STD   TSTDSAV2
            LDD   VARHERE
            STD   TSTVSAV2
            LDD   LATEST
            STD   TSTLSAV2

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTDSAV
            STD   DPHERE
            LDD   TSTVSAV
            STD   VARHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #TSTGUARD
            BNE   MKFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   MKFAIL

            LDD   TSTCSAV2          ; BUG FIX: was compared against TSTMKCOD, a
            CMPD  #TSTCBUF          ; See bugfix: TSTMARKER.1
            BNE   MKFAIL
            LDD   TSTDSAV2
            CMPD  #TSTDBUF
            BNE   MKFAIL
            LDD   TSTVSAV2
            CMPD  #TSTVBUF
            BNE   MKFAIL
            LDD   TSTLSAV2
            CMPD  TSTLSAV
            BNE   MKFAIL

            LDD   TSTLSAV
            STD   LATEST

            LDD   #TRUEV
            BRA   MKDONE
MKFAIL:     LDD   TSTLSAV
            STD   LATEST
            LDD   #FALSEV
MKDONE:     LDX   #TSTMARKERNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMARKERNAME:
            FCB   9
            FCC   "TSTMARKER"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; compiling-words tests (glossary section 3.10, 14 words, 19
; tests since several get separate cases: TICK
; found/not-found, ['] compiling/interpreting state,
; POSTPONE normal/immediate word, [COMPILE] normal/immediate
; word, SLITERAL compiling/interpreting state, ABORT"
; false/true flag).
; TSTCOMPWORDS
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTCOMPWORDS.0.
; ------------------------------------------------------------
TSTCOMPWORDS:
            JSR   CRW
            LDX   #TSTCWMSG
            PSHU  X
            LDD   #9
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-9     ; >>>>

            JSR   TSTIMMED
            JSR   TSTSTATE
            JSR   TSTBRACKETS
            JSR   TSTTICK1
            JSR   TSTTICK2
            JSR   TSTCOMPCOMMA
            JSR   TSTLITERAL
            JSR   TSTBRACKTICK1
            JSR   TSTBRACKTICK2
            JSR   TSTPOSTPONE1
            JSR   TSTPOSTPONE2
            JSR   TSTXCOMPILE1
            JSR   TSTXCOMPILE2
            JSR   TSTTOBODY
            JSR   TSTEXECUTE
            JSR   TSTSLITERAL1
            JSR   TSTSLITERAL2
            JSR   TSTABORTQ1
            JSR   TSTABORTQ2

            ENDC                    ; <<<<

            RTS

TSTCWMSG:   FCC   "CompWords"

            IFEQ  TSTSELECTOR-9     ; >>>>

; ------------------------------------------------------------
; Compiling-words test harness (glossary section 3.10).
; Original comment: shadow TSTCOMPWORDS.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for IMMEDIATE. Builds a fake header (LEN/ FL=3,
; no flags), points LATEST at it, calls IMMEDIATE, and
; verifies the header's own LEN/FL byte now has bit 7 set -
; confirmed a memory-only operation with no data-stack
; effect, so the guard check is the whole verification
; beyond that.
; TSTIMMED
;    Inputs:
;        none
;    Outputs:
;        prints "TSTIMMED OK" or "TSTIMMED FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTIMMED:   LDD   LATEST
            STD   TSTLSAV

            LDA   #3
            STA   TSTFHDR
            LDA   #'F'
            STA   TSTFHDR+1
            LDA   #'O'
            STA   TSTFHDR+2
            LDA   #'O'
            STA   TSTFHDR+3
            LDD   #0
            STD   TSTFHDR+4
            LDD   #DUPW
            STD   TSTFHDR+6

            LDD   #TSTFHDR
            STD   LATEST

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   IMMEDIATEW

            STU   TSTUAF

            LDA   TSTFHDR
            CMPA  #$83
            BNE   IMFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   IMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   IMFAIL

            LDD   #TRUEV
            BRA   IMDONE
IMFAIL:     LDD   #FALSEV
IMDONE:     LDX   #TSTIMMEDNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTLSAV
            STD   LATEST

            LDU   TSTU0
            RTS

TSTIMMEDNAME:
            FCB   8
            FCC   "TSTIMMED"

; ------------------------------------------------------------
; unit test for STATE. Verifies it pushes the address of the
; real STATE variable (a plain variable, per its own
; documented "( -- addr )" effect - not its current value).
; TSTSTATE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSTATE OK" or "TSTSTATE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSTATE:   STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   STATEW

            STU   TSTUAF

            PULU  D
            CMPD  #STATE
            BNE   STFAIL2
            PULU  D
            CMPD  #TSTGUARD
            BNE   STFAIL2

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   STFAIL2

            LDD   #TRUEV
            BRA   STDONE2
STFAIL2:    LDD   #FALSEV
STDONE2:    LDX   #TSTSTATENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSTATENAME:
            FCB   8
            FCC   "TSTSTATE"

; ------------------------------------------------------------
; unit test for [ and ] together. Verifies ] sets STATE to
; -1 (compiling) and [ sets it back to 0 (interpreting) -
; both memory-only operations, no data-stack effect.
; TSTBRACKETS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBRACKETS OK" or "TSTBRACKETS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTBRACKETS:
            LDD   STATE
            STD   TSTSTSAV

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   RBRACKETW

            LDD   STATE
            CMPD  #-1
            BNE   BKFAIL

            JSR   LBRACKETW

            STU   TSTUAF

            LDD   STATE
            CMPD  #0
            BNE   BKFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   BKFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   BKFAIL

            LDD   #TRUEV
            BRA   BKDONE
BKFAIL:     LDD   #FALSEV
BKDONE:     LDX   #TSTBRACKETSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTSTSAV
            STD   STATE

            LDU   TSTU0
            RTS

TSTBRACKETSNAME:
            FCB   11
            FCC   "TSTBRACKETS"

; ------------------------------------------------------------
; unit test for ' (tick), found case.
; TSTTICK1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTICK1 OK" or "TSTTICK1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTTICK1.0.
; ------------------------------------------------------------
TSTTICK1:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDA   #3
            STA   TSTFHDR
            LDA   #'F'
            STA   TSTFHDR+1
            LDA   #'O'
            STA   TSTFHDR+2
            LDA   #'O'
            STA   TSTFHDR+3
            LDD   #0
            STD   TSTFHDR+4
            LDD   #DUPW
            STD   TSTFHDR+6

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTFHDR
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   TICKW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #DUPW
            BNE   TK1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TK1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   TK1FAIL

            LDD   #TRUEV
            BRA   TK1DONE
TK1FAIL:    LDD   #FALSEV
TK1DONE:    LDX   #TSTTICK1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTICK1NAME:
            FCB   8
            FCC   "TSTTICK1"

; ------------------------------------------------------------
; unit test for ' (tick), not-found case. Redirects LATEST
; to an empty chain (0, the standard chain-terminator
; sentinel used throughout this ROM), so FIND has nothing to
; match. Verifies -13 via CATCH.
; TSTTICK2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTICK2 OK" or "TSTTICK2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTTICK2:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #0
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            STU   TSTU0

            LDX   #TICKW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #-13
            BNE   TK2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   TK2FAIL

            LDD   #TRUEV
            BRA   TK2DONE
TK2FAIL:    LDD   #FALSEV
TK2DONE:    LDX   #TSTTICK2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTICK2NAME:
            FCB   8
            FCC   "TSTTICK2"

; ------------------------------------------------------------
; unit test for COMPILE,. Compiles a call to DUP's own xt
; into scratch, then executes the result with a known value
; to confirm it genuinely behaves like DUP - not just that
; some bytes were written.
; TSTCOMPCOMMA
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCOMPCOMMA OK" or "TSTCOMPCOMMA FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCOMPCOMMA:
            LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            LDD   #DUPW
            PSHU  D
            JSR   COMPILECOMMAW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   CCFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   CCFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CCFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   CCFAIL

            LDD   #TRUEV
            BRA   CCDONE
CCFAIL:     LDD   #FALSEV
CCDONE:     LDX   #TSTCCNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCCNAME:  FCB   12
            FCC   "TSTCOMPCOMMA"

; ------------------------------------------------------------
; unit test for LITERAL. Already used extensively as an
; internal helper throughout sections 3.8/3.9's own tests,
; but gets its own dedicated, direct test here too, per this
; section's own coverage. Compiles a known value as a
; literal, then executes the result to confirm it genuinely
; pushes it.
; TSTLITERAL
;    Inputs:
;        none
;    Outputs:
;        prints "TSTLITERAL OK" or "TSTLITERAL FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTLITERAL: LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            LDD   #TSTVAL1
            PSHU  D
            JSR   LITERALW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   LIFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   LIFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   LIFAIL

            LDD   #TRUEV
            BRA   LIDONE
LIFAIL:     LDD   #FALSEV
LIDONE:     LDX   #TSTLITNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTLITNAME: FCB   10
            FCC   "TSTLITERAL"

; ------------------------------------------------------------
; unit test for ['], compiling-state case. Compile-only, so
; STATE must be -1 for this to work at all (confirmed by
; reading its own code: throws -14 otherwise). Builds a fake
; header pointing at DUP, compiles a literal of its xt via
; ['], then executes the result to confirm it genuinely
; pushes DUP's own xt.
; TSTBRACKTICK1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBRACKTICK1 OK" or "TSTBRACKTICK1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTBRACKTICK1:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #3
            STA   TSTFHDR
            LDA   #'F'
            STA   TSTFHDR+1
            LDA   #'O'
            STA   TSTFHDR+2
            LDA   #'O'
            STA   TSTFHDR+3
            LDD   #0
            STD   TSTFHDR+4
            LDD   #DUPW
            STD   TSTFHDR+6

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTFHDR
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            JSR   BRACKTICKW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #DUPW
            BNE   BT1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   BT1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   BT1FAIL

            LDD   #TRUEV
            BRA   BT1DONE
BT1FAIL:    LDD   #FALSEV
BT1DONE:    LDX   #TSTBT1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBT1NAME: FCB   13
            FCC   "TSTBRACKTICK1"

; ------------------------------------------------------------
; unit test for ['], interpreting-state case. STATE=0,
; verifies -14 via CATCH.
; TSTBRACKTICK2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBRACKTICK2 OK" or "TSTBRACKTICK2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTBRACKTICK2:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTFHDR
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #0
            STD   STATE

            STU   TSTU0

            LDX   #BRACKTICKW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #-14
            BNE   BT2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   BT2FAIL

            LDD   #TRUEV
            BRA   BT2DONE
BT2FAIL:    LDD   #FALSEV
BT2DONE:    LDX   #TSTBT2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBT2NAME: FCB   13
            FCC   "TSTBRACKTICK2"

; ------------------------------------------------------------
; unit test for POSTPONE, normal (non-immediate) word case.
; TSTPOSTPONE1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPOSTPONE1 OK" or "TSTPOSTPONE1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTPOSTPONE1.0.
; ------------------------------------------------------------
TSTPOSTPONE1:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #3
            STA   TSTFHDR
            LDA   #'F'
            STA   TSTFHDR+1
            LDA   #'O'
            STA   TSTFHDR+2
            LDA   #'O'
            STA   TSTFHDR+3
            LDD   #0
            STD   TSTFHDR+4
            LDD   #DUPW
            STD   TSTFHDR+6

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTFHDR
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   POSTPONEW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #TSTGUARD
            BNE   PP1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   PP1FAIL

            LDX   #TSTCBUF

            LDA   ,X
            CMPA  #OPJSR
            BNE   PP1FAIL
            LDD   1,X
            CMPD  #LIT
            BNE   PP1FAIL
            LDD   3,X
            CMPD  #DUPW
            BNE   PP1FAIL
            LDA   5,X
            CMPA  #OPJSR
            BNE   PP1FAIL
            LDD   6,X
            CMPD  #COMPILECOMMAW
            BNE   PP1FAIL

            LDD   #TRUEV
            BRA   PP1DONE
PP1FAIL:    LDD   #FALSEV
PP1DONE:    LDX   #TSTPP1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPP1NAME: FCB   12
            FCC   "TSTPOSTPONE1"

; ------------------------------------------------------------
; unit test for POSTPONE, immediate word case.
; TSTPOSTPONE2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPOSTPONE2 OK" or "TSTPOSTPONE2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTPOSTPONE2.0.
; ------------------------------------------------------------
TSTPOSTPONE2:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #$83
            STA   TSTFHDR
            LDA   #'F'
            STA   TSTFHDR+1
            LDA   #'O'
            STA   TSTFHDR+2
            LDA   #'O'
            STA   TSTFHDR+3
            LDD   #0
            STD   TSTFHDR+4
            LDD   #SPACEW
            STD   TSTFHDR+6

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTFHDR
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   POSTPONEW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #TSTGUARD
            BNE   PP2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   PP2FAIL

            LDX   #TSTCBUF

            LDA   ,X
            CMPA  #OPJSR
            BNE   PP2FAIL
            LDD   1,X
            CMPD  #SPACEW
            BNE   PP2FAIL

            LDD   #TRUEV
            BRA   PP2DONE
PP2FAIL:    LDD   #FALSEV
PP2DONE:    LDX   #TSTPP2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPP2NAME: FCB   12
            FCC   "TSTPOSTPONE2"

; ------------------------------------------------------------
; unit test for [COMPILE], normal (non-immediate) word case.
; TSTXCOMPILE1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTXCOMPILE1 OK" or "TSTXCOMPILE1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTXCOMPILE1.0.
; ------------------------------------------------------------
TSTXCOMPILE1:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #3
            STA   TSTFHDR
            LDA   #'F'
            STA   TSTFHDR+1
            LDA   #'O'
            STA   TSTFHDR+2
            LDA   #'O'
            STA   TSTFHDR+3
            LDD   #0
            STD   TSTFHDR+4
            LDD   #DUPW
            STD   TSTFHDR+6

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTFHDR
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   XCOMPILEW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #TSTGUARD
            BNE   XC1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   XC1FAIL

            LDX   #TSTCBUF

            LDA   ,X
            CMPA  #OPJSR
            BNE   XC1FAIL
            LDD   1,X
            CMPD  #DUPW
            BNE   XC1FAIL

            LDD   #TRUEV
            BRA   XC1DONE
XC1FAIL:    LDD   #FALSEV
XC1DONE:    LDX   #TSTXC1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTXC1NAME: FCB   13
            FCC   "TSTXCOMPILE1"

; ------------------------------------------------------------
; unit test for [COMPILE], immediate word case. Same fake
; header shape as TSTPOSTPONE2 (flags byte $83 - the $80
; IMMEDIATE bit set), to confirm XCOMPILE compiles the exact
; same direct-call byte sequence here as it did for the
; plain word above - i.e. that it genuinely ignores FIND's
; immediate flag entirely, unlike POSTPONE.
; TSTXCOMPILE2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTXCOMPILE2 OK" or "TSTXCOMPILE2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTXCOMPILE2:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #$83
            STA   TSTFHDR
            LDA   #'F'
            STA   TSTFHDR+1
            LDA   #'O'
            STA   TSTFHDR+2
            LDA   #'O'
            STA   TSTFHDR+3
            LDD   #0
            STD   TSTFHDR+4
            LDD   #SPACEW
            STD   TSTFHDR+6

            LDA   #'F'
            STA   TSTNAMEB
            LDA   #'O'
            STA   TSTNAMEB+1
            LDA   #'O'
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTFHDR
            STD   LATEST
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   XCOMPILEW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #TSTGUARD
            BNE   XC2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   XC2FAIL

            LDX   #TSTCBUF

            LDA   ,X
            CMPA  #OPJSR
            BNE   XC2FAIL
            LDD   1,X
            CMPD  #SPACEW
            BNE   XC2FAIL

            LDD   #TRUEV
            BRA   XC2DONE
XC2FAIL:    LDD   #FALSEV
XC2DONE:    LDX   #TSTXC2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTXC2NAME: FCB   13
            FCC   "TSTXCOMPILE2"

; ------------------------------------------------------------
; unit test for >BODY.
; TSTTOBODY
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTOBODY OK" or "TSTTOBODY FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTTOBODY.0.
; ------------------------------------------------------------
TSTTOBODY:  LDD   #TSTVAL1
            STD   TSTCBUF+5

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            STU   TSTUB4

            JSR   TOBODYW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   TBFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   TBFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   TBFAIL

            LDD   #TRUEV
            BRA   TBDONE
TBFAIL:     LDD   #FALSEV
TBDONE:     LDX   #TSTTBNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTBNAME:  FCB   9
            FCC   "TSTTOBODY"

; ------------------------------------------------------------
; unit test for EXECUTE. Executes DUP via its own xt with a
; known value, confirming it genuinely behaves like DUP -
; not just that the call returned.
; TSTEXECUTE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTEXECUTE OK" or "TSTEXECUTE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTEXECUTE: STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #DUPW
            PSHU  D
            STU   TSTUB4

            JSR   EXECUTEW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   XQFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   XQFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   XQFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   XQFAIL

            LDD   #TRUEV
            BRA   XQDONE
XQFAIL:     LDD   #FALSEV
XQDONE:     LDX   #TSTEXECNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEXECNAME:
            FCB   10
            FCC   "TSTEXECUTE"

; ------------------------------------------------------------
; unit test for SLITERAL, compiling-state case.
; TSTSLITERAL1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLITERAL1 OK" or "TSTSLITERAL1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSLITERAL1.0.
; ------------------------------------------------------------
TSTSLITERAL1:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'A'
            STA   TSTNAMEB
            LDA   #'B'
            STA   TSTNAMEB+1

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #-1
            STD   STATE

            LDD   #TSTNAMEB
            PSHU  D
            LDD   #2
            PSHU  D
            JSR   SLITERALW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSTSAV
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #2
            BNE   SL1FAIL

            PULU  D
            TFR   D,X
            LDA   ,X
            CMPA  #'A'
            BNE   SL1FAIL
            LDA   1,X
            CMPA  #'B'
            BNE   SL1FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   SL1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   SL1FAIL

            LDD   #TRUEV
            BRA   SL1DONE
SL1FAIL:    LDD   #FALSEV
SL1DONE:    LDX   #TSTSL1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSL1NAME: FCB   12
            FCC   "TSTSLITERAL1"

; ------------------------------------------------------------
; unit test for SLITERAL, interpreting-state case. STATE=0,
; verifies -14 via CATCH.
; TSTSLITERAL2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLITERAL2 OK" or "TSTSLITERAL2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSLITERAL2:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   STATE
            STD   TSTSTSAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #0
            STD   STATE

            STU   TSTU0

            LDD   #TSTNAMEB
            PSHU  D
            LDD   #2
            PSHU  D
            LDX   #SLITERALW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #-14
            BNE   SL2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   SL2FAIL

            LDD   #TRUEV
            BRA   SL2DONE
SL2FAIL:    LDD   #FALSEV
SL2DONE:    LDX   #TSTSL2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSL2NAME: FCB   12
            FCC   "TSTSLITERAL2"

; ------------------------------------------------------------
; unit test for ABORT", false-flag case.
; TSTABORTQ1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTABORTQ1 OK" or "TSTABORTQ1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTABORTQ1.0.
; ------------------------------------------------------------
TSTABORTQ1: LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'H'
            STA   TSTNAMEB
            LDA   #'I'
            STA   TSTNAMEB+1
            LDA   #34
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            JSR   ABORTQUOTEW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #FALSEV
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   AQ1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   AQ1FAIL

            LDD   #TRUEV
            BRA   AQ1DONE
AQ1FAIL:    LDD   #FALSEV
AQ1DONE:    LDX   #TSTAQ1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTAQ1NAME: FCB   10
            FCC   "TSTABORTQ1"

; ------------------------------------------------------------
; unit test for ABORT", true-flag case.
; TSTABORTQ2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTABORTQ2 OK" or "TSTABORTQ2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTABORTQ2.0.
; ------------------------------------------------------------
TSTABORTQ2: LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'H'
            STA   TSTNAMEB
            LDA   #'I'
            STA   TSTNAMEB+1
            LDA   #34
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            JSR   ABORTQUOTEW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            STU   TSTU0

            LDD   #TRUEV
            PSHU  D
            LDX   #TSTCBUF
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #-2
            BNE   AQ2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   AQ2FAIL

            LDD   #TRUEV
            BRA   AQ2DONE
AQ2FAIL:    LDD   #FALSEV
AQ2DONE:    LDX   #TSTAQ2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTAQ2NAME: FCB   10
            FCC   "TSTABORTQ2"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; memory tests (glossary section 3.11, 22 words, 16 tests
; since several are combined into round-trip tests that can
; only be meaningfully verified together: @/!, C@/C!, 2@/2!,
; and the CODEHERE-region words (,/C,/ALLOT/HERE) and
; VARHERE- region words (V,/VC,/VALLOT/VHERE) each combined
; into one sequential walk-through per region.
; TSTMEMORY
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTMEMORY.0.
; ------------------------------------------------------------
TSTMEMORY:  JSR   CRW
            LDX   #TSTMEMMSG
            PSHU  X
            LDD   #6
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-10    ; >>>>

            JSR   TSTFETCHSTORE
            JSR   TSTCFETCHSTORE
            JSR   TSTPLUSSTORE
            JSR   TST2FETCHSTORE
            JSR   TSTCODEHERE
            JSR   TSTVARHERE
            JSR   TSTPAD
            JSR   TSTUNUSED
            JSR   TSTVUNUSED
            JSR   TSTFILL
            JSR   TSTERASE
            JSR   TSTCMOVE
            JSR   TSTCMOVEGT
            JSR   TSTMOVE1
            JSR   TSTMOVE2
            JSR   TSTMOVE3

            ENDC                    ; <<<<

            RTS

TSTMEMMSG:  FCC   "Memory"

            IFEQ  TSTSELECTOR-10    ; >>>>

; ------------------------------------------------------------
; Memory test harness (glossary section 3.11).
; Original comment: shadow TSTMEMORY.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for @ and ! together (can only be meaningfully
; tested as a round trip). Stores a known value at scratch,
; fetches it back, verifies the match.
; TSTFETCHSTORE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTFETCHSTORE OK" or "TSTFETCHSTORE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTFETCHSTORE:
            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            STU   TSTUB4

            JSR   STOREW

            LDD   #TSTCBUF
            PSHU  D

            JSR   ATSIGNW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL1
            BNE   FSFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   FSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   FSFAIL

            LDD   #TRUEV
            BRA   FSDONE
FSFAIL:     LDD   #FALSEV
FSDONE:     LDX   #TSTFSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTFSNAME:  FCB   13
            FCC   "TSTFETCHSTORE"

; ------------------------------------------------------------
; unit test for C@ and C! together.
; TSTCFETCHSTORE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCFETCHSTORE OK" or "TSTCFETCHSTORE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCFETCHSTORE.0.
; ------------------------------------------------------------
TSTCFETCHSTORE:
            LDD   #$FFFF
            STD   TSTCBUF

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$34
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            STU   TSTUB4

            JSR   CSTOREW

            LDD   TSTCBUF
            CMPD  #$34FF
            BNE   CFFAIL

            LDD   #TSTCBUF
            PSHU  D

            JSR   CFETCHW

            STU   TSTUAF

            PULU  D
            CMPD  #$0034
            BNE   CFFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CFFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   CFFAIL

            LDD   #TRUEV
            BRA   CFDONE
CFFAIL:     LDD   #FALSEV
CFDONE:     LDX   #TSTCFNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCFNAME:  FCB   14
            FCC   "TSTCFETCHSTORE"

; ------------------------------------------------------------
; unit test for +!. Pre-initializes the cell to a known
; value, adds a known delta, and verifies the sum landed
; correctly.
; TSTPLUSSTORE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPLUSSTORE OK" or "TSTPLUSSTORE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTPLUSSTORE:
            LDD   #TSTVAL1
            STD   TSTCBUF

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #100
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            STU   TSTUB4

            JSR   PLUSSTOREW

            STU   TSTUAF

            LDD   TSTCBUF
            CMPD  #TSTVAL1+100
            BNE   PSFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   PSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   PSFAIL

            LDD   #TRUEV
            BRA   PSDONE
PSFAIL:     LDD   #FALSEV
PSDONE:     LDX   #TSTPSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPSNAME:  FCB   12
            FCC   "TSTPLUSSTORE"

; ------------------------------------------------------------
; unit test for 2@ and 2! together.
; TST2FETCHSTORE
;    Inputs:
;        none
;    Outputs:
;        prints "TST2FETCHSTORE OK" or "TST2FETCHSTORE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TST2FETCHSTORE.0.
; ------------------------------------------------------------
TST2FETCHSTORE:
            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            STU   TSTUB4

            JSR   DSTOREW

            LDD   #TSTCBUF
            PSHU  D

            JSR   DFETCHW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTVAL2
            BNE   DFFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   DFFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   DFFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   DFFAIL

            LDD   TSTCBUF
            CMPD  #TSTVAL2
            BNE   DFFAIL
            LDD   TSTCBUF+2
            CMPD  #TSTVAL1
            BNE   DFFAIL

            LDD   #TRUEV
            BRA   DFDONE
DFFAIL:     LDD   #FALSEV
DFDONE:     LDX   #TSTDFNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDFNAME:  FCB   14
            FCC   "TST2FETCHSTORE"

; ------------------------------------------------------------
; combined unit test for , C, ALLOT, and HERE together
; (glossary section 3.11's own CODEHERE-region words).
; TSTCODEHERE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCODEHERE OK" or "TSTCODEHERE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCODEHERE.0.
; ------------------------------------------------------------
TSTCODEHERE:
            LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   HEREW
            PULU  D
            CMPD  #TSTCBUF
            BNE   CHFAIL

            LDD   #TSTVAL1
            PSHU  D
            JSR   COMMAW
            LDD   TSTCBUF
            CMPD  #TSTVAL1
            BNE   CHFAIL
            LDD   CODEHERE
            CMPD  #TSTCBUF+2
            BNE   CHFAIL

            LDD   #$56
            PSHU  D
            JSR   CCOMMAW
            LDA   TSTCBUF+2
            CMPA  #$56
            BNE   CHFAIL
            LDD   CODEHERE
            CMPD  #TSTCBUF+3
            BNE   CHFAIL

            LDD   #10
            PSHU  D
            JSR   ALLOTW
            LDD   CODEHERE
            CMPD  #TSTCBUF+13
            BNE   CHFAIL

            LDD   #-4
            PSHU  D
            JSR   ALLOTW
            LDD   CODEHERE
            CMPD  #TSTCBUF+9
            BNE   CHFAIL

            JSR   HEREW
            PULU  D
            CMPD  #TSTCBUF+9
            BNE   CHFAIL

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   CHFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   CHFAIL

            LDD   #TRUEV
            BRA   CHDONE
CHFAIL:     LDD   #FALSEV
CHDONE:     LDX   #TSTCHNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTCHNAME:  FCB   11
            FCC   "TSTCODEHERE"

; ------------------------------------------------------------
; combined unit test for V, VC, VALLOT, and VHERE together -
; same structure as TSTCODEHERE, but for the
; mutable/variable region (VARHERE) instead.
; TSTVARHERE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTVARHERE OK" or "TSTVARHERE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTVARHERE: LDD   VARHERE
            STD   TSTVSAV

            LDD   #TSTVBUF
            STD   VARHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   VHEREW
            PULU  D
            CMPD  #TSTVBUF
            BNE   VHFAIL

            LDD   #TSTVAL1
            PSHU  D
            JSR   VCOMMAW
            LDD   TSTVBUF
            CMPD  #TSTVAL1
            BNE   VHFAIL
            LDD   VARHERE
            CMPD  #TSTVBUF+2
            BNE   VHFAIL

            LDD   #$56
            PSHU  D
            JSR   VCCOMMAW
            LDA   TSTVBUF+2
            CMPA  #$56
            BNE   VHFAIL
            LDD   VARHERE
            CMPD  #TSTVBUF+3
            BNE   VHFAIL

            LDD   #10
            PSHU  D
            JSR   VALLOTW
            LDD   VARHERE
            CMPD  #TSTVBUF+13
            BNE   VHFAIL

            LDD   #-4
            PSHU  D
            JSR   VALLOTW
            LDD   VARHERE
            CMPD  #TSTVBUF+9
            BNE   VHFAIL

            JSR   VHEREW
            PULU  D
            CMPD  #TSTVBUF+9
            BNE   VHFAIL

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   VHFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   VHFAIL

            LDD   #TRUEV
            BRA   VHDONE
VHFAIL:     LDD   #FALSEV
VHDONE:     LDX   #TSTVHNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTVSAV
            STD   VARHERE

            LDU   TSTU0
            RTS

TSTVHNAME:  FCB   10
            FCC   "TSTVARHERE"

; ------------------------------------------------------------
; unit test for PAD. Redirects CODEHERE, verifies PAD
; reports CODEHERE+PADOFFSET, using the same symbolic
; constant PADW's own code uses rather than a hardcoded
; number.
; TSTPAD
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPAD OK" or "TSTPAD FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTPAD:     LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   PADW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTCBUF+PADOFFSET
            BNE   PAFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   PAFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   PAFAIL

            LDD   #TRUEV
            BRA   PADONE
PAFAIL:     LDD   #FALSEV
PADONE:     LDX   #TSTPADNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTPADNAME: FCB   6
            FCC   "TSTPAD"

; ------------------------------------------------------------
; unit test for UNUSED. Redirects CODEHERE, verifies UNUSED
; reports CODETOP-CODEHERE, using the same symbolic constant
; UNUSEDW's own code uses.
; TSTUNUSED
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUNUSED OK" or "TSTUNUSED FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUNUSED:  LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   UNUSEDW

            STU   TSTUAF

            PULU  D
            CMPD  #CODETOP-TSTCBUF
            BNE   UNFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   UNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   UNFAIL

            LDD   #TRUEV
            BRA   UNDONE
UNFAIL:     LDD   #FALSEV
UNDONE:     LDX   #TSTUNNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTUNNAME:  FCB   9
            FCC   "TSTUNUSED"

; ------------------------------------------------------------
; unit test for VUNUSED.
; TSTVUNUSED
;    Inputs:
;        none
;    Outputs:
;        prints "TSTVUNUSED OK" or "TSTVUNUSED FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTVUNUSED.0.
; ------------------------------------------------------------
TSTVUNUSED: LDD   VARHERE
            STD   TSTVSAV

            LDD   #TSTVBUF
            STD   VARHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   VUNUSEDW

            STU   TSTUAF

            PULU  D
            CMPD  #APPVARSEND-TSTVBUF
            BNE   VUFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   VUFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   VUFAIL

            LDD   #TRUEV
            BRA   VUDONE
VUFAIL:     LDD   #FALSEV
VUDONE:     LDX   #TSTVUNNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTVSAV
            STD   VARHERE

            LDU   TSTU0
            RTS

TSTVUNNAME: FCB   10
            FCC   "TSTVUNUSED"

; ------------------------------------------------------------
; unit test for FILL. Fills 5 scratch bytes with a known
; character, then verifies every one of the 5 bytes
; individually - not just spot-checking the first and last.
; TSTFILL
;    Inputs:
;        none
;    Outputs:
;        prints "TSTFILL OK" or "TSTFILL FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTFILL:    STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            LDD   #$41
            PSHU  D
            STU   TSTUB4

            JSR   FILLW

            STU   TSTUAF

            LDX   #TSTCBUF
            LDB   #5
FILVLP:     LDA   ,X+
            CMPA  #$41
            BNE   FLFAIL
            DECB
            BNE   FILVLP

            PULU  D
            CMPD  #TSTGUARD
            BNE   FLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   FLFAIL

            LDD   #TRUEV
            BRA   FLDONE
FLFAIL:     LDD   #FALSEV
FLDONE:     LDX   #TSTFLNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTFLNAME:  FCB   7
            FCC   "TSTFILL"

; ------------------------------------------------------------
; unit test for ERASE. Pre-fills scratch with a nonzero
; pattern first (so a no-op couldn't accidentally pass),
; erases it, and verifies every byte is genuinely zero.
; TSTERASE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTERASE OK" or "TSTERASE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTERASE:   LDX   #TSTCBUF
            LDB   #5
ERSETLP:    LDA   #$FF
            STA   ,X+
            DECB
            BNE   ERSETLP

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   ERASEW

            STU   TSTUAF

            LDX   #TSTCBUF
            LDB   #5
ERSVLP:     LDA   ,X+
            CMPA  #0
            BNE   ERFAIL
            DECB
            BNE   ERSVLP

            PULU  D
            CMPD  #TSTGUARD
            BNE   ERFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   ERFAIL

            LDD   #TRUEV
            BRA   ERDONE
ERFAIL:     LDD   #FALSEV
ERDONE:     LDX   #TSTERNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTERNAME:  FCB   8
            FCC   "TSTERASE"

; ------------------------------------------------------------
; unit test for CMOVE. Non-overlapping regions (well
; separated within TSTCBUF's own 80 bytes) - CMOVE's own
; overlap-unsafe behavior in the high-over-low direction is
; exactly what MOVE exists to route around, so CMOVE's own
; tests stick to the simple, well-defined case; see
; TSTMOVE2/ TSTMOVE3 below for the overlap-specific
; verification.
; TSTCMOVE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCMOVE OK" or "TSTCMOVE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCMOVE:   LDA   #'A'
            STA   TSTCBUF
            LDA   #'B'
            STA   TSTCBUF+1
            LDA   #'C'
            STA   TSTCBUF+2
            LDA   #'D'
            STA   TSTCBUF+3
            LDA   #'E'
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #TSTCBUF+10
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   CMOVEW

            STU   TSTUAF

            LDA   TSTCBUF+10
            CMPA  #'A'
            BNE   CVFAIL
            LDA   TSTCBUF+11
            CMPA  #'B'
            BNE   CVFAIL
            LDA   TSTCBUF+12
            CMPA  #'C'
            BNE   CVFAIL
            LDA   TSTCBUF+13
            CMPA  #'D'
            BNE   CVFAIL
            LDA   TSTCBUF+14
            CMPA  #'E'
            BNE   CVFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   CVFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   CVFAIL

            LDD   #TRUEV
            BRA   CVDONE
CVFAIL:     LDD   #FALSEV
CVDONE:     LDX   #TSTCMNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCMNAME:  FCB   8
            FCC   "TSTCMOVE"

; ------------------------------------------------------------
; unit test for CMOVE>. Non-overlapping regions, same
; reasoning as TSTCMOVE.
; TSTCMOVEGT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCMOVEGT OK" or "TSTCMOVEGT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCMOVEGT: LDA   #'A'
            STA   TSTCBUF
            LDA   #'B'
            STA   TSTCBUF+1
            LDA   #'C'
            STA   TSTCBUF+2
            LDA   #'D'
            STA   TSTCBUF+3
            LDA   #'E'
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #TSTCBUF+10
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   CMOVEGTW

            STU   TSTUAF

            LDA   TSTCBUF+10
            CMPA  #'A'
            BNE   CXFAIL
            LDA   TSTCBUF+11
            CMPA  #'B'
            BNE   CXFAIL
            LDA   TSTCBUF+12
            CMPA  #'C'
            BNE   CXFAIL
            LDA   TSTCBUF+13
            CMPA  #'D'
            BNE   CXFAIL
            LDA   TSTCBUF+14
            CMPA  #'E'
            BNE   CXFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   CXFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   CXFAIL

            LDD   #TRUEV
            BRA   CXDONE
CXFAIL:     LDD   #FALSEV
CXDONE:     LDX   #TSTCGNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCGNAME:  FCB   10
            FCC   "TSTCMOVEGT"

; ------------------------------------------------------------
; unit test for MOVE, non-overlapping sanity case.
; TSTMOVE1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMOVE1 OK" or "TSTMOVE1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTMOVE1:   LDA   #'A'
            STA   TSTCBUF
            LDA   #'B'
            STA   TSTCBUF+1
            LDA   #'C'
            STA   TSTCBUF+2
            LDA   #'D'
            STA   TSTCBUF+3
            LDA   #'E'
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #TSTCBUF+20
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   MOVEW

            STU   TSTUAF

            LDA   TSTCBUF+20
            CMPA  #'A'
            BNE   MV1FAIL
            LDA   TSTCBUF+21
            CMPA  #'B'
            BNE   MV1FAIL
            LDA   TSTCBUF+22
            CMPA  #'C'
            BNE   MV1FAIL
            LDA   TSTCBUF+23
            CMPA  #'D'
            BNE   MV1FAIL
            LDA   TSTCBUF+24
            CMPA  #'E'
            BNE   MV1FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   MV1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   MV1FAIL

            LDD   #TRUEV
            BRA   MV1DONE
MV1FAIL:    LDD   #FALSEV
MV1DONE:    LDX   #TSTMV1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMV1NAME: FCB   8
            FCC   "TSTMOVE1"

; ------------------------------------------------------------
; unit test for MOVE, overlapping case with dst > src (dst =
; TSTCBUF+2, src = TSTCBUF, 5 bytes - a 2-byte forward
; shift).
; TSTMOVE2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMOVE2 OK" or "TSTMOVE2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTMOVE2.0.
; ------------------------------------------------------------
TSTMOVE2:   LDA   #'A'
            STA   TSTCBUF
            LDA   #'B'
            STA   TSTCBUF+1
            LDA   #'C'
            STA   TSTCBUF+2
            LDA   #'D'
            STA   TSTCBUF+3
            LDA   #'E'
            STA   TSTCBUF+4
            LDA   #'X'
            STA   TSTCBUF+5
            LDA   #'X'
            STA   TSTCBUF+6

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #TSTCBUF+2
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   MOVEW

            STU   TSTUAF

            LDA   TSTCBUF
            CMPA  #'A'
            BNE   MV2FAIL
            LDA   TSTCBUF+1
            CMPA  #'B'
            BNE   MV2FAIL
            LDA   TSTCBUF+2
            CMPA  #'A'
            BNE   MV2FAIL
            LDA   TSTCBUF+3
            CMPA  #'B'
            BNE   MV2FAIL
            LDA   TSTCBUF+4
            CMPA  #'C'
            BNE   MV2FAIL
            LDA   TSTCBUF+5
            CMPA  #'D'
            BNE   MV2FAIL
            LDA   TSTCBUF+6
            CMPA  #'E'
            BNE   MV2FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   MV2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   MV2FAIL

            LDD   #TRUEV
            BRA   MV2DONE
MV2FAIL:    LDD   #FALSEV
MV2DONE:    LDX   #TSTMV2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMV2NAME: FCB   8
            FCC   "TSTMOVE2"

; ------------------------------------------------------------
; unit test for MOVE, overlapping case with dst < src (dst =
; TSTCBUF, src = TSTCBUF+2, 5 bytes - a 2-byte backward
; shift).
; TSTMOVE3
;    Inputs:
;        none
;    Outputs:
;        prints "TSTMOVE3 OK" or "TSTMOVE3 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTMOVE3.0.
; ------------------------------------------------------------
TSTMOVE3:   LDA   #'X'
            STA   TSTCBUF
            LDA   #'X'
            STA   TSTCBUF+1
            LDA   #'A'
            STA   TSTCBUF+2
            LDA   #'B'
            STA   TSTCBUF+3
            LDA   #'C'
            STA   TSTCBUF+4
            LDA   #'D'
            STA   TSTCBUF+5
            LDA   #'E'
            STA   TSTCBUF+6

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF+2
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   MOVEW

            STU   TSTUAF

            LDA   TSTCBUF
            CMPA  #'A'
            BNE   MV3FAIL
            LDA   TSTCBUF+1
            CMPA  #'B'
            BNE   MV3FAIL
            LDA   TSTCBUF+2
            CMPA  #'C'
            BNE   MV3FAIL
            LDA   TSTCBUF+3
            CMPA  #'D'
            BNE   MV3FAIL
            LDA   TSTCBUF+4
            CMPA  #'E'
            BNE   MV3FAIL
            LDA   TSTCBUF+5
            CMPA  #'D'
            BNE   MV3FAIL
            LDA   TSTCBUF+6
            CMPA  #'E'
            BNE   MV3FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   MV3FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   MV3FAIL

            LDD   #TRUEV
            BRA   MV3DONE
MV3FAIL:    LDD   #FALSEV
MV3DONE:    LDX   #TSTMV3NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTMV3NAME: FCB   8
            FCC   "TSTMOVE3"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; strings & parsing tests (glossary section 3.12, 16 words,
; 19 tests since several get separate cases: [CHAR]
; compiling/interpreting state, S" compiling/interpreting
; state (this word genuinely has both), SEARCH
; found/not-found, REPLACES/SUBSTITUTE combined across two
; tests (covering all 4 of SUBSTITUTE's own documented
; %-delimiter cases), SNAME found/not-found.
; TSTSTRPARSE
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTSTRPARSE.0.
; ------------------------------------------------------------
TSTSTRPARSE:
            JSR   CRW
            LDX   #TSTSTRPMSG
            PSHU  X
            LDD   #8
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-11    ; >>>>

            JSR   TSTCOUNT
            JSR   TSTCHARW
            JSR   TSTBRACKCHAR1
            JSR   TSTBRACKCHAR2
            JSR   TSTPARSE
            JSR   TSTPARSENAME
            JSR   TSTSQUOTE1
            JSR   TSTSQUOTE2
            JSR   TSTDOTQUOTE
            JSR   TSTSCOMPARE
            JSR   TSTSEARCH1
            JSR   TSTSEARCH2
            JSR   TSTDASHTRAILING
            JSR   TSTSLASHSTRING
            JSR   TSTREPLSUBS1
            JSR   TSTREPLSUBS2
            JSR   TSTSNAME1
            JSR   TSTSNAME2
            JSR   TSTUNESCAPE

            ENDC                    ; <<<<

            RTS

TSTSTRPMSG: FCC   "StrParse"

            IFEQ  TSTSELECTOR-11    ; >>>>

; ------------------------------------------------------------
; Strings & Parsing test harness (glossary section 3.12).
; Original comment: shadow TSTSTRPARSE.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for COUNT. Builds a counted string at scratch,
; verifies the returned (addr len) correctly skips the count
; byte and reports its value.
; TSTCOUNT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCOUNT OK" or "TSTCOUNT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCOUNT:   LDA   #5
            STA   TSTCBUF
            LDA   #'H'
            STA   TSTCBUF+1
            LDA   #'E'
            STA   TSTCBUF+2
            LDA   #'L'
            STA   TSTCBUF+3
            LDA   #'L'
            STA   TSTCBUF+4
            LDA   #'O'
            STA   TSTCBUF+5

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            STU   TSTUB4

            JSR   COUNTW

            STU   TSTUAF

            PULU  D
            CMPD  #5
            BNE   CTFAIL
            PULU  D
            CMPD  #TSTCBUF+1
            BNE   CTFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CTFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   CTFAIL

            LDD   #TRUEV
            BRA   CTDONE
CTFAIL:     LDD   #FALSEV
CTDONE:     LDX   #TSTCTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCTNAME:  FCB   8
            FCC   "TSTCOUNT"

; ------------------------------------------------------------
; unit test for CHAR. Redirects CODEHERE (WORD's own parse
; output still lands there internally, even though CHAR
; itself doesn't compile anything) and the source, parses a
; space-delimited fake source ("AB CD"), and verifies it
; returns 'A' - the first character of the first word.
; TSTCHARW
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCHARW OK" or "TSTCHARW FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCHARW:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDA   #'A'
            STA   TSTNAMEB
            LDA   #'B'
            STA   TSTNAMEB+1
            LDA   #32
            STA   TSTNAMEB+2
            LDA   #'C'
            STA   TSTNAMEB+3
            LDA   #'D'
            STA   TSTNAMEB+4

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #5
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   CHARW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #'A'
            BNE   CWFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   CWFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   CWFAIL

            LDD   #TRUEV
            BRA   CWDONE
CWFAIL:     LDD   #FALSEV
CWDONE:     LDX   #TSTCWNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCWNAME:  FCB   8
            FCC   "TSTCHARW"

; ------------------------------------------------------------
; unit test for [CHAR], compiling-state case. Compile-only
; (throws -14 otherwise, per its own STATE check). Compiles
; the character as a literal, then executes the result to
; confirm it genuinely pushes 'A'.
; TSTBRACKCHAR1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBRACKCHAR1 OK" or "TSTBRACKCHAR1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTBRACKCHAR1:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'A'
            STA   TSTNAMEB
            LDA   #'B'
            STA   TSTNAMEB+1
            LDA   #32
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            JSR   BRACKCHARW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #'A'
            BNE   BC1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   BC1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   BC1FAIL

            LDD   #TRUEV
            BRA   BC1DONE
BC1FAIL:    LDD   #FALSEV
BC1DONE:    LDX   #TSTBC1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBC1NAME: FCB   13
            FCC   "TSTBRACKCHAR1"

; ------------------------------------------------------------
; unit test for [CHAR], interpreting-state case. STATE=0,
; verifies -14 via CATCH.
; TSTBRACKCHAR2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBRACKCHAR2 OK" or "TSTBRACKCHAR2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTBRACKCHAR2:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'A'
            STA   TSTNAMEB
            LDA   #'B'
            STA   TSTNAMEB+1
            LDA   #32
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #0
            STD   STATE

            STU   TSTU0

            LDX   #BRACKCHARW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #-14
            BNE   BC2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   BC2FAIL

            LDD   #TRUEV
            BRA   BC2DONE
BC2FAIL:    LDD   #FALSEV
BC2DONE:    LDX   #TSTBC2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBC2NAME: FCB   13
            FCC   "TSTBRACKCHAR2"

; ------------------------------------------------------------
; unit test for PARSE. Uses a fake source starting with the
; delimiter itself (",XY", delimiter ',') specifically to
; verify PARSE's own documented distinguishing behavior -
; "does not skip leading delimiters, unlike WORD" - the
; leading comma should be hit immediately, returning a
; zero-length token right where TOIN started, not skipped
; over to find "XY".
; TSTPARSE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPARSE OK" or "TSTPARSE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTPARSE:   LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDA   #','
            STA   TSTNAMEB
            LDA   #'X'
            STA   TSTNAMEB+1
            LDA   #'Y'
            STA   TSTNAMEB+2

            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #','
            PSHU  D
            STU   TSTUB4

            JSR   PARSEW

            STU   TSTUAF

            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #0
            BNE   PRFAIL
            PULU  D
            CMPD  #TSTNAMEB
            BNE   PRFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   PRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   PRFAIL

            LDD   #TRUEV
            BRA   PRDONE
PRFAIL:     LDD   #FALSEV
PRDONE:     LDX   #TSTPRNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPRNAME:  FCB   8
            FCC   "TSTPARSE"

; ------------------------------------------------------------
; unit test for PARSE-NAME. Fake source with 2 leading
; spaces before the token ("  AB CD"), verifying it
; genuinely skips them - the opposite of PARSE's own
; behavior, confirming the two aren't accidentally sharing
; one code path that only happens to work for one of them.
; TSTPARSENAME
;    Inputs:
;        none
;    Outputs:
;        prints "TSTPARSENAME OK" or "TSTPARSENAME FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTPARSENAME:
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDA   #32
            STA   TSTNAMEB
            LDA   #32
            STA   TSTNAMEB+1
            LDA   #'A'
            STA   TSTNAMEB+2
            LDA   #'B'
            STA   TSTNAMEB+3
            LDA   #32
            STA   TSTNAMEB+4
            LDA   #'C'
            STA   TSTNAMEB+5
            LDA   #'D'
            STA   TSTNAMEB+6

            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #7
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   PARSENAMEW

            STU   TSTUAF

            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #2
            BNE   PZFAIL
            PULU  D
            CMPD  #TSTNAMEB+2
            BNE   PZFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   PZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   PZFAIL

            LDD   #TRUEV
            BRA   PZDONE
PZFAIL:     LDD   #FALSEV
PZDONE:     LDX   #TSTPNNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTPNNAME:  FCB   12
            FCC   "TSTPARSENAME"

; ------------------------------------------------------------
; unit test for S", compiling-state case. Compiles a known
; 2-character string, then executes the result to confirm it
; genuinely pushes (addr len) with the correct content at
; addr - not just that the call returned two numbers.
; TSTSQUOTE1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSQUOTE1 OK" or "TSTSQUOTE1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSQUOTE1: LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'H'
            STA   TSTNAMEB
            LDA   #'I'
            STA   TSTNAMEB+1
            LDA   #34
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #-1
            STD   STATE

            JSR   SQUOTEW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            PULU  D
            CMPD  #2
            BNE   SQ1FAIL

            PULU  D
            TFR   D,X
            LDA   ,X
            CMPA  #'H'
            BNE   SQ1FAIL
            LDA   1,X
            CMPA  #'I'
            BNE   SQ1FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   SQ1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   SQ1FAIL

            LDD   #TRUEV
            BRA   SQ1DONE
SQ1FAIL:    LDD   #FALSEV
SQ1DONE:    LDX   #TSTSQ1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSQ1NAME: FCB   10
            FCC   "TSTSQUOTE1"

; ------------------------------------------------------------
; unit test for S", interpreting-state case.
; TSTSQUOTE2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSQUOTE2 OK" or "TSTSQUOTE2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSQUOTE2.0.
; ------------------------------------------------------------
TSTSQUOTE2: LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   STATE
            STD   TSTSTSAV

            LDA   #'H'
            STA   TSTNAMEB
            LDA   #'I'
            STA   TSTNAMEB+1
            LDA   #34
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN
            LDD   #0
            STD   STATE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   SQUOTEW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN
            LDD   TSTSTSAV
            STD   STATE

            PULU  D
            CMPD  #2
            BNE   SQ2FAIL

            PULU  D
            CMPD  #TSTCBUF+PADOFFSET
            BNE   SQ2FAIL

            TFR   D,X
            LDA   ,X
            CMPA  #'H'
            BNE   SQ2FAIL
            LDA   1,X
            CMPA  #'I'
            BNE   SQ2FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   SQ2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   SQ2FAIL

            LDD   #TRUEV
            BRA   SQ2DONE
SQ2FAIL:    LDD   #FALSEV
SQ2DONE:    LDX   #TSTSQ2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSQ2NAME: FCB   10
            FCC   "TSTSQUOTE2"

; ------------------------------------------------------------
; unit test for .".
; TSTDOTQUOTE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDOTQUOTE OK" or "TSTDOTQUOTE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTDOTQUOTE.0.
; ------------------------------------------------------------
TSTDOTQUOTE:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDA   #'H'
            STA   TSTNAMEB
            LDA   #'I'
            STA   TSTNAMEB+1
            LDA   #34
            STA   TSTNAMEB+2

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #3
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            JSR   DOTQUOTEW

            LDD   #OPRTS
            PSHU  D
            JSR   CCOMMAW

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDX   #TSTCBUF
            JSR   ,X

            STU   TSTUAF

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #2
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   DXFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'H'
            BNE   DXFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'I'
            BNE   DXFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #'I'
            BNE   DXFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   DXFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   DXFAIL

            LDD   #TRUEV
            BRA   DXDONE
DXFAIL:     LDD   #FALSEV
DXDONE:     LDX   #TSTDQNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDQNAME:  FCB   11
            FCC   "TSTDOTQUOTE"

; ------------------------------------------------------------
; unit test for COMPARE.
; TSTSCOMPARE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSCOMPARE OK" or "TSTSCOMPARE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSCOMPARE.0.
; ------------------------------------------------------------
TSTSCOMPARE:
            LDA   #'A'
            STA   TSTCBUF
            LDA   #'B'
            STA   TSTCBUF+1
            LDA   #'A'
            STA   TSTCBUF+2
            LDA   #'C'
            STA   TSTCBUF+3

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   #TSTCBUF
            PSHU  D
            LDD   #2
            PSHU  D
            LDD   #TSTCBUF+2
            PSHU  D
            LDD   #2
            PSHU  D
            JSR   COMPAREW
            PULU  D
            CMPD  #-1
            BNE   CQFAIL

            LDD   #TSTCBUF
            PSHU  D
            LDD   #2
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #2
            PSHU  D
            JSR   COMPAREW
            PULU  D
            CMPD  #0
            BNE   CQFAIL

            LDD   #TSTCBUF+2
            PSHU  D
            LDD   #2
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #2
            PSHU  D
            JSR   COMPAREW
            PULU  D
            CMPD  #1
            BNE   CQFAIL

            LDD   #TSTCBUF
            PSHU  D
            LDD   #2
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #3
            PSHU  D
            JSR   COMPAREW
            PULU  D
            CMPD  #-1
            BNE   CQFAIL

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   CQFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   CQFAIL

            LDD   #TRUEV
            BRA   CQDONE
CQFAIL:     LDD   #FALSEV
CQDONE:     LDX   #TSTCQNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCQNAME:  FCB   11
            FCC   "TSTSCOMPARE"

; ------------------------------------------------------------
; unit test for SEARCH, found case. Haystack "HELLOWORLD",
; needle "WOR" - verifies the returned addr3 lands exactly
; at the match position (not just that flag is true), len3
; equals the needle's own length, and flag is true.
; TSTSEARCH1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSEARCH1 OK" or "TSTSEARCH1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSEARCH1: LDA   #'H'
            STA   TSTCBUF
            LDA   #'E'
            STA   TSTCBUF+1
            LDA   #'L'
            STA   TSTCBUF+2
            LDA   #'L'
            STA   TSTCBUF+3
            LDA   #'O'
            STA   TSTCBUF+4
            LDA   #'W'
            STA   TSTCBUF+5
            LDA   #'O'
            STA   TSTCBUF+6
            LDA   #'R'
            STA   TSTCBUF+7
            LDA   #'L'
            STA   TSTCBUF+8
            LDA   #'D'
            STA   TSTCBUF+9

            LDA   #'W'
            STA   TSTCBUF+20
            LDA   #'O'
            STA   TSTCBUF+21
            LDA   #'R'
            STA   TSTCBUF+22

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #10
            PSHU  D
            LDD   #TSTCBUF+20
            PSHU  D
            LDD   #3
            PSHU  D
            STU   TSTUB4

            JSR   SEARCHW

            STU   TSTUAF

            PULU  D
            CMPD  #TRUEV
            BNE   SR1FAIL
            PULU  D
            CMPD  #3
            BNE   SR1FAIL
            PULU  D
            CMPD  #TSTCBUF+5
            BNE   SR1FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SR1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   SR1FAIL

            LDD   #TRUEV
            BRA   SR1DONE
SR1FAIL:    LDD   #FALSEV
SR1DONE:    LDX   #TSTSR1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSR1NAME: FCB   10
            FCC   "TSTSEARCH1"

; ------------------------------------------------------------
; unit test for SEARCH, not-found case. Verifies addr3/len3
; fall back to the original haystack (addr1/len1) unchanged,
; and flag is false.
; TSTSEARCH2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSEARCH2 OK" or "TSTSEARCH2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSEARCH2: LDA   #'H'
            STA   TSTCBUF
            LDA   #'E'
            STA   TSTCBUF+1
            LDA   #'L'
            STA   TSTCBUF+2
            LDA   #'L'
            STA   TSTCBUF+3
            LDA   #'O'
            STA   TSTCBUF+4

            LDA   #'X'
            STA   TSTCBUF+20
            LDA   #'Y'
            STA   TSTCBUF+21

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            LDD   #TSTCBUF+20
            PSHU  D
            LDD   #2
            PSHU  D
            STU   TSTUB4

            JSR   SEARCHW

            STU   TSTUAF

            PULU  D
            CMPD  #FALSEV
            BNE   SR2FAIL
            PULU  D
            CMPD  #5
            BNE   SR2FAIL
            PULU  D
            CMPD  #TSTCBUF
            BNE   SR2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SR2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   SR2FAIL

            LDD   #TRUEV
            BRA   SR2DONE
SR2FAIL:    LDD   #FALSEV
SR2DONE:    LDX   #TSTSR2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSR2NAME: FCB   10
            FCC   "TSTSEARCH2"

; ------------------------------------------------------------
; unit test for -TRAILING. "AB   " (2 letters, 3 trailing
; spaces, len=5) trims to len=2, addr unchanged - confirmed
; via its own code that it's a peek-and-modify-top operation
; on the stack, not a pop-then-push of a new addr.
; TSTDASHTRAILING
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDASHTRAILING OK" or "TSTDASHTRAILING FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDASHTRAILING:
            LDA   #'A'
            STA   TSTCBUF
            LDA   #'B'
            STA   TSTCBUF+1
            LDA   #32
            STA   TSTCBUF+2
            LDA   #32
            STA   TSTCBUF+3
            LDA   #32
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   DASHTRAILINGW

            STU   TSTUAF

            PULU  D
            CMPD  #2
            BNE   DTFAIL2
            PULU  D
            CMPD  #TSTCBUF
            BNE   DTFAIL2
            PULU  D
            CMPD  #TSTGUARD
            BNE   DTFAIL2

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   DTFAIL2

            LDD   #TRUEV
            BRA   DTDONE2
DTFAIL2:    LDD   #FALSEV
DTDONE2:    LDX   #TSTDTNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDTNAME:  FCB   15
            FCC   "TSTDASHTRAILING"

; ------------------------------------------------------------
; unit test for /STRING. "HELLO" trimmed by 2 from the front
; - verifies both the advanced address and the reduced
; length.
; TSTSLASHSTRING
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSLASHSTRING OK" or "TSTSLASHSTRING FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSLASHSTRING:
            LDA   #'H'
            STA   TSTCBUF
            LDA   #'E'
            STA   TSTCBUF+1
            LDA   #'L'
            STA   TSTCBUF+2
            LDA   #'L'
            STA   TSTCBUF+3
            LDA   #'O'
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            LDD   #2
            PSHU  D
            STU   TSTUB4

            JSR   SLASHSTRINGW

            STU   TSTUAF

            PULU  D
            CMPD  #3
            BNE   SLSFAIL
            PULU  D
            CMPD  #TSTCBUF+2
            BNE   SLSFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SLSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   SLSFAIL

            LDD   #TRUEV
            BRA   SLSDONE
SLSFAIL:    LDD   #FALSEV
SLSDONE:    LDX   #TSTSLSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSLSNAME: FCB   14
            FCC   "TSTSLASHSTRING"

; ------------------------------------------------------------
; unit test for REPLACES and SUBSTITUTE together (can only
; be meaningfully tested together - SUBSTITUTE depends on a
; prior REPLACES registration).
; TSTREPLSUBS1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTREPLSUBS1 OK" or "TSTREPLSUBS1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTREPLSUBS1.0.
; ------------------------------------------------------------
TSTREPLSUBS1:
            LDA   #'Z'
            STA   TSTCBUF

            LDA   #'X'
            STA   TSTCBUF+10

            LDA   #'%'
            STA   TSTCBUF+20
            LDA   #'%'
            STA   TSTCBUF+21
            LDA   #'A'
            STA   TSTCBUF+22
            LDA   #'%'
            STA   TSTCBUF+23
            LDA   #'X'
            STA   TSTCBUF+24
            LDA   #'%'
            STA   TSTCBUF+25
            LDA   #'B'
            STA   TSTCBUF+26
            LDA   #'%'
            STA   TSTCBUF+27
            LDA   #'Y'
            STA   TSTCBUF+28
            LDA   #'%'
            STA   TSTCBUF+29

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   #TSTCBUF
            PSHU  D
            LDD   #1
            PSHU  D
            LDD   #TSTCBUF+10
            PSHU  D
            LDD   #1
            PSHU  D
            JSR   REPLACESW

            LDD   #TSTCBUF+20
            PSHU  D
            LDD   #10
            PSHU  D
            LDD   #TSTCBUF+40
            PSHU  D
            LDD   #20
            PSHU  D
            JSR   SUBSTITUTEW

            STU   TSTUAF

            PULU  D
            CMPD  #1
            BNE   RS1FAIL
            PULU  D
            CMPD  #7
            BNE   RS1FAIL
            PULU  D
            CMPD  #TSTCBUF+40
            BNE   RS1FAIL

            LDX   #TSTCBUF+40
            LDA   ,X
            CMPA  #'%'
            BNE   RS1FAIL
            LDA   1,X
            CMPA  #'A'
            BNE   RS1FAIL
            LDA   2,X
            CMPA  #'Z'
            BNE   RS1FAIL
            LDA   3,X
            CMPA  #'B'
            BNE   RS1FAIL
            LDA   4,X
            CMPA  #'%'
            BNE   RS1FAIL
            LDA   5,X
            CMPA  #'Y'
            BNE   RS1FAIL
            LDA   6,X
            CMPA  #'%'
            BNE   RS1FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   RS1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #6
            BNE   RS1FAIL

            LDD   #TRUEV
            BRA   RS1DONE
RS1FAIL:    LDD   #FALSEV
RS1DONE:    LDX   #TSTRS1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTRS1NAME: FCB   12
            FCC   "TSTREPLSUBS1"

; ------------------------------------------------------------
; unit test for SUBSTITUTE's fourth documented case: an
; unpaired trailing '%' with no closing delimiter anywhere
; in the remainder passes the residue through unchanged.
; TSTREPLSUBS2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTREPLSUBS2 OK" or "TSTREPLSUBS2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTREPLSUBS2.0.
; ------------------------------------------------------------
TSTREPLSUBS2:
            LDA   #'Z'
            STA   TSTCBUF

            LDA   #'X'
            STA   TSTCBUF+10

            LDA   #'A'
            STA   TSTCBUF+20
            LDA   #'B'
            STA   TSTCBUF+21
            LDA   #'%'
            STA   TSTCBUF+22
            LDA   #'C'
            STA   TSTCBUF+23
            LDA   #'D'
            STA   TSTCBUF+24

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   #TSTCBUF
            PSHU  D
            LDD   #1
            PSHU  D
            LDD   #TSTCBUF+10
            PSHU  D
            LDD   #1
            PSHU  D
            JSR   REPLACESW

            LDD   #TSTCBUF+20
            PSHU  D
            LDD   #5
            PSHU  D
            LDD   #TSTCBUF+40
            PSHU  D
            LDD   #20
            PSHU  D
            JSR   SUBSTITUTEW

            STU   TSTUAF

            PULU  D
            CMPD  #0
            BNE   RS2FAIL
            PULU  D
            CMPD  #5
            BNE   RS2FAIL
            PULU  D
            CMPD  #TSTCBUF+40
            BNE   RS2FAIL

            LDX   #TSTCBUF+40
            LDA   ,X
            CMPA  #'A'
            BNE   RS2FAIL
            LDA   1,X
            CMPA  #'B'
            BNE   RS2FAIL
            LDA   2,X
            CMPA  #'%'
            BNE   RS2FAIL
            LDA   3,X
            CMPA  #'C'
            BNE   RS2FAIL
            LDA   4,X
            CMPA  #'D'
            BNE   RS2FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   RS2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #6
            BNE   RS2FAIL

            LDD   #TRUEV
            BRA   RS2DONE
RS2FAIL:    LDD   #FALSEV
RS2DONE:    LDX   #TSTRS2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTRS2NAME: FCB   12
            FCC   "TSTREPLSUBS2"

; ------------------------------------------------------------
; unit test for SNAME, found case. Searches the real, live
; dictionary (confirmed via its own code that it walks from
; the real LATEST, not a redirectable copy - no redirect
; needed or possible here) for DUP's own xt, verifying the
; returned name content matches "DUP" exactly, not just a
; nonzero length.
; TSTSNAME1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSNAME1 OK" or "TSTSNAME1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSNAME1:  LDD   LATEST
            STD   TSTLSAV

            LDD   #BASELATEST       ; BUG FIX: confirmed via a real MAME run -
            STD   LATEST            ; See bugfix: TSTSNAME1.1

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #DUPW
            PSHU  D
            STU   TSTUB4

            JSR   SNAMEW

            STU   TSTUAF

            PULU  D
            CMPD  #3
            BNE   SN1FAIL

            PULU  D
            TFR   D,X
            LDA   ,X
            CMPA  #'D'
            BNE   SN1FAIL
            LDA   1,X
            CMPA  #'U'
            BNE   SN1FAIL
            LDA   2,X
            CMPA  #'P'
            BNE   SN1FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   SN1FAIL

            LDD   TSTLSAV
            STD   LATEST

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   SN1FAIL

            LDD   #TRUEV
            BRA   SN1DONE
SN1FAIL:    LDD   #FALSEV
SN1DONE:    LDX   #TSTSN1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSN1NAME: FCB   9
            FCC   "TSTSNAME1"

; ------------------------------------------------------------
; unit test for SNAME, not-found case. TSTCBUF (a scratch
; APPVARS address, nowhere near the real code/dictionary
; region) doesn't match any real word's own CFA - verifies
; SNAME correctly reports (0 0) rather than a false match or
; a crash walking off the end of the chain.
; TSTSNAME2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSNAME2 OK" or "TSTSNAME2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSNAME2:  LDD   LATEST
            STD   TSTLSAV

            LDD   #BASELATEST       ; BUG FIX: same real, pre-COLD dependency
            STD   LATEST            ; See bugfix: TSTSNAME2.1

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            STU   TSTUB4

            JSR   SNAMEW

            STU   TSTUAF

            PULU  D
            CMPD  #0
            BNE   SN2FAIL
            PULU  D
            CMPD  #0
            BNE   SN2FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SN2FAIL

            LDD   TSTLSAV
            STD   LATEST

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   SN2FAIL

            LDD   #TRUEV
            BRA   SN2DONE
SN2FAIL:    LDD   #FALSEV
SN2DONE:    LDX   #TSTSN2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSN2NAME: FCB   9
            FCC   "TSTSNAME2"

; ------------------------------------------------------------
; unit test for UNESCAPE.
; TSTUNESCAPE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUNESCAPE OK" or "TSTUNESCAPE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTUNESCAPE.0.
; ------------------------------------------------------------
TSTUNESCAPE:
            LDA   #'A'
            STA   TSTCBUF
            LDA   #'%'
            STA   TSTCBUF+1
            LDA   #'B'
            STA   TSTCBUF+2

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #3
            PSHU  D
            LDD   #TSTCBUF+10
            PSHU  D
            STU   TSTUB4

            JSR   UNESCAPEW

            STU   TSTUAF

            PULU  D
            CMPD  #4
            BNE   UXFAIL
            PULU  D
            CMPD  #TSTCBUF+10
            BNE   UXFAIL

            TFR   D,X
            LDA   ,X
            CMPA  #'A'
            BNE   UXFAIL
            LDA   1,X
            CMPA  #'%'
            BNE   UXFAIL
            LDA   2,X
            CMPA  #'%'
            BNE   UXFAIL
            LDA   3,X
            CMPA  #'B'
            BNE   UXFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   UXFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   UXFAIL

            LDD   #TRUEV
            BRA   UXDONE
UXFAIL:     LDD   #FALSEV
UXDONE:     LDX   #TSTUENAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUENAME:  FCB   11
            FCC   "TSTUNESCAPE"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; numeric output tests (glossary section 3.13, 14 words, 13
; tests since #S and #> are combined into one test, matching
; how they're naturally used together as the tail of the
; standard pictured-output idiom "<# ... #S #>").
; TSTNUMOUT
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTNUMOUT.0.
; ------------------------------------------------------------
TSTNUMOUT:  JSR   CRW
            LDX   #TSTNUMOUTMSG
            PSHU  X
            LDD   #6
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-12    ; >>>>

            JSR   TSTLTNUM
            JSR   TSTHOLD
            JSR   TSTHOLDS
            JSR   TSTSIGN
            JSR   TSTNUMSIGN
            JSR   TSTNUMSIGNSGT
            JSR   TSTDOT
            JSR   TSTUDOT
            JSR   TSTDOTR
            JSR   TSTUDOTR
            JSR   TSTQMARK
            JSR   TSTDDOT
            JSR   TSTDDOTR

            ENDC                    ; <<<<

            RTS

TSTNUMOUTMSG:
            FCC   "NumOut"

            IFEQ  TSTSELECTOR-12    ; >>>>

; ------------------------------------------------------------
; Numeric Output test harness (glossary section 3.13).
; Original comment: shadow TSTNUMOUT.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for <#. No stack effect of its own - verifies it
; sets HLD to PAD's current (redirected) address.
; TSTLTNUM
;    Inputs:
;        none
;    Outputs:
;        prints "TSTLTNUM OK" or "TSTLTNUM FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTLTNUM:   LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   LTNUMW

            STU   TSTUAF

            LDD   HLD
            CMPD  #TSTCBUF+PADOFFSET
            BNE   LNFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   LNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   LNFAIL

            LDD   #TRUEV
            BRA   LNDONE
LNFAIL:     LDD   #FALSEV
LNDONE:     LDX   #TSTLNNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTLNNAME:  FCB   8
            FCC   "TSTLTNUM"

; ------------------------------------------------------------
; unit test for HOLD. Holds 'A' then 'B' - since HOLD grows
; the buffer downward and prepends (decrements HLD first,
; then writes at the new, lower position), the second-held
; character ends up at the lower address, so reading forward
; from the final HLD should give "BA", not "AB".
; TSTHOLD
;    Inputs:
;        none
;    Outputs:
;        prints "TSTHOLD OK" or "TSTHOLD FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTHOLD:    LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   LTNUMW

            LDD   #'A'
            PSHU  D
            JSR   HOLDW

            LDD   #'B'
            PSHU  D
            JSR   HOLDW

            STU   TSTUAF

            LDX   HLD
            LDA   ,X
            CMPA  #'B'
            BNE   HDFAIL
            LDA   1,X
            CMPA  #'A'
            BNE   HDFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   HDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   HDFAIL

            LDD   #TRUEV
            BRA   HDDONE
HDFAIL:     LDD   #FALSEV
HDDONE:     LDX   #TSTHDNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTHDNAME:  FCB   7
            FCC   "TSTHOLD"

; ------------------------------------------------------------
; unit test for HOLDS. Holds the string "XY" - since HOLDS
; iterates its source backward (last character first) and
; HOLD itself prepends, the two behaviors combine to
; preserve the original forward order in the pictured
; buffer, matching its own documented "depends on HOLD's
; exact decrement-by-one behavior".
; TSTHOLDS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTHOLDS OK" or "TSTHOLDS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTHOLDS:   LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            LDA   #'X'
            STA   TSTNAMEB
            LDA   #'Y'
            STA   TSTNAMEB+1

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   LTNUMW

            LDD   #TSTNAMEB
            PSHU  D
            LDD   #2
            PSHU  D
            JSR   HOLDSW

            STU   TSTUAF

            LDX   HLD
            LDA   ,X
            CMPA  #'X'
            BNE   HOFAIL
            LDA   1,X
            CMPA  #'Y'
            BNE   HOFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   HOFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   HOFAIL

            LDD   #TRUEV
            BRA   HODONE
HOFAIL:     LDD   #FALSEV
HODONE:     LDX   #TSTHSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTHSNAME:  FCB   8
            FCC   "TSTHOLDS"

; ------------------------------------------------------------
; unit test for SIGN.
; TSTSIGN
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSIGN OK" or "TSTSIGN FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTSIGN.0.
; ------------------------------------------------------------
TSTSIGN:    LDD   CODEHERE
            STD   TSTCSAV

            LDD   #TSTCBUF
            STD   CODEHERE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   LTNUMW

            LDD   #-5
            LDX   #1
            CMPX  #0
            PSHU  D
            JSR   SIGNW

            LDX   HLD
            LDA   ,X
            CMPA  #'-'
            BNE   SGFAIL

            JSR   LTNUMW

            LDD   #5
            LDX   #-1
            CMPX  #0
            PSHU  D
            JSR   SIGNW

            STU   TSTUAF

            LDD   HLD
            CMPD  #TSTCBUF+PADOFFSET
            BNE   SGFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   SGFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   SGFAIL

            LDD   #TRUEV
            BRA   SGDONE
SGFAIL:     LDD   #FALSEV
SGDONE:     LDX   #TSTSGNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTSGNAME:  FCB   7
            FCC   "TSTSIGN"

; ------------------------------------------------------------
; unit test for #. Converts one digit of 25 (base 10, ud1 =
; (25, 0)) - verifies the held character is '5' (the
; least-significant digit, processed first per the standard
; pictured-output convention) and the returned ud2 is the
; quotient (2, 0).
; TSTNUMSIGN
;    Inputs:
;        none
;    Outputs:
;        prints "TSTNUMSIGN OK" or "TSTNUMSIGN FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTNUMSIGN: LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   LTNUMW

            LDD   #25
            PSHU  D
            LDD   #0
            PSHU  D
            JSR   NUMSIGNW

            STU   TSTUAF

            LDD   TSTBASAV
            STD   BASE

            PULU  D
            CMPD  #0
            BNE   NZFAIL
            PULU  D
            CMPD  #2
            BNE   NZFAIL

            LDX   HLD
            LDA   ,X
            CMPA  #'5'
            BNE   NZFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   NZFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4                ; See bugfix: TSTNUMSIGN.1
            BNE   NZFAIL

            LDD   #TRUEV
            BRA   NZDONE
NZFAIL:     LDD   #FALSEV
NZDONE:     LDX   #TSTNSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTNSNAME:  FCB   10
            FCC   "TSTNUMSIGN"

; ------------------------------------------------------------
; combined unit test for #S and #> (naturally used together
; as the tail of the standard pictured-output idiom "<# ...
; #S #>"). Converts ud1=(12345,0) fully via #S, then #> to
; get (addr len) - verifies both the string content
; ("12345", all 5 digits in correct order) and the length.
; TSTNUMSIGNSGT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTNUMSIGNSGT OK" or "TSTNUMSIGNSGT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTNUMSIGNSGT:
            LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   LTNUMW

            LDD   #12345
            PSHU  D
            LDD   #0
            PSHU  D
            JSR   NUMSIGNSW
            JSR   NUMGTW

            STU   TSTUAF

            LDD   TSTBASAV
            STD   BASE

            PULU  D
            CMPD  #5
            BNE   NXFAIL

            PULU  D
            TFR   D,X
            LDA   ,X
            CMPA  #'1'
            BNE   NXFAIL
            LDA   1,X
            CMPA  #'2'
            BNE   NXFAIL
            LDA   2,X
            CMPA  #'3'
            BNE   NXFAIL
            LDA   3,X
            CMPA  #'4'
            BNE   NXFAIL
            LDA   4,X
            CMPA  #'5'
            BNE   NXFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   NXFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   NXFAIL

            LDD   #TRUEV
            BRA   NXDONE
NXFAIL:     LDD   #FALSEV
NXDONE:     LDX   #TSTNGNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTCSAV
            STD   CODEHERE

            LDU   TSTU0
            RTS

TSTNGNAME:  FCB   13
            FCC   "TSTNUMSIGNSGT"

; ------------------------------------------------------------
; unit test for .
; TSTDOT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDOT OK" or "TSTDOT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTDOT.0.
; ------------------------------------------------------------
TSTDOT:     LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #-42
            PSHU  D
            STU   TSTUB4

            JSR   DOTW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTBASAV
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #4
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   DTFAIL3

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'-'
            BNE   DTFAIL3
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'4'
            BNE   DTFAIL3
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'2'
            BNE   DTFAIL3
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   DTFAIL3
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #32
            BNE   DTFAIL3
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   DTFAIL3

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   DTFAIL3

            LDD   #TRUEV
            BRA   DTDONE3
DTFAIL3:    LDD   #FALSEV
DTDONE3:    LDX   #TSTDTNAME2
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDTNAME2: FCB   6
            FCC   "TSTDOT"

; ------------------------------------------------------------
; unit test for U. Prints 42, expecting "42 " (3 chars: two
; digits, trailing space).
; TSTUDOT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUDOT OK" or "TSTUDOT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUDOT:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #42
            PSHU  D
            STU   TSTUB4

            JSR   UDOTW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTBASAV
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #3
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   UFFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'4'
            BNE   UFFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'2'
            BNE   UFFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   UFFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #32
            BNE   UFFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   UFFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   UFFAIL

            LDD   #TRUEV
            BRA   UFDONE
UFFAIL:     LDD   #FALSEV
UFDONE:     LDX   #TSTUDNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTUDNAME:  FCB   7
            FCC   "TSTUDOT"

; ------------------------------------------------------------
; unit test for .R. Prints 42 with width 5, expecting "
; 42" (3 leading spaces + 2 digits = 5 chars total, no
; trailing space) - specifically exercising the padding
; path, not just a no-padding sanity case.
; TSTDOTR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDOTR OK" or "TSTDOTR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDOTR:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #42
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   DOTRW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTBASAV
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #5
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   DRFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #32
            BNE   DRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   DRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   DRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'4'
            BNE   DRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'2'
            BNE   DRFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #'2'
            BNE   DRFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   DRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   DRFAIL

            LDD   #TRUEV
            BRA   DRDONE
DRFAIL:     LDD   #FALSEV
DRDONE:     LDX   #TSTDRNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDRNAME:  FCB   7
            FCC   "TSTDOTR"

; ------------------------------------------------------------
; unit test for U.R. Prints 42 with width 5, expecting "
; 42" - same padding-path reasoning as TSTDOTR.
; TSTUDOTR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTUDOTR OK" or "TSTUDOTR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTUDOTR:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #42
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   UDOTRW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTBASAV
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #5
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   URFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #32
            BNE   URFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   URFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   URFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'4'
            BNE   URFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'2'
            BNE   URFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #'2'
            BNE   URFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   URFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   URFAIL

            LDD   #TRUEV
            BRA   URDONE
URFAIL:     LDD   #FALSEV
URDONE:     LDX   #TSTURNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTURNAME:  FCB   8
            FCC   "TSTUDOTR"

; ------------------------------------------------------------
; unit test for ?. Stores -7 at a scratch cell (separate
; from the CODEHERE-redirected pictured-output region, to
; avoid conflict), calls ? with its address, expects "-7 "
; (fetches and prints signed, via DOT internally).
; TSTQMARK
;    Inputs:
;        none
;    Outputs:
;        prints "TSTQMARK OK" or "TSTQMARK FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTQMARK:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            LDD   #-7
            STD   TSTCBUF+50

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF+50
            PSHU  D
            STU   TSTUB4

            JSR   QMARKW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTBASAV
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #3
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   QMFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'-'
            BNE   QMFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'7'
            BNE   QMFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   QMFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #32
            BNE   QMFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   QMFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   QMFAIL

            LDD   #TRUEV
            BRA   QMDONE
QMFAIL:     LDD   #FALSEV
QMDONE:     LDX   #TSTQMNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTQMNAME:  FCB   8
            FCC   "TSTQMARK"

; ------------------------------------------------------------
; unit test for D. Prints d = -100000 (a genuine double-cell
; value: high cell $FFFE, low cell $7960, computed and
; verified independently in Python before writing this test
; - specifically exercising the 32-bit negation path
; (MNEG32), not just a value that happens to fit in one
; cell). Expects "-100000 " (8 chars).
; TSTDDOT
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDDOT OK" or "TSTDDOT FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDDOT:    LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$7960
            PSHU  D
            LDD   #$FFFE
            PSHU  D
            STU   TSTUB4

            JSR   DDOTW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTBASAV
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #8
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   DDFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'-'
            BNE   DDFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'1'
            BNE   DDFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DDFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DDFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DDFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DDFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DDFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   DDFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #32
            BNE   DDFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   DDFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-4
            BNE   DDFAIL

            LDD   #TRUEV
            BRA   DDDONE
DDFAIL:     LDD   #FALSEV
DDDONE:     LDX   #TSTDDNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDDNAME:  FCB   7
            FCC   "TSTDDOT"

; ------------------------------------------------------------
; unit test for D.R. Same d = -100000 as TSTDDOT, width 10 -
; "-100000" is 7 chars, so padding = 3 spaces, expecting "
; -100000" (10 chars total, no trailing space).
; TSTDDOTR
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDDOTR OK" or "TSTDDOTR FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTDDOTR:   LDD   CODEHERE
            STD   TSTCSAV
            LDD   BASE
            STD   TSTBASAV

            LDD   #TSTCBUF
            STD   CODEHERE
            LDD   #10
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #$7960
            PSHU  D
            LDD   #$FFFE
            PSHU  D
            LDD   #10
            PSHU  D
            STU   TSTUB4

            JSR   DDOTRW

            STU   TSTUAF

            LDD   TSTCSAV
            STD   CODEHERE
            LDD   TSTBASAV
            STD   BASE

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #10
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   DRRFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #32
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'-'
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'1'
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DRRFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'0'
            BNE   DRRFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #'0'
            BNE   DRRFAIL
            ENDC                    ; <<<<<<<<<<

            PULU  D
            CMPD  #TSTGUARD
            BNE   DRRFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-6
            BNE   DRRFAIL

            LDD   #TRUEV
            BRA   DRRDONE
DRRFAIL:    LDD   #FALSEV
DRRDONE:    LDX   #TSTDRRNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDRRNAME: FCB   8
            FCC   "TSTDDOTR"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; base/radix control tests (glossary section 3.14, 4 words,
; 1 combined test - each word's own effect is a single BASE
; read/write, trivially covered together rather than
; separately).
; TSTBASERADIX
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTBASERADIX.0.
; ------------------------------------------------------------
TSTBASERADIX:
            JSR   CRW
            LDX   #TSTBRMSG
            PSHU  X
            LDD   #9
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-13    ; >>>>

            JSR   TSTBASE

            ENDC                    ; <<<<

            RTS

TSTBRMSG:   FCC   "BaseRadix"

            IFEQ  TSTSELECTOR-13    ; >>>>

; ------------------------------------------------------------
; Base/Radix Control test harness (glossary section 3.14).
; Original comment: shadow TSTBASERADIX.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; combined unit test for BASE, DECIMAL, HEX, and BINARY.
; TSTBASE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBASE OK" or "TSTBASE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTBASE.0.
; ------------------------------------------------------------
TSTBASE:    LDD   BASE
            STD   TSTBASAV

            STU   TSTU0

            JSR   HEXW
            LDD   BASE
            CMPD  #16
            BNE   BSFAIL

            JSR   BINARYW
            LDD   BASE
            CMPD  #2
            BNE   BSFAIL

            JSR   DECIMALW
            LDD   BASE
            CMPD  #10
            BNE   BSFAIL

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   BASEW

            STU   TSTUAF

            PULU  D
            CMPD  #BASE
            BNE   BSFAIL

            TFR   D,X
            LDD   ,X
            CMPD  #10
            BNE   BSFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   BSFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   BSFAIL

            LDD   #TRUEV
            BRA   BSDONE
BSFAIL:     LDD   #FALSEV
BSDONE:     LDX   #TSTBSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDD   TSTBASAV
            STD   BASE

            LDU   TSTU0
            RTS

TSTBSNAME:  FCB   7
            FCC   "TSTBASE"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; exception handling tests (glossary section 3.15, 2 words,
; 4 tests since CATCH/THROW can only be meaningfully tested
; together - THROW's own effect is only observable through a
; CATCH that traps it).
; TSTEXCEPTION
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTEXCEPTION.0.
; ------------------------------------------------------------
TSTEXCEPTION:
            JSR   CRW
            LDX   #TSTEXCMSG
            PSHU  X
            LDD   #6
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-14    ; >>>>

            JSR   TSTCATCHOK
            JSR   TSTCATCHTHROW
            JSR   TSTTHROWZERO
            JSR   TSTHANDLERSAVE

            ENDC                    ; <<<<

            RTS

TSTEXCMSG:  FCC   "Except"

            IFEQ  TSTSELECTOR-14    ; >>>>

; ------------------------------------------------------------
; Exception Handling test harness (glossary section 3.15).
; Original comment: shadow TSTEXCEPTION.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for CATCH, success path. Wraps DUP (a genuine,
; real dictionary word, not a synthetic stand-in) and
; verifies both that DUP's own effect genuinely happened
; (the value really was duplicated) and that CATCH itself
; returns 0.
; TSTCATCHOK
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCATCHOK OK" or "TSTCATCHOK FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTCATCHOK: STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTVAL1
            PSHU  D
            LDX   #DUPW
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #0
            BNE   COFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   COFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   COFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   COFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   COFAIL

            LDD   #TRUEV
            BRA   CODONE
COFAIL:     LDD   #FALSEV
CODONE:     LDX   #TSTCONAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCONAME:  FCB   10
            FCC   "TSTCATCHOK"

; ------------------------------------------------------------
; Helper for the CATCH tests (not a test itself): push three
; dummy values, then THROW a known code. Only called via CATCH.
; TSTTHROWHLP
;    Inputs:
;        none
;    Outputs:
;        pushes three dummy values, then THROWs a known code
;    Registers: all changed.
; Original comment: shadow TSTTHROWHLP.0.
; ------------------------------------------------------------
TSTTHROWHLP:
            LDD   #TSTVAL1
            PSHU  D
            LDD   #TSTVAL2
            PSHU  D
            LDD   #TSTNEG1
            PSHU  D
            JSR   THROW
            RTS

; ------------------------------------------------------------
; unit test for CATCH, exception path, and for THROW's own
; non-local exit together (the two can only be meaningfully
; tested as a pair - THROW's own effect is only observable
; through a CATCH that traps it).
; TSTCATCHTHROW
;    Inputs:
;        none
;    Outputs:
;        prints "TSTCATCHTHROW OK" or "TSTCATCHTHROW FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTCATCHTHROW.0.
; ------------------------------------------------------------
TSTCATCHTHROW:
            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDX   #TSTTHROWHLP
            PSHU  X
            STU   TSTUB4

            JSR   CATCHW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTNEG1
            BNE   CTFAIL2
            PULU  D
            CMPD  #TSTGUARD
            BNE   CTFAIL2

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   CTFAIL2

            LDD   #TRUEV
            BRA   CTDONE2
CTFAIL2:    LDD   #FALSEV
CTDONE2:    LDX   #TSTCTNAME2
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTCTNAME2: FCB   13
            FCC   "TSTCATCHTHROW"

; ------------------------------------------------------------
; unit test for THROW(0).
; TSTTHROWZERO
;    Inputs:
;        none
;    Outputs:
;        prints "TSTTHROWZERO OK" or "TSTTHROWZERO FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTTHROWZERO.0.
; ------------------------------------------------------------
TSTTHROWZERO:
            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #0
            PSHU  D
            STU   TSTUB4

            JSR   THROW

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   TVFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   TVFAIL

            LDD   #TRUEV
            BRA   TVDONE
TVFAIL:     LDD   #FALSEV
TVDONE:     LDX   #TSTTZNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTTZNAME:  FCB   12
            FCC   "TSTTHROWZERO"

; ------------------------------------------------------------
; unit test verifying CATCH correctly restores HANDLER
; afterward, on both paths - the success path (wrapping DUP)
; and the throw path (wrapping TSTTHROWHLP again).
; TSTHANDLERSAVE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTHANDLERSAVE OK" or "TSTHANDLERSAVE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTHANDLERSAVE.0.
; ------------------------------------------------------------
TSTHANDLERSAVE:
            LDD   HANDLER
            STD   TSTHANDSAV

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   #TSTVAL1
            PSHU  D
            LDX   #DUPW
            PSHU  X

            JSR   CATCHW

            LDD   HANDLER
            CMPD  TSTHANDSAV
            BNE   HNFAIL

            PULU  D
            CMPD  #0
            BNE   HNFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   HNFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   HNFAIL

            LDX   #TSTTHROWHLP
            PSHU  X

            JSR   CATCHW

            STU   TSTUAF

            LDD   HANDLER
            CMPD  TSTHANDSAV
            BNE   HNFAIL

            PULU  D
            CMPD  #TSTNEG1
            BNE   HNFAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   HNFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   HNFAIL

            LDD   #TRUEV
            BRA   HNDONE
HNFAIL:     LDD   #FALSEV
HNDONE:     LDX   #TSTHNNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTHNNAME:  FCB   14
            FCC   "TSTHANDLERSAVE"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; comments tests (glossary section 3.16, 2 words).
; TSTCOMMENTS
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTCOMMENTS.0.
; ------------------------------------------------------------
TSTCOMMENTS:
            JSR   CRW
            LDX   #TSTCOMMSG
            PSHU  X
            LDD   #8
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-15    ; >>>>

            JSR   TSTLPAREN
            JSR   TSTBACKSLASH

            ENDC                    ; <<<<

            RTS

TSTCOMMSG:  FCC   "Comments"

            IFEQ  TSTSELECTOR-15    ; >>>>

; ------------------------------------------------------------
; Comments test harness (glossary section 3.16).
; Original comment: shadow TSTCOMMENTS.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for (.
; TSTLPAREN
;    Inputs:
;        none
;    Outputs:
;        prints "TSTLPAREN OK" or "TSTLPAREN FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTLPAREN.0.
; ------------------------------------------------------------
TSTLPAREN:  LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDA   #'h'
            STA   TSTNAMEB
            LDA   #'i'
            STA   TSTNAMEB+1
            LDA   #')'
            STA   TSTNAMEB+2
            LDA   #'m'
            STA   TSTNAMEB+3

            LDD   #TSTNAMEB
            STD   SRCADDR
            LDD   #4
            STD   SRCLEN
            LDD   #0
            STD   TOIN

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   LPARENW

            STU   TSTUAF

            LDD   TOIN
            CMPD  #3
            BNE   LPFAIL

            LDA   TSTNAMEB+3
            CMPA  #'m'
            BNE   LPFAIL

            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #TSTGUARD
            BNE   LPFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   LPFAIL

            LDD   #TRUEV
            BRA   LPDONE
LPFAIL:     LDD   #FALSEV
LPDONE:     LDX   #TSTLPNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTLPNAME:  FCB   9
            FCC   "TSTLPAREN"

; ------------------------------------------------------------
; unit test for \.
; TSTBACKSLASH
;    Inputs:
;        none
;    Outputs:
;        prints "TSTBACKSLASH OK" or "TSTBACKSLASH FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTBACKSLASH.0.
; ------------------------------------------------------------
TSTBACKSLASH:
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   TOIN
            STD   TSTTISAV

            LDD   #10
            STD   SRCLEN
            LDD   #3
            STD   TOIN

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   BACKSLASHW

            STU   TSTUAF

            LDD   TOIN
            CMPD  #10
            BNE   BLFAIL

            LDD   TSTSLSAV
            STD   SRCLEN
            LDD   TSTTISAV
            STD   TOIN

            PULU  D
            CMPD  #TSTGUARD
            BNE   BLFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   BLFAIL

            LDD   #TRUEV
            BRA   BLDONE
BLFAIL:     LDD   #FALSEV
BLDONE:     LDX   #TSTBLNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTBLNAME:  FCB   12
            FCC   "TSTBACKSLASH"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; environmental & system queries tests (glossary section
; 3.17, 10 words, 8 tests since TIB/#TIB/>IN/SPAN/BL are
; combined into one test, and ENVIRONMENT? gets three
; separate tests of its own - single-cell, double-cell, and
; unsupported- string cases).
; TSTENVSYS
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTENVSYS.0.
; ------------------------------------------------------------
TSTENVSYS:  JSR   CRW
            LDX   #TSTENVSYSMSG
            PSHU  X
            LDD   #6
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-16    ; >>>>

            JSR   TSTENVVARS
            JSR   TSTSOURCE
            JSR   TSTSOURCEID
            JSR   TSTREFILL
            JSR   TSTEVALUATE
            JSR   TSTENVQUERY1
            JSR   TSTENVQUERY2
            JSR   TSTENVQUERY3

            ENDC                    ; <<<<

            RTS

TSTENVSYSMSG:
            FCC   "EnvSys"

            IFEQ  TSTSELECTOR-16    ; >>>>

; ------------------------------------------------------------
; Environmental & System Queries test harness (glossary
; section 3.17).
; Original comment: shadow TSTENVSYS.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; combined unit test for TIB, #TIB, >IN, SPAN, and BL. The
; first four are variables (return their own address); BL is
; a constant (returns 32 directly).
; TSTENVVARS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTENVVARS OK" or "TSTENVVARS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTENVVARS: STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   TIBW
            PULU  D
            CMPD  #TIBBUF
            BNE   EVFAIL

            JSR   NTIBW
            PULU  D
            CMPD  #NTIB
            BNE   EVFAIL

            JSR   TOINW
            PULU  D
            CMPD  #TOIN
            BNE   EVFAIL

            JSR   SPANW
            PULU  D
            CMPD  #SPAN
            BNE   EVFAIL

            JSR   BLW
            PULU  D
            CMPD  #32
            BNE   EVFAIL

            STU   TSTUAF

            PULU  D
            CMPD  #TSTGUARD
            BNE   EVFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   EVFAIL

            LDD   #TRUEV
            BRA   EVDONE
EVFAIL:     LDD   #FALSEV
EVDONE:     LDX   #TSTEVNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEVNAME:  FCB   10
            FCC   "TSTENVVARS"

; ------------------------------------------------------------
; unit test for SOURCE. Redirects SRCADDR/SRCLEN to known,
; distinctive values, verifies SOURCE returns exactly those.
; TSTSOURCE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSOURCE OK" or "TSTSOURCE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSOURCE:  LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV

            LDD   #TSTCBUF
            STD   SRCADDR
            LDD   #7
            STD   SRCLEN

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   SOURCEW

            STU   TSTUAF

            LDD   TSTSASAV
            STD   SRCADDR
            LDD   TSTSLSAV
            STD   SRCLEN

            PULU  D
            CMPD  #7
            BNE   SOFAIL
            PULU  D
            CMPD  #TSTCBUF
            BNE   SOFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SOFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   SOFAIL

            LDD   #TRUEV
            BRA   SODONE
SOFAIL:     LDD   #FALSEV
SODONE:     LDX   #TSTSONAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSONAME:  FCB   9
            FCC   "TSTSOURCE"

; ------------------------------------------------------------
; unit test for SOURCE-ID. Redirects SRCID to a known,
; distinctive value, verifies SOURCE-ID returns exactly
; that.
; TSTSOURCEID
;    Inputs:
;        none
;    Outputs:
;        prints "TSTSOURCEID OK" or "TSTSOURCEID FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTSOURCEID:
            LDD   SRCID
            STD   TSTSISAV

            LDD   #-1
            STD   SRCID

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   SOURCEIDW

            STU   TSTUAF

            LDD   TSTSISAV
            STD   SRCID

            PULU  D
            CMPD  #-1
            BNE   SIFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   SIFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   SIFAIL

            LDD   #TRUEV
            BRA   SIDONE
SIFAIL:     LDD   #FALSEV
SIDONE:     LDX   #TSTSINAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTSINAME:  FCB   11
            FCC   "TSTSOURCEID"

; ------------------------------------------------------------
; unit test for REFILL, string-source path only.
; TSTREFILL
;    Inputs:
;        none
;    Outputs:
;        prints "TSTREFILL OK" or "TSTREFILL FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTREFILL.0.
; ------------------------------------------------------------
TSTREFILL:  LDD   SRCID
            STD   TSTSISAV

            LDD   #-1
            STD   SRCID

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            JSR   REFILLW

            STU   TSTUAF

            LDD   TSTSISAV
            STD   SRCID

            PULU  D
            CMPD  #FALSEV
            BNE   RFFAIL2
            PULU  D
            CMPD  #TSTGUARD
            BNE   RFFAIL2

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   RFFAIL2

            LDD   #TRUEV
            BRA   RFDONE2
RFFAIL2:    LDD   #FALSEV
RFDONE2:    LDX   #TSTRFNAME2
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTRFNAME2: FCB   9
            FCC   "TSTREFILL"

; ------------------------------------------------------------
; unit test for EVALUATE.
; TSTEVALUATE
;    Inputs:
;        none
;    Outputs:
;        prints "TSTEVALUATE OK" or "TSTEVALUATE FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTEVALUATE.0.
; ------------------------------------------------------------
TSTEVALUATE:
            LDD   SRCADDR
            STD   TSTSASAV
            LDD   SRCLEN
            STD   TSTSLSAV
            LDD   SRCID
            STD   TSTSISAV
            LDD   TOIN
            STD   TSTTISAV
            LDD   BASE
            STD   TSTBASAV
            LDD   LATEST
            STD   TSTLSAV
            LDD   CODEHERE
            STD   TSTCSAV

            LDD   #10
            STD   BASE
            LDD   #BASELATEST       ; BUG FIX: confirmed via MAME - LATEST,
            STD   LATEST            ; See bugfix: TSTEVALUATE.1

            LDD   #TSTCBUF2         ; See bugfix: TSTEVALUATE.2
            STD   CODEHERE

            LDA   #'1'
            STA   TSTCBUF
            LDA   #32
            STA   TSTCBUF+1
            LDA   #'2'
            STA   TSTCBUF+2
            LDA   #32
            STA   TSTCBUF+3
            LDA   #'+'
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            STU   TSTUB4

            JSR   EVALUATEW

            STU   TSTUAF

            LDD   SRCADDR
            CMPD  TSTSASAV
            BNE   ELFAIL
            LDD   SRCLEN
            CMPD  TSTSLSAV
            BNE   ELFAIL
            LDD   SRCID
            CMPD  TSTSISAV
            BNE   ELFAIL
            LDD   TOIN
            CMPD  TSTTISAV
            BNE   ELFAIL

            LDD   TSTBASAV
            STD   BASE
            LDD   TSTLSAV
            STD   LATEST
            LDD   TSTCSAV
            STD   CODEHERE

            PULU  D
            CMPD  #3
            BNE   ELFAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   ELFAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #-2
            BNE   ELFAIL

            LDD   #TRUEV
            BRA   ELDONE
ELFAIL:     LDD   #FALSEV
ELDONE:     LDX   #TSTELNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTELNAME:  FCB   11
            FCC   "TSTEVALUATE"

; ------------------------------------------------------------
; unit test for ENVIRONMENT?, verifying the exact
; adjacent-entry pair its own bug-fix comment describes:
; "/COUNTED-STRING" (255) immediately followed by "MAX-N"
; (32767) - the specific mechanism that once let COMPAREW's
; own X-clobbering read bytes from the wrong table entry,
; confirmed via MAME with the exact $4E4D symptom (per the
; code's own comment).
; TSTENVQUERY1
;    Inputs:
;        none
;    Outputs:
;        prints "TSTENVQUERY1 OK" or "TSTENVQUERY1 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTENVQUERY1.0.
; ------------------------------------------------------------
TSTENVQUERY1:
            LDA   #'/'
            STA   TSTCBUF
            LDA   #'C'
            STA   TSTCBUF+1
            LDA   #'O'
            STA   TSTCBUF+2
            LDA   #'U'
            STA   TSTCBUF+3
            LDA   #'N'
            STA   TSTCBUF+4
            LDA   #'T'
            STA   TSTCBUF+5
            LDA   #'E'
            STA   TSTCBUF+6
            LDA   #'D'
            STA   TSTCBUF+7
            LDA   #'-'
            STA   TSTCBUF+8
            LDA   #'S'
            STA   TSTCBUF+9
            LDA   #'T'
            STA   TSTCBUF+10
            LDA   #'R'
            STA   TSTCBUF+11
            LDA   #'I'
            STA   TSTCBUF+12
            LDA   #'N'
            STA   TSTCBUF+13
            LDA   #'G'
            STA   TSTCBUF+14

            LDA   #'M'
            STA   TSTCBUF+20
            LDA   #'A'
            STA   TSTCBUF+21
            LDA   #'X'
            STA   TSTCBUF+22
            LDA   #'-'
            STA   TSTCBUF+23
            LDA   #'N'
            STA   TSTCBUF+24

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   #TSTCBUF
            PSHU  D
            LDD   #15
            PSHU  D
            JSR   ENVQUERYW

            PULU  D
            CMPD  #TRUEV
            BNE   EN1FAIL
            PULU  D
            CMPD  #255
            BNE   EN1FAIL

            LDD   #TSTCBUF+20
            PSHU  D
            LDD   #5
            PSHU  D
            JSR   ENVQUERYW

            STU   TSTUAF

            PULU  D
            CMPD  #TRUEV
            BNE   EN1FAIL
            PULU  D
            CMPD  #32767
            BNE   EN1FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   EN1FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #4
            BNE   EN1FAIL

            LDD   #TRUEV
            BRA   EN1DONE
EN1FAIL:    LDD   #FALSEV
EN1DONE:    LDX   #TSTEN1NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEN1NAME: FCB   12
            FCC   "TSTENVQUERY1"

; ------------------------------------------------------------
; unit test for ENVIRONMENT?, double-cell case. Queries
; "MAX-D" - confirmed via its own table entry to be
; $7FFFFFFF (low cell $FFFF, high cell $7FFF) - exercising
; the separate double-cell table path (ENVTABLE2/ENV2START),
; not just the single-cell one TSTENVQUERY1 already covers.
; TSTENVQUERY2
;    Inputs:
;        none
;    Outputs:
;        prints "TSTENVQUERY2 OK" or "TSTENVQUERY2 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTENVQUERY2:
            LDA   #'M'
            STA   TSTCBUF
            LDA   #'A'
            STA   TSTCBUF+1
            LDA   #'X'
            STA   TSTCBUF+2
            LDA   #'-'
            STA   TSTCBUF+3
            LDA   #'D'
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            JSR   ENVQUERYW

            STU   TSTUAF

            PULU  D
            CMPD  #TRUEV
            BNE   EW2FAIL
            PULU  D
            CMPD  #$7FFF
            BNE   EW2FAIL
            PULU  D
            CMPD  #$FFFF
            BNE   EW2FAIL

            PULU  D
            CMPD  #TSTGUARD
            BNE   EW2FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #6
            BNE   EW2FAIL

            LDD   #TRUEV
            BRA   EW2DONE
EW2FAIL:    LDD   #FALSEV
EW2DONE:    LDX   #TSTEW2NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEW2NAME: FCB   12
            FCC   "TSTENVQUERY2"

; ------------------------------------------------------------
; unit test for ENVIRONMENT?, unsupported string case.
; Queries "ZZZZZ" - genuinely absent from both tables -
; verifies false is reported, matching the documented "--
; false" result for an unrecognized string.
; TSTENVQUERY3
;    Inputs:
;        none
;    Outputs:
;        prints "TSTENVQUERY3 OK" or "TSTENVQUERY3 FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; ------------------------------------------------------------
TSTENVQUERY3:
            LDA   #'Z'
            STA   TSTCBUF
            STA   TSTCBUF+1
            STA   TSTCBUF+2
            STA   TSTCBUF+3
            STA   TSTCBUF+4

            STU   TSTU0

            LDD   #TSTGUARD
            PSHU  D
            STU   TSTUB4

            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            JSR   ENVQUERYW

            STU   TSTUAF

            PULU  D
            CMPD  #FALSEV
            BNE   EW3FAIL
            PULU  D
            CMPD  #TSTGUARD
            BNE   EW3FAIL

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #2
            BNE   EW3FAIL

            LDD   #TRUEV
            BRA   EW3DONE
EW3FAIL:    LDD   #FALSEV
EW3DONE:    LDX   #TSTEW3NAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTEW3NAME: FCB   12
            FCC   "TSTENVQUERY3"

            ENDC                    ; <<<<

; ------------------------------------------------------------
; tools word set tests (glossary section 3.18, 3 words).
; TSTTOOLS
;    Inputs:
;        none
;    Outputs:
;        group heading and each enabled test's result queued for output
;    Registers: all changed.
; Original comment: shadow TSTTOOLS.0.
; ------------------------------------------------------------
TSTTOOLS:   JSR   CRW
            LDX   #TSTTOOLSMSG
            PSHU  X
            LDD   #5
            PSHU  D
            JSR   TYPEW
            JSR   CRW

            IFEQ  TSTSELECTOR-17    ; >>>>

            JSR   TSTDOTS
            JSR   TSTWORDS
            JSR   TSTDUMP

            ENDC                    ; <<<<

            RTS

TSTTOOLSMSG:
            FCC   "Tools"

            IFEQ  TSTSELECTOR-17    ; >>>>

; ------------------------------------------------------------
; Tools test harness (glossary section 3.18).
; Original comment: shadow TSTTOOLS.1.
; ------------------------------------------------------------

; ------------------------------------------------------------
; unit test for .S.
; TSTDOTS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDOTS OK" or "TSTDOTS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTDOTS.0.
; ------------------------------------------------------------
TSTDOTS:    LDD   BASE
            STD   TSTBASAV

            LDD   #10
            STD   BASE              ; See bugfix: TSTDOTS.1

            STU   TSTU0

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            LDD   #TSTVAL1
            PSHU  D
            LDD   #7
            PSHU  D
            STU   TSTUB4

            JSR   DOTSW

            STU   TSTUAF

            IFEQ  SERIALPOLL        ; >>>> See bugfix: TSTDOTS.2
            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'7'
            BNE   DYFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   DYFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #0
            BEQ   DYFAIL
            ENDC                    ; <<<<<<<<<<

            LDD   TSTBASAV
            STD   BASE

            LDD   TSTUAF
            SUBD  TSTUB4
            CMPD  #0
            BNE   DYFAIL

            PULU  D
            CMPD  #7
            BNE   DYFAIL
            PULU  D
            CMPD  #TSTVAL1
            BNE   DYFAIL

            LDD   #TRUEV
            BRA   DYDONE
DYFAIL:     LDD   #FALSEV
DYDONE:     LDX   #TSTDSNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDSNAME:  FCB   7
            FCC   "TSTDOTS"

; ------------------------------------------------------------
; unit test for WORDS.
; TSTWORDS
;    Inputs:
;        none
;    Outputs:
;        prints "TSTWORDS OK" or "TSTWORDS FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTWORDS.0.
; ------------------------------------------------------------
TSTWORDS:   LDD   LATEST
            STD   TSTLSAV

            LDA   #2
            STA   TSTCBUF
            LDA   #'A'
            STA   TSTCBUF+1
            LDA   #'B'
            STA   TSTCBUF+2
            LDD   #0
            STD   TSTCBUF+3
            LDD   #DUPW
            STD   TSTCBUF+5

            LDA   #2
            STA   TSTCBUF+10
            LDA   #'C'
            STA   TSTCBUF+11
            LDA   #'D'
            STA   TSTCBUF+12
            LDD   #TSTCBUF
            STD   TSTCBUF+13
            LDD   #DUPW
            STD   TSTCBUF+15

            LDD   #TSTCBUF+10
            STD   LATEST

            IFEQ  SERIALPOLL        ; >>>>
            LDA   OUTHEAD
            STA   TSTOHSAV
            ENDC                    ; <<<<

            STU   TSTU0
            STU   TSTUB4

            JSR   WORDSW

            STU   TSTUAF

            LDD   TSTLSAV
            STD   LATEST

            IFEQ  SERIALPOLL        ; >>>>
            LDA   TSTOHSAV
            ADDA  #8
            ANDA  #OUTBUFSZ-1
            CMPA  OUTHEAD
            BNE   WOFAIL

            LDX   #OUTBUF
            LDB   TSTOHSAV
            LDA   B,X
            CMPA  #'C'
            BNE   WOFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'D'
            BNE   WOFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   WOFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'A'
            BNE   WOFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #'B'
            BNE   WOFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #32
            BNE   WOFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #13
            BNE   WOFAIL
            INCB
            ANDB  #OUTBUFSZ-1
            LDA   B,X
            CMPA  #10
            BNE   WOFAIL
            ELSE                    ; <<<<>>>>
            LDA   EMITCH
            CMPA  #10
            BNE   WOFAIL
            ENDC                    ; <<<<<<<<<<

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   WOFAIL

            LDD   #TRUEV
            BRA   WODONE
WOFAIL:     LDD   #FALSEV
WODONE:     LDX   #TSTWONAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTWONAME:  FCB   8
            FCC   "TSTWORDS"

; ------------------------------------------------------------
; unit test for DUMP.
; TSTDUMP
;    Inputs:
;        none
;    Outputs:
;        prints "TSTDUMP OK" or "TSTDUMP FAIL" (TSTREPORT)
;    Registers: U restored; all others changed.
; Original comment: shadow TSTDUMP.0.
; ------------------------------------------------------------
TSTDUMP:    LDA   #'A'
            STA   TSTCBUF
            LDA   #'B'
            STA   TSTCBUF+1
            LDA   #'C'
            STA   TSTCBUF+2
            LDA   #'D'
            STA   TSTCBUF+3
            LDA   #'E'
            STA   TSTCBUF+4

            STU   TSTU0
            STU   TSTUB4

            LDD   #TSTCBUF
            PSHU  D
            LDD   #5
            PSHU  D
            JSR   DUMPW

            STU   TSTUAF

            IFNE  SERIALPOLL        ; >>>> polled build: last char only
            LDA   EMITCH
            CMPA  #10
            BNE   DUFAIL
            ENDC                    ; <<<<
            ; Interrupt build: no content check. See bugfix: TSTDUMP.2

            LDD   TSTUB4
            SUBD  TSTUAF
            CMPD  #0
            BNE   DUFAIL

            LDD   #TRUEV
            BRA   DUDONE2
DUFAIL:     LDD   #FALSEV
DUDONE2:    LDX   #TSTDUNAME
            PSHU  X
            PSHU  D
            JSR   TSTREPORT

            LDU   TSTU0
            RTS

TSTDUNAME:  FCB   7
            FCC   "TSTDUMP"

            ENDC                    ; <<<<

