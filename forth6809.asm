; ============================================================
; 6809 ANS FORTH - subroutine threaded
;
; Layout of this file: memory map and constants, GLOBALS (page zero),
; serial buffers, SECTION 27 (dictionary headers), SECTIONS 3-26 (code),
; SECTION 2 (init code), SECTION 1 (vectors).
;
; Build options (lwasm -D): SERIALPOLL (1 = polled ACIA, 0 = interrupt
; driven), UNITTESTS (1 = include unit_tests.asm), TSTSELECTOR.
;
; Long explanatory and bug-fix comments are kept in the shadow file
; forth6809.shd, and are referred to here by their NAME.n codes.
; The original header comment is shadow HEADER.0.
; ============================================================

; ------------------------------------------------------------
; MEMORY MAP
; ------------------------------------------------------------
ROMSTRT     EQU   $C000             ; physical start of the 16K EPROM
USROMSTRT   EQU   $C100             ; usable ROM start (above INOUT)
USROMEND    EQU   VECTORS-1         ; usable ROM end (VECTORS-1)
VECTORS     EQU   $FFF0
INITCODE    EQU   $FFA4             ; start of the init code (COLDSTRT)
            ; Commented-out code moved to shadow: MEMMAP.5
BASECODE    EQU   $DD54             ; base code. See shadow MEMMAP.6
            ; Commented-out code moved to shadow: MEMMAP.7
BASEDICT    EQU   $D543             ; base dictionary. See shadow MEMMAP.8
INOUT       EQU   $C000             ; I/O block (ACIA), 256 bytes
INOUTEND    EQU   INOUT+$FF
RSTACK      EQU   $BFFF             ; return stack top
DSTACK      EQU   $BCFF             ; data stack top
CODETOP     EQU   $B900             ; code space ceiling

; ANS transient-region sizes (ANS 3.3.3.6):
;   PADMINSIZE  - size of PAD's scratch region, in characters.
;   WORDMINSIZE - minimum size for WORD's region (33).
;   HOLDMINSIZE - pictured numeric output buffer, (2 * 16) + 2 = 34;
;                 it grows downward from PAD into the CODEHERE-to-PAD
;                 gap.
; PADOFFSET (the CODEHERE-to-PAD gap) equals PADMINSIZE. Original
; comment: shadow PADSIZE.0.
PADMINSIZE  EQU   128
WORDMINSIZE EQU   33
HOLDMINSIZE EQU   34
PADOFFSET   EQU   PADMINSIZE        ; CODEHERE-to-PAD gap
WORDMAXCHARS EQU   PADOFFSET-HOLDMINSIZE-1-3
            ; Maximum characters WORD can scan in the CODEHERE-to-PAD gap:
            ; PADOFFSET - HOLDMINSIZE - 1 (count byte) - 3 (bytes reserved by
            ; S", ." and ABORT"). Original comment: shadow WORDMAXCHARS.1.

APPCODE     EQU   $7000             ; application code area
APPDICT     EQU   $2000             ; application dictionary
APPVARS     EQU   $021B             ; application variables
APPVARSEND  EQU   APPDICT-1         ; end of application variables
; Unclaimed: $01DD-$01FA (formerly WORDBUF) and $01FB-$021A (formerly
; SIBUF). Original comment: shadow MEMMAP.17.

; Commented-out code moved to shadow: MEMMAP.18
TIBBUF      EQU   $0106             ; terminal input buffer
TIBBUFL     EQU   80                ; length of TIBBUF

GLOBALS     EQU   $0000

SP0         EQU   DSTACK+1
RP0         EQU   RSTACK+1

; ------------------------------------------------------------
; SERIALPOLL - conditional-assembly switch for serial I/O.
; 1 (default): KEY/KEYQ/EMIT poll ACIASR directly, no interrupts,
; no ring buffers, no RTS/CTS handshaking - IRQH is a harmless RTI
; stub, matching the other unused vectors (NMIH/FIRQH/SWI2H/
; SWI3H). 0: the original interrupt-driven implementation, with
; INBUF/OUTBUF ring buffers serviced by IRQH and RTS-based flow
; control via INFILL/RTSCHECKHI/RTSCHECKLO. Uses LWASM's IFEQ/
; ELSE/ENDC (a numeric-expression test, not IFDEF/IFNDEF, since
; this is a value to compare, not a symbol's mere presence).
;
; SERIALPOLL can be chosen at build time with lwasm -DSERIALPOLL=0 or
; -DSERIALPOLL=1 (the default). Original comment: shadow SERIALPOLL.1.
; ------------------------------------------------------------
            IFNDEF SERIALPOLL
SERIALPOLL  SET   1                 ; default if -D not passed
            ENDC

; ------------------------------------------------------------
; ACIA (6850) constants - the chip sits at INOUT+8, not at the
; base of the I/O block, leaving INOUT+0..INOUT+7 free for other
; memory-mapped devices sharing this 256-byte region
; ------------------------------------------------------------
ACIA        EQU   INOUT+8
ACIACR      EQU   ACIA
ACIASR      EQU   ACIA
ACIADR      EQU   ACIA+1

; ACIA Status Register Bits

SR_IRQ      EQU   %10000000         ; ($80) (Interrupt Request)
SR_RDRF     EQU   %00000001         ; ($01) (Receive Data Register Full)
SR_TDRE     EQU   %00000010         ; ($02) (Transmit Data Register Empty)
SR_CTS      EQU   %00001000         ; ($08) CTS blocks transmit

; Errors only meaningful together with RDRF
SR_FE       EQU   %00010000         ; ($10) (Framing Error)
SR_OVRN     EQU   %00100000         ; ($20) (Overrun Error)
SR_PE       EQU   %01000000         ; ($40) (Parity Error)

; ACIA Control Register Bits

CR_RESET    EQU   %00000011         ; ($03) (Master Reset mode)
CR_BASE     EQU   %10010101         ; ($95) (Rx Int Enabled, 8-N-1, /16 Clock)
CR_RXON     EQU   %10010101         ; ($95) (Rx Int Enabled, 8-N-1, /16 Clock)
CR_RXTX     EQU   %10110101         ; ($B5) Rx Int, Tx Int/RTS, 8-N-1
CR_POLL     EQU   %00010101         ; ($15) Polling, no ints, 8-N-1
CR_RTSHI    EQU   %11010101         ; ($D5) RTS high, Tx int off, 8-N-1

; CR_POLL

; bit7=0 (RX interrupt disabled), bits6-5=00 (RTS
; low, TX interrupt disabled) - CR_RXON ($95) with
; only the RX-interrupt-enable bit cleared. Used
; only when SERIALPOLL=1; RTS stays permanently
; low (asserted), since polling mode has no ring
; buffer to overflow and so needs no flow control

; CR_RTSHI

; bits6-5=10: RTS high, TX int disabled, RX int enabled -
; derived from CR_RXON ($95) with bits6-5 changed from
; 00 to 10; the ACIA has no combination offering RTS
; high AND TX interrupt enabled simultaneously (bits6-5
; only has 00/01/10/11, and only 01 enables TX interrupt,
; which always ties RTS low) - EMIT/IRQH's OUTCHAR must
; respect this and defer transmission while RTS is high

; Ring buffer control
SERBUFCTL   EQU   $0176
SERBUF      EQU   $0180             ; ring buffer start, 64-byte aligned
INBUFSZ     EQU   64
OUTBUFSZ    EQU   64
INHIWATER   EQU   48                ; input ring level: RTS high
INLOWATER   EQU   16                ; input ring level: RTS low

; Input control
; /RTS flag states
INACCEPT    EQU   $00
INREJECT    EQU   $FF

; Output control
; Transmit buffer interrupt active flag states.
OUTIDLE     EQU   $00
OUTBUSY     EQU   $FF

; Software (in-band) flow control - polling build only. The
; interrupt-driven build has real RTS/CTS hardware flow control
; already (CHKHI/CHKLO/UPDATE_RTS); polling mode has no ring
; buffer and no hardware handshaking at all, so it needs its own
; substitute - see ACCEPT and PUTXON/PUTXOFF.
XONCH       EQU   $11
XOFFCH      EQU   $13

; ------------------------------------------------------------
; Flag / opcode constants
; ------------------------------------------------------------
TRUEV       EQU   $FFFF
FALSEV      EQU   $0000
OPJSR       EQU   $BD
OPRTS       EQU   $39               ; used by section 3.8's control-flow test
                                    ; harness to terminate each compiled test
                                    ; snippet, compiled via CCOMMA
RTSOPC      EQU   $39

; ------------------------------------------------------------
; Control-flow compile-time tags
; ------------------------------------------------------------
TAGFWD      EQU   1
TAGBACK     EQU   2
TAGDO       EQU   3
TAGCASE     EQU   4
TAGOF       EQU   5
TAGENDOF    EQU   6
TAGQDO      EQU   7                 ; ?DO marker. See bugfix: TAGQDO.1

; ============================================================
; GLOBALS - scratch and state cells in page zero (DP = $00, set in
; COLDSTRT), laid out in RMB order. 255 of 256 bytes are used
; (GLOBALS_USED). Original comment: shadow GLOBALS.0.
; ============================================================
            ORG   $0000             ; GLOBALS page (DP = $00)
STATE       RMB   2                 ; offset $00
BASE        RMB   2                 ; offset $02
LATEST      RMB   2                 ; offset $04
DPHERE      RMB   2                 ; offset $06
CODEHERE    RMB   2                 ; offset $08
VARHERE     RMB   2                 ; offset $0A
HANDLER     RMB   2                 ; offset $0C
THROWN      RMB   2                 ; offset $0E
TOIN        RMB   2                 ; offset $10
NTIB        RMB   2                 ; offset $12
DELIM       RMB   1                 ; offset $14
WSTART      RMB   2                 ; offset $15
SLEN        RMB   1                 ; offset $17
SNAMEP      RMB   2                 ; offset $18
FNDPTR      RMB   2                 ; offset $1A
HDRPTR      RMB   2                 ; offset $1C
HDRFLAGS    RMB   1                 ; offset $1E
CADDR       RMB   2                 ; offset $1F
CNTREM      RMB   1                 ; offset $21
NUMNEG      RMB   1                 ; offset $22
NADDR       RMB   2                 ; offset $23
NCNT        RMB   2                 ; offset $25
MULBASE     RMB   1                 ; offset $27
CARRY       RMB   1                 ; offset $28
MSCR        RMB   2                 ; offset $29 (shared: -, *, WITHIN...)
MSCR2       RMB   2                 ; offset $2B
MSCR3       RMB   2                 ; offset $2D
MSCR4       RMB   2                 ; offset $2F
HLD         RMB   2                 ; offset $31
DEPTHTMP    RMB   2                 ; offset $33
AMAX        RMB   2                 ; offset $35
ABUFP       RMB   2                 ; offset $37
ACNT        RMB   2                 ; offset $39
ACH         RMB   1                 ; offset $3B
EMITCH      RMB   1                 ; offset $3C
NEWHDR      RMB   2                 ; offset $3D
; CURXT is an alias of NEWHDR (page zero is full): it holds the xt of
; the word being compiled, for RECURSE. Original comment: shadow CURXT.1.
CURXT       EQU   NEWHDR
NAMEP       RMB   2                 ; offset $3F
NAMELEN     RMB   1                 ; offset $41
PTARGET     RMB   2                 ; offset $42
PFIELD      RMB   2                 ; offset $44
NEWFLD      RMB   2                 ; offset $46
CSP         RMB   2                 ; offset $48
EXITCNT     RMB   2                 ; offset $4A
EXITPTR     RMB   2                 ; offset $4C
HDRSMUDGE   RMB   1                 ; offset $4E
SCNT        RMB   2                 ; offset $4F
SPTR        RMB   2                 ; offset $51
SAVEN       RMB   2                 ; offset $53
DRWIDTH     RMB   2                 ; offset $55
DRLEN       RMB   2                 ; offset $57
DRADDR      RMB   2                 ; offset $59
DRPAD       RMB   2                 ; offset $5B
PRODHI      RMB   2                 ; offset $5D
PRODLO      RMB   2                 ; offset $5F
PSIGN       RMB   1                 ; offset $61
DIVNUM      RMB   2                 ; offset $62
DIVDEN      RMB   2                 ; offset $64
DIVREM      RMB   2                 ; offset $66
DIVCNT      RMB   1                 ; offset $68
DNSIGN      RMB   1                 ; offset $69
DVSIGN      RMB   1                 ; offset $6A
DVOWNSIGN   RMB   1                 ; offset $6B
MAHI        RMB   1                 ; offset $6C
MALO        RMB   1                 ; offset $6D
MBHI        RMB   1                 ; offset $6E
MBLO        RMB   1                 ; offset $6F
MSIGN       RMB   1                 ; offset $70
REM         RMB   2                 ; offset $71
DCNT        RMB   1                 ; offset $73
UDHI        RMB   2                 ; offset $74
UDLO        RMB   2                 ; offset $76
PRSIGN      RMB   1                 ; offset $78
R2A         RMB   2                 ; offset $79
R2B         RMB   2                 ; offset $7B
RDST        RMB   2                 ; offset $7D
RVAL        RMB   2                 ; offset $7F
TR1         RMB   2                 ; offset $81
TR2         RMB   2                 ; offset $83
SHCNT       RMB   1                 ; offset $85
SHCNT2      RMB   2                 ; offset $86
TYPECNT     RMB   2                 ; offset $88
TYPEADDR    RMB   2                 ; offset $8A
PDELIM      RMB   1                 ; offset $8C
PSTART      RMB   2                 ; offset $8D
PLEN        RMB   2                 ; offset $8F
CMPA1       RMB   2                 ; offset $91
CMPL1       RMB   2                 ; offset $93
CMPA2       RMB   2                 ; offset $95
CMPL2       RMB   2                 ; offset $97
CMPMIN      RMB   2                 ; offset $99
SRCH1       RMB   2                 ; offset $9B
SRCH1L      RMB   2                 ; offset $9D
SRCH2       RMB   2                 ; offset $9F
SRCH2L      RMB   2                 ; offset $A1
SRCHPOS     RMB   2                 ; offset $A3
SRCHI       RMB   2                 ; offset $A5
UEADDR      RMB   2                 ; offset $A7
UESRCLEN    RMB   2                 ; offset $A9
UEDST       RMB   2                 ; offset $AB
UEOUTLEN    RMB   2                 ; offset $AD
SNXT        RMB   2                 ; offset $AF
SNTARGET    RMB   2                 ; offset $B1
REPLNAME    RMB   2                 ; offset $B3
REPLNLEN    RMB   2                 ; offset $B5
REPLVAL     RMB   2                 ; offset $B7
REPLVLEN    RMB   2                 ; offset $B9
SUBDESTCAP  RMB   2                 ; offset $BB
SUBDESTADR  RMB   2                 ; offset $BD
SUBSRCADR   RMB   2                 ; offset $BF
SUBSRCLEN   RMB   2                 ; offset $C1
SUBOUTLEN   RMB   2                 ; offset $C3
SUBWPTR     RMB   2                 ; offset $C5
SUBCOPYCNT  RMB   2                 ; offset $C7
SUBCOPYSRC  RMB   2                 ; offset $C9
MKDP        RMB   2                 ; offset $CB
MKCODE      RMB   2                 ; offset $CD
MKVAR       RMB   2                 ; offset $CF
MKLATEST    RMB   2                 ; offset $D1
EVSAVEA     RMB   2                 ; offset $D3
EVSAVEL     RMB   2                 ; offset $D5
EVSAVEI     RMB   2                 ; offset $D7
EVSAVET     RMB   2                 ; offset $D9
SRCADDR     RMB   2                 ; offset $DB
SRCLEN      RMB   2                 ; offset $DD
SRCID       RMB   2                 ; offset $DF
SPAN        RMB   2                 ; offset $E1
DSPTMP      RMB   2                 ; offset $E3
WWALK       RMB   2                 ; offset $E5
DUMPADDR    RMB   2                 ; offset $E7
DUMPCNT     RMB   2                 ; offset $E9
DUMPCOL     RMB   1                 ; offset $EB
HEXBUF      RMB   2                 ; offset $EC
DUVALID     RMB   1                 ; offset $EE
ENVLEN      RMB   2                 ; offset $EF
ENVADDR     RMB   2                 ; offset $F1
QSAVEDP     RMB   2                 ; offset $F3
QSAVECODE   RMB   2                 ; offset $F5
QSAVEVAR    RMB   2                 ; offset $F7
QSAVELATEST RMB   2                 ; offset $F9
QTHROWCODE  RMB   2                 ; offset $FB
DOESBEH     RMB   2                 ; offset $FD - SETDOES scratch

GLOBALS_USED EQU   255              ; bytes used, of 256 available

; ------------------------------------------------------------
; MVSCRATCH - three cells shared, one at a time, by routine
; families that never call each other or run concurrently in
; this single-threaded interpreter: MOVE/CMOVE/CMOVE>, FILL, and
; HOLDS (plus the single-cell multiply routine). Sharing avoids
; needing 3x the physical storage for what is provably the same
; scratch need at different times; the tradeoff is that these
; three cells use ordinary extended addressing (3-byte LDD/STD),
; not direct-page (2-byte), since page zero has no room left.
;
;   MVCNT    - MOVE/CMOVE's remaining-byte count
;     HSLEN    EQU MVCNT   - HOLDS's remaining-char count
;   MVDST    - MOVE/CMOVE's destination address
;     HSADDR   EQU MVDST   - HOLDS's source address
;   MVSRC    - MOVE/CMOVE's source address
;     MRESULT  EQU MVSRC   - single-cell multiply's 16-bit result
;     FILLCHR  EQU MVSRC   - FILL's fill character (1 byte, uses
;                            MVSRC's first byte only)
; ------------------------------------------------------------
            ORG   $0100
MVCNT       RMB   2
MVDST       RMB   2
MVSRC       RMB   2
HSLEN       EQU   MVCNT
HSADDR      EQU   MVDST
MRESULT     EQU   MVSRC
FILLCHR     EQU   MVSRC

; ------------------------------------------------------------
; Ring buffers for serial communications.
; One for input, one for output.
; The 64 byte alignment is supposed to allow some speed tricks.
; The tricks are not used.
; ------------------------------------------------------------
            ORG   SERBUFCTL         ; $176.

INHEAD      RMB   1
INTAIL      RMB   1
; Open question moved to shadow: RTSSTATE.1
RTSSTATE    RMB   1                 ; $00 = RTS low, $FF = RTS high

OUTHEAD     RMB   1
OUTTAIL     RMB   1
OUTACTIVITY RMB   1                 ; $00 = Idle, $FF = Busy (tx_active)

FECOUNT     RMB   1                 ; framing errors
OVRNCOUNT   RMB   1                 ; overrun count, same as above
PECOUNT     RMB   1                 ; parity-error count, same as above
POLLREADYCNT
            RMB   1                 ; polling build; see shadow POLLREADYCNT.1

            ORG   SERBUF            ; $180, a 64 byte boundary.

            ALIGN 64                ; Force 64-byte boundary alignment
INBUF       RMB   INBUFSZ           ; Receive circular queue buffer

            ALIGN 64                ; Force 64-byte boundary alignment
OUTBUF      RMB   OUTBUFSZ          ; Transmit circular queue buffer

; ------------------------------------------------------------
; Provide padding, to ensure the correct ROM & .bin file size (and
; opcode offsets) for the MAME emulation and flash memory burn.
; ------------------------------------------------------------
            ORG   USROMSTRT

            IFNDEF UNITTESTS
UNITTESTS   SET   0                 ; default if -D not passed
            ; Default 0: unit tests excluded; -DUNITTESTS=1 includes them.
            ; Original comment: shadow UNITTESTS.1.
            ENDC

            IFNDEF TSTSELECTOR
TSTSELECTOR SET   2                 ; default if -D not passed
            ENDC

            IFNE  UNITTESTS         ; >>>>>>>>>>

; ------------------------------------------------------------
; The unit test framework itself (explanatory comment plus all
; test code) lives in unit_tests.asm, a separate file included
; here only when UNITTESTS is nonzero - see unit_tests.asm for
; the full framework description, or OPEN_ITEMS_CHECKLIST_
; part1.md/part2.md for its own development history.
; ------------------------------------------------------------
            INCLUDE unit_tests.asm

            ENDC                    ; <<<<<<<<<<

ROM:
            FILL  $FF,BASEDICT-ROM

; ============================================================
; SECTION 27: FORTH DICTIONARY (ROM base dictionary headers)
;
; One header per word, chained by LINK, placed at BASEDICT. Each
; header is: length|flags, name, LINK, CFA. Every CFA is the word's
; own code label (raw code entries, no trampoline), including TRUE
; and FALSE. DOES> is next to CREATE; its code label is DOESGTW
; because ">" is not valid in a label. ABORT and QUIT are
; hand-built at the end of the section.
;
; Names containing a double-quote (S", ." and ABORT") have it split
; out of the FCC into a separate FCB $22.
; The original header comment is shadow SECTION27.0.
; ============================================================

            ORG   BASEDICT          ; BASEDICT is $D83F

H_KEY:
            FCB   $03
            FCC   "KEY"
            FDB   0
            FDB   KEYW
H_KEYQ:
            FCB   $04
            FCC   "KEY?"
            FDB   H_KEY
            FDB   KEYQW
H_EMIT:
            FCB   $04
            FCC   "EMIT"
            FDB   H_KEYQ
            FDB   EMITW
H_ACCEPT:
            FCB   $06
            FCC   "ACCEPT"
            FDB   H_EMIT
            FDB   ACCEPTW
H_EXPECT:
            FCB   $06
            FCC   "EXPECT"
            FDB   H_ACCEPT
            FDB   EXPECTW
H_QUERY:
            FCB   $05
            FCC   "QUERY"
            FDB   H_EXPECT
            FDB   QUERYW
H_TYPE:
            FCB   $04
            FCC   "TYPE"
            FDB   H_QUERY
            FDB   TYPEW
H_CR:
            FCB   $02
            FCC   "CR"
            FDB   H_TYPE
            FDB   CRW
H_SPACE:
            FCB   $05
            FCC   "SPACE"
            FDB   H_CR
            FDB   SPACEW
H_SPACES:
            FCB   $06
            FCC   "SPACES"
            FDB   H_SPACE
            FDB   SPACESW
H_DUP:
            FCB   $03
            FCC   "DUP"
            FDB   H_SPACES
            FDB   DUPW
H_DROP:
            FCB   $04
            FCC   "DROP"
            FDB   H_DUP
            FDB   DROPW
H_SWAP:
            FCB   $04
            FCC   "SWAP"
            FDB   H_DROP
            FDB   SWAPW
H_OVER:
            FCB   $04
            FCC   "OVER"
            FDB   H_SWAP
            FDB   OVERW
H_ROT:
            FCB   $03
            FCC   "ROT"
            FDB   H_OVER
            FDB   ROTW
H_QDUP:
            FCB   $04
            FCC   "?DUP"
            FDB   H_ROT
            FDB   QDUPW
H_DEPTH:
            FCB   $05
            FCC   "DEPTH"
            FDB   H_QDUP
            FDB   DEPTHW
H_DDUP:
            FCB   $04
            FCC   "2DUP"
            FDB   H_DEPTH
            FDB   DDUPW
H_DDROP:
            FCB   $05
            FCC   "2DROP"
            FDB   H_DDUP
            FDB   DDROPW
H_DSWAP:
            FCB   $05
            FCC   "2SWAP"
            FDB   H_DDROP
            FDB   DSWAPW
H_DOVER:
            FCB   $05
            FCC   "2OVER"
            FDB   H_DSWAP
            FDB   DOVERW
H_NIP:
            FCB   $03
            FCC   "NIP"
            FDB   H_DOVER
            FDB   NIPW
H_TUCK:
            FCB   $04
            FCC   "TUCK"
            FDB   H_NIP
            FDB   TUCKW
H_PICK:
            FCB   $04
            FCC   "PICK"
            FDB   H_TUCK
            FDB   PICKW
H_ROLL:
            FCB   $04
            FCC   "ROLL"
            FDB   H_PICK
            FDB   ROLLW
H_DROT:
            FCB   $04
            FCC   "2ROT"
            FDB   H_ROLL
            FDB   DROTW
H_TOR:
            FCB   $02
            FCC   ">R"
            FDB   H_DROT
            FDB   TORW
H_FROMR:
            FCB   $02
            FCC   "R>"
            FDB   H_TOR
            FDB   FROMRW
H_RFETCH:
            FCB   $02
            FCC   "R@"
            FDB   H_FROMR
            FDB   RFETCHW
H_TWOTOR:
            FCB   $03
            FCC   "2>R"
            FDB   H_RFETCH
            FDB   TWOTORW
H_TWOFROMR:
            FCB   $03
            FCC   "2R>"
            FDB   H_TWOTOR
            FDB   TWOFROMRW
H_TWORFETCH:
            FCB   $03
            FCC   "2R@"
            FDB   H_TWOFROMR
            FDB   TWORFETCHW
H_PLUS:
            FCB   $01
            FCC   "+"
            FDB   H_TWORFETCH
            FDB   PLUSW
H_MINUS:
            FCB   $01
            FCC   "-"
            FDB   H_PLUS
            FDB   MINUSW
H_STAR:
            FCB   $01
            FCC   "*"
            FDB   H_MINUS
            FDB   STARW
H_SLASH:
            FCB   $01
            FCC   "/"
            FDB   H_STAR
            FDB   SLASHW
H_MOD:
            FCB   $03
            FCC   "MOD"
            FDB   H_SLASH
            FDB   MODW
H_SLASHMOD:
            FCB   $04
            FCC   "/MOD"
            FDB   H_MOD
            FDB   SLASHMODW
H_NEGATE:
            FCB   $06
            FCC   "NEGATE"
            FDB   H_SLASHMOD
            FDB   NEGATEW
H_ABS:
            FCB   $03
            FCC   "ABS"
            FDB   H_NEGATE
            FDB   ABSW
H_MIN:
            FCB   $03
            FCC   "MIN"
            FDB   H_ABS
            FDB   MINW
H_MAX:
            FCB   $03
            FCC   "MAX"
            FDB   H_MIN
            FDB   MAXW
H_ONEPLUS:
            FCB   $02
            FCC   "1+"
            FDB   H_MAX
            FDB   ONEPLUSW
H_ONEMINUS:
            FCB   $02
            FCC   "1-"
            FDB   H_ONEPLUS
            FDB   ONEMINUSW
H_TWOPLUS:
            FCB   $02
            FCC   "2+"
            FDB   H_ONEMINUS
            FDB   TWOPLUSW
H_TWOSTAR:
            FCB   $02
            FCC   "2*"
            FDB   H_TWOPLUS
            FDB   TWOSTARW
H_TWOSLASH:
            FCB   $02
            FCC   "2/"
            FDB   H_TWOSTAR
            FDB   TWOSLASHW
H_STARSLASH:
            FCB   $02
            FCC   "*/"
            FDB   H_TWOSLASH
            FDB   STARSLASHW
H_STARSLASHMOD:
            FCB   $05
            FCC   "*/MOD"
            FDB   H_STARSLASH
            FDB   STARSLASHMODW
H_UMSTAR:
            FCB   $03
            FCC   "UM*"
            FDB   H_STARSLASHMOD
            FDB   UMSTARW
H_UMSLASHMOD:
            FCB   $06
            FCC   "UM/MOD"
            FDB   H_UMSTAR
            FDB   UMSLASHMODW
H_MSTAR:
            FCB   $02
            FCC   "M*"
            FDB   H_UMSLASHMOD
            FDB   MSTARW
H_FMSLASHMOD:
            FCB   $06
            FCC   "FM/MOD"
            FDB   H_MSTAR
            FDB   FMSLASHMODW
H_SMSLASHREM:
            FCB   $06
            FCC   "SM/REM"
            FDB   H_FMSLASHMOD
            FDB   SMSLASHREMW
H_DPLUS:
            FCB   $02
            FCC   "D+"
            FDB   H_SMSLASHREM
            FDB   DPLUSW
H_DMINUS:
            FCB   $02
            FCC   "D-"
            FDB   H_DPLUS
            FDB   DMINUSW
H_DNEGATE:
            FCB   $07
            FCC   "DNEGATE"
            FDB   H_DMINUS
            FDB   DNEGATEW
H_DABS:
            FCB   $04
            FCC   "DABS"
            FDB   H_DNEGATE
            FDB   DABSW
H_MPLUS:
            FCB   $02
            FCC   "M+"
            FDB   H_DABS
            FDB   MPLUSW
H_STOD:
            FCB   $03
            FCC   "S>D"
            FDB   H_MPLUS
            FDB   STODW
H_DTOS:
            FCB   $03
            FCC   "D>S"
            FDB   H_STOD
            FDB   DTOSW
H_DMAX:
            FCB   $04
            FCC   "DMAX"
            FDB   H_DTOS
            FDB   DMAXW
H_DMIN:
            FCB   $04
            FCC   "DMIN"
            FDB   H_DMAX
            FDB   DMINW
H_AND:
            FCB   $03
            FCC   "AND"
            FDB   H_DMIN
            FDB   ANDW
H_OR:
            FCB   $02
            FCC   "OR"
            FDB   H_AND
            FDB   ORW
H_XOR:
            FCB   $03
            FCC   "XOR"
            FDB   H_OR
            FDB   XORW
H_INVERT:
            FCB   $06
            FCC   "INVERT"
            FDB   H_XOR
            FDB   INVERTW
H_LSHIFT:
            FCB   $06
            FCC   "LSHIFT"
            FDB   H_INVERT
            FDB   LSHIFTW
H_RSHIFT:
            FCB   $06
            FCC   "RSHIFT"
            FDB   H_LSHIFT
            FDB   RSHIFTW
H_CELLS:
            FCB   $05
            FCC   "CELLS"
            FDB   H_RSHIFT
            FDB   CELLSW
H_CELLPLUS:
            FCB   $05
            FCC   "CELL+"
            FDB   H_CELLS
            FDB   CELLPLUSW
H_CHARS:
            FCB   $05
            FCC   "CHARS"
            FDB   H_CELLPLUS
            FDB   CHARSW
H_CHARPLUS:
            FCB   $05
            FCC   "CHAR+"
            FDB   H_CHARS
            FDB   CHARPLUSW
H_ALIGN:
            FCB   $05
            FCC   "ALIGN"
            FDB   H_CHARPLUS
            FDB   ALIGNW
H_ALIGNED:
            FCB   $07
            FCC   "ALIGNED"
            FDB   H_ALIGN
            FDB   ALIGNEDW
H_EQUAL:
            FCB   $01
            FCC   "="
            FDB   H_ALIGNED
            FDB   EQUALW
H_LESS:
            FCB   $01
            FCC   "<"
            FDB   H_EQUAL
            FDB   LESSW
H_GREATER:
            FCB   $01
            FCC   ">"
            FDB   H_LESS
            FDB   GREATERW
H_ZEROEQ:
            FCB   $02
            FCC   "0="
            FDB   H_GREATER
            FDB   ZEROEQW
H_ZEROLT:
            FCB   $02
            FCC   "0<"
            FDB   H_ZEROEQ
            FDB   ZEROLTW
H_ULESS:
            FCB   $02
            FCC   "U<"
            FDB   H_ZEROLT
            FDB   ULESSW
H_NOTEQUAL:
            FCB   $02
            FCC   "<>"
            FDB   H_ULESS
            FDB   NOTEQUALW
H_ZERONE:
            FCB   $03
            FCC   "0<>"
            FDB   H_NOTEQUAL
            FDB   ZERONEW
H_ZEROGT:
            FCB   $02
            FCC   "0>"
            FDB   H_ZERONE
            FDB   ZEROGTW
H_UGREATER:
            FCB   $02
            FCC   "U>"
            FDB   H_ZEROGT
            FDB   UGREATERW
H_WITHIN:
            FCB   $06
            FCC   "WITHIN"
            FDB   H_UGREATER
            FDB   WITHINW
H_DEQUAL:
            FCB   $02
            FCC   "D="
            FDB   H_WITHIN
            FDB   DEQUALW
H_DLESS:
            FCB   $02
            FCC   "D<"
            FDB   H_DEQUAL
            FDB   DLESSW
H_DULESS:
            FCB   $03
            FCC   "DU<"
            FDB   H_DLESS
            FDB   DULESSW
H_IF:
            FCB   $82
            FCC   "IF"
            FDB   H_DULESS
            FDB   IFW
H_THEN:
            FCB   $84
            FCC   "THEN"
            FDB   H_IF
            FDB   THENW
H_ELSE:
            FCB   $84
            FCC   "ELSE"
            FDB   H_THEN
            FDB   ELSEW
H_BEGIN:
            FCB   $85
            FCC   "BEGIN"
            FDB   H_ELSE
            FDB   BEGINW
H_UNTIL:
            FCB   $85
            FCC   "UNTIL"
            FDB   H_BEGIN
            FDB   UNTILW
H_AGAIN:
            FCB   $85
            FCC   "AGAIN"
            FDB   H_UNTIL
            FDB   AGAINW
H_WHILE:
            FCB   $85
            FCC   "WHILE"
            FDB   H_AGAIN
            FDB   WHILEW
H_REPEAT:
            FCB   $86
            FCC   "REPEAT"
            FDB   H_WHILE
            FDB   REPEATW
H_RECURSE:
            FCB   $87
            FCC   "RECURSE"
            FDB   H_REPEAT
            FDB   RECURSEW
H_DO:
            FCB   $82
            FCC   "DO"
            FDB   H_RECURSE
            FDB   DOW
H_QDO:
            FCB   $83
            FCC   "?DO"
            FDB   H_DO
            FDB   QDOW
H_LOOP:
            FCB   $84
            FCC   "LOOP"
            FDB   H_QDO
            FDB   LOOPW
H_PLUSLOOP:
            FCB   $85
            FCC   "+LOOP"
            FDB   H_LOOP
            FDB   PLUSLOOPW
H_IWORD:
            FCB   $01
            FCC   "I"
            FDB   H_PLUSLOOP
            FDB   IWORDW
H_JWORD:
            FCB   $01
            FCC   "J"
            FDB   H_IWORD
            FDB   JWORDW
H_LEAVE:
            FCB   $05
            FCC   "LEAVE"
            FDB   H_JWORD
            FDB   LEAVEW
H_UNLOOP:
            FCB   $06
            FCC   "UNLOOP"
            FDB   H_LEAVE
            FDB   UNLOOPW
H_EXIT:
            FCB   $84
            FCC   "EXIT"
            FDB   H_UNLOOP
            FDB   EXITW
H_CASE:
            FCB   $84
            FCC   "CASE"
            FDB   H_EXIT
            FDB   CASEW
H_OF:
            FCB   $82
            FCC   "OF"
            FDB   H_CASE
            FDB   OFW
H_ENDOF:
            FCB   $85
            FCC   "ENDOF"
            FDB   H_OF
            FDB   ENDOFW
H_ENDCASE:
            FCB   $87
            FCC   "ENDCASE"
            FDB   H_ENDOF
            FDB   ENDCASEW
H_COLON:
            FCB   $01
            FCC   ":"
            FDB   H_ENDCASE
            FDB   COLONW
H_SEMI:
            FCB   $81
            FCC   ";"
            FDB   H_COLON
            FDB   SEMIW
H_NONAME:
            FCB   $07               ; not IMMEDIATE (runs only in INTERPRET)
            FCC   ":NONAME"
            FDB   H_SEMI
            FDB   NONAMEW
H_CREATE:
            FCB   $06
            FCC   "CREATE"
            FDB   H_NONAME
            FDB   CREATEW
H_DOESGT:
            FCB   $85               ; $80 IMMEDIATE | 5 (length of "DOES>")
            FCC   "DOES>"
            FDB   H_CREATE
            FDB   DOESGTW
H_VARIABLE:
            FCB   $08
            FCC   "VARIABLE"
            FDB   H_DOESGT
            FDB   VARIABLEW
H_CONSTANT:
            FCB   $08
            FCC   "CONSTANT"
            FDB   H_VARIABLE
            FDB   CONSTANTW
H_VALUE:
            FCB   $05
            FCC   "VALUE"
            FDB   H_CONSTANT
            FDB   VALUEW
H_TO:
            FCB   $82
            FCC   "TO"
            FDB   H_VALUE
            FDB   TOW
H_TWOVARIABLE:
            FCB   $09
            FCC   "2VARIABLE"
            FDB   H_TO
            FDB   TWOVARIABLEW
H_TWOCONSTANT:
            FCB   $09
            FCC   "2CONSTANT"
            FDB   H_TWOVARIABLE
            FDB   TWOCONSTANTW
H_BUFFERCOLON:
            FCB   $07
            FCC   "BUFFER:"
            FDB   H_TWOCONSTANT
            FDB   BUFFERCOLONW
H_DEFER:
            FCB   $05
            FCC   "DEFER"
            FDB   H_BUFFERCOLON
            FDB   DEFERW
H_DEFERFETCH:
            FCB   $06
            FCC   "DEFER@"
            FDB   H_DEFER
            FDB   DEFERFETCHW
H_DEFERSTORE:
            FCB   $06
            FCC   "DEFER!"
            FDB   H_DEFERFETCH
            FDB   DEFERSTOREW
H_IS:
            FCB   $82
            FCC   "IS"
            FDB   H_DEFERSTORE
            FDB   ISW
H_ACTIONOF:
            FCB   $89
            FCC   "ACTION-OF"
            FDB   H_IS
            FDB   ACTIONOFW
H_MARKER:
            FCB   $06
            FCC   "MARKER"
            FDB   H_ACTIONOF
            FDB   MARKERW
H_IMMEDIATE:
            FCB   $09
            FCC   "IMMEDIATE"
            FDB   H_MARKER
            FDB   IMMEDIATEW
H_STATE:
            FCB   $05
            FCC   "STATE"
            FDB   H_IMMEDIATE
            FDB   STATEW
H_LBRACKET:
            FCB   $81
            FCC   "["
            FDB   H_STATE
            FDB   LBRACKETW
H_RBRACKET:
            FCB   $81
            FCC   "]"
            FDB   H_LBRACKET
            FDB   RBRACKETW
H_TICK:
            FCB   $01
            FCC   "'"
            FDB   H_RBRACKET
            FDB   TICKW
H_COMPILECOMMA:
            FCB   $08
            FCC   "COMPILE,"
            FDB   H_TICK
            FDB   COMPILECOMMAW
H_LITERAL:
            FCB   $87
            FCC   "LITERAL"
            FDB   H_COMPILECOMMA
            FDB   LITERALW
H_BRACKTICK:
            FCB   $83
            FCC   "[']"
            FDB   H_LITERAL
            FDB   BRACKTICKW
H_POSTPONE:
            FCB   $88
            FCC   "POSTPONE"
            FDB   H_BRACKTICK
            FDB   POSTPONEW
H_XCOMPILE:
            FCB   $89               ; $80 IMMEDIATE | 9 (length of "[COMPILE]")
            FCC   "[COMPILE]"
            FDB   H_POSTPONE
            FDB   XCOMPILEW
H_TOBODY:
            FCB   $05
            FCC   ">BODY"
            FDB   H_XCOMPILE
            FDB   TOBODYW
H_EXECUTE:
            FCB   $07
            FCC   "EXECUTE"
            FDB   H_TOBODY
            FDB   EXECUTEW
H_SLITERAL:
            FCB   $88
            FCC   "SLITERAL"
            FDB   H_EXECUTE
            FDB   SLITERALW
H_ABORTQUOTE:
            FCB   $86
            FCC   "ABORT"
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_SLITERAL
            FDB   ABORTQUOTEW
H_ATSIGN:
            FCB   $01
            FCC   "@"
            FDB   H_ABORTQUOTE
            FDB   ATSIGNW
H_STORE:
            FCB   $01
            FCC   "!"
            FDB   H_ATSIGN
            FDB   STOREW
H_CFETCH:
            FCB   $02
            FCC   "C@"
            FDB   H_STORE
            FDB   CFETCHW
H_CSTORE:
            FCB   $02
            FCC   "C!"
            FDB   H_CFETCH
            FDB   CSTOREW
H_PLUSSTORE:
            FCB   $02
            FCC   "+!"
            FDB   H_CSTORE
            FDB   PLUSSTOREW
H_DFETCH:
            FCB   $02
            FCC   "2@"
            FDB   H_PLUSSTORE
            FDB   DFETCHW
H_DSTORE:
            FCB   $02
            FCC   "2!"
            FDB   H_DFETCH
            FDB   DSTOREW
H_COMMA:
            FCB   $01
            FCC   ","
            FDB   H_DSTORE
            FDB   COMMAW
H_CCOMMA:
            FCB   $02
            FCC   "C,"
            FDB   H_COMMA
            FDB   CCOMMAW
H_ALLOT:
            FCB   $05
            FCC   "ALLOT"
            FDB   H_CCOMMA
            FDB   ALLOTW
H_HERE:
            FCB   $04
            FCC   "HERE"
            FDB   H_ALLOT
            FDB   HEREW
H_VCOMMA:
            FCB   $02
            FCC   "V,"
            FDB   H_HERE
            FDB   VCOMMAW
H_VCCOMMA:
            FCB   $03
            FCC   "VC,"
            FDB   H_VCOMMA
            FDB   VCCOMMAW
H_VALLOT:
            FCB   $06
            FCC   "VALLOT"
            FDB   H_VCCOMMA
            FDB   VALLOTW
H_VHERE:
            FCB   $05
            FCC   "VHERE"
            FDB   H_VALLOT
            FDB   VHEREW
H_PAD:
            FCB   $03
            FCC   "PAD"
            FDB   H_VHERE
            FDB   PADW
H_UNUSED:
            FCB   $06
            FCC   "UNUSED"
            FDB   H_PAD
            FDB   UNUSEDW
H_VUNUSED:
            FCB   $07
            FCC   "VUNUSED"
            FDB   H_UNUSED
            FDB   VUNUSEDW
H_MOVE:
            FCB   $04
            FCC   "MOVE"
            FDB   H_VUNUSED
            FDB   MOVEW
H_FILL:
            FCB   $04
            FCC   "FILL"
            FDB   H_MOVE
            FDB   FILLW
H_ERASE:
            FCB   $05
            FCC   "ERASE"
            FDB   H_FILL
            FDB   ERASEW
H_CMOVE:
            FCB   $05
            FCC   "CMOVE"
            FDB   H_ERASE
            FDB   CMOVEW
H_CMOVEGT:
            FCB   $06
            FCC   "CMOVE>"
            FDB   H_CMOVE
            FDB   CMOVEGTW
H_COUNT:
            FCB   $05
            FCC   "COUNT"
            FDB   H_CMOVEGT
            FDB   COUNTW
H_WORD:
            FCB   $04
            FCC   "WORD"
            FDB   H_COUNT
            FDB   WORDW
H_CHAR:
            FCB   $04
            FCC   "CHAR"
            FDB   H_WORD
            FDB   CHARW
H_BRACKCHAR:
            FCB   $86
            FCC   "[CHAR]"
            FDB   H_CHAR
            FDB   BRACKCHARW
H_PARSE:
            FCB   $05
            FCC   "PARSE"
            FDB   H_BRACKCHAR
            FDB   PARSEW
H_PARSENAME:
            FCB   $0A
            FCC   "PARSE-NAME"
            FDB   H_PARSE
            FDB   PARSENAMEW
H_SQUOTE:
            FCB   $82
            FCC   "S"
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_PARSENAME
            FDB   SQUOTEW
H_DOTQUOTE:
            FCB   $82
            FCC   "."
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_SQUOTE
            FDB   DOTQUOTEW
H_COMPARE:
            FCB   $07
            FCC   "COMPARE"
            FDB   H_DOTQUOTE
            FDB   COMPAREW
H_SEARCH:
            FCB   $06
            FCC   "SEARCH"
            FDB   H_COMPARE
            FDB   SEARCHW
H_DASHTRAILING:
            FCB   $09
            FCC   "-TRAILING"
            FDB   H_SEARCH
            FDB   DASHTRAILINGW
H_SLASHSTRING:
            FCB   $07
            FCC   "/STRING"
            FDB   H_DASHTRAILING
            FDB   SLASHSTRINGW
H_REPLACES:
            FCB   $08
            FCC   "REPLACES"
            FDB   H_SLASHSTRING
            FDB   REPLACESW
H_SUBSTITUTE:
            FCB   $0A
            FCC   "SUBSTITUTE"
            FDB   H_REPLACES
            FDB   SUBSTITUTEW
H_SNAME:
            FCB   $05
            FCC   "SNAME"
            FDB   H_SUBSTITUTE
            FDB   SNAMEW
H_UNESCAPE:
            FCB   $08
            FCC   "UNESCAPE"
            FDB   H_SNAME
            FDB   UNESCAPEW
H_LTNUM:
            FCB   $02
            FCC   "<#"
            FDB   H_UNESCAPE
            FDB   LTNUMW
H_NUMSIGN:
            FCB   $01
            FCC   "#"
            FDB   H_LTNUM
            FDB   NUMSIGNW
H_NUMSIGNS:
            FCB   $02
            FCC   "#S"
            FDB   H_NUMSIGN
            FDB   NUMSIGNSW
H_NUMGT:
            FCB   $02
            FCC   "#>"
            FDB   H_NUMSIGNS
            FDB   NUMGTW
H_HOLD:
            FCB   $04
            FCC   "HOLD"
            FDB   H_NUMGT
            FDB   HOLDW
H_HOLDS:
            FCB   $05
            FCC   "HOLDS"
            FDB   H_HOLD
            FDB   HOLDSW
H_SIGN:
            FCB   $04
            FCC   "SIGN"
            FDB   H_HOLDS
            FDB   SIGNW
H_TONUMBER:
            FCB   $07
            FCC   ">NUMBER"
            FDB   H_SIGN
            FDB   TONUMBERW
H_DOT:
            FCB   $01
            FCC   "."
            FDB   H_TONUMBER
            FDB   DOTW
H_UDOT:
            FCB   $02
            FCC   "U."
            FDB   H_DOT
            FDB   UDOTW
H_DOTR:
            FCB   $02
            FCC   ".R"
            FDB   H_UDOT
            FDB   DOTRW
H_UDOTR:
            FCB   $03
            FCC   "U.R"
            FDB   H_DOTR
            FDB   UDOTRW
H_QMARK:
            FCB   $01
            FCC   "?"
            FDB   H_UDOTR
            FDB   QMARKW
H_DDOT:
            FCB   $02
            FCC   "D."
            FDB   H_QMARK
            FDB   DDOTW
H_DDOTR:
            FCB   $03
            FCC   "D.R"
            FDB   H_DDOT
            FDB   DDOTRW
H_BASE:
            FCB   $04
            FCC   "BASE"
            FDB   H_DDOTR
            FDB   BASEW
H_DECIMAL:
            FCB   $07
            FCC   "DECIMAL"
            FDB   H_BASE
            FDB   DECIMALW
H_HEX:
            FCB   $03
            FCC   "HEX"
            FDB   H_DECIMAL
            FDB   HEXW
H_BINARY:
            FCB   $06
            FCC   "BINARY"
            FDB   H_HEX
            FDB   BINARYW
H_CATCH:
            FCB   $05
            FCC   "CATCH"
            FDB   H_BINARY
            FDB   CATCHW
H_THRO:
            FCB   $05
            FCC   "THROW"
            FDB   H_CATCH
            FDB   THROW
H_LPAREN:
            FCB   $81
            FCC   "("
            FDB   H_THRO
            FDB   LPARENW
H_BACKSLASH:
            FCB   $81
            FCC   "\"
            FDB   H_LPAREN
            FDB   BACKSLASHW
H_ENVQUERY:
            FCB   $0C
            FCC   "ENVIRONMENT?"
            FDB   H_BACKSLASH
            FDB   ENVQUERYW
H_SOURCE:
            FCB   $06
            FCC   "SOURCE"
            FDB   H_ENVQUERY
            FDB   SOURCEW
H_SOURCEID:
            FCB   $09
            FCC   "SOURCE-ID"
            FDB   H_SOURCE
            FDB   SOURCEIDW
H_REFILL:
            FCB   $06
            FCC   "REFILL"
            FDB   H_SOURCEID
            FDB   REFILLW
H_EVALUATE:
            FCB   $08
            FCC   "EVALUATE"
            FDB   H_REFILL
            FDB   EVALUATEW
H_TIB:
            FCB   $03
            FCC   "TIB"
            FDB   H_EVALUATE
            FDB   TIBW
H_NTIB:
            FCB   $04
            FCC   "#TIB"
            FDB   H_TIB
            FDB   NTIBW
H_TOIN:
            FCB   $03
            FCC   ">IN"
            FDB   H_NTIB
            FDB   TOINW
H_SPAN:
            FCB   $04
            FCC   "SPAN"
            FDB   H_TOIN
            FDB   SPANW
H_BL:
            FCB   $02
            FCC   "BL"
            FDB   H_SPAN
            FDB   BLW
H_DOTS:
            FCB   $02
            FCC   ".S"
            FDB   H_BL
            FDB   DOTSW
H_WORDS:
            FCB   $05
            FCC   "WORDS"
            FDB   H_DOTS
            FDB   WORDSW
H_DUMP:
            FCB   $04
            FCC   "DUMP"
            FDB   H_WORDS
            FDB   DUMPW

H_TRUE:
            FCB   $04
            FCC   "TRUE"
            FDB   H_DUMP
            FDB   TRUEW

H_FALSE:
            FCB   $05
            FCC   "FALSE"
            FDB   H_TRUE
            FDB   FALSEW

; H_ABORT and H_QUIT are hand-built (HEADER/CREATE could not be used
; for them). Chain, newest first: H_NEGTWO, H_POSTWO, H_NEGONE,
; H_POSONE, H_FIND, H_QUIT, H_ABORT, H_FALSE ... H_KEY, then 0.
; Original comment: shadow H_ABORT.0.
H_ABORT:    FCB   5
            FCC   "ABORT"
            FDB   H_FALSE           ; previous newest entry
            FDB   ABORTW            ; See bugfix: H_ABORT.2

H_QUIT:     FCB   4
            FCC   "QUIT"
            FDB   H_ABORT
            FDB   QUITW

; FIND: pushes xt and 1 (immediate) or -1 (normal) on success; on
; failure pushes the original c-addr and 0.
H_FIND:     FCB   4
            FCC   "FIND"
            FDB   H_QUIT
            FDB   FINDW

H_POSONE:   FCB   1
            FCC   "1"
            FDB   H_FIND
            FDB   POSONEW

H_NEGONE:   FCB   2
            FCC   "-1"
            FDB   H_POSONE
            FDB   NEGONEW

H_POSTWO:   FCB   1
            FCC   "2"
            FDB   H_NEGONE
            FDB   POSTWOW

H_NEGTWO:   FCB   2
            FCC   "-2"
            FDB   H_POSTWO
            FDB   NEGTWOW

BASELATEST  EQU   H_NEGTWO          ; head of the ROM dictionary (see COLD)

; Verify no collision with base code.
; Value should match ORG BASECODE
BASEDICTEND EQU   *
BASEDICTSIZE EQU   BASEDICTEND-BASEDICT

; ============================================================
; SECTION 3: ACIA INTERRUPT HANDLER
; ============================================================
            ORG   BASECODE          ; See bugfix: BASECODE.1

; ------------------------------------------------------------
; Reset the serial ring buffers, flow-control state and
; receiver-error counters to zero.
; SERBUFCLR
;    Inputs:
;        none
;    Outputs:
;        INHEAD, INTAIL, OUTHEAD, OUTTAIL, RTSSTATE, OUTACTIVITY,
;        FECOUNT, OVRNCOUNT, PECOUNT and POLLREADYCNT all cleared
;    Registers: only CC changed.
; Original comment: shadow SERBUFCLR.0.
; See bugfix: SERBUFCLR.1.
; ------------------------------------------------------------

SERBUFCLR:  CLR   INHEAD
            CLR   INTAIL
            CLR   RTSSTATE          ; $00 = RTS Low (Clear)
            CLR   OUTHEAD
            CLR   OUTTAIL
            CLR   OUTACTIVITY       ; $00 = Idle


            CLR   FECOUNT
            CLR   OVRNCOUNT
            CLR   PECOUNT
            CLR   POLLREADYCNT
            RTS

; ------------------------------------------------------------
; Initialise the ACIA (6850): master reset, then select
; interrupt-driven or polling operation per SERIALPOLL.
; INITSERIAL
;    Inputs:
;        none
;    Outputs:
;        ring buffers cleared (SERBUFCLR); ACIACR set to the run mode
;    Registers: RegA and CC changed.
; Original comment: shadow INITSERIAL.0.
; See bugfix: INITSERIAL.1.
; ------------------------------------------------------------
INITSERIAL: JSR   SERBUFCLR
            LDA   CR_RESET          ; Master Software Reset command to 6850
            STA   ACIACR
            NOP                     ; Settling Delay
            NOP

            IFEQ  SERIALPOLL        ; >>>>>>>>>>
            LDA   #CR_RXON          ; interrupt-driven mode: RX interrupt on
            ELSE                    ; <<<<<>>>>>
            LDA   #CR_POLL          ; polling mode: no interrupts, RTS held low
            ENDC                    ; <<<<<<<<<<
            STA   ACIACR            ; See bugfix: INITSERIAL.1
            RTS

            IFEQ  SERIALPOLL        ; >>>>>>>>>>
; ------------------------------------------------------------
; Return the input ring buffer fill level (0 to INBUFSZ-1).
; INBUFSZ is a power of two and both indices stay in range, so a
; masked subtraction gives the true distance across the wrap.
; INFILL
;    Inputs:
;        none
;    Outputs:
;        RegA = (INHEAD - INTAIL) mod INBUFSZ
;    Registers: RegA and CC changed.
; ------------------------------------------------------------
INFILL:     LDA   INHEAD
            SUBA  INTAIL
            ANDA  #INBUFSZ-1        ; Output: RegA = fill level
            RTS
; ------------------------------------------------------------
; Assert RTS high (ask the sender to pause) if the input ring has
; reached INHIWATER and RTS is not already high. Called from the
; receive path with interrupts already masked.
; RTSCHECKHI
;    Inputs:
;        none
;    Outputs:
;        RTSSTATE = 1 and ACIACR = CR_RTSHI if the threshold was reached
;    Registers: RegA and CC changed.
; ------------------------------------------------------------
RTSCHECKHI: JSR   INFILL
            CMPA  #INHIWATER
            BLO   RTSCHIDONE
            TST   RTSSTATE
            BNE   RTSCHIDONE        ; already high - nothing to do
            LDA   #CR_RTSHI
            STA   ACIACR
            LDA   #1
            STA   RTSSTATE
RTSCHIDONE: RTS
; ------------------------------------------------------------
; Write the ACIA control byte for the current RTSSTATE and
; OUTACTIVITY: RTS high disables the Tx interrupt; RTS low
; enables it only while output is pending.
; UPDATE_RTS
;    Inputs:
;        RTSSTATE, OUTACTIVITY
;    Outputs:
;        ACIACR written (OUTACTIVITY cleared when RTS is high)
;    Registers: RegA and CC changed.
; ------------------------------------------------------------
UPDATE_RTS:
            TST   RTSSTATE
            BNE   SET_RTS_HI_TX_OFF

            TST   OUTACTIVITY       ; Is active?
            BEQ   SET_RTS_LO_TX_OFF ; No! Disable Transmit interrupt.

                                    ; $B5/%1011_0101
            LDA   #CR_RXTX          ; Yes! Accept input & transmit output
            BRA   WRITE_CR          ; RTS = Low, Tx Interrupt = Enabled

SET_RTS_LO_TX_OFF:                  ; $95/%10010101
            LDA   #CR_RXON          ; RTS = Low, Tx Interrupt = Disabled
            BRA   WRITE_CR          ; Open question moved to shadow: UPDATE_RTS.1

SET_RTS_HI_TX_OFF:                  ; $D5/%1101_0101
            LDA   #CR_RTSHI         ; RTS = High, Tx Interrupt = Disabled
            CLR   OUTACTIVITY       ; Interrupts are hardware-disabled; clear state
WRITE_CR:
            STA   ACIACR
            RTS
; ------------------------------------------------------------
; If the input ring is near full and RTS is not already high,
; set RTSSTATE to INREJECT and update the ACIA to drop RTS.
; Called after a character is added to the ring.
; CHKHI
;    Inputs:
;        RegB = input ring fill level
;    Outputs:
;        RTSSTATE and ACIACR updated if the high-water mark was reached
;    Registers: RegA and CC changed.
; Original comment: shadow CHKHI.0.
; ------------------------------------------------------------
CHKHI:
            CMPB  #INHIWATER        ; RegB = fill level. Near full?
            BLO   CHKHIDONE         ; No! Do nothing.
            TST   RTSSTATE
            BNE   CHKHIDONE         ; already high - nothing to do
            LDA   #INREJECT         ; Yes! De-assert RTS.
            STA   RTSSTATE
            JSR   UPDATE_RTS
CHKHIDONE:  RTS

; ------------------------------------------------------------
; If the input ring is near empty and RTS is high, set
; RTSSTATE to INACCEPT and update the ACIA to raise RTS.
; Called after a character is removed from the ring.
; CHKLO
;    Inputs:
;        RegB = input ring fill level
;    Outputs:
;        RTSSTATE and ACIACR updated if the low-water mark was reached
;    Registers: RegA and CC changed.
; ------------------------------------------------------------
CHKLO:
            CMPB  #INLOWATER        ; RegB = fill level. Near empty?
            BHS   CHKLODONE         ; No! Do nothing.
            TST   RTSSTATE
            BEQ   CHKLODONE         ; already low - nothing to do
            LDA   #INACCEPT         ; Yes! Assert RTS.
            STA   RTSSTATE
            JSR   UPDATE_RTS
CHKLODONE:  RTS
; ------------------------------------------------------------
; Send at most one character from the output ring to the ACIA
; by polling, then return. Nothing is sent if the ring is empty,
; the remote receiver is blocking (CTS) or the transmitter is not
; ready; the caller simply tries again on its next call.
; FLUSHOUTBUFFER
;    Inputs:
;        none
;    Outputs:
;        one character sent and OUTTAIL advanced, or no change
;    Registers: RegA, RegB, RegX and CC changed.
; See bugfix: FLUSHOUTBUFFER.1.
; ------------------------------------------------------------
FLUSHOUTBUFFER:
            LDB   OUTTAIL
            CMPB  OUTHEAD           ; Is transmit buffer empty?
            BEQ   FLUSHED           ; Yes! Exit.

            LDA   ACIASR            ; Is transmission blocked by remote receiver?
            BITA  #SR_CTS
            BNE   FLUSHED           ; Yes! Exit.

            BITA  #SR_TDRE          ; Is transmit register empty?
            BEQ   FLUSHED           ; No! Exit - try again next call rather
                                    ; than spin-wait here.

            LDX   #OUTBUF           ; The out buffer is occupied.
            LDA   B,X               ; Get the character from the out buffer.
            STA   ACIADR            ; Transmit character.

            INCB                    ; Update tail pointer to next character slot.
            ANDB  #OUTBUFSZ-1
            STB   OUTTAIL
                                    ; One character sent - return rather than
                                    ; loop back for more (see header comment).
FLUSHED:
            RTS
; ------------------------------------------------------------
; Queue a character for transmission. The character is discarded
; if the output ring is full. Runs as a critical section.
; PUTCHAR
;    Inputs:
;        RegA = character to insert into transmit buffer
;    Outputs:
;        none
;    Registers: RegA and RegB changed; RegX and CC preserved.
; ------------------------------------------------------------
PUTCHAR:
            PSHS  CC,X
            ORCC  #$50              ; Enter Critical Section. Disable IRQ & FIRQ

            LDB   OUTHEAD           ; Is buffer full?
            INCB
            ANDB  #OUTBUFSZ-1
            CMPB  OUTTAIL
            BEQ   PUT_EXIT          ; Yes! Exit discarding character.

            LDX   #OUTBUF           ; Put character into character slot.
            LDB   OUTHEAD
            STA   B,X               ; Input: RegA = character

            INCB                    ; Update tail pointer to next character slot.
            ANDB  #OUTBUFSZ-1
            STB   OUTHEAD

            TST   RTSSTATE          ; Is RTS currently low (chars still being accepted)?
            BEQ   CHK_INT_PATH      ; Yes! Interrupt-driven TX is still available.

            ; RTS is high so the Tx interrupt is off: drain by polling,
            ; with IRQ and FIRQ unmasked meanwhile. See bugfix: PUTCHAR.1
            ANDCC #$AF              ; unmask IRQ+FIRQ for the flush only
            JSR   FLUSHOUTBUFFER    ; Fallback to transmit by polling.
            ORCC  #$50              ; re-mask - PUT_EXIT below still
                                    ; expects the critical section active

            BRA   PUT_EXIT

; Re-start the interrupt driven character pump,
; priming the pump by transmitting a character.
CHK_INT_PATH:
            TST   OUTACTIVITY       ; Is the interrupt handler transmitting?
            BNE   PUT_EXIT          ; Yes! Exit, no action required.

                                    ; No! Restart.
            LDX   #OUTBUF           ; Pull character from the out buffer.
            LDB   OUTTAIL
            LDA   B,X
            STA   ACIADR            ; Load the char for transmission.

            INCB                    ; Update the tail pointer
            ANDB  #OUTBUFSZ-1       ; to point to the next character.
            STB   OUTTAIL

            LDA   #OUTBUSY          ; Flag restart of transmit interrupt handler.
            STA   OUTACTIVITY
            JSR   UPDATE_RTS        ; Turn on the Tx interrupt.

PUT_EXIT:
            PULS  CC,X,PC           ; Leaving the critical section,
                                    ; by restoring the CC.
; ------------------------------------------------------------
; Fetch the next character from the input ring, if any, and let
; the flow-control check re-assert RTS when the ring has drained.
; GETCHAR
;    Inputs:
;        none
;    Outputs:
;        RegA = next character from the receive buffer
;        Carry clear = character returned, set = ring empty
;    Registers: RegA, RegB, RegX and CC changed.
; ------------------------------------------------------------
GETCHAR:
            LDB   INTAIL            ; Is the out buffer populated?
            CMPB  INHEAD
            BEQ   GET_NO_CHAR       ; No! Exit.

            LDX   #INBUF            ; Pull character from the out buffer.
            LDA   B,X               ; Output: RegA = character

            INCB                    ; Update the tail pointer
            ANDB  #INBUFSZ-1        ; to point to the next character.
            STB   INTAIL

            ; Mask IRQ so the flow-control check cannot race the
            ; receive interrupt. See bugfix: GETCHAR.1
            ORCC  #$10
            LDB   INHEAD            ; Calculate current fill level fresh -
            SUBB  INTAIL            ; both pointers may have moved since
            ANDB  #INBUFSZ-1        ; the ISR last ran, so (unlike INCHAR)
                                    ; there's no already-loaded value here
                                    ; worth reusing.
            JSR   CHKLO
            ANDCC #$EF

            ANDCC #$FE              ; Carry flag %0 = valid character
            RTS

GET_NO_CHAR:
            ORCC  #$01              ; Carry flag %1 = no valid character.
            RTS
; ------------------------------------------------------------
; Raise RTS (accept input again) once the input ring has drained
; to INLOWATER or below, re-enabling the Tx interrupt if output is
; pending. Called from mainline code, so IRQ is masked while it runs.
; RTSCHECKLO
;    Inputs:
;        none
;    Outputs:
;        RTSSTATE = 0 and ACIACR rewritten if RTS was high and the ring is low
;    Registers: RegA, RegB and CC changed.
; Original comment: shadow RTSCHECKLO.0.
; ------------------------------------------------------------
RTSCHECKLO:
            ORCC  #$10              ; mask IRQ for the critical section

            JSR   INFILL
            CMPA  #INLOWATER
            BHI   RTSCLODONE
            TST   RTSSTATE
            BEQ   RTSCLODONE        ; already low - nothing to do


            CLR   RTSSTATE          ; Set flag asserting acceptance of chars

            LDB   OUTTAIL           ; Check if chars are available.
            CMPB  OUTHEAD
            BEQ   RTSCLONOTX        ; No! Just configure the ACIA to accept chars.

            LDA   #CR_RXTX          ; Yes! Configure the ACIA to accept chars.
            STA   ACIACR            ; & to generate transmit slot available interrupts.
            BRA   RTSCLOUNMASK

RTSCLONOTX: LDA   #CR_RXON          ; Configure the ACIA to accept chars.
            STA   ACIACR

RTSCLOUNMASK:
            ANDCC #$EF

RTSCLODONE: RTS

; ------------------------------------------------------------
; ACIA (6850) interrupt handler (SERIALPOLL=0). Services received
; characters (into the input ring, counting framing, overrun and
; parity errors) and transmit-ready (from the output ring), with a
; single exit point. IRQ is hardware-masked while it runs.
; IRQH
;    Inputs:
;        none (hardware interrupt entry)
;    Outputs:
;        none (returns with RTI)
;    Registers: all registers are saved and restored by the interrupt.
; Original comment: shadow IRQH.0.
; ------------------------------------------------------------
IRQH:       LDA   ACIASR            ; Get the status.

            BITA  #SR_IRQ           ; Is the ACIA the interrupt source?
            BEQ   IRQDONE0          ; No! Just exit.
            BITA  #SR_RDRF          ; Is an incoming character available?
            BNE   INCHAR
            BITA  #SR_TDRE          ; Is the slot for an outgoing character available?
            BNE   OUTCHAR
                                    ; Ignore all other interrupts such as DCD change.
IRQDONE0:   RTI                     ; Single point of exit - re-enables interrupts
                                    ; & restores state.

INCHAR:
            LDB   ACIADR            ; Get the char & clear RDRF & error flags.
            BITA  #SR_FE+SR_OVRN+SR_PE
                                    ; Any receiver error flagged?
            BEQ   INOK              ; No! - character is good, keep it.

            BITA  #SR_FE            ; Yes! char is corrupted, discard it.
            BEQ   INXFE             ; Tally each flagged error independently -
            INC   FECOUNT           ; more than one bit can be set at once.
INXFE:      BITA  #SR_OVRN
            BEQ   INXOVRN
            INC   OVRNCOUNT
INXOVRN:    BITA  #SR_PE
            BEQ   INXPE
            INC   PECOUNT
INXPE:      RTI

INOK:       TFR   B,A               ; Transfer good character from the receiver.
            LDX   #INBUF            ; Store it in the empty in buffer slot.
            LDB   INHEAD
            STA   B,X
            INCB                    ; Figure out the new head,
            ANDB  #INBUFSZ-1        ; pointing to the next the empty in buffer slot.
            CMPB  INTAIL            ; Would the new head slot meet the tail?
            BEQ   IRQDONE1          ; Don't allow it - buffer full, drop the character.
            STB   INHEAD            ; New head pointer is OK so store it.
            ; Commented-out code moved to shadow: INCHAR.2
            ; Reuse RegB (the new head) for the fill level.
            ; See shadow: INCHAR.1
            SUBB  INTAIL            ; RegB: new head - tail = current fill level.
            ANDB  #INBUFSZ-1
            JSR   CHKHI             ; Protect the in buffer from overflow.
IRQDONE1:   RTI

            ; Commented-out code moved to shadow: OUTCHAR.1

OUTCHAR:    LDB   OUTTAIL           ; Is the out buffer empty?
            CMPB  OUTHEAD
            BEQ   TXOFF             ; Yes! Stop transmitting.

            LDX   #OUTBUF           ; No! The out buffer is occupied.
            LDA   B,X               ; Get the character from the out buffer.
            STA   ACIADR            ; Transmit the char.

            INCB                    ; Update the tail pointer pointing to the next char.
            ANDB  #OUTBUFSZ-1
            STB   OUTTAIL
IRQDONE2    RTI

TXOFF:                              ; The output ring is empty.
            ; Commented-out code moved to shadow: TXOFF.1
            CLR   OUTACTIVITY
            JSR   UPDATE_RTS
IRQDONE3    RTI

            ELSE                    ; <<<<<>>>>>

IRQH:       RTI                     ; polling mode (SERIALPOLL=1) - ACIA
                                    ; interrupts are never enabled (see
                                    ; COLDSTRT's CR_POLL init), so this should
                                    ; never fire; kept as a safe stub matching
                                    ; the other unused vectors below
            ENDC                    ; <<<<<<<<<<

; ------------------------------------------------------------
; Unused interrupt handlers: return immediately. SWIH instead
; pushes the throw code -99 and jumps to THROW.
; ------------------------------------------------------------
SWI3H:      RTI
SWI2H:      RTI
FIRQH:      RTI
NMIH:       RTI                     ; unused now that NMI -> WARM
SWIH:       LDD   #-99              ; placeholder hardware-trap code; push and
            PSHU  D                 ; JMP THROW, per the CATCH/THROW turn
            JMP   THROW

; ============================================================
; SECTION 4: COLD / ABORT / QUIT  (with CATCH-wrapped INTERPRET)
; ============================================================
; ------------------------------------------------------------
; Cold start: set the dictionary, code and variable pointers to
; their application areas, BASE to 10 and the input source to the
; terminal buffer, print the sign-on banner, then enter ABORT.
; COLD
;    Inputs:
;        none (entered at reset)
;    Outputs:
;        none (does not return)
;    Registers: all changed.
; ------------------------------------------------------------
COLD:       LDD   #APPVARS
            STD   VARHERE
            LDD   #APPCODE
            STD   CODEHERE
            LDD   #APPDICT
            STD   DPHERE
            LDD   #BASELATEST
            STD   LATEST

            LDD   #10
            STD   BASE

            LDD   #TIBBUF
            STD   SRCADDR
            LDD   #0
            STD   SRCLEN
            STD   SRCID

            LDX   #SIGNON
            PSHU  X                 ; c-addr
            LDD   #SIGNONL
            PSHU  D                 ; u
            JSR   TYPEW
            JSR   CRW
            BRA   ABORT             ; Go to ABORT, skipping the ABORTW word.

; ------------------------------------------------------------
; ABORT  ( i*x -- ) ( R: j*x -- )
; Throw -1. With no CATCH frame, THROW falls into the ABORT reset below.
; ------------------------------------------------------------
ABORTW:     LDD   #-1
            PSHU  D                 ; throw code (-1)
            JMP   THROW

; ------------------------------------------------------------
; Reset the data stack to its base, then fall through into QUITW.
; ABORT
;    Inputs:
;        none
;    Outputs:
;        none (does not return)
;    Registers: RegU changed.
; ------------------------------------------------------------
ABORT:      LDU   #SP0
            ; falls through into QUIT

; ------------------------------------------------------------
; QUIT  ( -- ) ( R: i*x -- )
; Empty the return stack, set interpretation state, then loop reading
; a line and interpreting it under CATCH. Errors are reported as
; "ERROR n"; -1 (ABORT) is silent. Never returns.
; ------------------------------------------------------------
QUITW:      LDS   #RP0
            LDD   #0
            STD   STATE             ; See bugfix: QUITW.1

QLOOP:      JSR   QUERYW

            LDD   DPHERE
            STD   QSAVEDP
            LDD   CODEHERE
            STD   QSAVECODE
            LDD   VARHERE
            STD   QSAVEVAR
            LDD   LATEST
            STD   QSAVELATEST

            LDD   #INTERPRET
            PSHU  D                 ; xt
            JSR   CATCHW
            PULU  D                 ; throw code (0 = no error)
            STD   QTHROWCODE
            CMPD  #0
            BEQ   QOK

            LDD   QSAVEDP
            STD   DPHERE
            LDD   QSAVECODE
            STD   CODEHERE
            LDD   QSAVEVAR
            STD   VARHERE
            LDD   QSAVELATEST
            STD   LATEST
            LDU   #SP0

            ; Return to interpretation state after a caught error.
            ; See bugfix: QLOOP.1
            LDD   #0
            STD   STATE

            LDD   QTHROWCODE        ; -1 is ABORT: reset silently, no "ERROR -1"
            CMPD  #-1
            LBEQ  QLOOP

            JSR   CRW
            LDX   #ERRMSG
            PSHU  X                 ; c-addr
            LDD   #ERRMSGL
            PSHU  D                 ; u
            JSR   TYPEW
            LDD   QTHROWCODE
            PSHU  D                 ; n
            JSR   DOTW
            BRA   QLOOP

QOK:        JSR   CRW               ; See bugfix: QOK.1
            LDD   STATE
            BNE   QLOOP
            LDX   #OKMSG
            PSHU  X                 ; c-addr
            LDD   #OKMSGL
            PSHU  D                 ; u
            JSR   TYPEW
            BRA   QLOOP

SIGNON:     FCC   "6809 FORTH v1.0"
SIGNONL     EQU   *-SIGNON
OKMSG:      FCC   "  ok"
OKMSGL      EQU   *-OKMSG
ERRMSG:     FCC   "  ERROR "
ERRMSGL     EQU   *-ERRMSG

; ============================================================
; SECTION 5: INNER-INTERPRETER SUPPORT (LIT, ZBRANCH, BRANCH,
; DODOES, DODEFER, EXECUTE)
; ============================================================
; ------------------------------------------------------------
; Run-time for a literal: fetch the inline cell that follows the
; calling JSR, push it, and advance the return address past it.
; LIT   ( -- x )
;    Inputs:
;        return stack top = address of the inline 16-bit literal
;    Outputs:
;        x pushed on the data stack; return address advanced by 2
;    Registers: RegD, RegX and CC changed.
; ------------------------------------------------------------
LIT:        PULS  X
            LDD   ,X++
            PSHU  D                 ; x
            PSHS  X
            RTS

; ------------------------------------------------------------
; Run-time for a conditional branch: take the inline offset if the
; flag is false, otherwise skip it. The offset is relative to its own
; address.
; ZBRANCH   ( flag -- )
;    Inputs:
;        flag on the data stack
;        return stack top = address of the inline 16-bit offset
;    Outputs:
;        flag removed; return address set to the branch target or past
;        the offset
;    Registers: RegD, RegX and CC changed.
; ------------------------------------------------------------
ZBRANCH:    PULU  D                 ; flag
            PULS  X
            CMPD  #0
            BNE   ZSKIP
            LDD   ,X
            LEAX  D,X
            PSHS  X
            RTS
ZSKIP:      LEAX  2,X
            PSHS  X
            RTS

; ------------------------------------------------------------
; Run-time for an unconditional branch: add the inline offset
; (relative to its own address) to the return address.
; BRANCH
;    Inputs:
;        return stack top = address of the inline 16-bit offset
;    Outputs:
;        return address set to the branch target
;    Registers: RegD, RegX and CC changed.
; ------------------------------------------------------------
BRANCH:     PULS  X
            LDD   ,X
            LEAX  D,X
            PSHS  X
            RTS

; ------------------------------------------------------------
; Run-time entry of a CREATEd or DOES>-defined word. Its code is a
; trampoline: JSR DODOES, a BEHAVIOR address, then the data-field
; address. Pushes the data-field address and jumps to BEHAVIOR.
; DODOES   ( -- pfa )
;    Inputs:
;        return stack top = address of the BEHAVIOR cell in the
;        trampoline
;    Outputs:
;        pfa pushed on the data stack; control passes to BEHAVIOR
;    Registers: RegD, RegX, RegY and CC changed.
; ------------------------------------------------------------
DODOES:     PULS  X
            LDY   ,X++
            LDD   ,X
            PSHU  D                 ; pfa
            JMP   ,Y

; ------------------------------------------------------------
; Default BEHAVIOR for a CREATEd word: do nothing, leaving the data-
; field address on the stack.
; DOESRT0
;    Inputs:
;        none
;    Outputs:
;        none
;    Registers: none.
; ------------------------------------------------------------
DOESRT0:    RTS

; ------------------------------------------------------------
; Run-time for DOES>: patch the BEHAVIOR cell of the most recent
; definition with the code that follows the calling JSR, then return
; two levels up, skipping the rest of the defining word.
; SETDOES
;    Inputs:
;        return stack top = address after "JSR SETDOES" (the new
;        BEHAVIOR)
;        next on the return stack = the defining word's own return
;        address
;    Outputs:
;        BEHAVIOR cell of LATEST patched; control returns to the
;        defining word's caller
;    Registers: RegD, RegX, CC, HDRFLAGS and DOESBEH changed.
; ------------------------------------------------------------
SETDOES:    PULS  X                 ; X = addr right after "JSR SETDOES" - new BEHAVIOR
            STX   DOESBEH

            LDX   LATEST
            LDA   ,X
            STA   HDRFLAGS
            LEAX  1,X
            LDB   HDRFLAGS
            ANDB  #$1F
            CLRA
            LEAX  D,X               ; skip name -> LINK field
            LEAX  2,X               ; skip LINK -> CFA field
            LDD   ,X                ; D = CFA (trampoline address)
            ADDD  #3                ; +3 -> BEHAVIOR field (past JSR DODOES)
            TFR   D,X

            LDD   DOESBEH
            STD   ,X                ; patch it

            PULS  X                 ; X = the OUTER defining word's own return addr
            JMP   ,X                ; jump there directly - "double RTS"

; ------------------------------------------------------------
; BEHAVIOR of a DEFERred word: execute the xt stored in its data
; field. Tail-calls the xt, so it returns to the original caller.
; DODEFER   ( pfa -- )
;    Inputs:
;        pfa on the data stack
;    Outputs:
;        pfa removed; the stored xt is executed
;    Registers: RegD, RegX and CC changed.
; ------------------------------------------------------------
DODEFER:    PULU  X                 ; pfa
            LDD   ,X
            TFR   D,X
            JMP   ,X

; ------------------------------------------------------------
; Initial xt of a DEFER: throws -21 until IS stores a real xt.
; DOABORTUNDEF
;    Inputs:
;        none
;    Outputs:
;        none (does not return)
;    Registers: RegD changed.
; ------------------------------------------------------------
DOABORTUNDEF:
            LDD   #-21
            PSHU  D                 ; throw code (-21)
            JMP   THROW

; ------------------------------------------------------------
; BEHAVIOR of a MARKER word: restore the dictionary, code and variable
; pointers and LATEST from the four cells saved when it was defined.
; DOMARKER   ( pfa -- )
;    Inputs:
;        pfa on the data stack (the four saved cells)
;    Outputs:
;        pfa removed; DPHERE, CODEHERE, VARHERE and LATEST restored
;    Registers: RegD, RegX and CC changed.
; ------------------------------------------------------------
DOMARKER:   PULU  X                 ; pfa
            LDD   ,X
            STD   DPHERE
            LDD   2,X
            STD   CODEHERE
            LDD   4,X
            STD   VARHERE
            LDD   6,X
            STD   LATEST
            RTS

; ------------------------------------------------------------
; EXECUTE  ( i*x xt -- j*x )
; Execute the word whose execution token is xt.
; ------------------------------------------------------------
EXECUTEW:   PULU  X                 ; xt
            JSR   ,X
            RTS

; ============================================================
; SECTION 6: COMMA FAMILY (factored via APPENDCELL/APPENDBYTE)
; ============================================================
; ------------------------------------------------------------
; Append a 16-bit cell to the area whose "here" pointer is at RegX
; (CODEHERE or VARHERE), and advance that pointer by 2.
; APPENDCELL   ( x -- )
;    Inputs:
;        RegX = address of the here pointer
;        x on the data stack
;    Outputs:
;        x stored at the old here value; pointer advanced by 2
;    Registers: RegD, RegY and CC changed.
; ------------------------------------------------------------
APPENDCELL: PULU  D                 ; x
            LDY   ,X
            STD   ,Y++
            STY   ,X
            RTS

; ------------------------------------------------------------
; Append the low byte of the top cell to the area whose "here" pointer
; is at RegX (CODEHERE or VARHERE), and advance that pointer by 1.
; APPENDBYTE   ( char -- )
;    Inputs:
;        RegX = address of the here pointer
;        char on the data stack
;    Outputs:
;        char stored at the old here value; pointer advanced by 1
;    Registers: RegD, RegY and CC changed.
; ------------------------------------------------------------
APPENDBYTE: PULU  D                 ; char
            LDY   ,X
            STB   ,Y+
            STY   ,X
            RTS

; ------------------------------------------------------------
; ,  ( x -- )
; Append x to the code/data area (CODEHERE).
; ------------------------------------------------------------
COMMAW:     LDX   #CODEHERE
            JMP   APPENDCELL

; ------------------------------------------------------------
; CODECOMMA  ( x -- )
; Internal name for ",": append x at CODEHERE.
; ------------------------------------------------------------
CODECOMMA:  LDX   #CODEHERE
            JMP   APPENDCELL

; ------------------------------------------------------------
; C,  ( char -- )
; Append char to the code/data area (CODEHERE).
; ------------------------------------------------------------
CCOMMAW:    LDX   #CODEHERE
            JMP   APPENDBYTE

; ------------------------------------------------------------
; CCOMMA1  ( char -- )
; Internal name for "C,": append char at CODEHERE.
; ------------------------------------------------------------
CCOMMA1:    LDX   #CODEHERE
            JMP   APPENDBYTE

; ------------------------------------------------------------
; V,  ( x -- )
; Append x to the variable area (VARHERE).
; ------------------------------------------------------------
VCOMMAW:    LDX   #VARHERE
            JMP   APPENDCELL

; ------------------------------------------------------------
; VC,  ( char -- )
; Append char to the variable area (VARHERE).
; ------------------------------------------------------------
VCCOMMAW:   LDX   #VARHERE
            JMP   APPENDBYTE

; ------------------------------------------------------------
; ALLOT  ( n -- )
; Reserve n bytes in the code/data area by advancing CODEHERE.
; ------------------------------------------------------------
ALLOTW:     PULU  D                 ; n
            LDX   CODEHERE
            LEAX  D,X
            STX   CODEHERE
            RTS

; ------------------------------------------------------------
; VALLOT  ( n -- )
; Reserve n bytes in the variable area by advancing VARHERE.
; ------------------------------------------------------------
VALLOTW:    PULU  D                 ; n
            LDX   VARHERE
            LEAX  D,X
            STX   VARHERE
            RTS

; ------------------------------------------------------------
; HERE  ( -- addr )
; Return the next free address in the code/data area (CODEHERE).
; ------------------------------------------------------------
HEREW:      LDD   CODEHERE
            PSHU  D                 ; addr
            RTS

; ------------------------------------------------------------
; VHERE  ( -- addr )
; Return the next free address in the variable area (VARHERE).
; ------------------------------------------------------------
VHEREW:     LDD   VARHERE
            PSHU  D                 ; addr
            RTS

; ------------------------------------------------------------
; PAD  ( -- c-addr )
; Return the scratch buffer address, PADOFFSET bytes above CODEHERE.
; ------------------------------------------------------------
PADW:       LDD   CODEHERE
            ADDD  #PADOFFSET
            PSHU  D                 ; c-addr
            RTS

; ------------------------------------------------------------
; UNUSED  ( -- u )
; Return the number of free bytes remaining in the code/data area.
; ------------------------------------------------------------
UNUSEDW:    LDD   #CODETOP
            SUBD  CODEHERE
            PSHU  D                 ; u
            RTS

; ------------------------------------------------------------
; VUNUSED  ( -- u )
; Return the number of free bytes remaining in the variable area.
; ------------------------------------------------------------
VUNUSEDW:   LDD   #APPVARSEND       ; See bugfix: VUNUSEDW.1
            SUBD  VARHERE
            PSHU  D                 ; u
            RTS

; ============================================================
; SECTION 7: HEADER (factored from :/CREATE/VARIABLE)
; ============================================================
; ------------------------------------------------------------
; Build a dictionary header for the next name in the input: parse the
; name, then lay down the length byte (with the smudge bit set if
; requested), the name, the link to the previous header and the code
; field address (CODEHERE). LATEST and DPHERE are updated.
; HEADER   ( smudge-flag "name" -- )
;    Inputs:
;        smudge-flag on the data stack (non-zero hides the new word)
;        name parsed from the input stream
;    Outputs:
;        header built at DPHERE; LATEST and NEWHDR = address of the
;        new header
;    Registers: RegA, RegB, RegX, RegY and CC changed.
; ------------------------------------------------------------
HEADER:     LDD   #32
            PSHU  D
            JSR   WORDW
            PULU  X                 ; c-addr of the name
            LDA   ,X
            STA   NAMELEN
            LEAX  1,X
            STX   NAMEP

            PULU  D                 ; smudge flag
            STB   HDRSMUDGE

            LDD   DPHERE
            STD   NEWHDR
            LDX   DPHERE
            LDA   NAMELEN
            TST   HDRSMUDGE
            BEQ   HDNOSM
            ORA   #$40
HDNOSM:     STA   ,X+
            LDY   NAMEP
            LDB   NAMELEN
            BEQ   HDNONM
HDCPY:      LDA   ,Y+
            STA   ,X+
            DECB
            BNE   HDCPY
HDNONM:     LDD   LATEST
            STD   ,X++
            LDD   CODEHERE
            STD   ,X++
            STX   DPHERE
            LDD   NEWHDR
            STD   LATEST
            RTS

; ============================================================
; SECTION 8: DEFINING WORDS
; ============================================================
; ------------------------------------------------------------
; :  ( "name" -- )
; Start a colon definition: parse the name, build a smudged header,
; record the new xt in CURXT, note the control-flow stack position in
; CSP and enter compile state.
; ------------------------------------------------------------
COLONW:     LDD   #TRUEV
            PSHU  D
            JSR   HEADER
            LDD   CODEHERE          ; Record this word's xt for RECURSE.
            STD   CURXT             ; See bugfix: COLONW.1
            TFR   U,D
            STD   CSP
            LDD   #-1
            STD   STATE
            RTS

; ------------------------------------------------------------
; ;  ( -- )  IMMEDIATE
; End a colon definition: compile RTS, check that the control-flow
; stack is balanced (error -22 if not), clear the smudge bit of the
; new word and return to interpret state.
; ------------------------------------------------------------
SEMIW:      LDD   #RTSOPC
            PSHU  D
            JSR   CCOMMA1
            TFR   U,D
            CMPD  CSP
            BEQ   SEMIOK
            JSR   CFERR
SEMIOK:     LDX   LATEST
            LDA   ,X
            ANDA  #$BF
            STA   ,X
            LDD   #0
            STD   STATE
            RTS

; ------------------------------------------------------------
; :NONAME  ( -- xt )
; Start an anonymous definition: no header is built and LATEST is left
; alone, so the word can never be found. Leaves the xt (the current
; CODEHERE) on the stack, records it in CURXT, notes the control-flow
; stack position in CSP and enters compile state.
; Original comment: shadow NONAMEW.0.
; ------------------------------------------------------------
NONAMEW:    LDD   CODEHERE
            PSHU  D                 ; xt
            STD   CURXT             ; See bugfix: NONAMEW.1
            TFR   U,D
            STD   CSP
            LDD   #-1
            STD   STATE
            RTS

; ------------------------------------------------------------
; CREATE  ( "name" -- )
; Build a header whose code is a DODOES trampoline. The default
; behaviour (DOESRT0) leaves the data-field address, the next free
; address in the code area, on the stack.
; ------------------------------------------------------------
CREATEW:    LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DOESRT0
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE          ; PFA = the cell after this one
            ADDD  #2                ; See bugfix: CONSTANTW.1
            PSHU  D
            JSR   CODECOMMA
            RTS

; ------------------------------------------------------------
; DOES>  ( -- )  IMMEDIATE, compile-only
; Compile a call to SETDOES, which at run time patches the behaviour
; of the word being defined.
; Original comment: shadow DOESGTW.0.
; ------------------------------------------------------------
DOESGTW:    LDD   #SETDOES
            PSHU  D
            JSR   CCALL
            RTS

; ------------------------------------------------------------
; VARIABLE  ( "name" -- )
; Build a word that returns the address of a new cell in the variable
; area, initialised to zero.
; ------------------------------------------------------------
VARIABLEW:  LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DOESRT0
            PSHU  D
            JSR   CODECOMMA
            LDD   VARHERE
            PSHU  D
            JSR   CODECOMMA
            LDD   #0
            LDX   VARHERE
            STD   ,X++
            STX   VARHERE
            RTS

; ------------------------------------------------------------
; @  ( a-addr -- x )
; Fetch the cell at a-addr. Also the behaviour of CONSTANT words.
; ------------------------------------------------------------
ATSIGNW:    PULU  X                 ; a-addr
            LDD   ,X
            PSHU  D                 ; x
            RTS

; ------------------------------------------------------------
; CONSTANT  ( x "name" -- )
; Build a word that returns x. The value is stored in the code area
; after the trampoline and fetched with @.
; ------------------------------------------------------------
CONSTANTW:  LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #ATSIGNW
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE          ; PFA = the cell after this one
            ADDD  #2                ; See bugfix: CONSTANTW.1
            PSHU  D
            JSR   CODECOMMA
            JSR   COMMAW
            RTS

; ------------------------------------------------------------
; Behaviour of a VALUE word: fetch the value cell.
; DOVALUE   ( pfa -- x )
;    Inputs:
;        pfa on the data stack (address of the value cell)
;    Outputs:
;        pfa replaced by the value
;    Registers: RegD, RegX and CC changed.
; ------------------------------------------------------------
DOVALUE:    PULU  X                 ; pfa
            LDD   ,X
            PSHU  D                 ; x
            RTS

; ------------------------------------------------------------
; VALUE  ( x "name" -- )
; Build a word that returns x, which can be changed with TO. The value
; cell is kept in the variable area so that it is writable.
; ------------------------------------------------------------
VALUEW:     LDD   #0
            PSHU  D
            JSR   HEADER            ; not smudged - immediately findable
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DOVALUE
            PSHU  D
            JSR   CODECOMMA
            LDD   VARHERE           ; PFA = VARHERE (writable space)
            PSHU  D                 ; See bugfix: VALUEW.1
            JSR   CODECOMMA
            JSR   VCOMMAW           ; store x in the variable area
            RTS

; ------------------------------------------------------------
; TO  ( x "name" -- )  IMMEDIATE
; Store x in the named VALUE. When compiling, instead compile code to
; store a run-time x in it. Error -13 if the name is not found.
; ------------------------------------------------------------
TOW:        LDD   #32
            PSHU  D
            JSR   WORDW
            JSR   FINDW
            PULU  D
            CMPD  #0
            BNE   TOFOUND
            PULU  D
            LDD   #-13
            PSHU  D
            JSR   THROW
TOFOUND:    JSR   TOBODYW
            LDD   STATE
            BEQ   TOIMMED
            JSR   LITERALW
            LDD   #STOREW
            PSHU  D
            JSR   CCALL
            RTS
TOIMMED:    PULU  X                 ; a-addr of the value cell
            PULU  D                 ; x
            STD   ,X
            RTS

; ------------------------------------------------------------
; 2VARIABLE  ( "name" -- )
; Build a word that returns the address of a new two-cell variable in
; the variable area, initialised to zero.
; ------------------------------------------------------------
TWOVARIABLEW:
            LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DOESRT0
            PSHU  D
            JSR   CODECOMMA
            LDD   VARHERE
            PSHU  D
            JSR   CODECOMMA
            LDD   #0
            LDX   VARHERE
            STD   ,X++
            STD   ,X++
            STX   VARHERE
            RTS

; ------------------------------------------------------------
; 2CONSTANT  ( x1 x2 "name" -- )
; Build a word that returns x1 x2. The pair is stored in the code area
; with x2 at the lower address, as 2@ and 2! expect.
; ------------------------------------------------------------
TWOCONSTANTW:
            LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DFETCHW
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE          ; PFA = the cell after this one
            ADDD  #2                ; See bugfix: CONSTANTW.1
            PSHU  D
            JSR   CODECOMMA
            PULU  D                 ; x2
            STD   MSCR
            LDD   MSCR
            PSHU  D
            JSR   COMMAW            ; x2 -> lower address
            JSR   COMMAW            ; x1 -> higher. See bugfix: TWOCONSTANTW.1
            RTS

; ------------------------------------------------------------
; BUFFER:  ( u "name" -- )
; Build a word that returns the address of a u-byte buffer reserved in
; the variable area.
; ------------------------------------------------------------
BUFFERCOLONW:
            PULU  D                 ; u
            STD   MSCR2
            LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DOESRT0
            PSHU  D
            JSR   CODECOMMA
            LDD   VARHERE
            PSHU  D
            JSR   CODECOMMA
            LDD   MSCR2
            PSHU  D
            JSR   VALLOTW
            RTS

; ------------------------------------------------------------
; DEFER  ( "name" -- )
; Build a deferred word. Until IS stores an xt in it, executing it
; throws -21.
; ------------------------------------------------------------
DEFERW:     LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DODEFER
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE          ; PFA = the cell after this one
            ADDD  #2                ; See bugfix: CONSTANTW.1
            PSHU  D
            JSR   CODECOMMA
            LDD   #DOABORTUNDEF
            PSHU  D
            JSR   COMMAW
            RTS

; ------------------------------------------------------------
; DEFER@  ( xt1 -- xt2 )
; Return the xt currently stored in the deferred word xt1.
; ------------------------------------------------------------
DEFERFETCHW:
            JSR   TOBODYW
            PULU  X                 ; body address
            LDD   ,X
            PSHU  D                 ; xt2
            RTS

; ------------------------------------------------------------
; DEFER!  ( xt2 xt1 -- )
; Store xt2 as the action of the deferred word xt1.
; ------------------------------------------------------------
DEFERSTOREW:
            JSR   TOBODYW
            PULU  X                 ; body address of xt1
            PULU  D                 ; xt2
            STD   ,X
            RTS

; ------------------------------------------------------------
; IS  ( xt "name" -- )  IMMEDIATE
; Store xt as the action of the named deferred word. When compiling,
; compile code to do so at run time. Error -13 if the name is not
; found.
; ------------------------------------------------------------
ISW:        LDD   #32
            PSHU  D
            JSR   WORDW
            JSR   FINDW
            PULU  D
            CMPD  #0
            BNE   ISFOUND
            PULU  D
            LDD   #-13
            PSHU  D
            JSR   THROW
ISFOUND:    PULU  X
            LDD   STATE
            BEQ   ISIMMED
            PSHU  X
            JSR   LITERALW
            LDD   #DEFERSTOREW
            PSHU  D
            JSR   CCALL
            RTS
ISIMMED:    PSHU  X
            JSR   DEFERSTOREW
            RTS

; ------------------------------------------------------------
; ACTION-OF  ( "name" -- xt )  IMMEDIATE
; Return the xt currently stored in the named deferred word. When
; compiling, compile code to do so at run time. Error -13 if the name
; is not found.
; ------------------------------------------------------------
ACTIONOFW:  LDD   #32
            PSHU  D
            JSR   WORDW
            JSR   FINDW
            PULU  D
            CMPD  #0
            BNE   AOFOUND
            PULU  D
            LDD   #-13
            PSHU  D
            JSR   THROW
AOFOUND:    PULU  X
            LDD   STATE
            BEQ   AOIMMED
            PSHU  X
            JSR   LITERALW
            LDD   #DEFERFETCHW
            PSHU  D
            JSR   CCALL
            RTS
AOIMMED:    PSHU  X
            JSR   DEFERFETCHW
            RTS

; ------------------------------------------------------------
; MARKER  ( "name" -- )
; Save DPHERE, CODEHERE, VARHERE and LATEST in a new word, which when
; executed restores them (forgetting everything defined since).
; ------------------------------------------------------------
MARKERW:    LDD   DPHERE
            STD   MKDP
            LDD   CODEHERE
            STD   MKCODE
            LDD   VARHERE
            STD   MKVAR
            LDD   LATEST
            STD   MKLATEST
            LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            LDD   #DOMARKER
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE          ; PFA = the cell after this one
            ADDD  #2                ; See bugfix: CONSTANTW.1
            PSHU  D
            JSR   CODECOMMA
            LDD   MKDP
            PSHU  D
            JSR   COMMAW
            LDD   MKCODE
            PSHU  D
            JSR   COMMAW
            LDD   MKVAR
            PSHU  D
            JSR   COMMAW
            LDD   MKLATEST
            PSHU  D
            JSR   COMMAW
            RTS

; ============================================================
; SECTION 9: OUTER INTERPRETER (INTERPRET / WORD / FIND / NUMBER?)
; ============================================================
; ------------------------------------------------------------
; INTERPRET  ( -- )
; Interpret the rest of the input source: parse each word and look it
; up. A found word is executed, or compiled when STATE is compile and
; it is not immediate. Anything else is converted as a single or
; double number (compiled as literals when compiling). An unknown word
; is typed and THROW -13 is raised.
; ------------------------------------------------------------
INTERPRET:
ILOOP:      LDD   #32               ; Delimiter: space. See bugfix: INTERPRET.1
            PSHU  D                 ; char
            JSR   WORDW
            LDX   ,U
            LDA   ,X
            BEQ   IDONE

            JSR   FINDW
            PULU  D
            TSTB
            LBEQ  TRYNUM

            LDA   STATE+1
            BEQ   DOEXEC
            TSTB
            BPL   DOEXEC
            JSR   CCALL
            BRA   ILOOP

DOEXEC:     JSR   EXECUTEW
            BRA   ILOOP

TRYNUM:     JSR   NUMBERQ
            PULU  D
            CMPD  #0                ; flag (PULU does not set CC)
            BEQ   BADWORD

            CMPD  #1                ; 1 = double-number result
            BEQ   TNDOUBLE          ; See shadow: INTERPRET.3

            LDD   STATE
            BEQ   ILOOP
            LDD   #LIT
            PSHU  D
            JSR   CCALL
            JSR   CODECOMMA
            BRA   ILOOP

TNDOUBLE:                           ; U currently holds [UDLO(bottom), UDHI(top)], matching
                                    ; ANS's (ud1) stack order directly.
            LDD   STATE
            BEQ   ILOOP             ; interpreting: already correctly placed,
                                    ; nothing more to do
            ; compiling: need two literals compiled in the order they
            ; must execute at runtime - low first (lands deep), high
            ; second (lands on top). UDHI is currently on top of U, so
            ; pop it aside first, freeing UDLO to be compiled first.
            PULU  D
            STD   MSCR4             ; stash UDHI - confirmed safe scratch,
                                    ; untouched by CCALL/CODECOMMA
            LDD   #LIT
            PSHU  D
            JSR   CCALL
            JSR   CODECOMMA         ; compiles UDLO (still on U underneath)
            LDD   #LIT
            PSHU  D
            JSR   CCALL
            LDD   MSCR4
            PSHU  D
            JSR   CODECOMMA         ; compiles UDHI
            BRA   ILOOP

BADWORD:    JSR   COUNTW
            JSR   TYPEW
            LDD   #-13
            PSHU  D
            JSR   THROW

IDONE:      PULU  X                 ; c-addr from WORD (empty). See bugfix: INTERPRET.4
            RTS

; ------------------------------------------------------------
; WORD  ( char "<chars>ccc<char>" -- c-addr )
; Skip leading delimiters, then parse text up to the next char from
; the input source. The text is stored as a counted string at
; CODEHERE, which is not advanced. An exhausted input gives a zero
; count.
; ------------------------------------------------------------
WORDW:      PULU  D                 ; char
            STB   DELIM
            LDD   TOIN
            LDX   SRCADDR
            LEAX  D,X
            LDD   SRCLEN
            SUBD  TOIN
            LBLO  EMPTY             ; See bugfix: WORDW.1
            TFR   D,Y

SKIPLP:     CMPY  #0
            BEQ   EMPTY
            LDA   ,X
            CMPA  DELIM
            BNE   STARTW
            LEAX  1,X
            LEAY  -1,Y
            BRA   SKIPLP

STARTW:     STX   WSTART
            LDB   #0

SCANLP:     CMPY  #0
            BEQ   ENDW
            LDA   ,X
            CMPA  DELIM
            BEQ   CONSUME
            CMPB  #WORDMAXCHARS     ; Length limit. See shadow: WORDW.2
            BEQ   ENDW
            LEAX  1,X
            LEAY  -1,Y
            INCB
            BRA   SCANLP

CONSUME:    LEAX  1,X
            LEAY  -1,Y
ENDW:       PSHS  B                 ; Save the count. See bugfix: WORDW.3
            TFR   X,D
            SUBD  SRCADDR
            STD   TOIN
            PULS  B

            LDX   CODEHERE          ; Result buffer; CODEHERE is not advanced.
                                    ; See shadow: WORDW.4
            STB   ,X+
            LDY   WSTART
COPYLP:     TSTB
            BEQ   COPYDONE
            LDA   ,Y+
            STA   ,X+
            DECB
            BRA   COPYLP
COPYDONE:   LDX   CODEHERE          ; Result address (see WORDW.4)
            PSHU  X                 ; c-addr
            RTS

EMPTY:      LDX   CODEHERE          ; Empty string at the result buffer
            CLR   ,X
            PSHU  X                 ; c-addr
            RTS

; ------------------------------------------------------------
; FIND  ( c-addr -- c-addr 0 | xt 1 | xt -1 )
; Look up the counted string in the dictionary, newest first, ignoring
; smudged entries. Returns the xt and 1 if the word is immediate, or
; -1 if not. If not found, returns c-addr and 0.
; ------------------------------------------------------------
FINDW:      PULU  X                 ; c-addr
            LDA   ,X
            STA   SLEN
            LEAX  1,X
            STX   SNAMEP

            LDD   LATEST
            STD   FNDPTR

FFLOOP:     LDD   FNDPTR
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
CMPLP:      LDA   ,X+
            CMPA  ,Y+
            BNE   FNEXT
            DECB
            BNE   CMPLP

FMATCH:     LDX   HDRPTR
            LEAX  1,X
            LDB   HDRFLAGS
            ANDB  #$1F
            CLRA
            LEAX  D,X
            LEAX  2,X
            LDD   ,X
            PSHU  D                 ; xt
            LDA   HDRFLAGS
            BITA  #$80
            BEQ   FISNORM
            LDD   #1
            BRA   FPUSH
FISNORM:    LDD   #-1
FPUSH:      PSHU  D                 ; 1 = immediate, -1 = normal
            RTS

FNEXT:      LDX   HDRPTR
            LEAX  1,X
            LDB   HDRFLAGS
            ANDB  #$1F
            CLRA
            LEAX  D,X
            LDD   ,X
            STD   FNDPTR
            BRA   FFLOOP

NOTFOUND:   LDX   SNAMEP
            LEAX  -1,X
            PSHU  X                 ; c-addr
            LDD   #0
            PSHU  D                 ; 0 = not found
            RTS

; ------------------------------------------------------------
; Multiply the unsigned double UDHI:UDLO by BASE and add a digit.
; UDMULADD
;    Inputs:
;        UDHI:UDLO = ud
;        RegB = digit value to add
;        BASE
;    Outputs:
;        UDHI:UDLO = ud * BASE + digit
;    Registers: RegA, RegB and CC changed; CARRY and MULBASE used as
;        scratch.
; ------------------------------------------------------------
UDMULADD:   STB   CARRY
            LDA   BASE+1
            STA   MULBASE
            LDA   UDLO+1
            LDB   MULBASE
            MUL
            ADDB  CARRY
            BCC   UM0
            INCA
UM0:        STB   UDLO+1
            STA   CARRY
            LDA   UDLO
            LDB   MULBASE
            MUL
            ADDB  CARRY
            BCC   UM1
            INCA
UM1:        STB   UDLO
            STA   CARRY
            LDA   UDHI+1
            LDB   MULBASE
            MUL
            ADDB  CARRY
            BCC   UM2
            INCA
UM2:        STB   UDHI+1
            STA   CARRY
            LDA   UDHI
            LDB   MULBASE
            MUL
            ADDB  CARRY
            BCC   UM3
            INCA
UM3:        STB   UDHI
            RTS

; ------------------------------------------------------------
; Convert digits at NADDR into UDHI:UDLO, in BASE, until NCNT
; characters are used or a non-digit is reached.
; NUMLOOP
;    Inputs:
;        NADDR = address of the first character
;        NCNT = number of characters
;        UDHI:UDLO = initial value
;    Outputs:
;        UDHI:UDLO = accumulated value
;        NADDR, NCNT = first unconverted character and the count
;        remaining
;    Registers: RegA, RegB, RegX and CC changed.
; ------------------------------------------------------------
NUMLOOP:    LDD   NCNT
            BEQ   NLDONE
            LDX   NADDR
            LDA   ,X
            CMPA  #'0'
            BLO   NLDONE
            CMPA  #'9'
            BHI   NLALPHA
            SUBA  #'0'
            BRA   NLGOT
NLALPHA:    ANDA  #$DF
            CMPA  #'A'
            BLO   NLDONE
            CMPA  #'Z'
            BHI   NLDONE
            SUBA  #'A'-10
NLGOT:      CMPA  BASE+1
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
NLDONE:     RTS

; ------------------------------------------------------------
; >NUMBER  ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
; Convert the string into ud1, in BASE, stopping at the first
; unconvertible character. Returns the accumulated ud2 and the
; remaining string.
; ------------------------------------------------------------
TONUMBERW:  PULU  D                 ; u1
            STD   NCNT
            PULU  D                 ; c-addr1
            STD   NADDR
            PULU  D                 ; ud1 high
            STD   UDHI
            PULU  D                 ; ud1 low
            STD   UDLO
            JSR   NUMLOOP
            LDD   UDLO
            PSHU  D                 ; ud2 low
            LDD   UDHI
            PSHU  D                 ; ud2 high
            LDX   NADDR
            PSHU  X                 ; c-addr2
            LDD   NCNT
            PSHU  D                 ; u2
            RTS

; ------------------------------------------------------------
; Convert a counted string to a number in BASE. A leading "-" negates
; it; a trailing "." makes it a double-cell number.
; NUMBERQ   ( c-addr -- n -1 | ud 1 | c-addr 0 )
;    Inputs:
;        c-addr of the counted string on the data stack
;    Outputs:
;        single number: n and -1
;        double number: ud (low cell below high cell) and 1
;        not a number: c-addr and 0
;    Registers: RegA, RegB, RegX and CC changed.
; ------------------------------------------------------------
NUMBERQ:    PULU  X                 ; c-addr
            STX   CADDR
            LDA   ,X
            BEQ   NQBAD
            STA   CNTREM
            LEAX  1,X

            ; A trailing "." means a double number: leave it out of the
            ; digit count. See shadow: NUMBERQ.1
            LDB   CNTREM
            DECB
            LDA   B,X
            CMPA  #'.'
            BNE   NQNOSIGN
            DEC   CNTREM
            BEQ   NQBAD             ; lone "." with nothing before it

NQNOSIGN:   CLR   NUMNEG
            LDA   ,X
            CMPA  #'-'
            BNE   NQNOSIGN2
            COM   NUMNEG
            LEAX  1,X
            DEC   CNTREM
            BEQ   NQBAD

NQNOSIGN2:  STX   NADDR
            CLRA
            LDB   CNTREM
            STD   NCNT
            LDD   #0
            STD   UDHI
            STD   UDLO

            JSR   NUMLOOP

            LDD   NCNT
            BNE   NQBAD

            ; Negate the full 32-bit value. See bugfix: NUMBERQ.2
            TST   NUMNEG
            BEQ   NQPOS32
            LDD   UDLO
            COMA
            COMB
            ADDD  #1
            STD   UDLO
            PSHS  CC                ; Save the carry. See bugfix: NUMBERQ.3
            LDD   UDHI
            COMA
            COMB
            PULS  CC                ; restore the TRUE carry
            BCC   NQSTOREHI         ; See bugfix: NUMBERQ.4
            ADDD  #1
NQSTOREHI:  STD   UDHI

NQPOS32:                            ; re-derive from CADDR whether the ORIGINAL last character
            ; was '.' - determines which return convention to use
            LDX   CADDR
            LDB   ,X
            DECB
            LEAX  1,X
            LDA   B,X
            CMPA  #'.'
            BNE   NQSINGLE

            ; DOUBLE success: push low, high, then a distinct success
            ; code (1, not -1) so TRYNUM can tell single and double
            ; apart without needing a separate flag of its own either
            LDD   UDLO
            PSHU  D
            LDD   UDHI
            PSHU  D
            LDD   #1
            PSHU  D
            RTS

NQSINGLE:                           ; SINGLE success - unchanged from the original convention
            LDD   UDLO
            PSHU  D
            LDD   #-1
            PSHU  D
            RTS

NQBAD:      LDX   CADDR
            PSHU  X
            LDD   #0
            PSHU  D
            RTS

; ============================================================
; SECTION 10: QUERY / ACCEPT / EXPECT / KEY / KEY? / EMIT
; ============================================================
            IFEQ  SERIALPOLL        ; >>>>>>>>>>
; Unused alternative to KEY removed; see shadow X_KEY.1.

; ------------------------------------------------------------
; KEY  ( -- char )
; Wait for the next received character and return it. While waiting,
; drain the output ring by polling if RTS is high.
; ------------------------------------------------------------
KEYW:

            TST   RTSSTATE          ; Is throttling?
            BEQ   TRY_READ          ; No! Retrieve character from input buffer.

            ; IRQ stays unmasked during the flush. See bugfix: KEYW.1
            JSR   FLUSHOUTBUFFER    ; Drain the output buffer,
                                    ; by transmitting all chars.

TRY_READ:
            JSR   GETCHAR           ; Is char available in input buffer.
            BCS   KEYW              ; No? Try again to receive a char,
                                    ; while still transmitting!

            TFR   A,B               ; Move char result to Reg B (LSB of D)
            CLRA                    ; Clear MSB.
            PSHU  D                 ; char

            RTS

; ------------------------------------------------------------
; KEY?  ( -- flag )
; Return true if a received character is waiting in the input ring.
; ------------------------------------------------------------
KEYQW:
            ; Commented-out code moved to shadow: KEYQW.1

            LDA   INHEAD            ; Characters received?
            CMPA  INTAIL

            ; Commented-out code moved to shadow: KEYQW.2

            BNE   KQTRUE            ; Yes!

            LDD   #FALSEV           ; No! Return false result.
            PSHU  D                 ; flag = false

            RTS

KQTRUE:
            LDD   #TRUEV            ; Yes! Return true result.
            PSHU  D                 ; flag = true
            RTS

; Unused alternative to EMIT removed; see shadow X_EMIT.1.

; ------------------------------------------------------------
; EMIT  ( char -- )
; Transmit char through PUTCHAR (the output ring). The character is
; discarded if the ring is full.
; ------------------------------------------------------------
EMITW:
            PULU  D                 ; char
            TFR   B,A
            JSR   PUTCHAR           ; Transmit char.
            RTS

            ELSE                    ; <<<<<>>>>>
; ------------------------------------------------------------
; KEY  ( -- char )  [polling build, SERIALPOLL=1]
; Wait for RDRF and return the received character. There are no ring
; buffers, interrupts or hardware handshaking in this build; ACCEPT
; uses software XON/XOFF instead. Framing, overrun and parity errors
; are counted in FECOUNT, OVRNCOUNT and PECOUNT, and POLLREADYCNT
; counts characters already waiting when KEY was called.
; Original comment: shadow KEYW.2. KEY?, EMIT, PUTXON and PUTXOFF
; follow.
; ------------------------------------------------------------
KEYW:
            LDA   ACIASR
            BITA  #SR_RDRF
            BEQ   KWAIT
            INC   POLLREADYCNT      ; character was already queued when we
            BRA   KGOTSTAT          ; came back to poll - didn't need to wait
KWAIT:
KSPIN:      LDA   ACIASR
            BITA  #SR_RDRF
            BEQ   KSPIN
KGOTSTAT:                           ; A holds the status byte exactly as it was
                                    ; when RDRF first went true - check the
                                    ; error bits from THIS copy, not a fresh
                                    ; read, since reading ACIADR below clears
                                    ; RDRF and the latched error bits together
            BITA  #SR_FE+SR_OVRN+SR_PE
            BEQ   KGETCH
            BITA  #SR_FE
            BEQ   KXFE
            INC   FECOUNT
KXFE:       BITA  #SR_OVRN
            BEQ   KXOVRN
            INC   OVRNCOUNT
KXOVRN:     BITA  #SR_PE
            BEQ   KGETCH
            INC   PECOUNT
KGETCH:     LDA   ACIADR
            TFR   A,B
            CLRA
            PSHU  D                 ; char
            RTS

; ------------------------------------------------------------
; Send the software flow-control character XOFF (PUTXOFF) or XON
; (PUTXON) straight to the ACIA, waiting for TDRE. The data stack is
; not touched, so ACCEPT can call these at any point.
; PUTXON / PUTXOFF
;    Inputs:
;        none
;    Outputs:
;        XON or XOFF transmitted
;    Registers: RegA, RegB and CC changed.
; Original comment: shadow PUTXON.0.
; ------------------------------------------------------------
PUTXOFF:    LDA   #XOFFCH
            BRA   PUTXCH
PUTXON:     LDA   #XONCH
PUTXCH:     PSHS  A
PXWT:       LDB   ACIASR
            BITB  #SR_TDRE
            BEQ   PXWT
            PULS  A
            STA   ACIADR
            RTS

; ------------------------------------------------------------
; KEY?  ( -- flag )  [polling build]
; Return true if the ACIA has a received character (RDRF set).
; ------------------------------------------------------------
KEYQW:      LDA   ACIASR
            BITA  #SR_RDRF
            BEQ   KQFALSE
            LDD   #TRUEV
            PSHU  D                 ; flag = true
            RTS
KQFALSE:    LDD   #FALSEV
            PSHU  D                 ; flag = false
            RTS

; ------------------------------------------------------------
; EMIT  ( char -- )  [polling build]
; Wait for TDRE, then transmit char directly.
; ------------------------------------------------------------
EMITW:      PULU  D                 ; char
            STB   EMITCH
EMITWT:     LDA   ACIASR
            BITA  #SR_TDRE
            BEQ   EMITWT
            LDA   EMITCH
            STA   ACIADR
            RTS

            ENDC                    ; <<<<<<<<<<

; ------------------------------------------------------------
; ACCEPT  ( c-addr +n1 -- +n2 )
; Read a line of up to +n1 characters into the buffer at c-addr,
; echoing as it goes. Backspace and DEL erase the last character; LF
; is ignored; CR ends the line. Returns the count +n2.
; ------------------------------------------------------------
ACCEPTW:    PULU  D                 ; +n1
            STD   AMAX
            PULU  D                 ; c-addr
            STD   ABUFP
            LDD   #0
            STD   ACNT

            IFEQ  SERIALPOLL        ; >>>>>>>>>>  interrupt-driven build: real
                                    ; RTS/CTS hardware flow control already
                                    ; covers this, nothing extra needed
            ELSE                    ; <<<<<>>>>>  polling build: tell the host it's safe to
                                    ; stream this line's characters
            JSR   PUTXON
            ENDC                    ; <<<<<<<<<<

ALOOP:      JSR   KEYW
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
            JSR   EMITW
            BRA   ALOOP

ABKSP:      LDD   ACNT
            BEQ   ALOOP
            SUBD  #1
            STD   ACNT
            LDD   #8
            PSHU  D
            JSR   EMITW
            LDD   #32
            PSHU  D
            JSR   EMITW
            LDD   #8
            PSHU  D
            JSR   EMITW
            BRA   ALOOP

ADONE:
            IFEQ  SERIALPOLL        ; >>>>>>>>>>  interrupt-driven build: nothing
                                    ; extra needed, see ACCEPT's entry above
            ELSE                    ; <<<<<>>>>>  polling build: the line is complete - tell
                                    ; the host to pause before INTERPRET runs
                                    ; with KEY never polled at all
            JSR   PUTXOFF
            ENDC                    ; <<<<<<<<<<
            LDD   ACNT
            PSHU  D                 ; +n2
            RTS

; ------------------------------------------------------------
; EXPECT  ( c-addr +n -- )
; Read a line as ACCEPT does and store the count in SPAN.
; ------------------------------------------------------------
EXPECTW:    JSR   ACCEPTW
            PULU  D
            STD   SPAN
            RTS

; ------------------------------------------------------------
; QUERY  ( -- )
; Read a line into the terminal input buffer and make it the input
; source: set NTIB and SRCLEN to its length, SRCADDR to TIBBUF, SRCID
; to 0 and >IN to 0.
; ------------------------------------------------------------
QUERYW:     LDX   #TIBBUF
            PSHU  X
            LDD   #TIBBUFL
            PSHU  D
            JSR   ACCEPTW
            PULU  D
            STD   NTIB
            STD   SRCLEN
            LDD   #TIBBUF
            STD   SRCADDR
            LDD   #0
            STD   SRCID
            STD   TOIN
            RTS

; ============================================================
; SECTION 11: EXCEPTIONS (CFERR, CATCH, THROW)
; ============================================================
; ------------------------------------------------------------
; Report a control-structure mismatch: throw -22. Called by the
; control-flow words when the tag on the control-flow stack is not the
; one expected.
; CFERR
;    Inputs:
;        none
;    Outputs:
;        does not return (THROW -22)
;    Registers: RegD changed; THROW decides the rest.
; ------------------------------------------------------------
CFERR:      LDD   #-22
            PSHU  D                 ; -22
            JSR   THROW
            RTS

; ------------------------------------------------------------
; CATCH  ( i*x xt -- j*x 0 | i*x n )
; Execute xt with an exception frame in place. On normal return push
; 0. If xt (or anything it calls) executes THROW with a non-zero n,
; THROW unwinds to this frame and CATCH returns n.
; Frame on S, top first: >IN, SRCID, SRCLEN, SRCADDR, saved U,
; previous HANDLER. HANDLER points at the >IN cell.
; ------------------------------------------------------------
CATCHW:     PULU  X                 ; xt
            LDD   HANDLER
            PSHS  D
            PSHS  U
            ; Save the input source specification.
            ; See bugfix: CATCHW.1
            LDD   SRCADDR
            PSHS  D
            LDD   SRCLEN
            PSHS  D
            LDD   SRCID
            PSHS  D
            LDD   TOIN
            PSHS  D
            TFR   S,D
            STD   HANDLER

            JSR   ,X

            LEAS  8,S               ; drop saved input source
            LEAS  2,S               ; saved U
            PULS  D
            STD   HANDLER
            LDD   #0
            PSHU  D                 ; 0 = no exception
            RTS

; ------------------------------------------------------------
; THROW  ( k*x n -- k*x | i*x n )
; If n is zero, do nothing. Otherwise restore the state saved by the
; most recent CATCH (S, U, input source, >IN, HANDLER) and make that
; CATCH return n. With no CATCH active, push n and ABORT.
; ------------------------------------------------------------
THROW:      PULU  D                 ; n
            CMPD  #0
            BEQ   THDONE

            STD   THROWN
            LDX   HANDLER
            BEQ   THUNCAU

            TFR   X,S
            PULS  D                 ; restore input source saved by CATCH
            STD   TOIN
            PULS  D
            STD   SRCID
            PULS  D
            STD   SRCLEN
            PULS  D
            STD   SRCADDR
            PULS  D
            TFR   D,U
            PULS  D
            STD   HANDLER

            LDD   THROWN
            PSHU  D
            RTS
THDONE:     RTS

            ; No CATCH is active: leave n on the stack and ABORT.
THUNCAU:    LDD   THROWN
            PSHU  D
            JMP   ABORT

; ============================================================
; SECTION 12: CONTROL FLOW (IF/THEN/ELSE, BEGIN family,
; DO/LOOP/+LOOP/I/J/LEAVE/UNLOOP/?DO, EXIT, CASE family)
; ============================================================
; ------------------------------------------------------------
; Store a branch displacement: the cell at location receives target -
; location.
; PATCH   ( target location -- )
;    Inputs:
;        target and location on the data stack (location on top)
;    Outputs:
;        the cell at location holds target - location
;    Registers: RegD and RegX changed; PFIELD and PTARGET used as
;        scratch.
; ------------------------------------------------------------
PATCH:      PULU  D
            STD   PFIELD            ; location
            PULU  D
            STD   PTARGET           ; target
            LDD   PTARGET
            SUBD  PFIELD
            LDX   PFIELD
            STD   ,X
            RTS

; ------------------------------------------------------------
; IF  ( C: -- orig )
; Compile ZBRANCH with a placeholder operand. Leave the operand
; address and TAGFWD on the control-flow stack for ELSE or THEN.
; ------------------------------------------------------------
IFW:        LDD   #ZBRANCH
            PSHU  D
            JSR   CCALL
            LDD   #0
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE
            SUBD  #2
            PSHU  D                 ; orig
            LDD   #TAGFWD
            PSHU  D
            RTS

; ------------------------------------------------------------
; THEN  ( C: orig -- )
; Resolve the forward branch left by IF, ELSE or WHILE: patch its
; operand to jump to the current code address.
; ------------------------------------------------------------
THENW:      PULU  D
            CMPD  #TAGFWD
            BEQ   THOK
            JSR   CFERR
THOK:       PULU  X                 ; orig
            LDD   CODEHERE
            PSHU  D
            PSHU  X
            JSR   PATCH
            RTS

; ------------------------------------------------------------
; ELSE  ( C: orig1 -- orig2 )
; Compile BRANCH with a placeholder operand, resolve orig1 to the
; address just after it, and leave the new operand address and TAGFWD.
; ------------------------------------------------------------
ELSEW:      PULU  D
            CMPD  #TAGFWD
            BEQ   ELOK
            JSR   CFERR
ELOK:       PULU  D                 ; orig1
            STD   MSCR              ; See bugfix: ELSEW.1
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
            PSHU  D                 ; orig2
            LDD   #TAGFWD
            PSHU  D
            RTS

; ------------------------------------------------------------
; BEGIN  ( C: -- dest )
; Leave the current code address and TAGBACK on the control-flow
; stack.
; ------------------------------------------------------------
BEGINW:     LDD   CODEHERE
            PSHU  D                 ; dest
            LDD   #TAGBACK
            PSHU  D
            RTS

; ------------------------------------------------------------
; UNTIL  ( C: dest -- )
; Compile ZBRANCH with a displacement back to dest.
; ------------------------------------------------------------
UNTILW:     PULU  D
            CMPD  #TAGBACK
            BEQ   UNOK
            JSR   CFERR
UNOK:       PULU  D                 ; dest
            PSHU  D                 ; park dest. See bugfix: UNTILW.1
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

; ------------------------------------------------------------
; AGAIN  ( C: dest -- )
; Compile BRANCH with a displacement back to dest.
; ------------------------------------------------------------
AGAINW:     PULU  D
            CMPD  #TAGBACK
            BEQ   AGOK
            JSR   CFERR
AGOK:       PULU  D                 ; dest
            PSHU  D                 ; park dest. See bugfix: AGAINW.1
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

; ------------------------------------------------------------
; WHILE  ( C: dest -- orig dest )
; Compile ZBRANCH with a placeholder operand. Leave orig (its operand
; address) and TAGFWD on top of the BEGIN frame.
; ------------------------------------------------------------
WHILEW:     LDD   #ZBRANCH
            PSHU  D
            JSR   CCALL
            LDD   #0
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE
            SUBD  #2
            PSHU  D                 ; orig
            LDD   #TAGFWD
            PSHU  D
            RTS

; ------------------------------------------------------------
; REPEAT  ( C: orig dest -- )
; Compile BRANCH back to the BEGIN address and resolve the WHILE
; branch to just after it. A BEGIN frame beneath further open WHILE
; frames is found by scanning, and removed from beneath them.
; ------------------------------------------------------------
REPEATW:    PULU  D
            CMPD  #TAGFWD
            BEQ   RPOK1
            JSR   CFERR
RPOK1:      PULU  X                 ; orig
            STX   NEWFLD            ; save orig

            ; Find the BEGIN frame, scanning past any open TAGFWD frames.
            ; See bugfix: REPEATW.1
            LEAX  0,U               ; scan from top of control stack
            STX   MSCR2             ; MSCR2 = base of scan region
            STX   MSCR4             ; MSCR4 = scan pointer
RPSCAN:     LDD   MSCR4
            CMPD  CSP
            BNE   RPSCANOK
            JSR   CFERR             ; no matching BEGIN
RPSCANOK:   LDX   MSCR4
            LDD   ,X
            CMPD  #TAGBACK
            BEQ   RPFOUND
            CMPD  #TAGFWD
            BEQ   RPSKIP
            JSR   CFERR             ; anything else is a genuine mismatch
RPSKIP:     LDD   MSCR4
            ADDD  #4
            STD   MSCR4
            BRA   RPSCAN
RPFOUND:    LDX   MSCR4             ; X = found BEGIN frame
            LDD   2,X               ; dest = BEGIN's address
            STD   PFIELD            ; kept in PFIELD

            ; Close the gap: move the frames above the BEGIN frame down 4
            ; bytes, highest word first.
            LDD   MSCR4
            SUBD  MSCR2
            STD   MSCR3             ; MSCR3 = bytes to shift
            BEQ   RPSHIFTDONE
RPSHIFT:    LDD   MSCR3
            SUBD  #2
            STD   MSCR3
            LDX   MSCR2
            LEAX  D,X               ; X = MSCR2 + this pass's offset
            LDD   ,X
            LEAX  4,X
            STD   ,X                ; copy one word 4 bytes higher
            LDD   MSCR3
            BNE   RPSHIFT
RPSHIFTDONE:
            LDX   MSCR2
            LEAX  4,X
            TFR   X,U               ; U now excludes BEGIN frame

            LDD   #BRANCH
            PSHU  D
            JSR   CCALL
            LDD   #0
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE
            SUBD  #2
            STD   MSCR3             ; MSCR3 = branch operand address
            LDD   PFIELD            ; target = BEGIN's address
            PSHU  D
            LDD   MSCR3             ; location = the operand just compiled
            PSHU  D
            JSR   PATCH
            LDD   CODEHERE
            PSHU  D
            LDD   NEWFLD
            PSHU  D
            JSR   PATCH
            RTS

; ------------------------------------------------------------
; RECURSE  ( -- )
; Compile a call to the word being defined (named or :NONAME), using
; the xt held in CURXT.
; ------------------------------------------------------------
RECURSEW:   LDD   CURXT             ; xt of word being compiled
            PSHU  D                 ; See bugfix: RECURSEW.1
            JSR   CCALL
            RTS

; ------------------------------------------------------------
; DO  ( C: -- dest )
; Compile a call to DOSETUP and leave the loop start address and TAGDO
; on the control-flow stack for LOOP or +LOOP.
; ------------------------------------------------------------
DOW:        LDD   #DOSETUP
            PSHU  D
            JSR   CCALL
            LDD   CODEHERE
            PSHU  D                 ; dest
            LDD   #TAGDO
            PSHU  D
            RTS

; ------------------------------------------------------------
; Run-time start of DO and ?DO: build the loop frame on S, beneath the
; return address.
; DOSETUP   ( limit index -- )
;    Inputs:
;        limit and index on the data stack (index on top)
;    Outputs:
;        S holds index, limit and a zero leave flag (top first)
;    Registers: RegD and RegX changed; MSCR and MSCR2 used as scratch.
; ------------------------------------------------------------
DOSETUP:    PULU  D                 ; index
            STD   MSCR
            PULU  D                 ; limit
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

; ------------------------------------------------------------
; I  ( -- n )
; Push the index of the innermost loop (2,S, beyond the return
; address).
; ------------------------------------------------------------
IWORDW:     LDD   2,S               ; n. See bugfix: IWORDW.1
            PSHU  D
            RTS

; ------------------------------------------------------------
; J  ( -- n )
; Push the index of the next outer loop (8,S, beyond the return
; address and the inner loop frame).
; ------------------------------------------------------------
JWORDW:     LDD   8,S               ; n. See bugfix: JWORDW.1
            PSHU  D
            RTS

; ------------------------------------------------------------
; LEAVE  ( -- )
; Set the leave flag in the innermost loop frame. The loop exits at
; its next LOOP or +LOOP test.
; ------------------------------------------------------------
LEAVEW:     LDD   #TRUEV            ; true
            STD   6,S               ; See bugfix: LEAVEW.1
            RTS

; ------------------------------------------------------------
; LOOP  ( C: dest -- )
; Compile a call to DOTEST followed by a displacement back to dest.
; For a ?DO loop, also resolve its skip branch to the loop exit.
; ------------------------------------------------------------
LOOPW:      PULU  D
            CMPD  #TAGDO
            BEQ   LOOPOK
            JSR   CFERR
LOOPOK:     PULU  D                 ; dest
            PSHU  D                 ; park dest. See bugfix: LOOPW.1
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
            CMPD  #TAGQDO           ; ?DO frame? See bugfix: LOOPW.2
            BNE   LOOPDONE
            PULU  D
            PULU  X                 ; ?DO skip operand
            LDD   CODEHERE
            PSHU  D
            PSHU  X
            JSR   PATCH
LOOPDONE:   RTS

; ------------------------------------------------------------
; Run-time end of LOOP. Called by JSR; the return address points at
; the back-branch operand. Add 1 to the index. If the leave flag is
; set or the index has reached the limit, discard the loop frame and
; skip the operand; otherwise branch back to the loop start.
; DOTEST
;    Inputs:
;        S holds return address, index, limit and leave flag (top
;        first)
;    Outputs:
;        branch taken, or loop frame removed and operand skipped
;    Registers: RegD and RegX changed.
; ------------------------------------------------------------
DOTEST:     LDD   6,S               ; leave flag. See bugfix: DOTEST.1
            BNE   DTEXIT            ; set: exit
            LDD   2,S               ; index
            ADDD  #1
            STD   2,S
            CMPD  4,S               ; limit
            BEQ   DTEXIT
            PULS  X                 ; X = branch operand address
            LDD   ,X
            LEAX  D,X
            PSHS  X                 ; return to loop start
            RTS
DTEXIT:     PULS  X
            LEAX  2,X               ; skip the branch operand
            LEAS  6,S               ; discard the loop frame
            PSHS  X
            RTS

; ------------------------------------------------------------
; +LOOP  ( C: dest -- )
; Compile a call to DOPLUSTEST followed by a displacement back to
; dest. For a ?DO loop, also resolve its skip branch to the loop exit.
; ------------------------------------------------------------
PLUSLOOPW:  PULU  D
            CMPD  #TAGDO
            BEQ   PLOOPOK
            JSR   CFERR
PLOOPOK:    PULU  D                 ; dest
            PSHU  D                 ; park dest. See bugfix: PLUSLOOPW.1
            LDD   #DOPLUSTEST
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
            CMPD  #TAGQDO           ; ?DO frame? See bugfix: PLUSLOOPW.2
            BNE   PLOOPDONE
            PULU  D
            PULU  X                 ; ?DO skip operand
            LDD   CODEHERE
            PSHU  D
            PSHU  X
            JSR   PATCH
PLOOPDONE:  RTS

; ------------------------------------------------------------
; Run-time end of +LOOP. Called by JSR; the return address points at
; the back-branch operand. Add the step to the index. If the leave
; flag is set or the index crossed the limit, discard the loop frame
; and skip the operand; otherwise branch back to the loop start.
; DOPLUSTEST   ( n -- )
;    Inputs:
;        step n on the data stack; S as for DOTEST
;    Outputs:
;        branch taken, or loop frame removed and operand skipped
;    Registers: RegD and RegX changed; MSCR, MSCR2 and MSCR3 used as
;        scratch.
; ------------------------------------------------------------
DOPLUSTEST: PULU  D                 ; n = step. See bugfix: DOPLUSTEST.1
            STD   MSCR              ; MSCR = step
            LDD   6,S               ; leave flag. See bugfix: DOPLUSTEST.2
            BNE   DPTEXIT           ; set: exit
            LDD   2,S               ; old index
            SUBD  4,S               ; old_u = old_index - limit, mod 65536
            STD   MSCR2
            LDD   2,S
            ADDD  MSCR              ; new_index = old_index + step
            STD   2,S
            SUBD  4,S               ; new_u = new_index - limit, mod 65536
            STD   MSCR3
            ; Crossing test on the unsigned distances old_u and new_u: with a
            ; positive step the limit was crossed if new_u < old_u, with a
            ; negative step if new_u > old_u. See bugfix: DOPLUSTEST.3
            LDD   MSCR              ; reload the step to test its sign
            BMI   DPNEG
DPPOS:      LDD   MSCR3             ; step > 0: crossed if new_u < old_u
            CMPD  MSCR2
            BLO   DPTEXIT
            BRA   DPCONT
DPNEG:      LDD   MSCR3             ; step < 0: crossed if new_u > old_u
            CMPD  MSCR2
            BHI   DPTEXIT
DPCONT:     PULS  X                 ; X = branch operand address
            LDD   ,X
            LEAX  D,X
            PSHS  X
            RTS
DPTEXIT:    PULS  X
            LEAX  2,X               ; skip the branch operand
            LEAS  6,S               ; discard the loop frame
            PSHS  X
            RTS

; ------------------------------------------------------------
; ?DO  ( C: -- orig dest )
; Compile a call to QDOSETUP with a placeholder skip operand. Leave
; orig (the skip operand address) and TAGQDO, then dest and TAGDO.
; ------------------------------------------------------------
QDOW:       LDD   #QDOSETUP
            PSHU  D
            JSR   CCALL
            LDD   #0
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE
            SUBD  #2
            PSHU  D                 ; orig
            LDD   #TAGQDO           ; See bugfix: QDOW.1
            PSHU  D
            LDD   CODEHERE
            PSHU  D                 ; dest
            LDD   #TAGDO
            PSHU  D
            RTS

; ------------------------------------------------------------
; Run-time start of ?DO. If index equals limit, branch over the whole
; loop; otherwise build the loop frame as DOSETUP does and skip the
; branch operand.
; QDOSETUP   ( limit index -- )
;    Inputs:
;        limit and index on the data stack (index on top)
;    Outputs:
;        loop skipped, or loop frame on S and operand skipped
;    Registers: RegD and RegX changed; MSCR and MSCR2 used as scratch.
; ------------------------------------------------------------
QDOSETUP:   PULU  D                 ; index
            STD   MSCR
            PULU  D                 ; limit
            STD   MSCR2
            PULS  X
            LDD   MSCR2
            CMPD  MSCR
            BNE   QDBUILD
            LDD   ,X
            LEAX  D,X
            PSHS  X
            RTS
QDBUILD:    LEAX  2,X
            LDD   #0
            PSHS  D
            LDD   MSCR2
            PSHS  D
            LDD   MSCR
            PSHS  D
            PSHS  X
            RTS

; ------------------------------------------------------------
; UNLOOP  ( -- )
; Discard the loop frame (index, limit, leave flag) beneath UNLOOP's
; return address, so that a following I or J sees the enclosing loop.
; ------------------------------------------------------------
UNLOOPW:    PULS  X
            LEAS  6,S
            PSHS  X
            RTS

; ------------------------------------------------------------
; EXIT  ( -- )
; Compile a call to EXITUNLOOP followed by a count of the DO frames
; found on the control-flow stack. The count is not used at run time.
; A loop must be left with UNLOOP before EXIT.
; ------------------------------------------------------------
EXITW:      LDD   #0
            STD   EXITCNT
            TFR   U,D
            STD   EXITPTR
EXSCAN:     LDD   EXITPTR
            CMPD  CSP
            BEQ   EXSCANDONE
            LDX   EXITPTR
            LDD   ,X
            CMPD  #TAGDO
            BNE   EXNOTDO
            LDD   EXITCNT
            ADDD  #1
            STD   EXITCNT
EXNOTDO:    LDD   EXITPTR
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

; ------------------------------------------------------------
; Run-time part of EXIT: drop the address of the inline count, then
; return from the definition. Loop frames are not discarded.
; EXITUNLOOP
;    Inputs:
;        S holds the address of the inline count, then the return
;        address
;    Outputs:
;        returns to the caller of the definition
;    Registers: RegX and RegY changed.
; ------------------------------------------------------------
EXITUNLOOP: PULS  X                 ; See bugfix: EXITUNLOOP.1
            PULS  Y                 ; Y = return address
            JMP   ,Y

; ------------------------------------------------------------
; CASE  ( C: -- case-sys )
; Start a CASE structure. Leave a filler cell and TAGCASE, a 4-byte
; frame like those of DO and OF, which the EXIT scan relies on.
; ------------------------------------------------------------
CASEW:      LDD   #0                ; filler. See bugfix: CASEW.1
            PSHU  D
            LDD   #TAGCASE
            PSHU  D
            RTS

; ------------------------------------------------------------
; OF  ( C: -- orig )
; Compile OVER = ZBRANCH <operand> DROP. Leave orig (the operand
; address) and TAGOF.
; ------------------------------------------------------------
OFW:        LDD   #OVERW
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
            PSHU  D                 ; orig
            LDD   #DROPW
            PSHU  D
            JSR   CCALL
            LDD   #TAGOF
            PSHU  D
            RTS

; ------------------------------------------------------------
; ENDOF  ( C: orig1 -- orig2 )
; Compile BRANCH with a placeholder operand, resolve orig1 to just
; after it, and leave the new operand address and TAGENDOF.
; ------------------------------------------------------------
ENDOFW:     PULU  D
            CMPD  #TAGOF
            BEQ   EOFOK
            JSR   CFERR
EOFOK:      PULU  D                 ; orig1
            STD   MSCR              ; See bugfix: ENDOFW.1
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
            PSHU  D                 ; orig2
            LDD   #TAGENDOF
            PSHU  D
            RTS

; ------------------------------------------------------------
; ENDCASE  ( C: case-sys -- )
; Compile DROP, then resolve every ENDOF branch to the current code
; address and discard the CASE frame.
; ------------------------------------------------------------
ENDCASEW:   LDD   #DROPW
            PSHU  D
            JSR   CCALL
ECLOOP:     PULU  D
            CMPD  #TAGCASE
            BEQ   ECDONE
            CMPD  #TAGENDOF
            BEQ   ECPATCH
            JSR   CFERR
ECPATCH:    PULU  X                 ; orig
            LDD   CODEHERE
            PSHU  D
            PSHU  X
            JSR   PATCH
            BRA   ECLOOP
ECDONE:     PULU  D                 ; drop filler. See bugfix: ENDCASEW.1
            RTS

; ============================================================
; SECTION 13: COMPILING WORDS (IMMEDIATE/[/]/'/COMPILE,/
; LITERAL/[']/POSTPONE/>BODY, SLITERAL, ABORT")
; ============================================================
; ------------------------------------------------------------
; STATE  ( -- a-addr )
; Push the address of the STATE variable.
; ------------------------------------------------------------
STATEW:     LDD   #STATE
            PSHU  D                 ; a-addr
            RTS

; ------------------------------------------------------------
; IMMEDIATE  ( -- )
; Set the immediate flag ($80) in the length byte of the most recent
; definition (LATEST).
; ------------------------------------------------------------
IMMEDIATEW: LDX   LATEST
            LDA   ,X
            ORA   #$80
            STA   ,X
            RTS

; ------------------------------------------------------------
; [  ( -- )
; Enter interpretation state: STATE = 0.
; ------------------------------------------------------------
LBRACKETW:  LDD   #0
            STD   STATE
            RTS

; ------------------------------------------------------------
; ]  ( -- )
; Enter compilation state: STATE = -1.
; ------------------------------------------------------------
RBRACKETW:  LDD   #-1
            STD   STATE
            RTS

; ------------------------------------------------------------
; '  ( "name" -- xt )
; Parse the next blank-delimited name and return its xt. THROW -13 if
; the name is not found.
; ------------------------------------------------------------
TICKW:      LDD   #32
            PSHU  D                 ; BL delimiter
            JSR   WORDW
            JSR   FINDW
            PULU  D                 ; found flag
            CMPD  #0
            BNE   TICKOK
            PULU  D                 ; drop the name
            LDD   #-13              ; -13
            PSHU  D
            JSR   THROW
TICKOK:     RTS

; ------------------------------------------------------------
; COMPILE,  ( xt -- )
; Compile a call to xt (see CCALL).
; ------------------------------------------------------------
COMPILECOMMAW:
            JMP   CCALL

; ------------------------------------------------------------
; Append a JSR to xt at the code pointer CODEHERE.
; CCALL   ( xt -- )
;    Inputs:
;        xt on the data stack
;    Outputs:
;        JSR xt appended at CODEHERE; CODEHERE advanced by 3
;    Registers: RegA, RegB, RegD and RegX changed.
; ------------------------------------------------------------
CCALL:      LDX   CODEHERE          ; X = code pointer
            LDA   #OPJSR            ; JSR opcode
            STA   ,X+
            PULU  D                 ; xt
            STD   ,X++              ; See bugfix: CCALL.1
            STX   CODEHERE
            RTS

; ------------------------------------------------------------
; LITERAL  ( x -- )
; Compile LIT followed by x, so that x is pushed when the definition
; runs.
; ------------------------------------------------------------
LITERALW:   LDD   #LIT
            PSHU  D
            JSR   CCALL
            JSR   CODECOMMA         ; x
            RTS

; ------------------------------------------------------------
; [']  ( "name" -- )
; Compile the xt of the next name as a literal. THROW -14 if not
; compiling, -13 if the name is not found.
; ------------------------------------------------------------
BRACKTICKW: LDD   STATE
            BNE   BTSTOK
            LDD   #-14              ; -14
            PSHU  D
            JSR   THROW
BTSTOK:     LDD   #32
            PSHU  D
            JSR   WORDW
            JSR   FINDW
            PULU  D
            CMPD  #0
            BNE   BTOK
            PULU  D
            LDD   #-13              ; -13
            PSHU  D
            JSR   THROW
BTOK:       JSR   LITERALW
            RTS

; ------------------------------------------------------------
; POSTPONE  ( "name" -- )
; If the name is immediate, compile a call to it now. Otherwise
; compile its xt as a literal followed by a call to COMPILE, so that
; it is compiled when the enclosing definition runs. THROW -14 if not
; compiling, -13 if the name is not found.
; ------------------------------------------------------------
POSTPONEW:  LDD   STATE
            BNE   PPSTOK
            LDD   #-14              ; -14
            PSHU  D
            JSR   THROW
PPSTOK:     LDD   #32
            PSHU  D
            JSR   WORDW
            JSR   FINDW
            PULU  D
            CMPD  #0
            BNE   PPFOUND
            PULU  D
            LDD   #-13              ; -13
            PSHU  D
            JSR   THROW
PPFOUND:    CMPD  #1                ; 1 = immediate
            BEQ   PPIMM
            JSR   LITERALW
            LDD   #COMPILECOMMAW
            PSHU  D
            JSR   CCALL
            RTS
PPIMM:      JSR   COMPILECOMMAW
            RTS

; ------------------------------------------------------------
; [COMPILE]  ( "name" -- )
; Compile a call to the next name, whether or not it is immediate.
; Obsolescent: POSTPONE is the general replacement. THROW -14 if not
; compiling, -13 if the name is not found.
; Original comment: shadow XCOMPILEW.0.
; ------------------------------------------------------------
XCOMPILEW:  LDD   STATE
            BNE   XCSTOK
            LDD   #-14
            PSHU  D
            JSR   THROW
XCSTOK:     LDD   #32
            PSHU  D
            JSR   WORDW
            JSR   FINDW
            PULU  D
            CMPD  #0
            BNE   XCFOUND
            PULU  D
            LDD   #-13
            PSHU  D
            JSR   THROW
XCFOUND:    JSR   COMPILECOMMAW
            RTS

; ------------------------------------------------------------
; >BODY  ( xt -- a-addr )
; Return the data-field address of a CREATEd word: the cell at xt+5 of
; its JSR DODOES trampoline.
; ------------------------------------------------------------
TOBODYW:    PULU  D                 ; xt
            ADDD  #5
            TFR   D,X
            LDD   ,X
            PSHU  D
            RTS

; ------------------------------------------------------------
; SLITERAL  ( c-addr u -- )
; Compile DOSTR followed by a count byte and a copy of the string.
; THROW -14 if not compiling.
; ------------------------------------------------------------
SLITERALW:  LDD   STATE
            BNE   SLSTOK
            LDD   #-14
            PSHU  D
            JSR   THROW
SLSTOK:     PULU  D                 ; u
            STD   SCNT
            PULU  D                 ; c-addr
            STD   SPTR
            LDD   #DOSTR
            PSHU  D
            JSR   CCALL
            LDX   CODEHERE
            LDB   SCNT+1
            STB   ,X+
            LDY   SPTR
            LDB   SCNT+1
            BEQ   SLEND
SLCPY:      LDA   ,Y+
            STA   ,X+
            DECB
            BNE   SLCPY
SLEND:      STX   CODEHERE
            RTS

; ------------------------------------------------------------
; Run-time part of ABORT". The counted string follows the call. If
; flag is non-zero, TYPE the string and THROW -2; otherwise skip over
; the string.
; DOABORTQUOTE   ( flag -- )
;    Inputs:
;        flag on the data stack; return address on S points at the
;        count byte
;    Outputs:
;        execution continues after the string, or THROW -2
;    Registers: RegA, RegB, RegD, RegX changed; SPTR and SCNT used as
;        scratch.
; ------------------------------------------------------------
DOABORTQUOTE:
            PULS  X
            LDB   ,X
            LEAX  1,X
            STX   SPTR
            CLRA
            STD   SCNT
            LDX   SPTR
            LDB   SCNT+1
            LEAX  B,X
            PULU  D                 ; flag
            CMPD  #0
            BNE   AQTHROW
            PSHS  X
            RTS
AQTHROW:    LDD   SPTR
            PSHU  D
            LDD   SCNT
            PSHU  D
            JSR   TYPEW
            PSHS  X
            LDD   #-2               ; -2
            PSHU  D
            JMP   THROW

; ------------------------------------------------------------
; ABORT"  ( "ccc<quote>" -- )
; Compile DOABORTQUOTE followed by the string up to the closing quote
; as a counted string. THROW -14 if not compiling.
; ------------------------------------------------------------
ABORTQUOTEW:
            LDD   STATE
            BNE   AQSTOK
            LDD   #-14
            PSHU  D
            JSR   THROW
AQSTOK:     LDD   #34
            PSHU  D
            LDD   CODEHERE          ; reserve 3 bytes
            ADDD  #3                ; See bugfix: ABORTQUOTEW.1
            STD   CODEHERE
            JSR   WORDW
            PULU  X
            LDA   ,X
            STA   SCNT
            LEAX  1,X
            STX   SPTR
            LDD   CODEHERE          ; restore
            SUBD  #3
            STD   CODEHERE
            LDD   #DOABORTQUOTE
            PSHU  D
            JSR   CCALL
            LDX   CODEHERE
            LDA   SCNT
            STA   ,X+
            LDY   SPTR
            LDB   SCNT
            BEQ   AQEND
AQCPY:      LDA   ,Y+
            STA   ,X+
            DECB
            BNE   AQCPY
AQEND:      STX   CODEHERE
            RTS

; ------------------------------------------------------------
; BL  ( -- char )
; Push 32, the space character.
; ------------------------------------------------------------
BLW:        LDD   #32
            PSHU  D                 ; char
            RTS

; ------------------------------------------------------------
; >IN  ( -- a-addr )
; Push the address of the >IN variable (TOIN).
; ------------------------------------------------------------
TOINW:      LDD   #TOIN
            PSHU  D
            RTS

; ------------------------------------------------------------
; SPAN  ( -- a-addr )
; Push the address of the SPAN variable.
; ------------------------------------------------------------
SPANW:      LDD   #SPAN
            PSHU  D
            RTS

; ------------------------------------------------------------
; TIB  ( -- c-addr )
; Push the address of the terminal input buffer.
; ------------------------------------------------------------
TIBW:       LDD   #TIBBUF
            PSHU  D
            RTS

; ------------------------------------------------------------
; #TIB  ( -- a-addr )
; Push the address of the NTIB variable.
; ------------------------------------------------------------
NTIBW:      LDD   #NTIB
            PSHU  D
            RTS

; ============================================================
; SECTION 14: STACK MANIPULATION (Core + Core Ext + return stack)
; ============================================================
; ------------------------------------------------------------
; DUP  ( x -- x x )
; Duplicate the top cell.
; ------------------------------------------------------------
DUPW:       LDD   ,U                ; x
            PSHU  D
            RTS

; ------------------------------------------------------------
; DROP  ( x -- )
; Discard the top cell.
; ------------------------------------------------------------
DROPW:      LEAU  2,U               ; x
            RTS

; ------------------------------------------------------------
; SWAP  ( x1 x2 -- x2 x1 )
; Exchange the top two cells.
; ------------------------------------------------------------
SWAPW:      LDD   ,U                ; x2
            LDX   2,U               ; x1
            STX   ,U
            STD   2,U
            RTS

; ------------------------------------------------------------
; OVER  ( x1 x2 -- x1 x2 x1 )
; Copy the second cell to the top.
; ------------------------------------------------------------
OVERW:      LDD   2,U               ; x1
            PSHU  D
            RTS

; ------------------------------------------------------------
; ROT  ( x1 x2 x3 -- x2 x3 x1 )
; Rotate the third cell to the top.
; ------------------------------------------------------------
ROTW:       LDD   ,U                ; x3
            LDX   2,U               ; x2
            LDY   4,U               ; x1
            STY   ,U
            STD   2,U
            STX   4,U
            RTS

; ------------------------------------------------------------
; ?DUP  ( x -- 0 | x x )
; Duplicate the top cell if it is non-zero.
; ------------------------------------------------------------
QDUPW:      LDD   ,U                ; x
            CMPD  #0
            BEQ   QDUPDONE
            PSHU  D
QDUPDONE:   RTS

; ------------------------------------------------------------
; DEPTH  ( -- +n )
; Push the number of cells on the data stack: (SP0 - U) / 2.
; ------------------------------------------------------------
DEPTHW:     TFR   U,D
            STD   DEPTHTMP
            LDD   #SP0
            SUBD  DEPTHTMP
            LSRA
            RORB
            PSHU  D                 ; +n
            RTS

; ------------------------------------------------------------
; 2DUP  ( x1 x2 -- x1 x2 x1 x2 )
; Duplicate the top cell pair.
; ------------------------------------------------------------
DDUPW:      LDD   2,U               ; x1
            LDX   ,U                ; x2
            PSHU  D
            PSHU  X
            RTS

; ------------------------------------------------------------
; 2DROP  ( x1 x2 -- )
; Discard the top cell pair.
; ------------------------------------------------------------
DDROPW:     LEAU  4,U
            RTS

; ------------------------------------------------------------
; 2SWAP  ( x1 x2 x3 x4 -- x3 x4 x1 x2 )
; Exchange the top two cell pairs.
; ------------------------------------------------------------
DSWAPW:     LDD   ,U                ; x4
            STD   MSCR
            LDD   2,U               ; x3
            LDX   4,U               ; x2
            LDY   6,U               ; x1
            STD   6,U
            STX   ,U
            STY   2,U
            LDD   MSCR
            STD   4,U
            RTS

; ------------------------------------------------------------
; 2OVER  ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 )
; Copy the second cell pair to the top.
; ------------------------------------------------------------
DOVERW:     LDD   6,U               ; x1
            LDX   4,U               ; x2
            PSHU  D
            PSHU  X
            RTS

; ------------------------------------------------------------
; NIP  ( x1 x2 -- x2 )
; Discard the second cell.
; ------------------------------------------------------------
NIPW:       LDD   ,U                ; x2
            STD   2,U
            LEAU  2,U
            RTS

; ------------------------------------------------------------
; TUCK  ( x1 x2 -- x2 x1 x2 )
; Copy the top cell beneath the second cell.
; ------------------------------------------------------------
TUCKW:      LDD   ,U                ; x2
            LDX   2,U               ; x1
            PSHU  D
            STX   2,U
            STD   4,U
            RTS

; ------------------------------------------------------------
; PICK  ( xu ... x0 u -- xu ... x0 xu )
; Copy the cell u deep (0 PICK is DUP) to the top.
; ------------------------------------------------------------
PICKW:      PULU  D                 ; u
            LSLB
            ROLA
            LDD   D,U
            PSHU  D
            RTS

; ------------------------------------------------------------
; ROLL  ( xu xu-1 ... x0 u -- xu-1 ... x0 xu )
; Move the cell u deep (0 ROLL does nothing) to the top, shifting the
; cells above it down one place. RDST holds the byte offset and RVAL
; the cell being moved.
; ------------------------------------------------------------
ROLLW:      PULU  D                 ; u
            CMPD  #0
            BEQ   ROLLDONE
            LSLB
            ROLA
            STD   RDST
            LEAX  D,U
            LDD   ,X
            STD   RVAL
RLOOP:      LDD   RDST
            CMPD  #2
            BLT   RSTORE
            LEAY  D,U
            SUBD  #2
            LEAX  D,U
            LDD   ,X
            STD   ,Y
            LDD   RDST
            SUBD  #2
            STD   RDST
            BRA   RLOOP
RSTORE:     LDD   RVAL
            STD   ,U
ROLLDONE:   RTS

; ------------------------------------------------------------
; 2ROT  ( x1 x2 x3 x4 x5 x6 -- x3 x4 x5 x6 x1 x2 )
; Rotate the third cell pair to the top. TR1 and TR2 hold the pair
; while the others move.
; ------------------------------------------------------------
DROTW:      LDD   10,U              ; x1
            STD   TR1
            LDD   8,U               ; x2
            STD   TR2
            LDD   6,U
            STD   10,U
            LDD   4,U
            STD   8,U
            LDD   2,U
            STD   6,U
            LDD   0,U
            STD   4,U
            LDD   TR2
            STD   ,U
            LDD   TR1
            STD   2,U
            RTS

; ------------------------------------------------------------
; >R  ( x -- )  ( R: -- x )
; Move x from the data stack to the return stack. The return address
; of this call is on top of S, so it is lifted off and put back around
; the transfer.
; ------------------------------------------------------------
TORW:       PULU  D                 ; x
            PULS  X
            PSHS  D
            PSHS  X
            RTS

; ------------------------------------------------------------
; R>  ( -- x )  ( R: x -- )
; Move x from the return stack to the data stack. The return address
; of this call is on top of S, so it is lifted off and put back around
; the transfer.
; ------------------------------------------------------------
FROMRW:     PULS  X
            PULS  D                 ; x
            PSHS  X
            PSHU  D
            RTS

; ------------------------------------------------------------
; R@  ( -- x )  ( R: x -- x )
; Copy the top of the return stack to the data stack. The return
; address of this call is on top of S, so it is lifted off and put
; back around the transfer.
; ------------------------------------------------------------
RFETCHW:    PULS  X
            LDD   ,S                ; x
            PSHS  X
            PSHU  D
            RTS

; ------------------------------------------------------------
; 2>R  ( x1 x2 -- )  ( R: -- x1 x2 )
; Move a cell pair to the return stack. R2A and R2B are scratch. The
; return address of this call is on top of S, so it is lifted off and
; put back around the transfer.
; ------------------------------------------------------------
TWOTORW:    PULU  D                 ; x2
            STD   R2A
            PULU  D                 ; x1
            STD   R2B
            PULS  X
            LDD   R2B
            PSHS  D
            LDD   R2A
            PSHS  D
            PSHS  X
            RTS

; ------------------------------------------------------------
; 2R>  ( -- x1 x2 )  ( R: x1 x2 -- )
; Move a cell pair from the return stack. R2A and R2B are scratch. The
; return address of this call is on top of S, so it is lifted off and
; put back around the transfer.
; ------------------------------------------------------------
TWOFROMRW:  PULS  X
            PULS  D                 ; x2
            STD   R2A
            PULS  D                 ; x1
            STD   R2B
            PSHS  X
            LDD   R2B
            PSHU  D
            LDD   R2A
            PSHU  D
            RTS

; ------------------------------------------------------------
; 2R@  ( -- x1 x2 )  ( R: x1 x2 -- x1 x2 )
; Copy the top cell pair of the return stack. R2A and R2B are scratch.
; The return address of this call is on top of S, so it is lifted off
; and put back around the transfer.
; ------------------------------------------------------------
TWORFETCHW: PULS  X
            LDD   ,S                ; x2
            STD   R2A
            LDD   2,S               ; x1
            STD   R2B
            PSHS  X
            LDD   R2B
            PSHU  D
            LDD   R2A
            PSHU  D
            RTS

; ============================================================
; SECTION 15: ARITHMETIC (single + double + mixed precision)
; ============================================================
; ------------------------------------------------------------
; +  ( n1 n2 -- n3 )
; Add n2 to n1.
; ------------------------------------------------------------
PLUSW:      PULU  D                 ; n2
            ADDD  ,U
            STD   ,U
            RTS

; ------------------------------------------------------------
; -  ( n1 n2 -- n3 )
; Subtract n2 from n1.
; ------------------------------------------------------------
MINUSW:     PULU  D                 ; n2
            STD   MSCR
            LDD   ,U
            SUBD  MSCR
            STD   ,U
            RTS

; ------------------------------------------------------------
; NEGATE  ( n1 -- n2 )
; Two's complement negate.
; ------------------------------------------------------------
NEGATEW:    LDD   ,U                ; n1
            COMA
            COMB
            ADDD  #1
            STD   ,U
            RTS

; ------------------------------------------------------------
; ABS  ( n -- u )
; Absolute value.
; ------------------------------------------------------------
ABSW:       LDD   ,U                ; n
            BPL   ABSDONE
            COMA
            COMB
            ADDD  #1
            STD   ,U
ABSDONE:    RTS

; ------------------------------------------------------------
; MIN  ( n1 n2 -- n3 )
; The lesser of two signed numbers.
; ------------------------------------------------------------
MINW:       PULU  D                 ; n2
            CMPD  ,U
            BLT   MINISN2
            RTS
MINISN2:    STD   ,U
            RTS

; ------------------------------------------------------------
; MAX  ( n1 n2 -- n3 )
; The greater of two signed numbers.
; ------------------------------------------------------------
MAXW:       PULU  D                 ; n2
            CMPD  ,U
            BGT   MAXISN2
            RTS
MAXISN2:    STD   ,U
            RTS

; ------------------------------------------------------------
; 1+  ( n1 -- n2 )
; Add 1.
; ------------------------------------------------------------
ONEPLUSW:   LDD   ,U
            ADDD  #1
            STD   ,U
            RTS

; ------------------------------------------------------------
; 1-  ( n1 -- n2 )
; Subtract 1.
; ------------------------------------------------------------
ONEMINUSW:  LDD   ,U
            SUBD  #1
            STD   ,U
            RTS

; ------------------------------------------------------------
; 2+  ( n1 -- n2 )
; Add 2.
; ------------------------------------------------------------
TWOPLUSW:   LDD   ,U
            ADDD  #2
            STD   ,U
            RTS

; ------------------------------------------------------------
; *  ( n1 n2 -- n3 )
; Signed multiply, keeping the low 16 bits of the product. The
; magnitudes are multiplied byte-wise with MUL and the sign is
; restored.
; ------------------------------------------------------------
STARW:      PULU  D                 ; n2
            STD   MSCR
            LDD   ,U
            CLR   MSIGN
            BPL   SNOFLIP1
            COM   MSIGN
            COMA
            COMB
            ADDD  #1
SNOFLIP1:   STA   MAHI
            STB   MALO
            LDD   MSCR
            BPL   SNOFLIP2
            COM   MSIGN
            COMA
            COMB
            ADDD  #1
SNOFLIP2:   STA   MBHI
            STB   MBLO
            LDA   MALO
            LDB   MBLO
            MUL
            STD   MRESULT
            LDA   MAHI
            LDB   MBLO
            MUL
            LDA   MRESULT
            PSHS  B
            ADDA  ,S+               ; A = A + B
            STA   MRESULT
            LDA   MALO
            LDB   MBHI
            MUL
            LDA   MRESULT
            PSHS  B
            ADDA  ,S+               ; A = A + B
            STA   MRESULT
            LDD   MRESULT
            TST   MSIGN
            BEQ   SDONE
            COMA
            COMB
            ADDD  #1
SDONE:      STD   ,U
            RTS

; ------------------------------------------------------------
; 2*  ( x1 -- x2 )
; Shift left one bit.
; ------------------------------------------------------------
TWOSTARW:   LDD   ,U
            ASLB
            ROLA
            STD   ,U
            RTS

; ------------------------------------------------------------
; Unsigned 16-bit division by shift and subtract. The divisor is not
; checked for zero.
; UDIV16
;    Inputs:
;        DIVNUM = dividend, DIVDEN = divisor (unsigned)
;    Outputs:
;        DIVNUM = quotient, DIVREM = remainder
;    Registers: RegD changed; DIVCNT used as the loop counter.
; ------------------------------------------------------------
UDIV16:     CLR   DIVREM
            CLR   DIVREM+1
            LDB   #16
            STB   DIVCNT
UD16LOOP:   ASL   DIVNUM+1
            ROL   DIVNUM
            ROL   DIVREM+1
            ROL   DIVREM
            LDD   DIVREM
            SUBD  DIVDEN
            BLO   UDSKIP
            STD   DIVREM
            INC   DIVNUM+1
UDSKIP:     DEC   DIVCNT
            BNE   UD16LOOP
            RTS

; ------------------------------------------------------------
; Common part of /, MOD and /MOD: divide n1 by n2 with the sign
; handling for truncating division. THROW -10 if n2 is zero.
; DIVCOMMON   ( n1 n2 -- )
;    Inputs:
;        n1 and n2 on the data stack (n2 on top)
;    Outputs:
;        DIVNUM = quotient, DIVREM = remainder (data stack popped)
;    Registers: RegD changed; DIVNUM, DIVDEN, DIVREM, DNSIGN, DVSIGN
;        used.
; ------------------------------------------------------------
DIVCOMMON:  PULU  D                 ; n2
            STD   DIVDEN
            CMPD  #0
            BNE   DCOK
            LDD   #-10              ; -10
            PSHU  D
            JSR   THROW
DCOK:       PULU  D                 ; n1
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
DNPOS:      TST   DIVDEN
            BPL   DVPOS
            COM   DVSIGN
            LDD   DIVDEN
            COMA
            COMB
            ADDD  #1
            STD   DIVDEN
DVPOS:      JSR   UDIV16
            LDD   DIVNUM
            TST   DVSIGN
            BEQ   DQPOS
            COMA
            COMB
            ADDD  #1
            STD   DIVNUM
DQPOS:      LDD   DIVREM
            TST   DNSIGN
            BEQ   DCRPOS
            COMA
            COMB
            ADDD  #1
            STD   DIVREM
DCRPOS:     RTS

; ------------------------------------------------------------
; /  ( n1 n2 -- n3 )
; Quotient of n1 divided by n2. Division truncates toward zero; the
; remainder has the sign of the dividend. THROW -10 if the divisor is
; zero.
; ------------------------------------------------------------
SLASHW:     JSR   DIVCOMMON
            LDD   DIVNUM
            PSHU  D
            RTS

; ------------------------------------------------------------
; MOD  ( n1 n2 -- n3 )
; Remainder of n1 divided by n2. Division truncates toward zero; the
; remainder has the sign of the dividend. THROW -10 if the divisor is
; zero.
; ------------------------------------------------------------
MODW:       JSR   DIVCOMMON
            LDD   DIVREM
            PSHU  D
            RTS

; ------------------------------------------------------------
; /MOD  ( n1 n2 -- n3 n4 )
; Divide n1 by n2, giving the remainder n3 and the quotient n4.
; Division truncates toward zero; the remainder has the sign of the
; dividend. THROW -10 if the divisor is zero.
; ------------------------------------------------------------
SLASHMODW:  JSR   DIVCOMMON
            LDD   DIVREM
            PSHU  D
            LDD   DIVNUM
            PSHU  D
            RTS

; ------------------------------------------------------------
; 2/  ( x1 -- x2 )
; Arithmetic shift right one bit.
; ------------------------------------------------------------
TWOSLASHW:  LDD   ,U
            ASRA
            RORB
            STD   ,U
            RTS

; ------------------------------------------------------------
; Unsigned 16 x 16 to 32-bit multiply from four partial products.
; UMUL32
;    Inputs:
;        MAHI:MALO and MBHI:MBLO (unsigned factors)
;    Outputs:
;        PRODHI:PRODLO = product
;    Registers: RegA, RegB and RegD changed.
; ------------------------------------------------------------
UMUL32:     LDA   MALO
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
UM32A:      LDA   MALO
            LDB   MBHI
            MUL
            ADDB  PRODLO
            STB   PRODLO
            ADCA  #0
            ADDA  PRODHI+1
            STA   PRODHI+1
            BCC   UM32B
            INC   PRODHI
UM32B:      LDA   MAHI
            LDB   MBHI
            MUL
            ADDD  PRODHI
            STD   PRODHI
            RTS

; ------------------------------------------------------------
; Unsigned 32 / 16 division (restoring, 32 iterations). Used by
; UM/MOD, SM/REM, FM/MOD, */ and */MOD.
; UDIV32
;    Inputs:
;        PRODHI:PRODLO = dividend, DIVDEN = divisor (unsigned)
;    Outputs:
;        PRODLO = quotient, DIVREM = remainder
;    Registers: RegD changed; DIVCNT used as the loop counter.
; Original comment: shadow UDIV32.1.
; ------------------------------------------------------------
UDIV32:     CLR   DIVREM
            CLR   DIVREM+1
            LDB   #32
            STB   DIVCNT
UD32LP:     ASL   PRODLO+1
            ROL   PRODLO
            ROL   PRODHI+1
            ROL   PRODHI
            ROL   DIVREM+1
            ROL   DIVREM
            BCS   UD32FORCE         ; 17th bit set. See bugfix: UDIV32.1
            LDD   DIVREM
            SUBD  DIVDEN
            BLO   UD32SKIP
UD32TAKE:   STD   DIVREM
            INC   PRODLO+1
            BRA   UD32SKIP
UD32FORCE:  LDD   DIVREM
            SUBD  DIVDEN
            BRA   UD32TAKE
UD32SKIP:   DEC   DIVCNT
            BNE   UD32LP
            RTS

; ------------------------------------------------------------
; Negate the 32-bit value in PRODHI:PRODLO.
; MNEG32
;    Inputs:
;        PRODHI:PRODLO
;    Outputs:
;        PRODHI:PRODLO negated
;    Registers: RegD changed.
; ------------------------------------------------------------
MNEG32:     LDD   PRODLO
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
MN32DONE:   RTS

; ------------------------------------------------------------
; Common part of */ and */MOD: form the 32-bit product n1 * n2, then
; divide it by n3. The quotient is negated if an odd number of the
; three is negative, the remainder if the product is negative. THROW
; -10 if n3 is zero.
; STARSLASHCOMMON   ( n1 n2 n3 -- )
;    Inputs:
;        n1, n2 and n3 on the data stack (n3 on top)
;    Outputs:
;        PRODLO = quotient, DIVREM = remainder (data stack popped)
;    Registers: RegA, RegB and RegD changed; many scratch cells used.
; ------------------------------------------------------------
STARSLASHCOMMON:
            PULU  D                 ; n3
            STD   DIVDEN
            CMPD  #0
            BNE   SSOK
            LDD   #-10              ; -10
            PSHU  D
            JSR   THROW
SSOK:       CLR   PSIGN
            TST   DIVDEN
            BPL   SSN3POS
            COM   PSIGN
            LDD   DIVDEN
            COMA
            COMB
            ADDD  #1
            STD   DIVDEN
SSN3POS:    LDA   #0
            STA   PRSIGN
            PULU  D                 ; n2
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
SSN2POS:    LDA   MSCR
            STA   MBHI
            LDA   MSCR+1
            STA   MBLO
            PULU  D                 ; n1
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
SSN1POS:    LDA   MSCR
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
SSQPOS:     LDD   DIVREM
            TST   PRSIGN
            BEQ   SSRPOS
            COMA
            COMB
            ADDD  #1
            STD   DIVREM
SSRPOS:     RTS

; ------------------------------------------------------------
; */  ( n1 n2 n3 -- n4 )
; Multiply n1 by n2 giving a 32-bit intermediate product, then divide
; by n3. The quotient is n4.
; ------------------------------------------------------------
STARSLASHW: JSR   STARSLASHCOMMON
            LDD   PRODLO
            PSHU  D
            RTS

; ------------------------------------------------------------
; */MOD  ( n1 n2 n3 -- n4 n5 )
; Multiply n1 by n2 giving a 32-bit intermediate product, then divide
; by n3, giving the remainder n4 and the quotient n5.
; ------------------------------------------------------------
STARSLASHMODW:
            JSR   STARSLASHCOMMON
            LDD   DIVREM
            PSHU  D
            LDD   PRODLO
            PSHU  D
            RTS

; ------------------------------------------------------------
; UM*  ( u1 u2 -- ud )
; Unsigned 16 x 16 to 32-bit multiply.
; ------------------------------------------------------------
UMSTARW:    PULU  D                 ; u2
            STD   MSCR
            PULU  D                 ; u1
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

; ------------------------------------------------------------
; UM/MOD  ( ud u1 -- u2 u3 )
; Divide the unsigned double ud by u1, giving the remainder u2 and the
; quotient u3. THROW -10 if u1 is zero.
; ------------------------------------------------------------
UMSLASHMODW:
            PULU  D                 ; u1
            STD   DIVDEN
            CMPD  #0
            BNE   UMOK
            LDD   #-10              ; -10
            PSHU  D
            JSR   THROW
UMOK:       PULU  D                 ; ud
            STD   PRODHI
            PULU  D
            STD   PRODLO
            JSR   UDIV32
            LDD   DIVREM
            PSHU  D
            LDD   PRODLO
            PSHU  D
            RTS

; ------------------------------------------------------------
; M*  ( n1 n2 -- d )
; Signed 16 x 16 to 32-bit multiply.
; ------------------------------------------------------------
MSTARW:     PULU  D                 ; n2
            STD   MSCR
            PULU  D                 ; n1
            CLR   MSIGN
            TSTA                    ; sign of n1. See bugfix: MSTARW.1
            BPL   MSN1POS
            COM   MSIGN
            COMA
            COMB
            ADDD  #1
MSN1POS:    STA   MAHI
            STB   MALO
            LDD   MSCR
            BPL   MSN2POS
            COM   MSIGN
            COMA
            COMB
            ADDD  #1
MSN2POS:    STA   MBHI
            STB   MBLO
            JSR   UMUL32
            TST   MSIGN
            BEQ   MSDONE
            JSR   MNEG32
MSDONE:     LDD   PRODLO
            PSHU  D
            LDD   PRODHI
            PSHU  D
            RTS

; ------------------------------------------------------------
; SM/REM  ( d n1 -- n2 n3 )
; Symmetric division of the double d by n1, giving the remainder n2
; and the quotient n3. The quotient is truncated toward zero and the
; remainder has the sign of d. THROW -10 if n1 is zero.
; ------------------------------------------------------------
SMSLASHREMW:
            PULU  D                 ; n1
            STD   DIVDEN
            CMPD  #0
            BNE   SMOK
            LDD   #-10              ; -10
            PSHU  D
            JSR   THROW
SMOK:       PULU  D                 ; d
            STD   PRODHI
            PULU  D
            STD   PRODLO
            CLR   DNSIGN
            CLR   DVSIGN
            TST   PRODHI
            BPL   SMDPOS
            COM   DNSIGN
            COM   DVSIGN
            JSR   MNEG32
SMDPOS:     LDD   DIVDEN
            BPL   SMDVPOS
            COM   DVSIGN
            LDD   DIVDEN
            COMA
            COMB
            ADDD  #1
            STD   DIVDEN
SMDVPOS:    JSR   UDIV32
            LDD   DIVREM
            TST   DNSIGN
            BEQ   SMRPOS
            COMA
            COMB
            ADDD  #1
SMRPOS:     PSHU  D
            LDD   PRODLO
            TST   DVSIGN
            BEQ   SMQPOS
            COMA
            COMB
            ADDD  #1
SMQPOS:     PSHU  D
            RTS

; ------------------------------------------------------------
; FM/MOD  ( d n1 -- n2 n3 )
; Floored division of the double d by n1, giving the remainder n2 and
; the quotient n3. The quotient is rounded toward negative infinity
; and the remainder has the sign of n1. THROW -10 if n1 is zero.
; ------------------------------------------------------------
FMSLASHMODW:
            PULU  D                 ; n1
            STD   DIVDEN
            CMPD  #0
            BNE   FMOK
            LDD   #-10              ; -10
            PSHU  D
            JSR   THROW
FMOK:       PULU  D                 ; d
            STD   PRODHI
            PULU  D
            STD   PRODLO
            CLR   DNSIGN
            CLR   DVSIGN
            CLR   DVOWNSIGN
            TST   PRODHI
            BPL   FMDPOS
            COM   DNSIGN
            COM   DVSIGN
            JSR   MNEG32
FMDPOS:     LDD   DIVDEN
            BPL   FMDVPOS
            COM   DVSIGN
            COM   DVOWNSIGN
            LDD   DIVDEN
            COMA
            COMB
            ADDD  #1
            STD   DIVDEN
FMDVPOS:    JSR   UDIV32
            TST   DVSIGN
            BEQ   FMNOFLOOR
            LDD   DIVREM
            BEQ   FMNOFLOOR
            LDD   PRODLO
            ADDD  #1
            STD   PRODLO
            LDD   DIVDEN
            SUBD  DIVREM
            STD   DIVREM
FMNOFLOOR:  LDD   DIVREM
            TST   DVOWNSIGN
            BEQ   FMRPOS
            COMA
            COMB
            ADDD  #1
FMRPOS:     PSHU  D
            LDD   PRODLO
            TST   DVSIGN
            BEQ   FMQPOS
            COMA
            COMB
            ADDD  #1
FMQPOS:     PSHU  D
            RTS

; ------------------------------------------------------------
; D+  ( d1 d2 -- d3 )
; Add two doubles.
; ------------------------------------------------------------
DPLUSW:     PULU  D                 ; d2 high
            STD   MSCR
            PULU  D                 ; d2 low
            STD   MSCR2
            PULU  D                 ; d1 high
            STD   MSCR3
            PULU  D                 ; d1 low
            ADDD  MSCR2
            STD   MSCR4
            BCC   DPNOCY
            LDD   MSCR3
            ADDD  MSCR
            ADDD  #1
            BRA   DPHIDONE
DPNOCY:     LDD   MSCR3
            ADDD  MSCR
DPHIDONE:   STD   MSCR3
            LDD   MSCR4
            PSHU  D
            LDD   MSCR3
            PSHU  D
            RTS

; ------------------------------------------------------------
; D-  ( d1 d2 -- d3 )
; Subtract d2 from d1.
; ------------------------------------------------------------
DMINUSW:    PULU  D                 ; d2 high
            STD   MSCR
            PULU  D                 ; d2 low
            STD   MSCR2
            PULU  D                 ; d1 high
            STD   MSCR3
            PULU  D                 ; d1 low
            SUBD  MSCR2
            STD   MSCR4
            BCC   DMNOBOR
            LDD   MSCR3
            SUBD  MSCR
            SUBD  #1
            BRA   DMHIDONE
DMNOBOR:    LDD   MSCR3
            SUBD  MSCR
DMHIDONE:   STD   MSCR3
            LDD   MSCR4
            PSHU  D
            LDD   MSCR3
            PSHU  D
            RTS

; ------------------------------------------------------------
; DNEGATE  ( d1 -- d2 )
; Negate a double.
; ------------------------------------------------------------
DNEGATEW:   PULU  D                 ; d1 high
            STD   PRODHI
            PULU  D                 ; d1 low
            STD   PRODLO
            JSR   MNEG32
            LDD   PRODLO
            PSHU  D
            LDD   PRODHI
            PSHU  D
            RTS

; ------------------------------------------------------------
; DABS  ( d -- ud )
; Absolute value of a double.
; ------------------------------------------------------------
DABSW:      PULU  D                 ; d high
            STD   PRODHI
            PULU  D                 ; d low
            STD   PRODLO
            TST   PRODHI
            BPL   DABSDONE
            JSR   MNEG32
DABSDONE:   LDD   PRODLO
            PSHU  D
            LDD   PRODHI
            PSHU  D
            RTS

; ------------------------------------------------------------
; M+  ( d1 n -- d2 )
; Add the single n, sign-extended, to the double d1.
; ------------------------------------------------------------
MPLUSW:     PULU  D                 ; n
            STD   MSCR2
            BPL   MPPOSN
            LDD   #-1
            BRA   MPSIGNED
MPPOSN:     LDD   #0
MPSIGNED:   STD   MSCR
            PULU  D                 ; d1 high
            STD   MSCR3
            PULU  D                 ; d1 low
            ADDD  MSCR2
            STD   MSCR4
            BCC   MPNOCY
            LDD   MSCR3
            ADDD  MSCR
            ADDD  #1
            BRA   MPHIDONE
MPNOCY:     LDD   MSCR3
            ADDD  MSCR
MPHIDONE:   STD   MSCR3
            LDD   MSCR4
            PSHU  D
            LDD   MSCR3
            PSHU  D
            RTS

; ------------------------------------------------------------
; S>D  ( n -- d )
; Sign-extend a single to a double.
; ------------------------------------------------------------
STODW:      PULU  D                 ; n
            PSHU  D
            TSTA                    ; sign of n. See bugfix: STODW.1
            BPL   SDPOS
            LDD   #-1
            BRA   SDPUSH
SDPOS:      LDD   #0
SDPUSH:     PSHU  D
            RTS

; ------------------------------------------------------------
; D>S  ( d -- n )
; Drop the high cell of a double.
; ------------------------------------------------------------
DTOSW:      PULU  D                 ; drop high cell
            RTS

; ------------------------------------------------------------
; DMAX  ( d1 d2 -- d3 )
; The greater of two signed doubles.
; ------------------------------------------------------------
DMAXW:      PULU  D                 ; d2 high
            STD   MSCR
            PULU  D                 ; d2 low
            STD   MSCR2
            PULU  D                 ; d1 high
            STD   MSCR3
            PULU  D                 ; d1 low
            STD   MSCR4
            LDD   MSCR3
            CMPD  MSCR
            BGT   DMXD1
            BLT   DMXD2
            LDD   MSCR4
            CMPD  MSCR2
            BHS   DMXD1
DMXD2:      LDD   MSCR2
            PSHU  D
            LDD   MSCR
            PSHU  D
            RTS
DMXD1:      LDD   MSCR4
            PSHU  D
            LDD   MSCR3
            PSHU  D
            RTS

; ------------------------------------------------------------
; DMIN  ( d1 d2 -- d3 )
; The lesser of two signed doubles.
; ------------------------------------------------------------
DMINW:      PULU  D                 ; d2 high
            STD   MSCR
            PULU  D                 ; d2 low
            STD   MSCR2
            PULU  D                 ; d1 high
            STD   MSCR3
            PULU  D                 ; d1 low
            STD   MSCR4
            LDD   MSCR3
            CMPD  MSCR
            BLT   DMND1
            BGT   DMND2
            LDD   MSCR4
            CMPD  MSCR2
            BLS   DMND1
DMND2:      LDD   MSCR2
            PSHU  D
            LDD   MSCR
            PSHU  D
            RTS
DMND1:      LDD   MSCR4
            PSHU  D
            LDD   MSCR3
            PSHU  D
            RTS

; ============================================================
; SECTION 16: LOGIC / SHIFTS / ADDRESS ARITHMETIC
; ============================================================
; ------------------------------------------------------------
; AND  ( x1 x2 -- x3 )
; Bitwise AND.
; ------------------------------------------------------------
ANDW:       PULU  D                 ; x2
            ANDA  ,U
            ANDB  1,U
            STD   ,U
            RTS

; ------------------------------------------------------------
; OR  ( x1 x2 -- x3 )
; Bitwise OR.
; ------------------------------------------------------------
ORW:        PULU  D                 ; x2
            ORA   ,U
            ORB   1,U
            STD   ,U
            RTS

; ------------------------------------------------------------
; XOR  ( x1 x2 -- x3 )
; Bitwise exclusive OR.
; ------------------------------------------------------------
XORW:       PULU  D                 ; x2
            EORA  ,U
            EORB  1,U
            STD   ,U
            RTS

; ------------------------------------------------------------
; INVERT  ( x1 -- x2 )
; Ones complement.
; ------------------------------------------------------------
INVERTW:    LDD   ,U
            COMA
            COMB
            STD   ,U
            RTS

; ------------------------------------------------------------
; LSHIFT  ( x1 u -- x2 )
; Shift x1 left u bits (only the low byte of u is used).
; ------------------------------------------------------------
LSHIFTW:    PULU  D                 ; u
            STB   SHCNT
            LDD   ,U
LSLOOP:     LDB   SHCNT
            BEQ   LSDONE
            ASL   1,U
            ROL   ,U
            DEC   SHCNT
            BRA   LSLOOP
LSDONE:     RTS

; ------------------------------------------------------------
; RSHIFT  ( x1 u -- x2 )
; Logical shift of x1 right u bits (only the low byte of u is used).
; ------------------------------------------------------------
RSHIFTW:    PULU  D                 ; u
            STB   SHCNT
RSLOOP:     LDB   SHCNT
            BEQ   RSDONE
            LSR   ,U
            ROR   1,U
            DEC   SHCNT
            BRA   RSLOOP
RSDONE:     RTS

; ------------------------------------------------------------
; CELLS  ( n1 -- n2 )
; Convert a cell count to address units (multiply by 2).
; ------------------------------------------------------------
CELLSW:     LDD   ,U
            ASLB
            ROLA
            STD   ,U
            RTS

; ------------------------------------------------------------
; CELL+  ( a-addr1 -- a-addr2 )
; Add the size of a cell (2).
; ------------------------------------------------------------
CELLPLUSW:  LDD   ,U
            ADDD  #2
            STD   ,U
            RTS

; ------------------------------------------------------------
; CHARS  ( n1 -- n2 )
; Convert a character count to address units. A character is one
; address unit, so nothing is done.
; ------------------------------------------------------------
CHARSW:     RTS

; ------------------------------------------------------------
; CHAR+  ( c-addr1 -- c-addr2 )
; Add the size of a character (1).
; ------------------------------------------------------------
CHARPLUSW:  LDD   ,U
            ADDD  #1
            STD   ,U
            RTS

; ------------------------------------------------------------
; ALIGN  ( -- )
; Nothing to do: the 6809 has no alignment restrictions.
; ------------------------------------------------------------
ALIGNW:     RTS

; ------------------------------------------------------------
; ALIGNED  ( addr -- a-addr )
; Nothing to do: the 6809 has no alignment restrictions.
; ------------------------------------------------------------
ALIGNEDW:   RTS

; ============================================================
; SECTION 17: COMPARISON
; ============================================================
; ------------------------------------------------------------
; =  ( x1 x2 -- flag )
; True if x1 equals x2.
; ------------------------------------------------------------
EQUALW:     PULU  D                 ; x2
            CMPD  ,U
            BEQ   EQTRUE
            LDD   #FALSEV
            STD   ,U
            RTS
EQTRUE:     LDD   #TRUEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; <  ( n1 n2 -- flag )
; True if n1 is less than n2 (signed).
; ------------------------------------------------------------
LESSW:      PULU  D                 ; n2
            STD   MSCR
            LDD   ,U
            CMPD  MSCR
            BLT   LTTRUE
            LDD   #FALSEV
            STD   ,U
            RTS
LTTRUE:     LDD   #TRUEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; >  ( n1 n2 -- flag )
; True if n1 is greater than n2 (signed).
; ------------------------------------------------------------
GREATERW:   PULU  D                 ; n2
            STD   MSCR
            LDD   ,U
            CMPD  MSCR
            BGT   GTTRUE
            LDD   #FALSEV
            STD   ,U
            RTS
GTTRUE:     LDD   #TRUEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; 0=  ( x -- flag )
; True if x is zero.
; ------------------------------------------------------------
ZEROEQW:    LDD   ,U                ; x
            BEQ   ZEQTRUE
            LDD   #FALSEV
            STD   ,U
            RTS
ZEQTRUE:    LDD   #TRUEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; 0<  ( n -- flag )
; True if n is negative.
; ------------------------------------------------------------
ZEROLTW:    LDD   ,U                ; n
            BMI   ZLTTRUE
            LDD   #FALSEV
            STD   ,U
            RTS
ZLTTRUE:    LDD   #TRUEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; U<  ( u1 u2 -- flag )
; True if u1 is less than u2 (unsigned).
; ------------------------------------------------------------
ULESSW:     PULU  D                 ; u2
            STD   MSCR
            LDD   ,U
            CMPD  MSCR
            BLO   ULTRUE
            LDD   #FALSEV
            STD   ,U
            RTS
ULTRUE:     LDD   #TRUEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; <>  ( x1 x2 -- flag )
; True if x1 is not equal to x2 (= then invert).
; ------------------------------------------------------------
NOTEQUALW:  JSR   EQUALW
            LDD   ,U
            COMA
            COMB
            STD   ,U
            RTS

; ------------------------------------------------------------
; 0<>  ( x -- flag )
; True if x is non-zero (0= then invert).
; ------------------------------------------------------------
ZERONEW:    JSR   ZEROEQW
            LDD   ,U
            COMA
            COMB
            STD   ,U
            RTS

; ------------------------------------------------------------
; 0>  ( n -- flag )
; True if n is greater than zero.
; ------------------------------------------------------------
ZEROGTW:    LDD   ,U                ; n
            BEQ   ZGTFALSE
            BMI   ZGTFALSE
            LDD   #TRUEV
            STD   ,U
            RTS
ZGTFALSE:   LDD   #FALSEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; U>  ( u1 u2 -- flag )
; True if u1 is greater than u2 (unsigned).
; ------------------------------------------------------------
UGREATERW:  PULU  D                 ; u2
            STD   MSCR
            LDD   ,U
            CMPD  MSCR
            BLO   UGFALSE
            BEQ   UGFALSE
            LDD   #TRUEV
            STD   ,U
            RTS
UGFALSE:    LDD   #FALSEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; WITHIN  ( n1 n2 n3 -- flag )
; True if n2 <= n1 < n3, evaluated as the unsigned comparison (n1 -
; n2) U< (n3 - n2), so it also works for ranges that wrap.
; ------------------------------------------------------------
WITHINW:    PULU  D                 ; n3
            STD   MSCR
            PULU  D                 ; n2
            STD   MSCR2
            LDD   ,U
            SUBD  MSCR2
            STD   MSCR3
            LDD   MSCR
            SUBD  MSCR2
            STD   MSCR
            LDD   MSCR3
            CMPD  MSCR
            BLO   WITHTRUE
            LDD   #FALSEV
            STD   ,U
            RTS
WITHTRUE:   LDD   #TRUEV
            STD   ,U
            RTS

; ------------------------------------------------------------
; D=  ( d1 d2 -- flag )
; True if the doubles are equal.
; ------------------------------------------------------------
DEQUALW:    PULU  D                 ; d2 high
            STD   MSCR
            PULU  D                 ; d2 low
            STD   MSCR2
            PULU  D                 ; d1 high
            STD   MSCR3
            PULU  D                 ; d1 low
            CMPD  MSCR2
            BNE   DEQFALSE
            LDD   MSCR3
            CMPD  MSCR
            BNE   DEQFALSE
            LDD   #TRUEV
            PSHU  D
            RTS
DEQFALSE:   LDD   #FALSEV
            PSHU  D
            RTS

; ------------------------------------------------------------
; D<  ( d1 d2 -- flag )
; True if d1 is less than d2 (signed): compare the high cells signed,
; then the low cells unsigned.
; ------------------------------------------------------------
DLESSW:     PULU  D                 ; d2 high
            STD   MSCR
            PULU  D                 ; d2 low
            STD   MSCR2
            PULU  D                 ; d1 high
            STD   MSCR3
            PULU  D                 ; d1 low
            STD   MSCR4
            LDD   MSCR3
            CMPD  MSCR
            BLT   DLTRUE
            BGT   DLFALSE
            LDD   MSCR4
            CMPD  MSCR2
            BLO   DLTRUE
DLFALSE:    LDD   #FALSEV
            PSHU  D
            RTS
DLTRUE:     LDD   #TRUEV
            PSHU  D
            RTS

; ------------------------------------------------------------
; DU<  ( ud1 ud2 -- flag )
; True if ud1 is less than ud2 (unsigned).
; ------------------------------------------------------------
DULESSW:    PULU  D                 ; ud2 high
            STD   MSCR
            PULU  D                 ; ud2 low
            STD   MSCR2
            PULU  D                 ; ud1 high
            STD   MSCR3
            PULU  D                 ; ud1 low
            STD   MSCR4
            LDD   MSCR3
            CMPD  MSCR
            BLO   DULTRUE
            BHI   DULFALSE
            LDD   MSCR4
            CMPD  MSCR2
            BLO   DULTRUE
DULFALSE:   LDD   #FALSEV
            PSHU  D
            RTS
DULTRUE:    LDD   #TRUEV
            PSHU  D
            RTS

; ============================================================
; SECTION 18: MEMORY (fetch/store, block ops)
; ============================================================
; ------------------------------------------------------------
; !  ( x a-addr -- )
; Store x at a-addr.
; ------------------------------------------------------------
STOREW:     PULU  X                 ; a-addr
            PULU  D                 ; x
            STD   ,X
            RTS

; ------------------------------------------------------------
; C@  ( c-addr -- char )
; Fetch the byte at c-addr.
; ------------------------------------------------------------
CFETCHW:    PULU  X                 ; c-addr
            LDB   ,X
            CLRA
            PSHU  D
            RTS

; ------------------------------------------------------------
; C!  ( char c-addr -- )
; Store the low byte of char at c-addr.
; ------------------------------------------------------------
CSTOREW:    PULU  X                 ; c-addr
            PULU  D                 ; char
            STB   ,X
            RTS

; ------------------------------------------------------------
; +!  ( n a-addr -- )
; Add n to the cell at a-addr.
; ------------------------------------------------------------
PLUSSTOREW: PULU  X                 ; a-addr
            PULU  D                 ; n
            ADDD  ,X
            STD   ,X
            RTS

; ------------------------------------------------------------
; 2@  ( a-addr -- x1 x2 )
; Fetch the cell pair at a-addr: x2 from a-addr (on top) and x1 from
; a-addr+2.
; ------------------------------------------------------------
DFETCHW:    PULU  X                 ; a-addr. See bugfix: DFETCHW.1
            LDD   2,X
            PSHU  D
            LDD   ,X
            PSHU  D
            RTS

; ------------------------------------------------------------
; 2!  ( x1 x2 a-addr -- )
; Store the cell pair: x2 at a-addr and x1 at a-addr+2.
; ------------------------------------------------------------
DSTOREW:    PULU  X                 ; a-addr
            PULU  D                 ; x2
            STD   ,X
            PULU  D                 ; x1
            STD   2,X
            RTS

; ------------------------------------------------------------
; CMOVE  ( c-addr1 c-addr2 u -- )
; Copy u bytes from c-addr1 to c-addr2, starting at the low addresses.
; ------------------------------------------------------------
CMOVEW:     PULU  D                 ; u
            STD   MVCNT
            PULU  D                 ; c-addr2
            STD   MVDST
            PULU  D                 ; c-addr1
            STD   MVSRC
            LDX   MVSRC
            LDY   MVDST
CMVLOOP:    LDD   MVCNT
            BEQ   CMDONE
            SUBD  #1                ; count - 1. See bugfix: CMOVEW.1
            STD   MVCNT
            LDA   ,X+
            STA   ,Y+
            BRA   CMVLOOP
CMDONE:     RTS

; ------------------------------------------------------------
; CMOVE>  ( c-addr1 c-addr2 u -- )
; Copy u bytes from c-addr1 to c-addr2, starting at the high
; addresses.
; ------------------------------------------------------------
CMOVEGTW:   PULU  D                 ; u
            STD   MVCNT
            PULU  D                 ; c-addr2
            STD   MVDST
            PULU  D                 ; c-addr1
            STD   MVSRC
            LDD   MVCNT
            BEQ   CGDONE
            LDX   MVSRC
            LEAX  D,X
            LEAX  -1,X
            LDY   MVDST
            LEAY  D,Y
            LEAY  -1,Y
CGLOOP:     LDA   ,X
            STA   ,Y
            LEAX  -1,X
            LEAY  -1,Y
            LDD   MVCNT
            SUBD  #1
            STD   MVCNT
            BNE   CGLOOP
CGDONE:     RTS

; ------------------------------------------------------------
; MOVE  ( addr1 addr2 u -- )
; Copy u bytes from addr1 to addr2, choosing CMOVE or CMOVE> so that
; overlapping regions are handled correctly.
; ------------------------------------------------------------
MOVEW:      PULU  D                 ; u
            STD   MVCNT
            PULU  D                 ; addr2
            STD   MVDST
            PULU  D                 ; addr1
            STD   MVSRC
            LDD   MVDST
            CMPD  MVSRC
            BLS   MVLOW
            LDD   MVSRC
            PSHU  D
            LDD   MVDST
            PSHU  D
            LDD   MVCNT
            PSHU  D
            JMP   CMOVEGTW
MVLOW:      LDD   MVSRC
            PSHU  D
            LDD   MVDST
            PSHU  D
            LDD   MVCNT
            PSHU  D
            JMP   CMOVEW

; ------------------------------------------------------------
; FILL  ( c-addr u char -- )
; Store char in each of u bytes starting at c-addr.
; ------------------------------------------------------------
FILLW:      PULU  D                 ; char
            STB   FILLCHR
            PULU  D                 ; u
            TFR   D,Y               ; Y = count. See bugfix: FILLW.1
            PULU  D                 ; c-addr
            TFR   D,X               ; X = address
FILLOOP:    CMPY  #0
            BEQ   FDONE
            LDA   FILLCHR
            STA   ,X+
            LEAY  -1,Y
            BRA   FILLOOP
FDONE:      RTS

; ------------------------------------------------------------
; ERASE  ( c-addr u -- )
; Fill u bytes starting at c-addr with zero.
; ------------------------------------------------------------
ERASEW:     LDD   #0
            PSHU  D
            JMP   FILLW

; ============================================================
; SECTION 19: STRING WORDS
; ============================================================
; ------------------------------------------------------------
; Run-time part of S". The counted string follows the call: push its
; address and length and skip over it.
; DOSTR   ( -- c-addr u )
;    Inputs:
;        return address on S points at the count byte
;    Outputs:
;        c-addr and u on the data stack; execution resumes after the
;        string
;    Registers: RegB, RegD and RegX changed.
; ------------------------------------------------------------
DOSTR:      PULS  X
            LDB   ,X
            LEAX  1,X
            PSHU  X
            CLRA
            PSHU  D
            LEAX  B,X
            PSHS  X
            RTS

; ------------------------------------------------------------
; S"  ( "ccc<quote>" -- c-addr u )
; Parse up to the closing quote. When compiling, compile DOSTR
; followed by the counted string. When interpreting, copy the string
; to PAD and return its address and length.
; A 3-byte gap is reserved at CODEHERE while WORD parses, so that the
; compiled JSR DOSTR does not overwrite the text being staged.
; ------------------------------------------------------------
SQUOTEW:    LDD   #34
            PSHU  D
            LDD   CODEHERE          ; reserve 3 bytes
            ADDD  #3                ; See bugfix: SQUOTEW.1
            STD   CODEHERE
            JSR   WORDW
            PULU  X
            LDA   ,X
            STA   SCNT
            LEAX  1,X
            STX   SPTR
            LDD   CODEHERE          ; restore - undo the temporary reserve
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
SQCPY:      LDA   ,Y+
            STA   ,X+
            DECB
            BNE   SQCPY
SQEND:      STX   CODEHERE
            RTS

            ; Interpreting: copy the string to PAD. Original comment: shadow
            ; SQUOTEW.2.
SQINTERP:
            JSR   PADW
            PULU  X
            STX   MSCR4             ; save PAD address
            LDY   SPTR
            LDB   SCNT
            BEQ   SQIEND
SQICPY:     LDA   ,Y+
            STA   ,X+
            DECB
            BNE   SQICPY
SQIEND:     LDX   MSCR4
            PSHU  X
            CLRA
            LDB   SCNT
            PSHU  D
            RTS

; ------------------------------------------------------------
; Run-time part of ."  The counted string follows the call: TYPE it
; and skip over it.
; DOTSTR
;    Inputs:
;        return address on S points at the count byte
;    Outputs:
;        string displayed; execution resumes after the string
;    Registers: RegB, RegD and RegX changed; SPTR and SCNT used as
;        scratch.
; ------------------------------------------------------------
DOTSTR:     PULS  X
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
            JSR   TYPEW
            RTS

; ------------------------------------------------------------
; ."  ( "ccc<quote>" -- )
; Compile DOTSTR followed by the string up to the closing quote as a
; counted string.
; ------------------------------------------------------------
DOTQUOTEW:  LDD   #34
            PSHU  D
            LDD   CODEHERE          ; reserve 3 bytes
            ADDD  #3                ; See bugfix: DOTQUOTEW.1
            STD   CODEHERE
            JSR   WORDW
            PULU  X
            LDA   ,X
            STA   SCNT
            LEAX  1,X
            STX   SPTR
            LDD   CODEHERE          ; restore
            SUBD  #3
            STD   CODEHERE
            LDD   #DOTSTR
            PSHU  D
            JSR   CCALL
            LDX   CODEHERE
            LDA   SCNT
            STA   ,X+
            LDY   SPTR
            LDB   SCNT
            BEQ   DQEND
DQCPY:      LDA   ,Y+
            STA   ,X+
            DECB
            BNE   DQCPY
DQEND:      STX   CODEHERE
            RTS

; ------------------------------------------------------------
; TYPE  ( c-addr u -- )
; Display u characters starting at c-addr, through EMIT.
; ------------------------------------------------------------
TYPEW:      PULU  D                 ; u
            STD   TYPECNT
            PULU  D                 ; c-addr
            STD   TYPEADDR
TYLOOP:     LDD   TYPECNT
            BEQ   TYDONE
            LDX   TYPEADDR
            LDA   ,X+
            STX   TYPEADDR
            TFR   A,B
            CLRA
            PSHU  D
            JSR   EMITW
            LDD   TYPECNT
            SUBD  #1
            STD   TYPECNT
            BRA   TYLOOP
TYDONE:     RTS

; ------------------------------------------------------------
; COUNT  ( c-addr1 -- c-addr2 u )
; Convert a counted string to its address and length.
; ------------------------------------------------------------
COUNTW:     PULU  X                 ; c-addr1
            LDB   ,X
            CLRA
            STD   MSCR
            LEAX  1,X
            PSHU  X
            LDD   MSCR
            PSHU  D
            RTS

; ------------------------------------------------------------
; CHAR  ( "name" -- char )
; Parse the next blank-delimited name and return its first character.
; ------------------------------------------------------------
CHARW:      LDD   #32
            PSHU  D
            JSR   WORDW
            PULU  X
            LDB   1,X
            CLRA
            PSHU  D
            RTS

; ------------------------------------------------------------
; [CHAR]  ( "name" -- )
; Compile the first character of the next name as a literal. THROW -14
; if not compiling.
; ------------------------------------------------------------
BRACKCHARW: LDD   STATE
            BNE   BCSTOK
            LDD   #-14              ; -14
            PSHU  D
            JSR   THROW
BCSTOK:     LDD   #32
            PSHU  D
            JSR   WORDW
            PULU  X
            LDB   1,X
            CLRA
            PSHU  D
            JSR   LITERALW
            RTS

; ------------------------------------------------------------
; PARSE  ( char "ccc<char>" -- c-addr u )
; Parse the input up to the delimiter char (which is consumed) and
; return the parsed text. A >IN beyond the end of the input is treated
; as an exhausted input (empty result).
; ------------------------------------------------------------
PARSEW:     PULU  D                 ; char
            STB   PDELIM
            LDD   TOIN
            LDX   SRCADDR
            LEAX  D,X
            STX   PSTART
            LDD   SRCLEN
            SUBD  TOIN
            LBLO  PNEMPTY           ; See bugfix: PARSEW.1
            TFR   D,Y
            LDD   #0
            STD   PLEN
PSCAN:      CMPY  #0
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
PFOUND:     LEAX  1,X
            LEAY  -1,Y
PDONE:      TFR   X,D
            SUBD  SRCADDR
            STD   TOIN
            LDX   PSTART
            PSHU  X
            LDD   PLEN
            PSHU  D
            RTS

; ------------------------------------------------------------
; PARSE-NAME  ( "<spaces>name<space>" -- c-addr u )
; Skip leading blanks, then parse a blank-delimited name and return
; it. An empty result is returned at the end of the input.
; ------------------------------------------------------------
PARSENAMEW: LDD   TOIN
            LDX   SRCADDR
            LEAX  D,X
            LDD   SRCLEN
            SUBD  TOIN
            BLO   PNEMPTY           ; See bugfix: PARSENAMEW.1
            TFR   D,Y
PNSKIP:     CMPY  #0
            BEQ   PNEMPTY
            LDA   ,X
            CMPA  #32
            BNE   PNSTART
            LEAX  1,X
            LEAY  -1,Y
            BRA   PNSKIP
PNSTART:    STX   PSTART
            LDD   #0
            STD   PLEN
PNSCAN:     CMPY  #0
            BEQ   PNDONE
            LDA   ,X
            CMPA  #32
            BEQ   PNFOUND
            LEAX  1,X
            LEAY  -1,Y
            LDD   PLEN
            ADDD  #1
            STD   PLEN
            BRA   PNSCAN
PNFOUND:    LEAX  1,X
            LEAY  -1,Y
PNDONE:     TFR   X,D
            SUBD  SRCADDR
            STD   TOIN
            LDX   PSTART
            PSHU  X
            LDD   PLEN
            PSHU  D
            RTS
PNEMPTY:    LDD   SRCLEN
            LDX   SRCADDR
            LEAX  D,X
            STD   TOIN
            PSHU  X
            LDD   #0
            PSHU  D
            RTS

; ------------------------------------------------------------
; /STRING  ( c-addr1 u1 n -- c-addr2 u2 )
; Remove n characters from the start of the string.
; ------------------------------------------------------------
SLASHSTRINGW:
            PULU  D                 ; n
            STD   MSCR
            PULU  D
            SUBD  MSCR
            STD   MSCR2
            PULU  D
            ADDD  MSCR
            PSHU  D
            LDD   MSCR2
            PSHU  D
            RTS

; ------------------------------------------------------------
; -TRAILING  ( c-addr u1 -- c-addr u2 )
; Reduce the length to exclude trailing blanks.
; ------------------------------------------------------------
DASHTRAILINGW:
            LDD   ,U
            STD   PLEN
DTLOOP:     LDD   PLEN
            BEQ   DTDONE
            LDX   2,U
            LEAX  D,X
            LEAX  -1,X
            LDA   ,X
            CMPA  #32
            BNE   DTDONE
            LDD   PLEN
            SUBD  #1
            STD   PLEN
            BRA   DTLOOP
DTDONE:     LDD   PLEN
            STD   ,U
            RTS

; ------------------------------------------------------------
; COMPARE  ( c-addr1 u1 c-addr2 u2 -- n )
; Compare two strings byte by byte. n is -1, 0 or 1 as the first
; string is less than, equal to or greater than the second; if one is
; a prefix of the other, the shorter is less.
; ------------------------------------------------------------
COMPAREW:   PULU  D                 ; u2
            STD   CMPL2
            PULU  D                 ; c-addr2
            STD   CMPA2
            PULU  D                 ; u1
            STD   CMPL1
            PULU  D                 ; c-addr1
            STD   CMPA1
            LDD   CMPL1
            CMPD  CMPL2
            BLS   CMMINIS1
            LDD   CMPL2
            BRA   CMMINSET
CMMINIS1:   LDD   CMPL1
CMMINSET:   STD   CMPMIN
            LDX   CMPA1
            LDY   CMPA2
CMPLOOP:    LDD   CMPMIN
            BEQ   CMTIEBREAK
            LDA   ,X+
            CMPA  ,Y
            BLO   CMLT
            BHI   CMGT
            LEAY  1,Y
            LDD   CMPMIN
            SUBD  #1
            STD   CMPMIN
            BRA   CMPLOOP
CMTIEBREAK: LDD   CMPL1
            CMPD  CMPL2
            BLO   CMLT
            BHI   CMGT
            LDD   #0
            PSHU  D
            RTS
CMLT:       LDD   #-1
            PSHU  D
            RTS
CMGT:       LDD   #1
            PSHU  D
            RTS

; ------------------------------------------------------------
; SEARCH  ( c-addr1 u1 c-addr2 u2 -- c-addr3 u3 flag )
; Search the string c-addr1 u1 for the string c-addr2 u2. If found,
; return the address and remaining length of the match and true;
; otherwise return the original string and false.
; ------------------------------------------------------------
SEARCHW:    PULU  D                 ; u2
            STD   SRCH2L
            PULU  D                 ; c-addr2
            STD   SRCH2
            PULU  D                 ; u1
            STD   SRCH1L
            PULU  D                 ; c-addr1
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
SPOSLOOP:   LDD   SRCHI
            CMPD  SRCHPOS
            BEQ   SRCHNOTFOUND
            LDX   SRCH1
            LDD   SRCHI
            LEAX  D,X
            LDY   SRCH2
            LDD   SRCH2L
            STD   MSCR3
SMATCH:     LDD   MSCR3
            BEQ   SFOUND
            LDA   ,X+
            CMPA  ,Y+
            BNE   SNOMATCH
            LDD   MSCR3
            SUBD  #1
            STD   MSCR3
            BRA   SMATCH
SNOMATCH:   LDD   SRCHI
            ADDD  #1
            STD   SRCHI
            BRA   SPOSLOOP
SFOUND:     LDX   SRCH1
            LDD   SRCHI
            LEAX  D,X
            PSHU  X
            LDD   SRCH2L
            PSHU  D
            LDD   #TRUEV
            PSHU  D
            RTS
SRCHNOTFOUND:
            LDD   SRCH1
            PSHU  D
            LDD   SRCH1L
            PSHU  D
            LDD   #FALSEV
            PSHU  D
            RTS

; ------------------------------------------------------------
; SNAME  ( xt -- c-addr u | 0 0 )
; Find the name of the word whose xt is given by searching the
; dictionary from LATEST. Return the name or two zeros if not found.
; ------------------------------------------------------------
SNAMEW:     PULU  D                 ; xt
            STD   SNTARGET
            LDD   LATEST
            STD   SNXT
SNLOOP:     LDD   SNXT
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
SNFOUND:    LDX   SNXT
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
SNNOTFOUND: LDD   #0
            PSHU  D
            PSHU  D
            RTS

; ------------------------------------------------------------
; UNESCAPE  ( c-addr1 u1 c-addr2 -- c-addr2 u2 )
; Copy the string c-addr1 u1 to c-addr2, doubling every "%" so that
; SUBSTITUTE turns it back into the original. u2 is the length of the
; result.
; ------------------------------------------------------------
UNESCAPEW:  PULU  D                 ; c-addr2 (destination)
            STD   UEDST             ; See bugfix: UNESCAPEW.1
            PULU  D                 ; u1
            STD   UESRCLEN
            PULU  D                 ; c-addr1
            STD   UEADDR
            LDD   #0
            STD   UEOUTLEN
            LDX   UEADDR
            LDY   UEDST

            ; Double every %; copy all other characters unchanged.
            ; See bugfix: UNESCAPEW.2
UELOOP:     LDD   UESRCLEN
            BEQ   UEDONE
            LDA   ,X+
            CMPA  #'%'
            BNE   UENOTPCT
            LDB   #'%'              ; extra % written first
            STB   ,Y+
UENOTPCT:   STA   ,Y+               ; write the character
            LDD   UESRCLEN
            SUBD  #1
            STD   UESRCLEN
            BRA   UELOOP
UEDONE:     TFR   Y,D               ; See bugfix: UNESCAPEW.4
            SUBD  UEDST             ; u2 = end - destination
            STD   UEOUTLEN
            LDD   UEDST
            PSHU  D                 ; push c-addr2 (destination address)
            LDD   UEOUTLEN
            PSHU  D                 ; push u2 (actual unescaped length)
            RTS

; ------------------------------------------------------------
; REPLACES  ( c-addr1 u1 c-addr2 u2 -- )
; Register the substitution text c-addr1 u1 for the name c-addr2 u2.
; Only one registration is kept (a single slot); a new call replaces
; the previous one. The strings are not copied.
; Original comment: shadow REPLACESW.0.
; ------------------------------------------------------------
REPLACESW:  PULU  D                 ; u2
            STD   REPLNLEN
            PULU  D                 ; c-addr2
            STD   REPLNAME
            PULU  D                 ; u1
            STD   REPLVLEN
            PULU  D                 ; c-addr1
            STD   REPLVAL
            RTS

; ------------------------------------------------------------
; Append bytes to the SUBSTITUTE output buffer. THROW -1 if the buffer
; would overflow.
; SUBCOPY
;    Inputs:
;        RegD = byte count, RegX = source address
;    Outputs:
;        bytes appended at SUBWPTR; SUBOUTLEN and SUBWPTR advanced
;    Registers: RegA, RegD, RegX and RegY changed; SUBCOPYCNT and
;        SUBCOPYSRC used.
; ------------------------------------------------------------
SUBCOPY:    STD   SUBCOPYCNT
            STX   SUBCOPYSRC
SUBCPLP:    LDD   SUBCOPYCNT
            BEQ   SUBCPDONE
            LDD   SUBOUTLEN
            CMPD  SUBDESTCAP
            LBHS  SUBOVERFLOW       ; buffer full: THROW -1
            LDX   SUBCOPYSRC
            LDA   ,X+
            STX   SUBCOPYSRC
            LDY   SUBWPTR
            STA   ,Y+
            STY   SUBWPTR
            LDD   SUBOUTLEN
            ADDD  #1
            STD   SUBOUTLEN
            LDD   SUBCOPYCNT
            SUBD  #1
            STD   SUBCOPYCNT
            BRA   SUBCPLP
SUBCPDONE:  RTS

; ------------------------------------------------------------
; SUBSTITUTE  ( c-addr1 u1 c-addr2 u2 -- c-addr2 u3 n )
; Copy the template c-addr1 u1 to the buffer c-addr2 u2, replacing
; each %name% that matches the name registered by REPLACES with its
; text. "%%" becomes a single "%"; a %name% that does not match, and
; an unpaired "%", are copied unchanged. u3 is the output length and n
; the number of substitutions. THROW -1 if the output does not fit.
; Scratch: MSCR = read position, MSCR2 = substitution count, MSCR3 and
; MSCR4 = temporaries for each %-pair. Original comment: shadow
; SUBSTITUTEW.1.
; ------------------------------------------------------------
SUBSTITUTEW:
            PULU  D                 ; u2
            STD   SUBDESTCAP
            PULU  D                 ; c-addr2
            STD   SUBDESTADR
            PULU  D                 ; u1
            STD   SUBSRCLEN
            PULU  D                 ; c-addr1
            STD   SUBSRCADR

            LDY   SUBDESTADR
            STY   SUBWPTR
            LDD   #0
            STD   SUBOUTLEN
            STD   MSCR              ; read position, starts at 0
            STD   MSCR2             ; substitution count, starts at 0

SUBSCAN:    LDD   MSCR
            CMPD  SUBSRCLEN
            LBHS  SUBSDONE
            LDX   SUBSRCADR
            LEAX  D,X
            LDA   ,X
            CMPA  #$25              ; '%' delimiter
            BEQ   SUBPCT
            LDD   #1
            JSR   SUBCOPY
            LDD   MSCR
            ADDD  #1
            STD   MSCR
            LBRA  SUBSCAN

SUBPCT:     LDD   MSCR
            ADDD  #1
            STD   MSCR3             ; scan for the closing '%'
SUBFINDCL:  LDD   MSCR3
            CMPD  SUBSRCLEN
            BLO   SUBFC2
            ; no closing delimiter found - residue passed unchanged
            LDD   MSCR
            LDX   SUBSRCADR
            LEAX  D,X
            LDD   SUBSRCLEN
            SUBD  MSCR
            JSR   SUBCOPY
            LDD   SUBSRCLEN
            STD   MSCR
            LBRA  SUBSCAN
SUBFC2:     LDD   MSCR3
            LDX   SUBSRCADR
            LEAX  D,X
            LDA   ,X
            CMPA  #$25
            BEQ   SUBFOUNDCL
            LDD   MSCR3
            ADDD  #1
            STD   MSCR3
            LBRA  SUBFINDCL

SUBFOUNDCL: LDD   MSCR3
            SUBD  MSCR
            SUBD  #1
            STD   MSCR4             ; enclosed name length
            LBNE  SUBHASNAME
            ; namelen 0: "%%" -> single '%' to output, count unchanged
            LDD   MSCR
            LDX   SUBSRCADR
            LEAX  D,X
            LDD   #1
            JSR   SUBCOPY
            LDD   MSCR3
            ADDD  #1
            STD   MSCR
            LBRA  SUBSCAN

SUBHASNAME: LDD   MSCR
            ADDD  #1
            LDX   SUBSRCADR
            LEAX  D,X
            PSHU  X
            LDD   MSCR4
            PSHU  D
            LDD   REPLNAME
            PSHU  D
            LDD   REPLNLEN
            PSHU  D
            JSR   COMPAREW
            PULU  D
            CMPD  #0
            BNE   SUBNOMATCH
            ; valid name - replace the whole %name% span
            LDX   REPLVAL
            LDD   REPLVLEN
            JSR   SUBCOPY
            LDD   MSCR2
            ADDD  #1
            STD   MSCR2
            LDD   MSCR3
            ADDD  #1
            STD   MSCR
            LBRA  SUBSCAN

            ; Not a registered name: pass %name% through unchanged.
SUBNOMATCH:
            LDD   MSCR
            LDX   SUBSRCADR
            LEAX  D,X
            LDD   MSCR3
            SUBD  MSCR
            ADDD  #1
            JSR   SUBCOPY
            LDD   MSCR3
            ADDD  #1
            STD   MSCR
            LBRA  SUBSCAN

SUBSDONE:   LDX   SUBDESTADR
            PSHU  X
            LDD   SUBOUTLEN
            PSHU  D
            LDD   MSCR2
            PSHU  D
            RTS

            ; The output buffer is too small: THROW -1.
SUBOVERFLOW:
            LDD   #-1
            PSHU  D
            JSR   THROW

; ============================================================
; SECTION 20: NUMERIC OUTPUT (pictured + direct)
; ============================================================
; ------------------------------------------------------------
; <#  ( -- )
; Start a pictured numeric output string: HLD is set to the end of
; PAD. The string is built backwards from there.
; ------------------------------------------------------------
LTNUMW:     JSR   PADW
            PULU  D
            STD   HLD
            RTS

; ------------------------------------------------------------
; HOLD  ( char -- )
; Add char to the front of the pictured numeric output string.
; ------------------------------------------------------------
HOLDW:      PULU  D                 ; char
            LDX   HLD
            LEAX  -1,X
            STX   HLD
            STB   ,X
            RTS

; ------------------------------------------------------------
; HOLDS  ( c-addr u -- )
; Add the string c-addr u to the front of the pictured numeric output
; string.
; ------------------------------------------------------------
HOLDSW:     PULU  D                 ; u
            STD   HSLEN
            PULU  D                 ; c-addr
            STD   HSADDR
HSLOOP:     LDD   HSLEN
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
            JSR   HOLDW
            BRA   HSLOOP
HSDONE:     RTS

; ------------------------------------------------------------
; #  ( ud1 -- ud2 )
; Divide ud1 by BASE, add the remainder as a digit to the pictured
; numeric output string, and leave the quotient ud2.
; ------------------------------------------------------------
NUMSIGNW:   PULU  D                 ; ud1 high
            STD   UDHI
            PULU  D                 ; ud1 low
            STD   UDLO
            JSR   UDDIGIT
            LDA   REM
            CMPA  #10
            BLO   NDIGIT
            ADDA  #'A'-10
            BRA   NHOLD
NDIGIT:     ADDA  #'0'
NHOLD:      TFR   A,B
            CLRA
            PSHU  D
            JSR   HOLDW
            LDD   UDLO
            PSHU  D
            LDD   UDHI
            PSHU  D
            RTS

; ------------------------------------------------------------
; Divide the unsigned double UDHI:UDLO by BASE (restoring division, 32
; iterations). Only the low byte of BASE is used.
; UDDIGIT
;    Inputs:
;        UDHI:UDLO = dividend
;    Outputs:
;        UDHI:UDLO = quotient, REM = remainder
;    Registers: RegA and RegB changed; DCNT used as the loop counter.
; ------------------------------------------------------------
UDDIGIT:    CLR   REM
            LDB   #32
            STB   DCNT
UDDLOOP:    ASL   UDLO+1
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
UDNEXT:     DEC   DCNT
            BNE   UDDLOOP
            RTS

; ------------------------------------------------------------
; #S  ( ud -- 0 0 )
; Convert digits with # until the quotient is zero (at least one digit
; is produced).
; ------------------------------------------------------------
NUMSIGNSW:  JSR   NUMSIGNW
            LDD   UDHI
            BNE   NUMSIGNSW
            LDD   UDLO
            BNE   NUMSIGNSW
            RTS

; ------------------------------------------------------------
; SIGN  ( n -- )
; If n is negative, add a minus sign to the pictured numeric output
; string.
; ------------------------------------------------------------
SIGNW:      PULU  D                 ; n
            TSTA                    ; sign of n. See bugfix: SIGNW.1
            BPL   SIGNDONE
            LDD   #'-'
            PSHU  D
            JSR   HOLDW
SIGNDONE:   RTS

; ------------------------------------------------------------
; #>  ( xd -- c-addr u )
; Drop xd and return the pictured numeric output string.
; ------------------------------------------------------------
NUMGTW:     PULU  D                 ; xd high
            PULU  D                 ; xd low
            LDX   HLD
            PSHU  X
            JSR   PADW
            PULU  D
            SUBD  HLD
            PSHU  D
            RTS

; ------------------------------------------------------------
; .  ( n -- )
; Display n in the current base, followed by a space.
; ------------------------------------------------------------
DOTW:       PULU  D                 ; n
            STD   SAVEN
            BPL   DABSOK
            COMA
            COMB
            ADDD  #1
DABSOK:     PSHU  D
            LDD   #0
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSIGNSW
            LDD   SAVEN
            PSHU  D
            JSR   SIGNW
            JSR   NUMGTW
            JSR   TYPEW
            LDD   #32
            PSHU  D
            JSR   EMITW
            RTS

; ------------------------------------------------------------
; U.  ( u -- )
; Display u in the current base, followed by a space.
; ------------------------------------------------------------
UDOTW:      LDD   #0                ; ud high cell = 0
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSIGNSW
            JSR   NUMGTW
            JSR   TYPEW
            LDD   #32
            PSHU  D
            JSR   EMITW
            RTS

; ------------------------------------------------------------
; .R  ( n1 n2 -- )
; Display n1 right-justified in a field of n2 characters.
; ------------------------------------------------------------
DOTRW:      PULU  D                 ; n2 (width)
            STD   DRWIDTH
            PULU  D                 ; n1
            STD   SAVEN
            BPL   DRABSOK
            COMA
            COMB
            ADDD  #1
DRABSOK:    PSHU  D
            LDD   #0
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSIGNSW
            LDD   SAVEN
            PSHU  D
            JSR   SIGNW
            JSR   NUMGTW
            PULU  D
            STD   DRLEN
            PULU  D
            STD   DRADDR
            LDD   DRWIDTH
            SUBD  DRLEN
            BLE   DRNOPAD
            STD   DRPAD
DRPADLP:    LDD   DRPAD
            BEQ   DRNOPAD
            SUBD  #1
            STD   DRPAD
            LDD   #32
            PSHU  D
            JSR   EMITW
            BRA   DRPADLP
DRNOPAD:    LDX   DRADDR
            PSHU  X
            LDD   DRLEN
            PSHU  D
            JSR   TYPEW
            RTS

; ------------------------------------------------------------
; U.R  ( u n -- )
; Display u right-justified in a field of n characters.
; ------------------------------------------------------------
UDOTRW:     PULU  D                 ; n (width)
            STD   DRWIDTH
            LDD   #0                ; ud high cell = 0
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSIGNSW
            JSR   NUMGTW
            PULU  D
            STD   DRLEN
            PULU  D
            STD   DRADDR
            LDD   DRWIDTH
            SUBD  DRLEN
            BLE   UDRNOPAD
            STD   DRPAD
UDRPADLP:   LDD   DRPAD
            BEQ   UDRNOPAD
            SUBD  #1
            STD   DRPAD
            LDD   #32
            PSHU  D
            JSR   EMITW
            BRA   UDRPADLP
UDRNOPAD:   LDX   DRADDR
            PSHU  X
            LDD   DRLEN
            PSHU  D
            JSR   TYPEW
            RTS

; ------------------------------------------------------------
; ?  ( a-addr -- )
; Display the cell at a-addr.
; ------------------------------------------------------------
QMARKW:     PULU  X                 ; a-addr
            LDD   ,X
            PSHU  D
            JSR   DOTW
            RTS

; ------------------------------------------------------------
; D.  ( d -- )
; Display the double d in the current base, followed by a space.
; ------------------------------------------------------------
DDOTW:      PULU  D                 ; d high
            STD   PRODHI
            PULU  D                 ; d low
            STD   PRODLO
            LDD   PRODHI
            STD   SAVEN
            BPL   DDPOS
            JSR   MNEG32
DDPOS:      LDD   PRODLO
            PSHU  D
            LDD   PRODHI
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSIGNSW
            LDD   SAVEN
            PSHU  D
            JSR   SIGNW
            JSR   NUMGTW
            JSR   TYPEW
            LDD   #32
            PSHU  D
            JSR   EMITW
            RTS

; ------------------------------------------------------------
; D.R  ( d n -- )
; Display the double d right-justified in a field of n characters.
; ------------------------------------------------------------
DDOTRW:     PULU  D                 ; n (width)
            STD   DRWIDTH
            PULU  D                 ; d high
            STD   PRODHI
            PULU  D                 ; d low
            STD   PRODLO
            LDD   PRODHI
            STD   SAVEN
            BPL   DDRPOS
            JSR   MNEG32
DDRPOS:     LDD   PRODLO
            PSHU  D
            LDD   PRODHI
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSIGNSW
            LDD   SAVEN
            PSHU  D
            JSR   SIGNW
            JSR   NUMGTW
            PULU  D
            STD   DRLEN
            PULU  D
            STD   DRADDR
            LDD   DRWIDTH
            SUBD  DRLEN
            BLE   DRDNOPAD
            STD   DRPAD
DRDPADLP:   LDD   DRPAD
            BEQ   DRDNOPAD
            SUBD  #1
            STD   DRPAD
            LDD   #32
            PSHU  D
            JSR   EMITW
            BRA   DRDPADLP
DRDNOPAD:   LDX   DRADDR
            PSHU  X
            LDD   DRLEN
            PSHU  D
            JSR   TYPEW
            RTS

; ============================================================
; SECTION 21: BASE / RADIX CONTROL
; ============================================================
; ------------------------------------------------------------
; BASE  ( -- a-addr )
; Push the address of the BASE variable.
; ------------------------------------------------------------
BASEW:      LDD   #BASE             ; a-addr
            PSHU  D
            RTS

; ------------------------------------------------------------
; DECIMAL  ( -- )
; Set BASE to 10.
; ------------------------------------------------------------
DECIMALW:   LDD   #10
            STD   BASE
            RTS

; ------------------------------------------------------------
; HEX  ( -- )
; Set BASE to 16.
; ------------------------------------------------------------
HEXW:       LDD   #16
            STD   BASE
            RTS

; ------------------------------------------------------------
; BINARY  ( -- )
; Set BASE to 2.
; ------------------------------------------------------------
BINARYW:    LDD   #2
            STD   BASE
            RTS

; ============================================================
; SECTION 22: OUTPUT FORMATTING (CR/SPACE/SPACES)
; ============================================================
; ------------------------------------------------------------
; CR  ( -- )
; Send carriage return and line feed.
; ------------------------------------------------------------
CRW:        LDD   #13
            PSHU  D
            JSR   EMITW
            LDD   #10
            PSHU  D
            JSR   EMITW
            RTS

; ------------------------------------------------------------
; SPACE  ( -- )
; Send one space.
; ------------------------------------------------------------
SPACEW:     LDD   #32
            PSHU  D
            JSR   EMITW
            RTS

; ------------------------------------------------------------
; SPACES  ( n -- )
; Send n spaces (nothing if n is zero or negative).
; ------------------------------------------------------------
SPACESW:    PULU  D                 ; n
            STD   SHCNT2
SPLOOP:     LDD   SHCNT2
            BLE   SPDONE
            LDD   #32
            PSHU  D
            JSR   EMITW
            LDD   SHCNT2
            SUBD  #1
            STD   SHCNT2
            BRA   SPLOOP
SPDONE:     RTS

; ============================================================
; SECTION 23: COMMENT WORDS
; ============================================================
; ------------------------------------------------------------
; (  ( "ccc<paren>" -- )
; Parse and discard text up to the closing parenthesis.
; ------------------------------------------------------------
LPARENW:    LDD   #')'
            PSHU  D
            JSR   WORDW
            PULU  D                 ; discard c-addr. See bugfix: LPARENW.1
            RTS

; ------------------------------------------------------------
; \  ( "ccc<eol>" -- )
; Discard the rest of the input line by setting >IN to the source
; length.
; ------------------------------------------------------------
BACKSLASHW: LDD   SRCLEN
            STD   TOIN
            RTS

; ============================================================
; SECTION 24: ENVIRONMENTAL QUERY / SOURCE / REFILL / EVALUATE
; ============================================================
; ------------------------------------------------------------
; SOURCE  ( -- c-addr u )
; Push the address and length of the current input source.
; ------------------------------------------------------------
SOURCEW:    LDD   SRCADDR
            PSHU  D
            LDD   SRCLEN
            PSHU  D
            RTS

; ------------------------------------------------------------
; SOURCE-ID  ( -- 0 | -1 )
; Push 0 for the terminal, -1 for a string being EVALUATEd.
; ------------------------------------------------------------
SOURCEIDW:  LDD   SRCID
            PSHU  D
            RTS

; ------------------------------------------------------------
; REFILL  ( -- flag )
; From the terminal, read a new line with QUERY and return true. From
; an EVALUATEd string, return false.
; ------------------------------------------------------------
REFILLW:    LDD   SRCID
            BEQ   RFTERM
            LDD   #FALSEV
            PSHU  D
            RTS
RFTERM:     JSR   QUERYW
            LDD   #TRUEV
            PSHU  D
            RTS

; ------------------------------------------------------------
; EVALUATE  ( c-addr u -- )
; Interpret the string c-addr u as the input source, then restore the
; previous input source (kept on the return stack).
; ------------------------------------------------------------
EVALUATEW:  LDD   SRCADDR           ; save the input source on S
            PSHS  D                 ; See bugfix: EVALUATEW.1
            LDD   SRCLEN
            PSHS  D
            LDD   SRCID
            PSHS  D
            LDD   TOIN
            PSHS  D
            PULU  D                 ; u
            STD   SRCLEN
            PULU  D                 ; c-addr
            STD   SRCADDR
            LDD   #-1
            STD   SRCID
            LDD   #0
            STD   TOIN
            JSR   INTERPRET
            PULS  D
            STD   TOIN
            PULS  D
            STD   SRCID
            PULS  D
            STD   SRCLEN
            PULS  D
            STD   SRCADDR
            RTS

; ------------------------------------------------------------
; ENVIRONMENT?  ( c-addr u -- false | i*x true )
; Look up the attribute name c-addr u first in ENVTABLE (single-cell
; values), then in ENVTABLE2 (double-cell values). If found, return
; the value and true; otherwise return false. WORDLISTS is
; deliberately absent because the Search-Order word set is not
; implemented. FLOORED is false because /, MOD and /MOD use symmetric
; division.
; Original comment: shadow ENVQUERYW.0.
; ------------------------------------------------------------
ENVQUERYW:  PULU  D                 ; u
            STD   ENVLEN
            PULU  D                 ; c-addr
            STD   ENVADDR
            LDX   #ENVTABLE
ENVLOOP:    LDD   ,X
            CMPD  #0
            BEQ   ENV2START         ; end of table: try ENVTABLE2
            PSHS  X                 ; See bugfix: ENVQUERYW.2
            PSHU  D
            LDD   2,X
            PSHU  D
            LDD   ENVADDR
            PSHU  D
            LDD   ENVLEN
            PSHU  D
            JSR   COMPAREW
            PULS  X                 ; restore X before using it again
            PULU  D
            CMPD  #0
            BEQ   ENVFOUND
            LEAX  6,X
            BRA   ENVLOOP
ENVFOUND:   LDD   4,X
            PSHU  D
            LDD   #TRUEV
            PSHU  D
            RTS

ENV2START:  LDX   #ENVTABLE2        ; double-cell table
ENV2LOOP:   LDD   ,X
            CMPD  #0
            BEQ   ENVNOTFOUND
            PSHS  X                 ; See bugfix: ENVQUERYW.2
            PSHU  D
            LDD   2,X
            PSHU  D
            LDD   ENVADDR
            PSHU  D
            LDD   ENVLEN
            PSHU  D
            JSR   COMPAREW
            PULS  X
            PULU  D
            CMPD  #0
            BEQ   ENV2FOUND
            LEAX  8,X               ; 8-byte entries
            BRA   ENV2LOOP
ENV2FOUND:  LDD   4,X               ; low cell, pushed first
            PSHU  D
            LDD   6,X               ; high cell - pushed second/top
            PSHU  D
            LDD   #TRUEV
            PSHU  D
            RTS

ENVNOTFOUND:
            LDD   #FALSEV
            PSHU  D
            RTS

; ------------------------------------------------------------
; ENVTABLE2
; Double-cell ENVIRONMENT? entries: name address, name length, low
; cell, high cell. A zero ends the table.
; ------------------------------------------------------------
ENVTABLE2:
            FDB   EN11,EN11L,$FFFF,$7FFF
                                    ; MAX-D
            FDB   EN12,EN12L,$FFFF,$FFFF
                                    ; MAX-UD
            FDB   0
EN11:       FCC   "MAX-D"
EN11L       EQU   *-EN11
EN12:       FCC   "MAX-UD"
EN12L       EQU   *-EN12

; ------------------------------------------------------------
; ENVTABLE
; Single-cell ENVIRONMENT? entries: name address, name length, value.
; A zero ends the table.
; ------------------------------------------------------------
ENVTABLE:
            FDB   EN1,EN1L,255      ; /COUNTED-STRING. See bugfix: ENVTABLE.1
            FDB   EN2,EN2L,32767    ; MAX-N
            FDB   EN3,EN3L,65535    ; MAX-U
            FDB   EN6,EN6L,8        ; ADDRESS-UNIT-BITS
            FDB   EN7,EN7L,HOLDMINSIZE
                                    ; /HOLD
            FDB   EN8,EN8L,PADMINSIZE
                                    ; /PAD
            FDB   EN9,EN9L,0        ; FLOORED = false
            FDB   EN10,EN10L,255    ; MAX-CHAR
            FDB   EN13,EN13L,(RSTACK-DSTACK)/2
                                    ; RETURN-STACK-CELLS
            FDB   EN14,EN14L,(DSTACK-CODETOP+1)/2
                                    ; STACK-CELLS
            FDB   0
EN1:        FCC   "/COUNTED-STRING"
EN1L        EQU   *-EN1
EN2:        FCC   "MAX-N"
EN2L        EQU   *-EN2
EN3:        FCC   "MAX-U"
EN3L        EQU   *-EN3
EN6:        FCC   "ADDRESS-UNIT-BITS"
EN6L        EQU   *-EN6
EN7:        FCC   "/HOLD"
EN7L        EQU   *-EN7
EN8:        FCC   "/PAD"
EN8L        EQU   *-EN8
EN9:        FCC   "FLOORED"
EN9L        EQU   *-EN9
EN10:       FCC   "MAX-CHAR"
EN10L       EQU   *-EN10
EN13:       FCC   "RETURN-STACK-CELLS"
EN13L       EQU   *-EN13
EN14:       FCC   "STACK-CELLS"
EN14L       EQU   *-EN14

; ============================================================
; SECTION 25: TOOLS WORD SET (.S / WORDS / DUMP)
; ============================================================
; ------------------------------------------------------------
; .S  ( -- )
; Display every cell on the data stack, top first, each followed by a
; space, using ".". The stack is not changed.
; ------------------------------------------------------------
DOTSW:      TFR   U,D
            STD   DSPTMP
DSLOOP:     LDD   DSPTMP
            CMPD  #SP0
            BEQ   DSDONE
            LDX   DSPTMP
            LDD   ,X
            PSHU  D
            JSR   DOTW
            LDD   DSPTMP
            ADDD  #2
            STD   DSPTMP
            BRA   DSLOOP
DSDONE:     RTS

; ------------------------------------------------------------
; WORDS  ( -- )
; Display the names of all dictionary words, newest first, then a
; carriage return.
; ------------------------------------------------------------
WORDSW:     LDD   LATEST
            STD   WWALK
WWLOOP:     LDD   WWALK
            BEQ   WWDONE
            LDX   WWALK
            LDA   ,X
            STA   HDRFLAGS
            LEAX  1,X
            PSHU  X
            LDB   HDRFLAGS
            ANDB  #$1F
            CLRA
            PSHU  D
            JSR   TYPEW
            JSR   SPACEW
            LDX   WWALK
            LEAX  1,X
            LDB   HDRFLAGS
            ANDB  #$1F
            CLRA
            LEAX  D,X
            LDD   ,X
            STD   WWALK
            BRA   WWLOOP
WWDONE:     JSR   CRW
            RTS

; ------------------------------------------------------------
; Display one hexadecimal digit.
; HEXDIGIT   ( n -- )
;    Inputs:
;        n (0 to 15) on the data stack
;    Outputs:
;        the digit sent with EMIT
;    Registers: RegD changed.
; ------------------------------------------------------------
HEXDIGIT:   PULU  D
            CMPD  #10
            BLO   HDDIGIT
            ADDD  #'A'-10
            BRA   HDEMIT
HDDIGIT:    ADDD  #'0'
HDEMIT:     PSHU  D
            JSR   EMITW
            RTS

; ------------------------------------------------------------
; Display a byte as two hexadecimal digits.
; HEXBYTE   ( byte -- )
;    Inputs:
;        byte on the data stack
;    Outputs:
;        two digits sent with EMIT
;    Registers: RegD changed; MSCR used as scratch.
; ------------------------------------------------------------
HEXBYTE:    PULU  D
            STB   MSCR              ; See bugfix: HEXBYTE.1
            LDB   MSCR              ; high nibble
            LSRB
            LSRB
            LSRB
            LSRB
            CLRA
            PSHU  D
            JSR   HEXDIGIT
            LDB   MSCR              ; low nibble
            ANDB  #$0F
            CLRA
            PSHU  D
            JSR   HEXDIGIT
            RTS

; ------------------------------------------------------------
; DUMP  ( addr u -- )
; Display u bytes starting at addr, 16 per line: the hex bytes (no
; address), then the same bytes as ASCII with non-printing characters
; shown as ".". A partial last line is padded so the ASCII columns
; line up. A carriage return is sent first and after every line.
; ------------------------------------------------------------
DUMPW:      PULU  D                 ; u
            STD   DUMPCNT
            PULU  D                 ; addr
            STD   DUMPADDR
            JSR   CRW               ; leading CR
DULINE:     LDD   DUMPCNT
            LBEQ  DUDONE            ; no bytes left
            LDD   DUMPADDR
            STD   HEXBUF
            CLR   DUMPCOL
            LDA   #16
            STA   DUVALID
DUHEX:      LDB   DUMPCOL
            CMPB  #16
            BEQ   DUASCII
            LDD   DUMPCNT
            BNE   DUHEXBYTE
            LDA   DUMPCOL
            STA   DUVALID
            BRA   DUHEXPAD
DUHEXBYTE:  LDX   DUMPADDR
            LDB   ,X
            CLRA
            PSHU  D
            JSR   HEXBYTE
            LDD   #32
            PSHU  D
            JSR   EMITW
            LDX   DUMPADDR
            LEAX  1,X
            STX   DUMPADDR
            LDD   DUMPCNT
            SUBD  #1
            STD   DUMPCNT
            INC   DUMPCOL
            BRA   DUHEX
DUHEXPAD:   LDD   #32
            PSHU  D
            JSR   EMITW
            PSHU  D
            JSR   EMITW
            PSHU  D
            JSR   EMITW
            INC   DUMPCOL
            LDB   DUMPCOL
            CMPB  #16
            BNE   DUHEXPAD
            BRA   DUASCII
DUASCII:    LDD   #32
            PSHU  D
            JSR   EMITW
            CLR   DUMPCOL
DUACHAR:    LDB   DUMPCOL
            CMPB  #16
            BEQ   DULEND
            CMPB  DUVALID
            BHS   DUABLANK
            LDX   HEXBUF
            LDB   DUMPCOL
            CLRA
            LEAX  D,X
            LDA   ,X
            CMPA  #32
            BLO   DUDOT
            CMPA  #127
            BHS   DUDOT
            BRA   DUPRINT
DUDOT:      LDA   #'.'
DUPRINT:    TFR   A,B
            CLRA
            PSHU  D
            JSR   EMITW
            INC   DUMPCOL
            BRA   DUACHAR
DUABLANK:   LDD   #32
            PSHU  D
            JSR   EMITW
            INC   DUMPCOL
            BRA   DUACHAR
DULEND:     JSR   CRW
            LDD   DUMPCNT
            LBNE  DULINE            ; more bytes: next line
DUDONE:     RTS

; ============================================================
; SECTION 26: CONSTANT-VALUE WORDS (TRUE, FALSE, 1, -1, 2, -2)
; ============================================================
; ------------------------------------------------------------
; TRUE  ( -- flag )
; Push true ($FFFF), the value of TRUEV. A direct LDD/PSHU/RTS: no
; DODOES trampoline and no value cell.
; Original comment: shadow TRUEW.0.
; ------------------------------------------------------------
TRUEW:      LDD   #$FFFF
            PSHU  D
            RTS

; ------------------------------------------------------------
; FALSE  ( -- flag )
; Push false ($0000), the value of FALSEV.
; ------------------------------------------------------------
FALSEW:     LDD   #$0000
            PSHU  D
            RTS

; ------------------------------------------------------------
; 1  ( -- 1 )
; Push the constant 1. The words -1, 2 and -2 below work the same way.
; Their headers are H_POSONE, H_NEGONE, H_POSTWO and H_NEGTWO (Section
; 27), since "1" and "-1" are not valid assembler labels.
; Original comment: shadow POSONEW.0.
; ------------------------------------------------------------
POSONEW:    LDD   #1
            PSHU  D
            RTS

; ------------------------------------------------------------
; -1  ( -- -1 )
; Push the constant -1.
; ------------------------------------------------------------
NEGONEW:    LDD   #-1
            PSHU  D
            RTS

; ------------------------------------------------------------
; 2  ( -- 2 )
; Push the constant 2.
; ------------------------------------------------------------
POSTWOW:    LDD   #2
            PSHU  D
            RTS

; ------------------------------------------------------------
; -2  ( -- -2 )
; Push the constant -2.
; ------------------------------------------------------------
NEGTWOW:    LDD   #-2
            PSHU  D
            RTS

; Verify no collision with init code,
; value should match ORG INITCODE.
BASECODEEND EQU   *
BASECODESIZE EQU   BASECODEEND-BASECODE

; Prevent the assembler from extinguishing the gap between the
; BASECODE block and the INITCODE block when it generates the
; .bin file.
BASEND:
            FILL  $FF,INITCODE-BASEND

; ============================================================
; SECTION 2: INIT CODE (COLDSTRT / WARM)
; ============================================================
            ORG   INITCODE          ; init code block

; ------------------------------------------------------------
; Cold start, entered from the reset vector: mask interrupts, set up
; the stacks and the direct page, clear GLOBALS, initialise the ACIA,
; unmask interrupts, run the unit tests if they are built in, then
; enter COLD.
; COLDSTRT
;    Inputs:
;        hardware reset
;    Outputs:
;        does not return
;    Registers: all registers initialised.
; ------------------------------------------------------------
COLDSTRT:
            ORCC  #$50              ; Disable IRQ & FIRQ
            LDS   #RSTACK+1
            LDU   #DSTACK+1
            CLRA
            TFR   A,DP

            LDX   #GLOBALS
            LDB   #0
CLRGLOB:    CLR   ,X+
            DECB
            BNE   CLRGLOB

            JSR   INITSERIAL

            ANDCC #$AF              ; Enable IRQ & FIRQ

            ; IRQ and FIRQ are unmasked above. See bugfix: COLDSTRT.1

            IFNE  UNITTESTS         ; >>>>>>>>>>
            JSR   TSTRUNNER
            ELSE                    ; <<<<<>>>>>
            NOP                     ; same size as JSR TSTRUNNER
            NOP                     ; See bugfix: COLDSTRT.2
            NOP
            ENDC                    ; <<<<<<<<<<

            JMP   COLD

; ------------------------------------------------------------
; Warm start, entered from the NMI vector: mask interrupts, reset the
; stacks and direct page, re-initialise the ACIA, print the warm-start
; message, unmask interrupts and ABORT. GLOBALS is not cleared.
; WARM
;    Inputs:
;        NMI
;    Outputs:
;        does not return
;    Registers: all registers initialised.
; ------------------------------------------------------------
WARM:       ORCC  #$50              ; Disable IRQ & FIRQ
            CLRA
            TFR   A,DP
            LDU   #SP0
            LDS   #RP0

            JSR   INITSERIAL        ; See bugfix: WARM.1

            LDX   #WARMMSG
            PSHU  X
            LDD   #WARMMSGL
            PSHU  D
            JSR   TYPEW
            ANDCC #$AF              ; Enable IRQ & FIRQ
            JMP   ABORT             ; restart the interpreter

WARMMSG:    FCC   "  warm"
WARMMSGL    EQU   *-WARMMSG

            ; Verify no collision with vectors: INITEND should equal VECTORS.
INITEND     EQU   *
INITSIZE    EQU   INITEND-INITCODE

; Prevent the assembler from extinguishing the gap between the
; INITCODE block and the VECTORS block when it generates the
; .bin file.
            FILL  $FF,VECTORS-INITEND

; ============================================================
; SECTION 1: HARDWARE VECTOR TABLE
; ============================================================
            ORG   VECTORS           ; hardware vector table
VRESV       FDB   $0000
VSWI3       FDB   SWI3H             ; SWI3
VSWI2       FDB   SWI2H             ; SWI2
VFIRQ       FDB   FIRQH             ; FIRQ
VIRQ        FDB   IRQH              ; IRQ
VSWI        FDB   SWIH              ; SWI
VNMI        FDB   WARM              ; NMI -> warm restart
VRESET      FDB   COLDSTRT          ; reset

VECTOREND   EQU   *                 ; vectors size, should be $10
VECTORSIZE  EQU   VECTOREND-VECTORS

; ============================================================
; END OF CONSOLIDATED SOURCE
; ============================================================
