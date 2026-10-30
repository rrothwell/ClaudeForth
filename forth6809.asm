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
BASECODE    EQU   $D952             ; base code. See shadow MEMMAP.6
            ; Commented-out code moved to shadow: MEMMAP.7
BASEDICT    EQU   $CFA3             ; base dictionary. See shadow MEMMAP.8
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
            ; PADOFFSET - HOLDMINSIZE - 1 (count byte) - 3. The 3 bytes were
            ; once reserved by S", ." and ABORT" (they now use PARSE, stage
            ; 5i). See shadow WORDMAXCHARS.2. Original comment: shadow
            ; WORDMAXCHARS.1.

APPCODE     EQU   $7000             ; application code area
APPDICT     EQU   $2000             ; application dictionary
SUBPOOL     EQU   $0200             ; REPLACES substitution table. See shadow
SUBPOOLSZ   EQU   64                ; REPLACES.1; $0200-$023F
APPVARS     EQU   SUBPOOL+SUBPOOLSZ ; application variables ($0240)
APPVARSEND  EQU   APPDICT-1         ; end of application variables
; $01DD-$01FF were formerly WORDBUF and SIBUF; $0200 now starts SUBPOOL.
; Original comment: shadow MEMMAP.17.

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
; COLDSTRT), laid out in RMB order. 131 of 256 bytes are used
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
MSCR        RMB   2                 ; offset $14 (shared: -, *, WITHIN...)
MSCR2       RMB   2                 ; offset $16
MSCR3       RMB   2                 ; offset $18
MSCR4       RMB   2                 ; offset $1A
HLD         RMB   2                 ; offset $1C
EMITCH      RMB   1                 ; offset $1E
; CURXT holds the xt of the word being compiled, for RECURSE.
; Original comment: shadow CURXT.1.
CURXT       RMB   2                 ; offset $1F
CSP         RMB   2                 ; offset $21
PRODHI      RMB   2                 ; offset $23
PRODLO      RMB   2                 ; offset $25
PSIGN       RMB   1                 ; offset $27
DIVNUM      RMB   2                 ; offset $28
DIVDEN      RMB   2                 ; offset $2A
DIVREM      RMB   2                 ; offset $2C
DIVCNT      RMB   1                 ; offset $2E
DNSIGN      RMB   1                 ; offset $2F
DVSIGN      RMB   1                 ; offset $30
DVOWNSIGN   RMB   1                 ; offset $31
MAHI        RMB   1                 ; offset $32
MALO        RMB   1                 ; offset $33
MBHI        RMB   1                 ; offset $34
MBLO        RMB   1                 ; offset $35
MSIGN       RMB   1                 ; offset $36
PRSIGN      RMB   1                 ; offset $37
SHCNT       RMB   1                 ; offset $38
SRCADDR     RMB   2                 ; offset $39
SRCLEN      RMB   2                 ; offset $3B
SRCID       RMB   2                 ; offset $3D
SPAN        RMB   2                 ; offset $3F

SUBHEAD     RMB   2                 ; offset $41: newest REPLACES entry, 0 = none
SUBFREE     RMB   2                 ; offset $43: next free byte of SUBPOOL, 0 = empty

; Search-Order word set. A WID is the address of a cell in WLHEADS that
; holds the newest header of that wordlist (0 = empty). WLEND is the
; address just past the last WLHEADS cell in use. ORDER holds the
; WIDs of the search order, first searched at the lowest address, and
; ORDEND is the address just past the last one in use. The second
; wordlist is ROOT, which is also always searched, last. WLEND, CURRENT, ORDEND and
; ORDER are adjacent because MARKER saves and restores them together
; (SRCHSAVE, SRCHSAVESZ). See shadow WLHEADS.1
SRCHSAVE
WLEND       RMB   2                 ; offset $45
CURRENT     RMB   2                 ; offset $47: WID that receives new words
ORDEND      RMB   2                 ; offset $49
ORDER       RMB   16                ; offset $4B-$5A: up to 8 WIDs
SRCHSAVESZ  EQU   *-SRCHSAVE
WLHEADS     RMB   20                ; offset $5B-$6E: FORTH, ROOT, 8 more
WLNAMES     RMB   20                ; offset $6F-$82: for each wordlist the header
                                    ; of the word that names it (0 = none)
WLNOFF      EQU   WLNAMES-WLHEADS   ; from a WID to its WLNAMES cell
WLCELLS     EQU   10                ; wordlists, including FORTH and ROOT
WLMAX       EQU   8                 ; WIDs in the search order

GLOBALS_USED EQU   131              ; bytes used, of 256 available

; $0100-$0105 is unclaimed (was MVSCRATCH). See shadow MVSCRATCH.1

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

TSTEND     EQU *                   ; Mark where tests end to size spare space.

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
; hand-built. Headers are in search order (shadow SECTION27.1).
;
; Names containing a double-quote (S", ." and ABORT") have it split
; out of the FCC into a separate FCB $22.
; The original header comment is shadow SECTION27.0.
; ============================================================

            ORG   BASEDICT
; ROOT wordlist: the Search-Order words. It is always searched, last,
; and FORTH continues into it (the link of the first FORTH header names
; BASEROOTLATEST), so FORTH-WORDLIST also contains these words.
; See shadow BASEROOTLATEST.1
H_WORDLIST: FCB   8
            FCC   "WORDLIST"
            FDB   0
            FDB   WORDLISTW

H_FORTHWL:  FCB   14
            FCC   "FORTH-WORDLIST"
            FDB   H_WORDLIST
            FDB   FORTHWLW

H_GETORDER: FCB   9
            FCC   "GET-ORDER"
            FDB   H_FORTHWL
            FDB   GETORDERW

H_SETORDER: FCB   9
            FCC   "SET-ORDER"
            FDB   H_GETORDER
            FDB   SETORDERW

H_SEARCHWL: FCB   15
            FCC   "SEARCH-WORDLIST"
            FDB   H_SETORDER
            FDB   SEARCHWLW

H_GETCUR:   FCB   11
            FCC   "GET-CURRENT"
            FDB   H_SEARCHWL
            FDB   GETCURW

H_SETCUR:   FCB   11
            FCC   "SET-CURRENT"
            FDB   H_GETCUR
            FDB   SETCURW

H_DEFINITIONS:
            FCB   11
            FCC   "DEFINITIONS"
            FDB   H_SETCUR
            FDB   DEFINITIONSW

H_ONLY:     FCB   4
            FCC   "ONLY"
            FDB   H_DEFINITIONS
            FDB   ONLYW

H_ALSO:     FCB   4
            FCC   "ALSO"
            FDB   H_ONLY
            FDB   ALSOW

H_PREVIOUS: FCB   8
            FCC   "PREVIOUS"
            FDB   H_ALSO
            FDB   PREVIOUSW

H_ORDER:    FCB   5
            FCC   "ORDER"
            FDB   H_PREVIOUS
            FDB   ORDERW

H_VOCABULARY:
            FCB   10
            FCC   "VOCABULARY"
            FDB   H_ORDER
            FDB   VOCABULARYW

H_ROOT:     FCB   4
            FCC   "ROOT"
            FDB   H_VOCABULARY
            FDB   ROOTW

H_FORTH:    FCB   5
            FCC   "FORTH"
            FDB   H_ROOT
            FDB   FORTHW

BASEROOTLATEST EQU H_FORTH

; Search order: head first, and so last in memory. See shadow SECTION27.1.
; Headers are laid out tail first, so each LINK points back to the header
; just before it in memory (0 for the first) and BASELATEST names the last.

H_HEADER:   FCB   6
            FCC   "HEADER"
            FDB   BASEROOTLATEST
            FDB   HEADER

H_SMUDGE:   FCB   6
            FCC   "SMUDGE"
            FDB   H_HEADER
            FDB   SMUDGEW

H_BRTHEN:   FCB   $86
            FCC   "[THEN]"
            FDB   H_SMUDGE
            FDB   BRTHENW

H_BRELSE:   FCB   $86
            FCC   "[ELSE]"
            FDB   H_BRTHEN
            FDB   BRELSEW

H_BRIF:     FCB   $84
            FCC   "[IF]"
            FDB   H_BRELSE
            FDB   BRIFW

H_DUMP:
            FCB   $04
            FCC   "DUMP"
            FDB   H_BRIF
            FDB   DUMPW

H_WORDS:
            FCB   $05
            FCC   "WORDS"
            FDB   H_DUMP
            FDB   WORDSW

H_DOTS:
            FCB   $02
            FCC   ".S"
            FDB   H_WORDS
            FDB   DOTSW

H_BL:
            FCB   $02
            FCC   "BL"
            FDB   H_DOTS
            FDB   BLW

H_SPAN:
            FCB   $04
            FCC   "SPAN"
            FDB   H_BL
            FDB   SPANW

H_TOIN:
            FCB   $03
            FCC   ">IN"
            FDB   H_SPAN
            FDB   TOINW

H_NUMTIB:
            FCB   $04
            FCC   "#TIB"
            FDB   H_TOIN
            FDB   NUMTIBW

H_TIB:
            FCB   $03
            FCC   "TIB"
            FDB   H_NUMTIB
            FDB   TIBW

H_EVALUATE:
            FCB   $08
            FCC   "EVALUATE"
            FDB   H_TIB
            FDB   EVALUATEW

H_REFILL:
            FCB   $06
            FCC   "REFILL"
            FDB   H_EVALUATE
            FDB   REFILLW

H_SOURCEID:
            FCB   $09
            FCC   "SOURCE-ID"
            FDB   H_REFILL
            FDB   SOURCEIDW

H_SOURCE:
            FCB   $06
            FCC   "SOURCE"
            FDB   H_SOURCEID
            FDB   SOURCEW

H_ENVQ:
            FCB   $0C
            FCC   "ENVIRONMENT?"
            FDB   H_SOURCE
            FDB   ENVQW

H_TWOVALUE: FCB   6
            FCC   "2VALUE"
            FDB   H_ENVQ
            FDB   TWOVALUEW

H_MARKER:
            FCB   $06
            FCC   "MARKER"
            FDB   H_TWOVALUE
            FDB   MARKERW

H_ACTIONOF:
            FCB   $89
            FCC   "ACTION-OF"
            FDB   H_MARKER
            FDB   ACTIONOFW

H_IS:
            FCB   $82
            FCC   "IS"
            FDB   H_ACTIONOF
            FDB   ISW

H_DEFERSTORE:
            FCB   $06
            FCC   "DEFER!"
            FDB   H_IS
            FDB   DEFERSTOREW

H_DEFERFETCH:
            FCB   $06
            FCC   "DEFER@"
            FDB   H_DEFERSTORE
            FDB   DEFERFETCHW

H_DEFER:
            FCB   $05
            FCC   "DEFER"
            FDB   H_DEFERFETCH
            FDB   DEFERW

H_BUFFERCOLON:
            FCB   $07
            FCC   "BUFFER:"
            FDB   H_DEFER
            FDB   BUFFERCOLONW

H_TWOCONSTANT:
            FCB   $09
            FCC   "2CONSTANT"
            FDB   H_BUFFERCOLON
            FDB   TWOCONSTANTW

H_TWOVARIABLE:
            FCB   $09
            FCC   "2VARIABLE"
            FDB   H_TWOCONSTANT
            FDB   TWOVARIABLEW

H_TO:
            FCB   $82
            FCC   "TO"
            FDB   H_TWOVARIABLE
            FDB   TOW

H_VALUE:
            FCB   $05
            FCC   "VALUE"
            FDB   H_TO
            FDB   VALUEW

H_CONSTANT:
            FCB   $08
            FCC   "CONSTANT"
            FDB   H_VALUE
            FDB   CONSTANTW

H_VARIABLE:
            FCB   $08
            FCC   "VARIABLE"
            FDB   H_CONSTANT
            FDB   VARIABLEW

H_DOESGT:
            FCB   $85               ; $80 IMMEDIATE | 5 (length of "DOES>")
            FCC   "DOES>"
            FDB   H_VARIABLE
            FDB   DOESGTW

H_CREATE:
            FCB   $06
            FCC   "CREATE"
            FDB   H_DOESGT
            FDB   CREATEW

H_NONAME:
            FCB   $07               ; not IMMEDIATE (runs only in INTERPRET)
            FCC   ":NONAME"
            FDB   H_CREATE
            FDB   NONAMEW

H_SEMI:
            FCB   $81
            FCC   ";"
            FDB   H_NONAME
            FDB   SEMIW

H_COLON:
            FCB   $01
            FCC   ":"
            FDB   H_SEMI
            FDB   COLONW

H_TWOLITERAL: FCB $88
            FCC   "2LITERAL"
            FDB   H_COLON
            FDB   TWOLITERALW

H_ABORTQUOTE:
            FCB   $86
            FCC   "ABORT"
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_TWOLITERAL
            FDB   ABORTQUOTEW

H_SLITERAL:
            FCB   $88
            FCC   "SLITERAL"
            FDB   H_ABORTQUOTE
            FDB   SLITERALW

H_EXECUTE:
            FCB   $07
            FCC   "EXECUTE"
            FDB   H_SLITERAL
            FDB   EXECUTEW

H_TOBODY:
            FCB   $05
            FCC   ">BODY"
            FDB   H_EXECUTE
            FDB   TOBODYW

H_BRACKCOMPILE:
            FCB   $89               ; $80 IMMEDIATE | 9 (length of "[COMPILE]")
            FCC   "[COMPILE]"
            FDB   H_TOBODY
            FDB   BRACKCOMPILEW

H_POSTPONE:
            FCB   $88
            FCC   "POSTPONE"
            FDB   H_BRACKCOMPILE
            FDB   POSTPONEW

H_BRACKTICK:
            FCB   $83
            FCC   "[']"
            FDB   H_POSTPONE
            FDB   BRACKTICKW

H_LITERAL:
            FCB   $87
            FCC   "LITERAL"
            FDB   H_BRACKTICK
            FDB   LITERALW

H_COMPILECOMMA:
            FCB   $08
            FCC   "COMPILE,"
            FDB   H_LITERAL
            FDB   COMPILECOMMAW

H_TICK:
            FCB   $01
            FCC   "'"
            FDB   H_COMPILECOMMA
            FDB   TICKW

H_RBRACKET:
            FCB   $81
            FCC   "]"
            FDB   H_TICK
            FDB   RBRACKETW

H_LBRACKET:
            FCB   $81
            FCC   "["
            FDB   H_RBRACKET
            FDB   LBRACKETW

H_STATE:
            FCB   $05
            FCC   "STATE"
            FDB   H_LBRACKET
            FDB   STATEW

H_IMMEDIATE:
            FCB   $09
            FCC   "IMMEDIATE"
            FDB   H_STATE
            FDB   IMMEDIATEW

H_CONVERT:  FCB   7
            FCC   "CONVERT"
            FDB   H_IMMEDIATE
            FDB   CONVERTW

H_SQUOTEESC: FCB  $83
            FCC   "S\"
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_CONVERT
            FDB   SQUOTEESCW

H_RESTOREINPUT: FCB 13
            FCC   "RESTORE-INPUT"
            FDB   H_SQUOTEESC
            FDB   RESTOREINPUTW

H_SAVEINPUT: FCB  10
            FCC   "SAVE-INPUT"
            FDB   H_RESTOREINPUT
            FDB   SAVEINPUTW

H_CQUOTE:   FCB   $82
            FCC   "C"
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_SAVEINPUT
            FDB   CQUOTEW

; FIND: pushes xt and 1 (immediate) or -1 (normal) on success; on
; failure pushes the original c-addr and 0.
H_FIND:     FCB   4
            FCC   "FIND"
            FDB   H_CQUOTE
            FDB   FINDW

H_TONUMBER:
            FCB   $07
            FCC   ">NUMBER"
            FDB   H_FIND
            FDB   TONUMBERW

H_UNESCAPE:
            FCB   $08
            FCC   "UNESCAPE"
            FDB   H_TONUMBER
            FDB   UNESCAPEW

H_SNAME:
            FCB   $05
            FCC   "SNAME"
            FDB   H_UNESCAPE
            FDB   SNAMEW

H_SUBSTITUTE:
            FCB   $0A
            FCC   "SUBSTITUTE"
            FDB   H_SNAME
            FDB   SUBSTITUTEW

H_CLRREPLACES:
            FCB   $0C
            FCC   "CLR-REPLACES"
            FDB   H_SUBSTITUTE
            FDB   CLRREPLACESW

H_REPLACES:
            FCB   $08
            FCC   "REPLACES"
            FDB   H_CLRREPLACES
            FDB   REPLACESW

H_SLASHSTRING:
            FCB   $07
            FCC   "/STRING"
            FDB   H_REPLACES
            FDB   SLASHSTRINGW

H_DASHTRAILING:
            FCB   $09
            FCC   "-TRAILING"
            FDB   H_SLASHSTRING
            FDB   DASHTRAILINGW

H_SEARCH:
            FCB   $06
            FCC   "SEARCH"
            FDB   H_DASHTRAILING
            FDB   SEARCHW

H_COMPARE:
            FCB   $07
            FCC   "COMPARE"
            FDB   H_SEARCH
            FDB   COMPAREW

H_SQUOTE:
            FCB   $82
            FCC   "S"
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_COMPARE
            FDB   SQUOTEW

H_PARSENAME:
            FCB   $0A
            FCC   "PARSE-NAME"
            FDB   H_SQUOTE
            FDB   PARSENAMEW

H_PARSE:
            FCB   $05
            FCC   "PARSE"
            FDB   H_PARSENAME
            FDB   PARSEW

H_BRACKCHAR:
            FCB   $86
            FCC   "[CHAR]"
            FDB   H_PARSE
            FDB   BRACKCHARW

H_CHAR:
            FCB   $04
            FCC   "CHAR"
            FDB   H_BRACKCHAR
            FDB   CHARW

H_WORD:
            FCB   $04
            FCC   "WORD"
            FDB   H_CHAR
            FDB   WORDW

H_COUNT:
            FCB   $05
            FCC   "COUNT"
            FDB   H_WORD
            FDB   COUNTW

H_MSTARSLASH: FCB 3
            FCC   "M*/"
            FDB   H_COUNT
            FDB   MSTARSLASHW

H_DTWOSLASH: FCB  3
            FCC   "D2/"
            FDB   H_MSTARSLASH
            FDB   DTWOSLASHW

H_DTWOSTAR: FCB   3
            FCC   "D2*"
            FDB   H_DTWOSLASH
            FDB   DTWOSTARW

H_DZEROLT:  FCB   3
            FCC   "D0<"
            FDB   H_DTWOSTAR
            FDB   DZEROLTW

H_DZEROEQ:  FCB   3
            FCC   "D0="
            FDB   H_DZEROLT
            FDB   DZEROEQW

H_DMIN:
            FCB   $04
            FCC   "DMIN"
            FDB   H_DZEROEQ
            FDB   DMINW

H_DMAX:
            FCB   $04
            FCC   "DMAX"
            FDB   H_DMIN
            FDB   DMAXW

H_DTOS:
            FCB   $03
            FCC   "D>S"
            FDB   H_DMAX
            FDB   DTOSW

H_STOD:
            FCB   $03
            FCC   "S>D"
            FDB   H_DTOS
            FDB   STODW

H_MPLUS:
            FCB   $02
            FCC   "M+"
            FDB   H_STOD
            FDB   MPLUSW

H_DABS:
            FCB   $04
            FCC   "DABS"
            FDB   H_MPLUS
            FDB   DABSW

H_DNEGATE:
            FCB   $07
            FCC   "DNEGATE"
            FDB   H_DABS
            FDB   DNEGATEW

H_DMINUS:
            FCB   $02
            FCC   "D-"
            FDB   H_DNEGATE
            FDB   DMINUSW

H_DPLUS:
            FCB   $02
            FCC   "D+"
            FDB   H_DMINUS
            FDB   DPLUSW

H_SMSLASHREM:
            FCB   $06
            FCC   "SM/REM"
            FDB   H_DPLUS
            FDB   SMSLASHREMW

H_FMSLASHMOD:
            FCB   $06
            FCC   "FM/MOD"
            FDB   H_SMSLASHREM
            FDB   FMSLASHMODW

H_MSTAR:
            FCB   $02
            FCC   "M*"
            FDB   H_FMSLASHMOD
            FDB   MSTARW

H_UMSLASHMOD:
            FCB   $06
            FCC   "UM/MOD"
            FDB   H_MSTAR
            FDB   UMSLASHMODW

H_UMSTAR:
            FCB   $03
            FCC   "UM*"
            FDB   H_UMSLASHMOD
            FDB   UMSTARW

H_TWORFETCH:
            FCB   $03
            FCC   "2R@"
            FDB   H_UMSTAR
            FDB   TWORFETCHW

H_TWOFROMR:
            FCB   $03
            FCC   "2R>"
            FDB   H_TWORFETCH
            FDB   TWOFROMRW

H_TWOTOR:
            FCB   $03
            FCC   "2>R"
            FDB   H_TWOFROMR
            FDB   TWOTORW

H_RFETCH:
            FCB   $02
            FCC   "R@"
            FDB   H_TWOTOR
            FDB   RFETCHW

H_FROMR:
            FCB   $02
            FCC   "R>"
            FDB   H_RFETCH
            FDB   FROMRW

H_TOR:
            FCB   $02
            FCC   ">R"
            FDB   H_FROMR
            FDB   TORW

H_THROW:
            FCB   $05
            FCC   "THROW"
            FDB   H_TOR
            FDB   THROWW

H_CATCH:
            FCB   $05
            FCC   "CATCH"
            FDB   H_THROW
            FDB   CATCHW

H_QUIT:     FCB   4
            FCC   "QUIT"
            FDB   H_CATCH
            FDB   QUITW

; H_ABORT and H_QUIT are hand-built (HEADER/CREATE could not be used
; for them). Original comment: shadow H_ABORT.0.
H_ABORT:    FCB   5
            FCC   "ABORT"
            FDB   H_QUIT           ; previous newest entry
            FDB   ABORTW            ; See bugfix: H_ABORT.2

H_SPACES:
            FCB   $06
            FCC   "SPACES"
            FDB   H_ABORT
            FDB   SPACESW

H_CR:
            FCB   $02
            FCC   "CR"
            FDB   H_SPACES
            FDB   CRW

H_TYPE:
            FCB   $04
            FCC   "TYPE"
            FDB   H_CR
            FDB   TYPEW

H_QUERY:
            FCB   $05
            FCC   "QUERY"
            FDB   H_TYPE
            FDB   QUERYW

H_EXPECT:
            FCB   $06
            FCC   "EXPECT"
            FDB   H_QUERY
            FDB   EXPECTW

H_ACCEPT:
            FCB   $06
            FCC   "ACCEPT"
            FDB   H_EXPECT
            FDB   ACCEPTW

H_EMIT:
            FCB   $04
            FCC   "EMIT"
            FDB   H_ACCEPT
            FDB   EMITW

H_KEYQ:
            FCB   $04
            FCC   "KEY?"
            FDB   H_EMIT
            FDB   KEYQW

H_KEY:
            FCB   $03
            FCC   "KEY"
            FDB   H_KEYQ
            FDB   KEYW

H_SPACE:
            FCB   $05
            FCC   "SPACE"
            FDB   H_KEY
            FDB   SPACEW

H_DOTQUOTE:
            FCB   $82
            FCC   "."
            FCB   $22               ; '"' split out of the FCC string
            FDB   H_SPACE
            FDB   DOTQUOTEW

H_BINARY:
            FCB   $06
            FCC   "BINARY"
            FDB   H_DOTQUOTE
            FDB   BINARYW

H_HEX:
            FCB   $03
            FCC   "HEX"
            FDB   H_BINARY
            FDB   HEXW

H_DECIMAL:
            FCB   $07
            FCC   "DECIMAL"
            FDB   H_HEX
            FDB   DECIMALW

H_BASE:
            FCB   $04
            FCC   "BASE"
            FDB   H_DECIMAL
            FDB   BASEW

H_DDOTR:
            FCB   $03
            FCC   "D.R"
            FDB   H_BASE
            FDB   DDOTRW

H_DDOT:
            FCB   $02
            FCC   "D."
            FDB   H_DDOTR
            FDB   DDOTW

H_QMARK:
            FCB   $01
            FCC   "?"
            FDB   H_DDOT
            FDB   QMARKW

H_UDOTR:
            FCB   $03
            FCC   "U.R"
            FDB   H_QMARK
            FDB   UDOTRW

H_DOTR:
            FCB   $02
            FCC   ".R"
            FDB   H_UDOTR
            FDB   DOTRW

H_UDOT:
            FCB   $02
            FCC   "U."
            FDB   H_DOTR
            FDB   UDOTW

H_SIGN:
            FCB   $04
            FCC   "SIGN"
            FDB   H_UDOT
            FDB   SIGNW

H_HOLDS:
            FCB   $05
            FCC   "HOLDS"
            FDB   H_SIGN
            FDB   HOLDSW

H_HOLD:
            FCB   $04
            FCC   "HOLD"
            FDB   H_HOLDS
            FDB   HOLDW

H_NUMGT:
            FCB   $02
            FCC   "#>"
            FDB   H_HOLD
            FDB   NUMGTW

H_NUMS:
            FCB   $02
            FCC   "#S"
            FDB   H_NUMGT
            FDB   NUMSW

H_NUM:
            FCB   $01
            FCC   "#"
            FDB   H_NUMS
            FDB   NUMW

H_LTNUM:
            FCB   $02
            FCC   "<#"
            FDB   H_NUM
            FDB   LTNUMW

H_DOT:
            FCB   $01
            FCC   "."
            FDB   H_LTNUM
            FDB   DOTW

H_CMOVEGT:
            FCB   $06
            FCC   "CMOVE>"
            FDB   H_DOT
            FDB   CMOVEGTW

H_CMOVE:
            FCB   $05
            FCC   "CMOVE"
            FDB   H_CMOVEGT
            FDB   CMOVEW

H_BLANK:
            FCB   $05
            FCC   "BLANK"
            FDB   H_CMOVE
            FDB   BLANKW

H_ERASE:
            FCB   $05
            FCC   "ERASE"
            FDB   H_BLANK
            FDB   ERASEW

H_FILL:
            FCB   $04
            FCC   "FILL"
            FDB   H_ERASE
            FDB   FILLW

H_MOVE:
            FCB   $04
            FCC   "MOVE"
            FDB   H_FILL
            FDB   MOVEW

H_VUNUSED:
            FCB   $07
            FCC   "VUNUSED"
            FDB   H_MOVE
            FDB   VUNUSEDW

H_UNUSED:
            FCB   $06
            FCC   "UNUSED"
            FDB   H_VUNUSED
            FDB   UNUSEDW

H_PAD:
            FCB   $03
            FCC   "PAD"
            FDB   H_UNUSED
            FDB   PADW

H_VHERE:
            FCB   $05
            FCC   "VHERE"
            FDB   H_PAD
            FDB   VHEREW

H_VALLOT:
            FCB   $06
            FCC   "VALLOT"
            FDB   H_VHERE
            FDB   VALLOTW

H_VCCOMMA:
            FCB   $03
            FCC   "VC,"
            FDB   H_VALLOT
            FDB   VCCOMMAW

H_VCOMMA:
            FCB   $02
            FCC   "V,"
            FDB   H_VCCOMMA
            FDB   VCOMMAW

H_HERE:
            FCB   $04
            FCC   "HERE"
            FDB   H_VCOMMA
            FDB   HEREW

H_ALLOT:
            FCB   $05
            FCC   "ALLOT"
            FDB   H_HERE
            FDB   ALLOTW

H_CCOMMA:
            FCB   $02
            FCC   "C,"
            FDB   H_ALLOT
            FDB   CCOMMAW

H_COMMA:
            FCB   $01
            FCC   ","
            FDB   H_CCOMMA
            FDB   COMMAW

H_TWOSTORE:
            FCB   $02
            FCC   "2!"
            FDB   H_COMMA
            FDB   TWOSTOREW

H_TWOFETCH:
            FCB   $02
            FCC   "2@"
            FDB   H_TWOSTORE
            FDB   TWOFETCHW

H_PLUSSTORE:
            FCB   $02
            FCC   "+!"
            FDB   H_TWOFETCH
            FDB   PLUSSTOREW

H_CSTORE:
            FCB   $02
            FCC   "C!"
            FDB   H_PLUSSTORE
            FDB   CSTOREW

H_CFETCH:
            FCB   $02
            FCC   "C@"
            FDB   H_CSTORE
            FDB   CFETCHW

H_STORE:
            FCB   $01
            FCC   "!"
            FDB   H_CFETCH
            FDB   STOREW

H_FETCH:
            FCB   $01
            FCC   "@"
            FDB   H_STORE
            FDB   FETCHW

H_ALIGNED:
            FCB   $07
            FCC   "ALIGNED"
            FDB   H_FETCH
            FDB   ALIGNEDW

H_ALIGN:
            FCB   $05
            FCC   "ALIGN"
            FDB   H_ALIGNED
            FDB   ALIGNW

H_CHARPLUS:
            FCB   $05
            FCC   "CHAR+"
            FDB   H_ALIGN
            FDB   CHARPLUSW

H_CHARS:
            FCB   $05
            FCC   "CHARS"
            FDB   H_CHARPLUS
            FDB   CHARSW

H_CELLPLUS:
            FCB   $05
            FCC   "CELL+"
            FDB   H_CHARS
            FDB   CELLPLUSW

H_CELLS:
            FCB   $05
            FCC   "CELLS"
            FDB   H_CELLPLUS
            FDB   CELLSW

H_RSHIFT:
            FCB   $06
            FCC   "RSHIFT"
            FDB   H_CELLS
            FDB   RSHIFTW

H_LSHIFT:
            FCB   $06
            FCC   "LSHIFT"
            FDB   H_RSHIFT
            FDB   LSHIFTW

H_INVERT:
            FCB   $06
            FCC   "INVERT"
            FDB   H_LSHIFT
            FDB   INVERTW

H_XOR:
            FCB   $03
            FCC   "XOR"
            FDB   H_INVERT
            FDB   XORW

H_OR:
            FCB   $02
            FCC   "OR"
            FDB   H_XOR
            FDB   ORW

H_AND:
            FCB   $03
            FCC   "AND"
            FDB   H_OR
            FDB   ANDW

H_ENDCASE:
            FCB   $87
            FCC   "ENDCASE"
            FDB   H_AND
            FDB   ENDCASEW

H_ENDOF:
            FCB   $85
            FCC   "ENDOF"
            FDB   H_ENDCASE
            FDB   ENDOFW

H_OF:
            FCB   $82
            FCC   "OF"
            FDB   H_ENDOF
            FDB   OFW

H_CASE:
            FCB   $84
            FCC   "CASE"
            FDB   H_OF
            FDB   CASEW

H_EXIT:
            FCB   $84
            FCC   "EXIT"
            FDB   H_CASE
            FDB   EXITW

H_UNLOOP:
            FCB   $06
            FCC   "UNLOOP"
            FDB   H_EXIT
            FDB   UNLOOPW

H_LEAVE:
            FCB   $05
            FCC   "LEAVE"
            FDB   H_UNLOOP
            FDB   LEAVEW

H_J:
            FCB   $01
            FCC   "J"
            FDB   H_LEAVE
            FDB   JW

H_I:
            FCB   $01
            FCC   "I"
            FDB   H_J
            FDB   IW

H_PLUSLOOP:
            FCB   $85
            FCC   "+LOOP"
            FDB   H_I
            FDB   PLUSLOOPW

H_LOOP:
            FCB   $84
            FCC   "LOOP"
            FDB   H_PLUSLOOP
            FDB   LOOPW

H_QDO:
            FCB   $83
            FCC   "?DO"
            FDB   H_LOOP
            FDB   QDOW

H_DO:
            FCB   $82
            FCC   "DO"
            FDB   H_QDO
            FDB   DOW

H_RECURSE:
            FCB   $87
            FCC   "RECURSE"
            FDB   H_DO
            FDB   RECURSEW

H_REPEAT:
            FCB   $86
            FCC   "REPEAT"
            FDB   H_RECURSE
            FDB   REPEATW

H_WHILE:
            FCB   $85
            FCC   "WHILE"
            FDB   H_REPEAT
            FDB   WHILEW

H_AGAIN:
            FCB   $85
            FCC   "AGAIN"
            FDB   H_WHILE
            FDB   AGAINW

H_UNTIL:
            FCB   $85
            FCC   "UNTIL"
            FDB   H_AGAIN
            FDB   UNTILW

H_BEGIN:
            FCB   $85
            FCC   "BEGIN"
            FDB   H_UNTIL
            FDB   BEGINW

H_ELSE:
            FCB   $84
            FCC   "ELSE"
            FDB   H_BEGIN
            FDB   ELSEW

H_THEN:
            FCB   $84
            FCC   "THEN"
            FDB   H_ELSE
            FDB   THENW

H_IF:
            FCB   $82
            FCC   "IF"
            FDB   H_THEN
            FDB   IFW

H_FALSE:
            FCB   $05
            FCC   "FALSE"
            FDB   H_IF
            FDB   FALSEW

H_TRUE:
            FCB   $04
            FCC   "TRUE"
            FDB   H_FALSE
            FDB   TRUEW

H_DULESS:
            FCB   $03
            FCC   "DU<"
            FDB   H_TRUE
            FDB   DULESSW

H_DLESS:
            FCB   $02
            FCC   "D<"
            FDB   H_DULESS
            FDB   DLESSW

H_DEQUAL:
            FCB   $02
            FCC   "D="
            FDB   H_DLESS
            FDB   DEQUALW

H_WITHIN:
            FCB   $06
            FCC   "WITHIN"
            FDB   H_DEQUAL
            FDB   WITHINW

H_UGREATER:
            FCB   $02
            FCC   "U>"
            FDB   H_WITHIN
            FDB   UGREATERW

H_ZEROGT:
            FCB   $02
            FCC   "0>"
            FDB   H_UGREATER
            FDB   ZEROGTW

H_ZERONE:
            FCB   $03
            FCC   "0<>"
            FDB   H_ZEROGT
            FDB   ZERONEW

H_NOTEQUAL:
            FCB   $02
            FCC   "<>"
            FDB   H_ZERONE
            FDB   NOTEQUALW

H_ULESS:
            FCB   $02
            FCC   "U<"
            FDB   H_NOTEQUAL
            FDB   ULESSW

H_ZEROLT:
            FCB   $02
            FCC   "0<"
            FDB   H_ULESS
            FDB   ZEROLTW

H_ZEROEQ:
            FCB   $02
            FCC   "0="
            FDB   H_ZEROLT
            FDB   ZEROEQW

H_GREATER:
            FCB   $01
            FCC   ">"
            FDB   H_ZEROEQ
            FDB   GREATERW

H_LESS:
            FCB   $01
            FCC   "<"
            FDB   H_GREATER
            FDB   LESSW

H_EQUAL:
            FCB   $01
            FCC   "="
            FDB   H_LESS
            FDB   EQUALW

H_STARSLASHMOD:
            FCB   $05
            FCC   "*/MOD"
            FDB   H_EQUAL
            FDB   STARSLASHMODW

H_STARSLASH:
            FCB   $02
            FCC   "*/"
            FDB   H_STARSLASHMOD
            FDB   STARSLASHW

H_TWOSLASH:
            FCB   $02
            FCC   "2/"
            FDB   H_STARSLASH
            FDB   TWOSLASHW

H_TWOSTAR:
            FCB   $02
            FCC   "2*"
            FDB   H_TWOSLASH
            FDB   TWOSTARW

H_TWOPLUS:
            FCB   $02
            FCC   "2+"
            FDB   H_TWOSTAR
            FDB   TWOPLUSW

H_MAX:
            FCB   $03
            FCC   "MAX"
            FDB   H_TWOPLUS
            FDB   MAXW

H_MIN:
            FCB   $03
            FCC   "MIN"
            FDB   H_MAX
            FDB   MINW

H_ABS:
            FCB   $03
            FCC   "ABS"
            FDB   H_MIN
            FDB   ABSW

H_NEGATE:
            FCB   $06
            FCC   "NEGATE"
            FDB   H_ABS
            FDB   NEGATEW

H_SLASHMOD:
            FCB   $04
            FCC   "/MOD"
            FDB   H_NEGATE
            FDB   SLASHMODW

H_MOD:
            FCB   $03
            FCC   "MOD"
            FDB   H_SLASHMOD
            FDB   MODW

H_SLASH:
            FCB   $01
            FCC   "/"
            FDB   H_MOD
            FDB   SLASHW

H_STAR:
            FCB   $01
            FCC   "*"
            FDB   H_SLASH
            FDB   STARW

H_NEGTWO:   FCB   2
            FCC   "-2"
            FDB   H_STAR
            FDB   NEGTWOW

H_NEGONE:   FCB   2
            FCC   "-1"
            FDB   H_NEGTWO
            FDB   NEGONEW

H_POSTWO:   FCB   1
            FCC   "2"
            FDB   H_NEGONE
            FDB   POSTWOW

H_POSONE:   FCB   1
            FCC   "1"
            FDB   H_POSTWO
            FDB   POSONEW

H_ONEMINUS:
            FCB   $02
            FCC   "1-"
            FDB   H_POSONE
            FDB   ONEMINUSW

H_ONEPLUS:
            FCB   $02
            FCC   "1+"
            FDB   H_ONEMINUS
            FDB   ONEPLUSW

H_MINUS:
            FCB   $01
            FCC   "-"
            FDB   H_ONEPLUS
            FDB   MINUSW

H_PLUS:
            FCB   $01
            FCC   "+"
            FDB   H_MINUS
            FDB   PLUSW

H_DROT:
            FCB   $04
            FCC   "2ROT"
            FDB   H_PLUS
            FDB   DROTW

H_ROLL:
            FCB   $04
            FCC   "ROLL"
            FDB   H_DROT
            FDB   ROLLW

H_PICK:
            FCB   $04
            FCC   "PICK"
            FDB   H_ROLL
            FDB   PICKW

H_TUCK:
            FCB   $04
            FCC   "TUCK"
            FDB   H_PICK
            FDB   TUCKW

H_NIP:
            FCB   $03
            FCC   "NIP"
            FDB   H_TUCK
            FDB   NIPW

H_DOVER:
            FCB   $05
            FCC   "2OVER"
            FDB   H_NIP
            FDB   DOVERW

H_DSWAP:
            FCB   $05
            FCC   "2SWAP"
            FDB   H_DOVER
            FDB   DSWAPW

H_DDROP:
            FCB   $05
            FCC   "2DROP"
            FDB   H_DSWAP
            FDB   DDROPW

H_DDUP:
            FCB   $04
            FCC   "2DUP"
            FDB   H_DDROP
            FDB   DDUPW

H_DEPTH:
            FCB   $05
            FCC   "DEPTH"
            FDB   H_DDUP
            FDB   DEPTHW

H_ROT:
            FCB   $03
            FCC   "ROT"
            FDB   H_DEPTH
            FDB   ROTW

H_QDUP:
            FCB   $04
            FCC   "?DUP"
            FDB   H_ROT
            FDB   QDUPW

H_OVER:
            FCB   $04
            FCC   "OVER"
            FDB   H_QDUP
            FDB   OVERW

H_SWAP:
            FCB   $04
            FCC   "SWAP"
            FDB   H_OVER
            FDB   SWAPW

H_DROP:
            FCB   $04
            FCC   "DROP"
            FDB   H_SWAP
            FDB   DROPW

H_DUP:
            FCB   $03
            FCC   "DUP"
            FDB   H_DROP
            FDB   DUPW

H_DOTPAREN: FCB   $82
            FCC   ".("
            FDB   H_DUP
            FDB   DOTPARENW

H_LPAREN:
            FCB   $81
            FCC   "("
            FDB   H_DOTPAREN
            FDB   LPARENW

H_BACKSLASH:
            FCB   $81
            FCC   "\"
            FDB   H_LPAREN
            FDB   BACKSLASHW

BASELATEST  EQU   H_BACKSLASH         ; head of the ROM dictionary (see COLD). See shadow BASELATEST.2

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
            LDA   #CR_RESET         ; Master Software Reset. See bugfix: INITSERIAL.2
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
            JMP   THROWW

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
            JSR   WLINIT            ; FORTH wordlist, search order and CURRENT

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
            JMP   THROWW

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

            LDD   DPHERE            ; Checkpoint on the return stack. CATCH
            PSHS  D                 ; and THROW restore S, so the frame is
            LDD   CODEHERE          ; intact whichever way INTERPRET ends.
            PSHS  D                 ; See shadow QLOOP.2
            LDD   VARHERE
            PSHS  D
            LDD   LATEST
            PSHS  D

            LDD   #INTERPRET
            PSHU  D                 ; xt
            JSR   CATCHW
            PULU  D                 ; throw code (0 = no error)
            PSHS  D                 ; frame: 0,S code  2,S LATEST  4,S VARHERE
            CMPD  #0                ;        6,S CODEHERE  8,S DPHERE
            BEQ   QOK

            LDD   8,S
            STD   DPHERE
            JSR   PRUNE             ; unlink headers newer than DPHERE
            LDD   6,S
            STD   CODEHERE
            LDD   4,S
            STD   VARHERE
            LDD   2,S
            STD   LATEST
            LDU   #SP0

            ; Return to interpretation state after a caught error.
            ; See bugfix: QLOOP.1
            LDD   #0
            STD   STATE

            LDD   ,S                ; -1 is ABORT: reset silently, no "ERROR -1"
            CMPD  #-1
            BNE   QSHOWERR
            LEAS  10,S              ; drop the frame
            LBRA  QLOOP

QSHOWERR:   JSR   CRW
            LDX   #ERRMSG
            PSHU  X                 ; c-addr
            LDD   #ERRMSGL
            PSHU  D                 ; u
            JSR   TYPEW
            LDD   ,S
            PSHU  D                 ; n
            JSR   DOTW
            LEAS  10,S              ; drop the frame
            BRA   QLOOP

QOK:        LEAS  10,S              ; drop the frame
            JSR   CRW               ; See bugfix: QOK.1
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
;    Registers: RegD, RegX, RegY and CC changed.
; ------------------------------------------------------------
SETDOES:    PULS  X                 ; X = addr right after "JSR SETDOES" - new BEHAVIOR
            TFR   X,Y               ; Y = new BEHAVIOR, kept across the walk

            LDX   LATEST
            LDB   ,X
            ANDB  #$1F
            CLRA
            LEAX  D,X               ; header + name length
            LDD   3,X               ; D = CFA (trampoline address), past name and LINK
            ADDD  #3                ; +3 -> BEHAVIOR field (past JSR DODOES)
            TFR   D,X

            STY   ,X                ; patch it

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
            JMP   THROWW

; ------------------------------------------------------------
; BEHAVIOR of a MARKER word: restore the dictionary, code and variable
; pointers and LATEST from the four cells saved when it was defined,
; then the search order state (SRCHSAVESZ bytes after them), then
; unlink every RAM header newer than DPHERE from every wordlist.
; DOMARKER   ( pfa -- )
;    Inputs:
;        pfa on the data stack (the saved cells)
;    Outputs:
;        pfa removed; DPHERE, CODEHERE, VARHERE, LATEST, WLEND, CURRENT
;        and the search order restored; wordlists pruned
;    Registers: RegA, RegB, RegX, RegY and CC changed.
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
            LEAX  8,X               ; the saved search-order state follows
            LDY   #SRCHSAVE
            LDB   #SRCHSAVESZ
DMCOPY:     LDA   ,X+
            STA   ,Y+
            DECB
            BNE   DMCOPY
            LDD   DPHERE
            JMP   PRUNE             ; unlink headers newer than DPHERE

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
; field address (CODEHERE). LATEST, DPHERE and the head of the CURRENT
; wordlist are updated.
; HEADER   ( smudge-flag "name" -- )
;    Inputs:
;        smudge-flag on the data stack (non-zero hides the new word)
;        name parsed from the input stream
;    Outputs:
;        header built at DPHERE, linked into the CURRENT wordlist;
;        LATEST = address of the new header
;    Registers: RegA, RegB, RegX, RegY and CC changed.
; ------------------------------------------------------------
HEADER:     LDD   #32
            PSHU  D
            JSR   WORDW
            PULU  X                 ; c-addr of the name
            PULU  D                 ; smudge flag in B
            LDA   ,X+               ; name length, X = name text
            PSHS  A                 ; 2,S = length (5k: S-frame, no scratch)
            TSTB
            BEQ   HDNOSM
            ORA   #$40
HDNOSM:     LDY   DPHERE
            PSHS  Y                 ; 0,S = address of the new header
            STA   ,Y+
            LDB   2,S
            BEQ   HDNONM
HDCPY:      LDA   ,X+
            STA   ,Y+
            DECB
            BNE   HDCPY
HDNONM:     LDX   CURRENT           ; X = WID of the wordlist receiving the word
            LDD   ,X
            STD   ,Y++              ; LINK = old head of that wordlist
            LDD   CODEHERE
            STD   ,Y++
            STY   DPHERE
            PULS  D
            STD   LATEST            ; LATEST = newest header of any wordlist
            STD   ,X                ; and the new head of the CURRENT wordlist
            LEAS  1,S
            RTS

; ------------------------------------------------------------
; Toggle the smudge bit (bit 6 of the length|flags byte) of the newest
; header, the one LATEST names. A smudged word is hidden from FIND, so
; HEADER with a true flag, then SMUDGE once the word is complete,
; brackets the definition of a word such as CODE ... END-CODE.
; SMUDGE   ( -- )
;    Inputs:
;        none
;    Outputs:
;        bit 6 of the length|flags byte at LATEST inverted
;    Registers: RegA, RegX and CC changed.
; ------------------------------------------------------------
SMUDGEW:    LDX   LATEST
            LDA   ,X
            EORA  #$40
            STA   ,X
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
; Common start of every DODOES-style defining word: build a header
; and compile the DODOES trampoline followed by the behaviour address.
; BLDDOES
;    Inputs:
;        RegD = address of the behaviour routine
;    Outputs:
;        header built, trampoline and behaviour cell compiled
;    Registers: all changed.
; BLDSELF
;    Inputs:
;        RegD = address of the behaviour routine
;    Outputs:
;        as BLDDOES, then the PFA cell compiled pointing at the
;        cell that follows it (the word's own data field)
;    Registers: all changed.
; Used by CREATE, CONSTANT, 2CONSTANT, DEFER and MARKER (BLDSELF)
; and by VALUE (BLDDOES, which supplies its own PFA).
; ------------------------------------------------------------
BLDDOES:    PSHS  D                 ; behaviour address
            LDD   #0
            PSHU  D
            JSR   HEADER
            LDD   #DODOES
            PSHU  D
            JSR   CCALL
            PULS  D
            PSHU  D                 ; behaviour address
            JSR   CODECOMMA
            RTS

BLDSELF:    JSR   BLDDOES
            LDD   CODEHERE          ; PFA = the cell after this one
            ADDD  #2                ; See bugfix: CONSTANTW.1
            PSHU  D
            JSR   CODECOMMA
            RTS

; ------------------------------------------------------------
; CREATE  ( "name" -- )
; Build a header whose code is a DODOES trampoline. The default
; behaviour (DOESRT0) leaves the data-field address, the next free
; address in the code area, on the stack.
; ------------------------------------------------------------
CREATEW:    LDD   #DOESRT0
            JSR   BLDSELF           ; See bugfix: BLDSELF.1
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
FETCHW:     PULU  X                 ; a-addr
            LDD   ,X
            PSHU  D                 ; x
            RTS

; ------------------------------------------------------------
; CONSTANT  ( x "name" -- )
; Build a word that returns x. The value is stored in the code area
; after the trampoline and fetched with @.
; ------------------------------------------------------------
CONSTANTW:  LDD   #FETCHW
            JSR   BLDSELF           ; See bugfix: BLDSELF.1
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
VALUEW:     LDD   #DOVALUE
            JSR   BLDDOES
            LDD   VARHERE           ; PFA = VARHERE (writable space)
            PSHU  D                 ; See bugfix: VALUEW.1
            JSR   CODECOMMA
            JSR   VCOMMAW           ; store x in the variable area
            RTS

; ------------------------------------------------------------
; Behaviour of a 2VALUE word: fetch the two-cell value, x2 at the
; lower address as 2@ expects.
; DO2VALUE   ( pfa -- x1 x2 )
; ------------------------------------------------------------
DO2VALUE:   JMP   TWOFETCHW

; ------------------------------------------------------------
; 2VALUE  ( x1 x2 "name" -- )
; Build a word that returns x1 x2, which can be changed with TO. The
; two cells are kept in the variable area so that they are writable.
; ------------------------------------------------------------
TWOVALUEW:  LDD   #DO2VALUE
            JSR   BLDDOES
            LDD   VARHERE           ; PFA = VARHERE (writable space)
            PSHU  D
            JSR   CODECOMMA
            JSR   VCOMMAW           ; x2 at the lower address
            JSR   VCOMMAW           ; then x1
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
            JSR   THROWW
TOFOUND:    LDX   ,U                ; xt: is it a 2VALUE? (behaviour cell at xt+3)
            LDD   3,X
            CMPD  #DO2VALUE
            BEQ   TOTWO
            JSR   TOBODYW
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
TOTWO:      JSR   TOBODYW           ; 2VALUE: store x1 x2 with 2!
            LDD   STATE
            BEQ   TOTWOIMM
            JSR   LITERALW
            LDD   #TWOSTOREW
            PSHU  D
            JSR   CCALL
            RTS
TOTWOIMM:   JMP   TWOSTOREW

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
            LDD   #TWOFETCHW
            JSR   BLDSELF           ; See bugfix: BLDSELF.1
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
DEFERW:     LDD   #DODEFER
            JSR   BLDSELF           ; See bugfix: BLDSELF.1
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
            JSR   THROWW
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
            JSR   THROWW
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
; Save DPHERE, CODEHERE, VARHERE, LATEST and the search order state in
; a new word, which when executed restores them (forgetting everything
; defined since, in every wordlist).
; ------------------------------------------------------------
MARKERW:    LDD   DPHERE
            PSHS  D                 ; 6,S
            LDD   CODEHERE
            PSHS  D                 ; 4,S
            LDD   VARHERE
            PSHS  D                 ; 2,S
            LDD   LATEST
            PSHS  D                 ; 0,S
            LDD   #DOMARKER
            JSR   BLDSELF           ; See bugfix: BLDSELF.1
            LDD   6,S
            PSHU  D
            JSR   COMMAW
            LDD   4,S
            PSHU  D
            JSR   COMMAW
            LDD   2,S
            PSHU  D
            JSR   COMMAW
            LDD   ,S
            PSHU  D
            JSR   COMMAW
            LDX   CODEHERE          ; then the search order state
            LDY   #SRCHSAVE
            LDB   #SRCHSAVESZ
MKCOPY:     LDA   ,Y+
            STA   ,X+
            DECB
            BNE   MKCOPY
            STX   CODEHERE
            LEAS  8,S
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
            JSR   THROWW

IDONE:      PULU  X                 ; c-addr from WORD (empty). See bugfix: INTERPRET.4
            RTS

; ------------------------------------------------------------
; WORD  ( char "<chars>ccc<char>" -- c-addr )
; Skip leading delimiters, then parse text up to the next char from
; the input source. The text is stored as a counted string at
; CODEHERE, which is not advanced. An exhausted input gives a zero
; count. Its scratch lives in an S frame; see shadow WORDW.7.
; ------------------------------------------------------------
WORDW:      PULU  D                 ; char
            LEAS  -3,S              ; frame (5k): 0,S = delimiter,
            STB   ,S                ; 1,S = start of the text
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
            CMPA  ,S
            BNE   STARTW
            LEAX  1,X
            LEAY  -1,Y
            BRA   SKIPLP

STARTW:     STX   1,S
            LDB   #0

SCANLP:     CMPY  #0
            BEQ   ENDW
            LDA   ,X
            CMPA  ,S
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
            LDY   1,S
COPYLP:     TSTB
            BEQ   COPYDONE
            LDA   ,Y+
            STA   ,X+
            DECB
            BRA   COPYLP
COPYDONE:   LEAS  3,S               ; drop the frame
            LDX   CODEHERE          ; Result address (see WORDW.4)
            PSHU  X                 ; c-addr
            RTS

EMPTY:      LEAS  3,S               ; drop the frame
            LDX   CODEHERE          ; Empty string at the result buffer
            CLR   ,X
            PSHU  X                 ; c-addr
            RTS

; ------------------------------------------------------------
; Search one chain of headers for a name, ignoring smudged entries.
; Case matters. A zero-length name matches a zero-length header.
; The Search-Order design is in shadow SEARCHORDER.1.
; FDSEARCH
;    Inputs:
;        RegX = first header of the chain (0 = empty chain)
;        RegY = address of the name text
;        RegB = name length
;    Outputs:
;        RegX = the matching header, or 0 if there is none
;    Registers: RegA, RegB, RegX, RegY and CC changed.
; ------------------------------------------------------------
FDSEARCH:   PSHS  Y,B               ; 0,S = length, 1,S = name text
FDLOOP:     CMPX  #0
            BEQ   FDRET
            LDA   ,X
            BITA  #$40
            BNE   FDNEXT            ; smudged
            ANDA  #$1F
            CMPA  ,S
            BNE   FDNEXT
            PSHS  X                 ; header, kept across the compare
            LEAX  1,X
            LDY   3,S               ; name text
            LDB   2,S               ; length
            BEQ   FDHIT
FDCMP:      LDA   ,X+
            CMPA  ,Y+
            BNE   FDMISS
            DECB
            BNE   FDCMP
FDHIT:      PULS  X                 ; header
            BRA   FDRET
FDMISS:     PULS  X
FDNEXT:     LDB   ,X
            ANDB  #$1F
            CLRA
            LEAX  1,X
            LEAX  D,X
            LDX   ,X                ; LINK field
            BRA   FDLOOP
FDRET:      LEAS  3,S
            RTS

; ------------------------------------------------------------
; Search every wordlist of the search order, first to last, and then
; ROOT, for a name.
; SRCHORD
;    Inputs:
;        RegY = address of the name text
;        RegB = name length
;    Outputs:
;        RegX = the matching header, or 0 if there is none
;    Registers: RegA, RegB, RegX, RegY and CC changed.
; ------------------------------------------------------------
SRCHORD:    PSHS  Y,B               ; 0,S = length, 1,S = name text
            LDX   #ORDER
            PSHS  X                 ; 0,S = next ORDER cell (length is now 2,S)
SOLOOP:     LDX   ,S
            CMPX  ORDEND
            BHS   SOROOT
            LDY   ,X++              ; WID
            STX   ,S
            LDX   ,Y                ; newest header of that wordlist
            LDY   3,S
            LDB   2,S
            BSR   FDSEARCH
            CMPX  #0
            BEQ   SOLOOP
            BRA   SORDONE
SOROOT:     LDX   WLHEADS+2         ; ROOT
            LDY   3,S
            LDB   2,S
            BSR   FDSEARCH
SORDONE:    LEAS  5,S
            RTS

; ------------------------------------------------------------
; Split a header into its xt and its immediate flag.
; HDRXT
;    Inputs:
;        RegX = header
;    Outputs:
;        RegX = xt (the CFA field), RegA = length|flags byte
;    Registers: RegA, RegB, RegX and CC changed.
; ------------------------------------------------------------
HDRXT:      LDA   ,X
            TFR   A,B
            ANDB  #$1F
            LEAX  1,X
            ABX
            LDX   2,X               ; CFA field
            RTS

; ------------------------------------------------------------
; FIND  ( c-addr -- c-addr 0 | xt 1 | xt -1 )
; Look up the counted string in the search order, then in ROOT, ignoring
; smudged entries. Returns the xt and 1 if the word is immediate, or
; -1 if not. If not found, returns c-addr and 0.
; Holds no scratch cells; see shadow FINDW.1 and SEARCHORDER.1.
; ------------------------------------------------------------
FINDW:      LDY   ,U                ; counted string
            LDB   ,Y+
            BSR   SRCHORD
            CMPX  #0
            BEQ   NOTFOUND
            BSR   HDRXT
            STX   ,U                ; xt replaces c-addr
            TSTA
            BPL   FISNORM
            LDD   #1
            BRA   FPUSH
FISNORM:    LDD   #-1
FPUSH:      PSHU  D                 ; 1 = immediate, -1 = normal
            RTS

NOTFOUND:   LDD   #0
            PSHU  D                 ; 0 = not found, c-addr still beneath
            RTS

; ------------------------------------------------------------
; SEARCH-WORDLIST  ( c-addr u wid -- 0 | xt 1 | xt -1 )
; Search the one wordlist wid for the name c-addr u. Returns 0 if it is
; not found, else its xt and 1 if the word is immediate or -1 if not.
; Throws -11 for an invalid wid.
; ------------------------------------------------------------
SEARCHWLW:  PULU  X                 ; wid
            BSR   WIDCHK
            LDX   ,X                ; newest header of the wordlist
            PULU  D                 ; u
            PULU  Y                 ; c-addr
            TSTA
            BNE   SWNOT             ; longer than any name
            CMPB  #31
            BHI   SWNOT
            JSR   FDSEARCH
            CMPX  #0
            BEQ   SWNOT
            BSR   HDRXT
            PSHU  X                 ; xt
            TSTA
            BPL   SWNORM
            LDD   #1
            BRA   SWPUSH
SWNORM:     LDD   #-1
SWPUSH:     PSHU  D
            RTS
SWNOT:      LDD   #0
            PSHU  D
            RTS

; ------------------------------------------------------------
; Throw -11 unless RegX is the address of a wordlist cell in use.
; WIDCHK
;    Inputs:
;        RegX = candidate WID
;    Outputs:
;        none if valid (RegX and RegY unchanged); THROW -11 if not
;    Registers: RegD and CC changed.
; ------------------------------------------------------------
WIDCHK:     TFR   X,D
            SUBD  #WLHEADS
            BCS   WIDBAD
            BITB  #1
            BNE   WIDBAD
            CMPX  WLEND
            BHS   WIDBAD
            RTS
WIDBAD:     LDD   #-11
            PSHU  D
            JMP   THROWW

; ------------------------------------------------------------
; Set the Search-Order state to its initial value: two wordlists
; (FORTH, holding the ROM dictionary, and ROOT), the search order
; FORTH, and CURRENT = FORTH.
; WLINIT
;    Inputs:
;        none
;    Outputs:
;        WLHEADS, WLNAMES (FORTH, ROOT), WLEND, CURRENT, ORDER, ORDEND set
;    Registers: RegD and CC changed.
; ------------------------------------------------------------
WLINIT:     LDD   #BASELATEST
            STD   WLHEADS
            LDD   #BASEROOTLATEST
            STD   WLHEADS+2
            LDD   #H_FORTH
            STD   WLNAMES
            LDD   #H_ROOT
            STD   WLNAMES+2
            LDD   #WLHEADS+4
            STD   WLEND
            LDD   #WLHEADS
            STD   CURRENT
            JMP   ONLYW             ; the order is FORTH only

; ------------------------------------------------------------
; Remove from every wordlist the RAM headers that are at or above a
; mark. Headers are allocated upwards from DPHERE, so these are the
; newest ones of each chain. ROM headers are never touched.
; PRUNE
;    Inputs:
;        RegD = mark (a DPHERE value)
;    Outputs:
;        the head of every wordlist in use points below the mark or
;        into ROM
;    Registers: RegD, RegX, RegY and CC changed.
; ------------------------------------------------------------
PRUNE:      PSHS  D                 ; 0,S = mark
            LDX   #WLHEADS
PRLOOP:     CMPX  WLEND
            BHS   PRNDONE
            LDY   ,X                ; newest header of this wordlist
PRWALK:     CMPY  #ROMSTRT
            BHS   PRSTORE           ; ROM header: keep
            CMPY  ,S
            BLO   PRSTORE           ; below the mark (or empty): keep
            LDB   ,Y
            ANDB  #$1F
            CLRA
            LEAY  1,Y
            LEAY  D,Y
            LDY   ,Y                ; follow the LINK
            BRA   PRWALK
PRSTORE:    STY   ,X++
            BRA   PRLOOP
PRNDONE:     LEAS  2,S
            RTS

; ============================================================
; SECTION 9A: SEARCH-ORDER WORD SET
; ============================================================
; ------------------------------------------------------------
; WORDLIST  ( -- wid )
; Create a new, empty wordlist. Throws -8 when all WLCELLS are in use.
; ------------------------------------------------------------
WORDLISTW:  LDX   WLEND
            CMPX  #WLHEADS+2*WLCELLS
            BHS   WLFULL
            LDD   #0
            STD   ,X
            STD   WLNOFF,X
            PSHU  X
            LEAX  2,X
            STX   WLEND
            RTS
WLFULL:     LDD   #-8
            PSHU  D
            JMP   THROWW

; ------------------------------------------------------------
; FORTH-WORDLIST  ( -- wid )
; Push the WID of the wordlist holding the standard words.
; ------------------------------------------------------------
FORTHWLW:   LDD   #WLHEADS
            PSHU  D
            RTS

; ------------------------------------------------------------
; GET-ORDER  ( -- widn ... wid1 n )
; Return the search order: wid1 is searched first. ROOT is not part of
; it, as it is always searched last.
; ------------------------------------------------------------
GETORDERW:  LDX   ORDEND
GOLOOP:     CMPX  #ORDER
            BLS   GODONE
            LDD   ,--X
            PSHU  D
            BRA   GOLOOP
GODONE:     LDD   ORDEND
            SUBD  #ORDER
            LSRA
            RORB
            PSHU  D                 ; n
            RTS

; ------------------------------------------------------------
; SET-ORDER  ( widn ... wid1 n -- )
; Set the search order. n = -1 selects the minimum order (FORTH only).
; n = 0 empties it (ROOT can still be searched). Throws -49 when n is
; more than 8, -50 when n is less than -1 and -11 for an invalid wid.
; ------------------------------------------------------------
SETORDERW:  PULU  D                 ; n
            CMPD  #-1
            BEQ   ONLYW             ; the minimum order
SO1:        TSTA
            BMI   SOUNDER
            BNE   SOOVER
            CMPB  #WLMAX
            BHI   SOOVER
            PSHS  B                 ; 1,S = n
            PSHS  B                 ; 0,S = count down
            TFR   U,Y
SOCHK:      TST   ,S
            BEQ   SOCOPY
            LDX   ,Y++
            JSR   WIDCHK            ; keeps Y
            DEC   ,S
            BRA   SOCHK
SOCOPY:     PULS  A,B               ; B = n
            LDX   #ORDER
SOCP2:      TSTB
            BEQ   SOCPEND
            PULU  Y
            STY   ,X++
            DECB
            BRA   SOCP2
SOCPEND:    STX   ORDEND
            RTS
SOOVER:     LDD   #-49
            BRA   SOTHROW
SOUNDER:    LDD   #-50
SOTHROW:    PSHU  D
            JMP   THROWW

; ------------------------------------------------------------
; GET-CURRENT  ( -- wid )
; Return the WID of the wordlist that receives new definitions.
; ------------------------------------------------------------
GETCURW:    LDD   CURRENT
            PSHU  D
            RTS

; ------------------------------------------------------------
; SET-CURRENT  ( wid -- )
; Make wid the wordlist that receives new definitions. Throws -11 for
; an invalid wid.
; ------------------------------------------------------------
SETCURW:    PULU  X
            JSR   WIDCHK
            STX   CURRENT
            RTS

; ------------------------------------------------------------
; DEFINITIONS  ( -- )
; Make the first wordlist of the search order the one that receives new
; definitions. Throws -50 when the search order is empty.
; ------------------------------------------------------------
DEFINITIONSW:
            LDX   #ORDER
            CMPX  ORDEND
            BHS   DFUNDER
            LDD   ,X
            STD   CURRENT
            RTS
DFUNDER:    LDD   #-50
            PSHU  D
            JMP   THROWW

; ------------------------------------------------------------
; ONLY  ( -- )
; Set the minimum search order: FORTH only (ROOT is still searched).
; ------------------------------------------------------------
ONLYW:      LDD   #WLHEADS
            STD   ORDER
            LDD   #ORDER+2
            STD   ORDEND
            RTS

; ------------------------------------------------------------
; Replace the first wordlist of the search order with the WID in RegX,
; or make it the only one if the order is empty.
; SETTOP
;    Inputs:
;        RegX = WID
;    Outputs:
;        ORDER(0) = WID; ORDEND at least ORDER+2
;    Registers: RegD and CC changed.
; ------------------------------------------------------------
SETTOP:     STX   ORDER
            LDD   ORDEND
            CMPD  #ORDER+2
            BHS   STDONE
            LDD   #ORDER+2
            STD   ORDEND
STDONE:     RTS

; ------------------------------------------------------------
; FORTH  ( -- )
; Replace the first wordlist of the search order with FORTH-WORDLIST.
; ------------------------------------------------------------
FORTHW:     LDX   #WLHEADS
            BRA   SETTOP

; ------------------------------------------------------------
; ROOT  ( -- )
; Replace the first wordlist of the search order with ROOT.
; ------------------------------------------------------------
ROOTW:      LDX   #WLHEADS+2
            BRA   SETTOP

; ------------------------------------------------------------
; PREVIOUS  ( -- )
; Remove the first wordlist from the search order. Throws -50 if the
; order is empty.
; ------------------------------------------------------------
PREVIOUSW:  LDX   ORDEND
            CMPX  #ORDER
            BLS   DFUNDER
            LEAX  -2,X
            STX   ORDEND
            LDX   #ORDER            ; close the gap at the front
PVLOOP:     CMPX  ORDEND
            BHS   PVDONE
            LDD   2,X
            STD   ,X++
            BRA   PVLOOP
PVDONE:     RTS

; ------------------------------------------------------------
; ALSO  ( -- )
; Duplicate the first wordlist of the search order. Throws -50 if the
; order is empty and -49 if it is full.
; ------------------------------------------------------------
ALSOW:      LDX   ORDEND
            CMPX  #ORDER
            BLS   DFUNDER
            CMPX  #ORDER+2*WLMAX
            BHS   SOOVER
            LEAX  2,X
            STX   ORDEND
ALLOOP:     LDD   -4,X              ; open a gap at the front
            STD   -2,X
            LEAX  -2,X
            CMPX  #ORDER+2
            BHI   ALLOOP
            RTS

; ------------------------------------------------------------
; The behaviour of a word made by VOCABULARY: replace the first
; wordlist of the search order with the wordlist whose WID is in the
; word's data field.
; DOVOCAB   ( pfa -- )
; ------------------------------------------------------------
DOVOCAB:    PULU  X
            LDX   ,X
            BRA   SETTOP

; ------------------------------------------------------------
; VOCABULARY  ( "name" -- )
; Create a new wordlist and a word that makes it the first wordlist of
; the search order. The word's header is recorded for ORDER.
; Throws -8 when all the wordlists are in use.
; ------------------------------------------------------------
VOCABULARYW:
            JSR   WORDLISTW
            LDD   #DOVOCAB
            JSR   BLDSELF
            LDX   ,U                ; WID
            LDD   LATEST
            STD   WLNOFF,X          ; the header of the naming word
            JMP   COMMAW

; ------------------------------------------------------------
; Display a wordlist: its name if it has one, else its WID, then a space.
; PRWID
;    Inputs:
;        RegD = WID
;    Outputs:
;        text sent with TYPE and SPACE or "."
;    Registers: RegD, RegX, RegY and CC changed.
; ------------------------------------------------------------
PRWID:      PSHS  D
            TFR   D,X
            LDX   WLNOFF,X
            BEQ   PRNUM
            CMPX  #ROMSTRT
            BHS   PRNAME
            CMPX  DPHERE
            BHS   PRNUM             ; a name that has been forgotten
PRNAME:     LDB   ,X
            ANDB  #$1F
            CLRA
            LEAX  1,X
            PSHU  X
            PSHU  D
            JSR   TYPEW
            JSR   SPACEW
            LEAS  2,S
            RTS
PRNUM:      PULS  D
            PSHU  D
            JMP   DOTW

; ------------------------------------------------------------
; ORDER  ( -- )
; Display the search order, first wordlist first, then the wordlist
; that receives new definitions.
; ------------------------------------------------------------
ORDERW:     LDX   #ORDER
            PSHS  X                 ; next ORDER cell
OLOOP:      LDX   ,S
            CMPX  ORDEND
            BHS   ODONE
            LDD   ,X++
            STX   ,S
            BSR   PRWID
            BRA   OLOOP
ODONE:      LEAS  2,S
            LDX   #CURMSG
            PSHU  X
            LDD   #CURMSGL
            PSHU  D
            JSR   TYPEW
            LDD   CURRENT
            BSR   PRWID
            JMP   CRW
CURMSG:     FCC   " Current: "
CURMSGL     EQU   *-CURMSG

; ------------------------------------------------------------
; Multiply the unsigned double ud on the data stack by BASE and add a
; digit. (5m: the accumulator lives on the data stack, in the frame of
; >NUMBER, so no page-zero cells are needed.)
; UDMULADD
;    Inputs:
;        ud at 4,U (high cell) and 6,U (low cell), as in the >NUMBER
;        frame ( ud c-addr u )
;        RegB = digit value to add
;        BASE
;    Outputs:
;        ud = ud * BASE + digit
;    Registers: RegA, RegB and CC changed.
; ------------------------------------------------------------
UDMULADD:   LEAS  -2,S              ; 0,S = carry, 1,S = BASE multiplier
            STB   ,S
            LDA   BASE+1
            STA   1,S
            LDA   7,U
            LDB   1,S
            MUL
            ADDB  ,S
            BCC   UM0
            INCA
UM0:        STB   7,U
            STA   ,S
            LDA   6,U
            LDB   1,S
            MUL
            ADDB  ,S
            BCC   UM1
            INCA
UM1:        STB   6,U
            STA   ,S
            LDA   5,U
            LDB   1,S
            MUL
            ADDB  ,S
            BCC   UM2
            INCA
UM2:        STB   5,U
            STA   ,S
            LDA   4,U
            LDB   1,S
            MUL
            ADDB  ,S
            BCC   UM3
            INCA
UM3:        STB   4,U
            LEAS  2,S
            RTS

; ------------------------------------------------------------
; >NUMBER  ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
; Convert the string into ud1, in BASE, stopping at the first
; unconvertible character. Returns the accumulated ud2 and the
; remaining string. The conversion works in place on the three
; parameters (NUMLOOP), which are also the frame NUMBERQ builds.
; NUMLOOP
;    Inputs:
;        ( ud c-addr u ) on the data stack
;    Outputs:
;        ud accumulated; c-addr u = first unconverted character and
;        the count remaining
;    Registers: RegA, RegB, RegX and CC changed.
; ------------------------------------------------------------
TONUMBERW:
NUMLOOP:    LDD   ,U
            BEQ   NLDONE
            LDX   2,U
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
            LDX   2,U
            LEAX  1,X
            STX   2,U
            LDD   ,U
            SUBD  #1
            STD   ,U
            BRA   NUMLOOP
NLDONE:     RTS

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
;    Registers: RegA, RegB, RegX, RegY and CC changed.
; The original c-addr and the negate flag live in an S frame (0,S and
; 2,S); the count is kept in RegB. See shadow NUMBERQ.1 and
; NUMBERQ.6.
; ------------------------------------------------------------
NUMBERQ:    PULU  X                 ; c-addr
            LEAS  -3,S
            STX   ,S
            LDB   ,X
            BEQ   NQBAD
            LEAX  1,X

            ; A trailing "." means a double number: leave it out of the
            ; digit count. See shadow: NUMBERQ.1
            DECB
            LDA   B,X
            INCB
            CMPA  #'.'
            BNE   NQNOSIGN
            DECB
            BEQ   NQBAD             ; lone "." with nothing before it

NQNOSIGN:   CLR   2,S
            LDA   ,X
            CMPA  #'-'
            BNE   NQNOSIGN2
            COM   2,S
            LEAX  1,X
            DECB
            BEQ   NQBAD

NQNOSIGN2:  LDY   #0
            PSHU  Y                 ; ud low
            PSHU  Y                 ; ud high
            PSHU  X                 ; c-addr
            CLRA
            PSHU  D                 ; u

            JSR   NUMLOOP

            LDD   ,U
            BNE   NQBADF            ; unconverted characters remain
            LEAU  4,U               ; drop u and c-addr: ud remains

            ; Negate the full 32-bit value. See bugfix: NUMBERQ.2
            TST   2,S
            BEQ   NQPOS32
            LDD   ,U
            COMA
            COMB
            STD   ,U
            LDD   2,U
            COMA
            COMB
            ADDD  #1
            STD   2,U
            BCC   NQPOS32
            LDD   ,U
            ADDD  #1
            STD   ,U

NQPOS32:                            ; re-derive from the original c-addr whether the
            ; last character was '.' - determines which return convention
            LDX   ,S
            LDB   ,X
            DECB
            LEAX  1,X
            LDA   B,X
            LEAS  3,S
            CMPA  #'.'
            BNE   NQSINGLE

            ; DOUBLE success: ud is already low below high; add a
            ; distinct success code (1, not -1) so TRYNUM can tell
            ; single and double apart
            LDD   #1
            PSHU  D
            RTS

NQSINGLE:   LEAU  2,U               ; SINGLE success: drop the high cell
            LDD   #-1
            PSHU  D
            RTS

NQBADF:     LEAU  8,U               ; drop the frame
NQBAD:      LDX   ,S
            LEAS  3,S
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
ACCEPTW:    LEAU  -2,U              ; local count at 0,U; then +n1 at 2,U and
            LDD   #0                ; c-addr at 4,U. See shadow ACCEPTW.5
            STD   ,U

            IFEQ  SERIALPOLL        ; >>>>>>>>>>  interrupt-driven build: real
                                    ; RTS/CTS hardware flow control already
                                    ; covers this, nothing extra needed
            ELSE                    ; <<<<<>>>>>  polling build: tell the host it's safe to
                                    ; stream this line's characters
            JSR   PUTXON
            ENDC                    ; <<<<<<<<<<

ALOOP:      JSR   KEYW
            PULU  D
            TFR   D,Y               ; Y = the character

            CMPB  #13
            BEQ   ADONE
            CMPB  #10
            BEQ   ALOOP
            CMPB  #8
            BEQ   ABKSP
            CMPB  #127
            BEQ   ABKSP

            LDD   ,U
            CMPD  2,U
            BEQ   ALOOP

            LDX   4,U
            LEAX  D,X
            TFR   Y,D
            STB   ,X
            LDD   ,U
            ADDD  #1
            STD   ,U

            TFR   Y,D
            CLRA
            PSHU  D
            JSR   EMITW
            BRA   ALOOP

ABKSP:      LDD   ,U
            BEQ   ALOOP
            SUBD  #1
            STD   ,U
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
            LDD   ,U
            STD   4,U               ; +n2
            LEAU  4,U
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
            JSR   THROWW
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
THROWW:     PULU  D                 ; n
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
;    Registers: RegD and RegX changed.
; ------------------------------------------------------------
PATCH:      PULU  X                 ; location
            PULU  D                 ; target
            PSHS  X
            SUBD  ,S++              ; target - location
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
            PSHS  D                 ; See bugfix: ELSEW.1 (5k: kept on S)
            LDD   #BRANCH
            PSHU  D
            JSR   CCALL
            LDD   #0
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE
            PSHU  D
            PULS  D                 ; orig1
            PSHU  D
            JSR   PATCH
            LDD   CODEHERE
            SUBD  #2
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
            PSHU  D                 ; location; the parked dest is beneath
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
            PSHU  D                 ; location; the parked dest is beneath
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
            PSHS  X                 ; 2,S = orig (5k: S-frame)

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
            PSHS  D                 ; 0,S = dest

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
            LDD   0,S               ; target = BEGIN's address
            PSHU  D
            LDD   CODEHERE
            SUBD  #2                ; location = the operand just compiled
            PSHU  D
            JSR   PATCH
            LDD   CODEHERE
            PSHU  D
            LDD   2,S               ; orig
            PSHU  D
            JSR   PATCH
            LEAS  4,S               ; drop the frame
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
IW:         LDD   2,S               ; n. See bugfix: IW.1
            PSHU  D
            RTS

; ------------------------------------------------------------
; J  ( -- n )
; Push the index of the next outer loop (8,S, beyond the return
; address and the inner loop frame).
; ------------------------------------------------------------
JW:         LDD   8,S               ; n. See bugfix: JW.1
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
            PSHU  D                 ; location; the parked dest is beneath
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
            PSHU  D                 ; location; the parked dest is beneath
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
EXITW:      LDY   #0                ; Y = count of DO frames (5k: no scratch)
            TFR   U,X               ; X = scan pointer
EXSCAN:     CMPX  CSP
            BEQ   EXSCANDONE
            LDD   ,X
            CMPD  #TAGDO
            BNE   EXNOTDO
            LEAY  1,Y
EXNOTDO:    LEAX  4,X
            BRA   EXSCAN
EXSCANDONE:
            PSHS  Y                 ; the count survives CCALL on S
            LDD   #EXITUNLOOP
            PSHU  D
            JSR   CCALL
            PULS  D
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
            PSHS  D                 ; See bugfix: ENDOFW.1 (5k: kept on S)
            LDD   #BRANCH
            PSHU  D
            JSR   CCALL
            LDD   #0
            PSHU  D
            JSR   CODECOMMA
            LDD   CODEHERE
            PSHU  D
            PULS  D                 ; orig1
            PSHU  D
            JSR   PATCH
            LDD   CODEHERE
            SUBD  #2
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
            JSR   THROWW
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
; 2LITERAL  ( x1 x2 -- )  IMMEDIATE
; Compile two LITs so that x1 x2 are pushed when the definition runs.
; ------------------------------------------------------------
TWOLITERALW:
            PULU  D                 ; x2
            PSHS  D
            JSR   LITERALW          ; x1 first, so it lands below x2
            PULS  D
            PSHU  D
            JSR   LITERALW
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
            JSR   THROWW
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
            JSR   THROWW
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
            JSR   THROWW
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
            JSR   THROWW
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
; Original comment: shadow BRACKCOMPILEW.0.
; ------------------------------------------------------------
BRACKCOMPILEW:
            LDD   STATE
            BNE   XCSTOK
            LDD   #-14
            PSHU  D
            JSR   THROWW
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
            JSR   THROWW
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
            JSR   THROWW
SLSTOK:     LDD   #DOSTR
            JMP   CSTRCOMP          ; compile DOSTR and the counted string

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
;    Registers: RegA, RegB, RegD, RegX, RegY changed.
; ------------------------------------------------------------
DOABORTQUOTE:
            PULS  X
            LDB   ,X
            LEAX  1,X               ; X = text, B = length
            CLRA
            PULU  Y                 ; flag
            CMPY  #0
            BNE   AQTHROW
            LEAX  B,X
            PSHS  X
            RTS
AQTHROW:    PSHU  X
            PSHU  D
            JSR   TYPEW
            LDD   #-2               ; -2
            PSHU  D
            JMP   THROWW

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
            JSR   THROWW
AQSTOK:     JSR   PARSEQUOTE        ; See bugfix: SQUOTEW.3
            LDD   #DOABORTQUOTE
            JMP   CSTRCOMP

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
NUMTIBW:    LDD   #NTIB
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
DEPTHW:     LDD   #SP0
            PSHS  U
            SUBD  ,S++
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
ROLLW:      LDD   ,U++              ; u (LDD sets CC; PULU would not). See
            BEQ   ROLLDONE          ; bugfix: ROLLW.1
            TFR   D,Y               ; Y = cells to shift
            LSLB
            ROLA
            LEAX  D,U               ; X = xu
            LDD   ,X
            PSHS  D                 ; xu waits on the return stack
RLOOP:      LDD   -2,X
            STD   ,X
            LEAX  -2,X
            LEAY  -1,Y
            BNE   RLOOP
            PULS  D
            STD   ,U
ROLLDONE:   RTS

; ------------------------------------------------------------
; 2ROT  ( x1 x2 x3 x4 x5 x6 -- x3 x4 x5 x6 x1 x2 )
; Rotate the third cell pair to the top. X and Y hold the pair
; while the others move.
; ------------------------------------------------------------
DROTW:      LDX   10,U              ; x1
            LDY   8,U               ; x2
            LDD   6,U
            STD   10,U
            LDD   4,U
            STD   8,U
            LDD   2,U
            STD   6,U
            LDD   0,U
            STD   4,U
            STY   ,U
            STX   2,U
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
TWOTORW:    PULS  X                 ; return address
            PULU  D                 ; x2
            PULU  Y                 ; x1
            PSHS  Y
            PSHS  D
            PSHS  X
            RTS

; ------------------------------------------------------------
; 2R>  ( -- x1 x2 )  ( R: x1 x2 -- )
; Move a cell pair from the return stack. The
; return address of this call is on top of S, so it is lifted off and
; put back around the transfer.
; ------------------------------------------------------------
TWOFROMRW:  PULS  X                 ; return address
            PULS  D                 ; x2
            PULS  Y                 ; x1
            PSHS  X
            PSHU  Y
            PSHU  D
            RTS

; ------------------------------------------------------------
; 2R@  ( -- x1 x2 )  ( R: x1 x2 -- x1 x2 )
; Copy the top cell pair of the return stack.
; The return address of this call is on top of S, so it is lifted off
; and put back around the transfer.
; ------------------------------------------------------------
TWORFETCHW: PULS  X                 ; return address
            LDD   ,S                ; x2
            LDY   2,S               ; x1
            PSHS  X
            PSHU  Y
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
            PSHS  D                 ; partial product on the return stack
            LDA   MAHI
            LDB   MBLO
            MUL
            ADDB  ,S                ; cross term into the high byte
            STB   ,S
            LDA   MALO
            LDB   MBHI
            MUL
            ADDB  ,S
            STB   ,S
            PULS  D                 ; 16-bit result. See shadow MVSCRATCH.1
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
            JSR   THROWW
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
            JSR   THROWW
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
            JSR   THROWW
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
            JSR   THROWW
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
            JSR   THROWW
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

; ------------------------------------------------------------
; D0=  ( xd -- flag )
; True if the double is zero.
; ------------------------------------------------------------
DZEROEQW:   LDD   ,U                ; high cell
            BNE   DZEFALSE
            LDD   2,U               ; low cell
            BNE   DZEFALSE
            LDD   #TRUEV
            BRA   DZEDONE
DZEFALSE:   LDD   #FALSEV
DZEDONE:    LEAU  2,U
            STD   ,U
            RTS

; ------------------------------------------------------------
; D0<  ( d -- flag )
; True if the double is negative.
; ------------------------------------------------------------
DZEROLTW:   LDD   ,U                ; high cell holds the sign
            BMI   DZLTRUE
            LDD   #FALSEV
            BRA   DZLDONE
DZLTRUE:    LDD   #TRUEV
DZLDONE:    LEAU  2,U
            STD   ,U
            RTS

; ------------------------------------------------------------
; D2*  ( xd1 -- xd2 )
; Shift the double left one bit.
; ------------------------------------------------------------
DTWOSTARW:  LDD   2,U               ; low cell
            ASLB
            ROLA
            STD   2,U               ; STD leaves the carry alone
            LDD   ,U                ; neither does LDD
            ROLB
            ROLA
            STD   ,U
            RTS

; ------------------------------------------------------------
; D2/  ( xd1 -- xd2 )
; Arithmetic shift of the double right one bit; the sign is kept.
; ------------------------------------------------------------
DTWOSLASHW: LDD   ,U                ; high cell
            ASRA
            RORB
            STD   ,U
            LDD   2,U               ; low cell takes the bit shifted out
            RORA
            RORB
            STD   2,U
            RTS

; ------------------------------------------------------------
; M*/  ( d1 n1 +n2 -- d2 )
; Multiply d1 by n1 into a 48-bit intermediate product and divide it
; by n2. The quotient is truncated toward zero (like */ and symmetric
; division in this system) and its low 32 bits are returned. THROW -10
; if n2 is zero. Method: take the magnitudes; form |d1.lo|*|n1| and
; |d1.hi|*|n1| with UMUL32 and add them into three words P2:P1:P0;
; then divide P2, then R:P1, then R:P0 by |n2| with UDIV32, each a
; 32/16 division whose quotient fits in 16 bits. The sign is applied
; to the 32-bit result at the end. See shadow M*/W.1.
; M*/W
;    Inputs:
;        d1 n1 n2 on the data stack (n2 on top)
;    Outputs:
;        d2 on the data stack
;    Registers: RegD, RegX changed; PRODHI/PRODLO, DIVDEN, DIVREM,
;        MAHI-MBLO used. S frame: 0,S sign, 1,S P0, 3,S P1, 5,S P2.
; ------------------------------------------------------------
MSTARSLASHW:
            LDD   ,U
            BNE   MSLOK
            LDD   #-10              ; -10, division by zero
            PSHU  D
            JSR   THROWW
MSLOK:      LEAS  -7,S
            CLR   ,S                ; sign of the result
            LDD   ,U                ; |n2|
            BPL   MSLN1
            COM   ,S
            COMA
            COMB
            ADDD  #1
            STD   ,U
MSLN1:      LDD   2,U               ; |n1|
            BPL   MSLD1
            COM   ,S
            COMA
            COMB
            ADDD  #1
            STD   2,U
MSLD1:      LDD   4,U               ; |d1|
            BPL   MSLMUL
            COM   ,S
            LDD   6,U
            STD   PRODLO
            LDD   4,U
            STD   PRODHI
            JSR   MNEG32
            LDD   PRODLO
            STD   6,U
            LDD   PRODHI
            STD   4,U
MSLMUL:     LDD   6,U               ; d1 low * n1
            STA   MAHI
            STB   MALO
            LDD   2,U
            STA   MBHI
            STB   MBLO
            JSR   UMUL32
            LDD   PRODLO
            STD   1,S               ; P0
            LDD   PRODHI
            STD   3,S               ; P1 so far
            LDD   4,U               ; d1 high * n1
            STA   MAHI
            STB   MALO
            LDD   2,U
            STA   MBHI
            STB   MBLO
            JSR   UMUL32
            LDD   3,S
            ADDD  PRODLO
            STD   3,S               ; P1
            LDD   PRODHI
            ADCB  #0
            ADCA  #0
            STD   5,S               ; P2
            LDD   ,U                ; divisor
            STD   DIVDEN
            CLR   PRODHI
            CLR   PRODHI+1
            LDD   5,S
            STD   PRODLO
            JSR   UDIV32            ; remainder only; the quotient is above bit 31
            LDD   DIVREM
            STD   PRODHI
            LDD   3,S
            STD   PRODLO
            JSR   UDIV32
            LDD   PRODLO
            STD   3,S               ; q1
            LDD   DIVREM
            STD   PRODHI
            LDD   1,S
            STD   PRODLO
            JSR   UDIV32            ; PRODLO = q0
            LDD   3,S
            STD   PRODHI            ; PRODHI:PRODLO = q1:q0
            TST   ,S
            BEQ   MSLPOS
            JSR   MNEG32
MSLPOS:     LEAU  4,U               ; drop n2 and n1
            LDD   PRODHI
            STD   ,U
            LDD   PRODLO
            STD   2,U
            LEAS  7,S
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
TWOFETCHW:  PULU  X                 ; a-addr. See bugfix: TWOFETCHW.1
            LDD   2,X
            PSHU  D
            LDD   ,X
            PSHU  D
            RTS

; ------------------------------------------------------------
; 2!  ( x1 x2 a-addr -- )
; Store the cell pair: x2 at a-addr and x1 at a-addr+2.
; ------------------------------------------------------------
TWOSTOREW:  PULU  X                 ; a-addr
            PULU  D                 ; x2
            STD   ,X
            PULU  D                 ; x1
            STD   2,X
            RTS

; ------------------------------------------------------------
; CMOVE  ( c-addr1 c-addr2 u -- )
; Copy u bytes from c-addr1 to c-addr2, starting at the low addresses.
; ------------------------------------------------------------
CMOVEW:     LDD   ,U                ; u. Parameters stay on the data stack,
            BEQ   CMDONE            ; addressed relative to U: u at 0, c-addr2
            LDX   4,U               ; at 2, c-addr1 at 4. See shadow CMOVEW.2
            LEAX  D,X               ; end address = c-addr1 + u
            STX   ,U                ; keep it in u's old slot as the loop limit
            LDX   4,U               ; X = source
            LDY   2,U               ; Y = destination
CMVLOOP:    LDA   ,X+
            STA   ,Y+
            CMPX  ,U                ; reached the end address?
            BNE   CMVLOOP
CMDONE:     LEAU  6,U               ; drop the three parameters
            RTS

; ------------------------------------------------------------
; CMOVE>  ( c-addr1 c-addr2 u -- )
; Copy u bytes from c-addr1 to c-addr2, starting at the high
; addresses.
; ------------------------------------------------------------
CMOVEGTW:   LDD   ,U                ; u. Parameters stay on the data stack:
            BEQ   CGDONE            ; u at 0, c-addr2 at 2, c-addr1 at 4
            LDX   4,U
            LEAX  D,X               ; X = one past the end of the source
            LDY   2,U
            LEAY  D,Y               ; Y = one past the end of the destination
CGLOOP:     LDA   ,-X
            STA   ,-Y
            CMPX  4,U               ; back at the start of the source?
            BNE   CGLOOP
CGDONE:     LEAU  6,U               ; drop the three parameters
            RTS

; ------------------------------------------------------------
; MOVE  ( addr1 addr2 u -- )
; Copy u bytes from addr1 to addr2, choosing CMOVE or CMOVE> so that
; overlapping regions are handled correctly.
; ------------------------------------------------------------
MOVEW:      LDD   2,U               ; addr2
            CMPD  4,U               ; addr1
            BHI   CMOVEGTW          ; addr2 above addr1: copy from the top
            JMP   CMOVEW

; ------------------------------------------------------------
; FILL  ( c-addr u char -- )
; Store char in each of u bytes starting at c-addr.
; ------------------------------------------------------------
FILLW:      LDD   2,U               ; u. char is at 0, c-addr at 4
            BEQ   FDONE
            LDX   4,U
            LEAY  D,X               ; end address
            STY   2,U               ; keep it in u's slot as the loop limit
            LDA   1,U               ; fill byte. See bugfix: FILLW.1
FILLOOP:    STA   ,X+
            CMPX  2,U
            BNE   FILLOOP
FDONE:      LEAU  6,U               ; drop the three parameters
            RTS

; ------------------------------------------------------------
; ERASE  ( c-addr u -- )
; Fill u bytes starting at c-addr with zero.
; ------------------------------------------------------------
ERASEW:     LDD   #0
            PSHU  D
            JMP   FILLW

; ------------------------------------------------------------
; BLANK  ( c-addr u -- )
; Store a space in each of u bytes starting at c-addr.
; ------------------------------------------------------------
BLANKW:     LDD   #32
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
; Parse the text up to the next double quote for S", ." and ABORT".
; WORD cannot be used: it skips leading delimiters, so an empty string
; (S" ") ran on to the next quote in the source. PARSE does not skip.
; PARSEQUOTE
;    Inputs:
;        none (parses from >IN)
;    Outputs:
;        c-addr u on the data stack: the text in the input buffer.
;        THROW -18 if the text is longer than 255 characters.
;    Registers: RegA, RegB, RegX, RegY changed.
; ------------------------------------------------------------
PARSEQUOTE: LDD   #34
            PSHU  D
            JSR   PARSEW
            TST   ,U                ; high byte of the length
            BNE   PQLONG
            RTS
PQLONG:     LDD   #-18
            PSHU  D
            JMP   THROWW

; ------------------------------------------------------------
; Compile a call to a run-time word followed by a counted string.
; CSTRCOMP   ( c-addr u -- )
;    Inputs:
;        RegD = xt of the run-time word (DOSTR, DOTSTR, DOABORTQUOTE)
;        c-addr u on the data stack
;    Outputs:
;        JSR xt, the count byte and the text compiled at CODEHERE
;    Registers: RegA, RegB, RegX, RegY changed.
; ------------------------------------------------------------
CSTRCOMP:   PSHU  D
            JSR   CCALL
            PULU  D                 ; u
            PULU  Y                 ; c-addr
            LDX   CODEHERE
            STB   ,X+
            TSTB
            BEQ   CSEND
CSCPY:      LDA   ,Y+
            STA   ,X+
            DECB
            BNE   CSCPY
CSEND:      STX   CODEHERE
            RTS

; ------------------------------------------------------------
; S"  ( "ccc<quote>" -- c-addr u )
; Parse up to the closing quote (PARSEQUOTE). When compiling, compile
; DOSTR followed by the counted string. When interpreting, copy the
; string to PAD and return its address and length. An empty string is
; valid. See shadow SQUOTEW.3.
; ------------------------------------------------------------
SQUOTEW:    JSR   PARSEQUOTE        ; See bugfix: SQUOTEW.3
SQSTATE:    LDD   STATE
            BEQ   SQINTERP
            LDD   #DOSTR
            JMP   CSTRCOMP

            ; Interpreting: copy the string to PAD. Original comment: shadow
            ; SQUOTEW.2.
SQINTERP:
            JSR   PADW
            PULU  X                 ; PAD
            PULU  D                 ; u
            PULU  Y                 ; c-addr
            PSHU  X                 ; result c-addr
            PSHU  D                 ; result u
            TSTB
            BEQ   SQIEND
SQICPY:     LDA   ,Y+
            STA   ,X+
            DECB
            BNE   SQICPY
SQIEND:     RTS

; ------------------------------------------------------------
; S\"  ( "ccc<quote>" -- c-addr u )
; As S", but the text may contain escape sequences introduced by a
; backslash, and a backslash-quote does not end the string. The
; translated text is built at PAD and then handled exactly like S" text
; (SQSTATE). The escapes are: \a 7, \b 8, \e 27, \f 12, \l 10, \m the
; pair 13 10, \n 10, \q 34, \r 13, \t 9, \v 11, \z 0, \" 34, \\ 92 and
; \xhh (one or two hex digits). Any other character after a backslash
; stands for itself. An unterminated string ends at the end of the line.
; A result over 255 characters throws -18.
; Frame on S: 0,S input end, 2,S output start, 4,S output pointer.
; ------------------------------------------------------------
SQUOTEESCW: JSR   PADW              ; leaves PAD on the data stack
            LDD   ,U
            PSHS  D                 ; output pointer
            PSHS  D                 ; output start
            LDD   SRCADDR
            ADDD  SRCLEN
            PSHS  D                 ; input end
            LDD   SRCADDR
            ADDD  TOIN
            TFR   D,Y               ; input pointer
SQEL:       CMPY  0,S
            BHS   SQEND
            LDA   ,Y+
            CMPA  #34
            BEQ   SQEND
            CMPA  #92
            BNE   SQEPUT
            CMPY  0,S
            BHS   SQEND
            LDA   ,Y+               ; the escaped character
            CMPA  #'x'
            BEQ   SQEHEX
            CMPA  #'m'
            BEQ   SQEM
            LDX   #SQETAB
SQEFND:     TST   ,X
            BEQ   SQEPUT            ; not in the table: stands for itself
            CMPA  ,X++
            BNE   SQEFND
            LDA   -1,X
SQEPUT:     LDX   4,S
            STA   ,X+
            STX   4,S
            BRA   SQEL
SQEM:       LDX   4,S
            LDA   #13
            STA   ,X+
            LDA   #10
            STA   ,X+
            STX   4,S
            BRA   SQEL
SQEHEX:     BSR   SQEHD             ; first digit
            BCS   SQEL              ; none: nothing is added
            LEAY  1,Y
            TFR   A,B
            BSR   SQEHD             ; second digit
            BCC   SQEH2
            TFR   B,A               ; one digit only
            BRA   SQEPUT
SQEH2:      LEAY  1,Y
            ASLB
            ASLB
            ASLB
            ASLB
            PSHS  B
            ADDA  ,S+
            BRA   SQEPUT
; Hex digit at ,Y: value in A, carry clear; carry set if not a digit
; or the input is exhausted. Y is not advanced. RegB is preserved.
SQEHD:      CMPY  2,S               ; input end (one return address down)
            BHS   SQEHNO
            LDA   ,Y
            CMPA  #'0'
            BLO   SQEHNO
            CMPA  #'9'
            BLS   SQEHDG
            ANDA  #$DF              ; to upper case
            CMPA  #'A'
            BLO   SQEHNO
            CMPA  #'F'
            BHI   SQEHNO
            SUBA  #'A'-10
            ANDCC #$FE
            RTS
SQEHDG:     SUBA  #'0'
            ANDCC #$FE
            RTS
SQEHNO:     ORCC  #1
            RTS
SQEND:      TFR   Y,D
            SUBD  SRCADDR
            STD   TOIN              ; resume after the closing quote
            LDD   4,S
            SUBD  2,S               ; length
            LEAS  6,S
            TSTA
            BNE   SQEOVF
            PSHU  D                 ; ( c-addr u )
            JMP   SQSTATE
SQEOVF:     LDD   #-18
            PSHU  D
            JMP   THROWW

; Escape table: character, value. A zero character ends it.
SQETAB:     FCB   'a',7
            FCB   'b',8
            FCB   'e',27
            FCB   'f',12
            FCB   'l',10
            FCB   'n',10
            FCB   'q',34
            FCB   'r',13
            FCB   't',9
            FCB   'v',11
            FCB   'z',0
            FCB   0

; ------------------------------------------------------------
; CONVERT  ( ud1 c-addr1 -- ud2 c-addr2 )
; Obsolescent. Convert the digits after c-addr1 using >NUMBER with no
; length limit; c-addr2 is the first character that is not a digit.
; ------------------------------------------------------------
CONVERTW:   LDD   ,U
            ADDD  #1
            STD   ,U                ; skip the character at c-addr1
            LDD   #$FFFF
            PSHU  D                 ; u
            JSR   TONUMBERW
            LEAU  2,U               ; drop u2
            RTS

; ------------------------------------------------------------
; Run-time part of ."  The counted string follows the call: TYPE it
; and skip over it.
; DOTSTR
;    Inputs:
;        return address on S points at the count byte
;    Outputs:
;        string displayed; execution resumes after the string
;    Registers: RegB, RegD and RegX changed.
; ------------------------------------------------------------
DOTSTR:     PULS  X
            LDB   ,X
            LEAX  1,X
            PSHU  X
            CLRA
            PSHU  D
            LEAX  B,X
            PSHS  X
            JMP   TYPEW

; ------------------------------------------------------------
; ."  ( "ccc<quote>" -- )
; Compile DOTSTR followed by the string up to the closing quote as a
; counted string.
; ------------------------------------------------------------
DOTQUOTEW:  JSR   PARSEQUOTE        ; See bugfix: SQUOTEW.3
            LDD   #DOTSTR
            JMP   CSTRCOMP

; ------------------------------------------------------------
; Run-time part of C"  The counted string follows the call: push its
; address and skip over it.
; DOCSTR
;    Outputs:
;        ( -- c-addr ) the count byte address; execution resumes after
;        the string
;    Registers: RegB, RegD and RegX changed.
; ------------------------------------------------------------
DOCSTR:     PULS  X
            PSHU  X
            LDB   ,X
            LEAX  1,X
            LEAX  B,X
            PSHS  X
            RTS

; ------------------------------------------------------------
; C"  ( "ccc<quote>" -- )  compile: ( -- c-addr ) run-time
; Compile DOCSTR followed by the string up to the closing quote as a
; counted string. THROW -14 if not compiling.
; ------------------------------------------------------------
CQUOTEW:    LDD   STATE
            BNE   CQOK
            LDD   #-14
            PSHU  D
            JSR   THROWW
CQOK:       JSR   PARSEQUOTE
            LDD   #DOCSTR
            JMP   CSTRCOMP

; ------------------------------------------------------------
; .(  ( "ccc<paren>" -- )
; Immediate. Parse up to the closing parenthesis and display the text
; at once, even while compiling.
; ------------------------------------------------------------
DOTPARENW:  LDD   #41
            PSHU  D
            JSR   PARSEW
            JMP   TYPEW

; ------------------------------------------------------------
; TYPE  ( c-addr u -- )
; Display u characters starting at c-addr, through EMIT.
; ------------------------------------------------------------
TYPEW:      LDD   ,U                ; u. Parameters stay on the data stack:
            BEQ   TYDONE            ; u at 0, c-addr at 2
TYLOOP:     LDX   2,U
            LDA   ,X+
            STX   2,U
            TFR   A,B
            CLRA
            PSHU  D
            JSR   EMITW
            LDD   ,U
            SUBD  #1
            STD   ,U
            BNE   TYLOOP
TYDONE:     LEAU  4,U               ; drop the two parameters
            RTS

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
            JSR   THROWW
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
            PSHS  B                 ; 0,S = delimiter (5k: no scratch cells)
            LDD   SRCLEN
            SUBD  TOIN
            LBLO  PEMP              ; See bugfix: PARSEW.1
            TFR   D,Y
            LDD   TOIN
            LDX   SRCADDR
            LEAX  D,X
            PSHU  X                 ; c-addr result; u is computed at the end
PSCAN:      CMPY  #0
            BEQ   PDONE
            LDA   ,X
            CMPA  ,S
            BEQ   PFOUND
            LEAX  1,X
            LEAY  -1,Y
            BRA   PSCAN
PFOUND:     TFR   X,D
            SUBD  ,U                ; length excludes the delimiter
            PSHU  D
            LEAX  1,X               ; consume the delimiter
            BRA   PFIN
PDONE:      TFR   X,D
            SUBD  ,U
            PSHU  D
PFIN:       TFR   X,D
            SUBD  SRCADDR
            STD   TOIN
            LEAS  1,S
            RTS
PEMP:       LEAS  1,S
            LBRA  PNEMPTY

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
PNSTART:    PSHU  X                 ; c-addr result
PNSCAN:     CMPY  #0
            BEQ   PNDONE
            LDA   ,X
            CMPA  #32
            BEQ   PNFOUND
            LEAX  1,X
            LEAY  -1,Y
            BRA   PNSCAN
PNFOUND:    TFR   X,D
            SUBD  ,U
            PSHU  D
            LEAX  1,X
            BRA   PNFIN
PNDONE:     TFR   X,D
            SUBD  ,U
            PSHU  D
PNFIN:      TFR   X,D
            SUBD  SRCADDR
            STD   TOIN
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
            LDY   ,U
            LDX   2,U
            TFR   Y,D
            LEAX  D,X               ; X = end of the string
DTLOOP:     CMPY  #0
            BEQ   DTDONE
            LDA   ,-X
            CMPA  #32
            BNE   DTDONE
            LEAY  -1,Y
            BRA   DTLOOP
DTDONE:     STY   ,U
            RTS

; ------------------------------------------------------------
; COMPARE  ( c-addr1 u1 c-addr2 u2 -- n )
; Compare two strings byte by byte. n is -1, 0 or 1 as the first
; string is less than, equal to or greater than the second; if one is
; a prefix of the other, the shorter is less.
; ------------------------------------------------------------
COMPAREW:   LDX   6,U                ; Parameters stay on the data stack: u2 at 0,
            LDY   2,U               ; c-addr2 at 2, u1 at 4, c-addr1 at 6
            LDD   4,U
            CMPD  ,U
            BLS   CMMINSET
            LDD   ,U                ; D = the shorter length
CMMINSET:   STD   2,U               ; the c-addr2 slot is free now: use it as
CMPLOOP:    LDD   2,U               ; the remaining count
            BEQ   CMTIEBREAK
            LDA   ,X+
            CMPA  ,Y+
            BLO   CMLT
            BHI   CMGT
            LDD   2,U
            SUBD  #1
            STD   2,U
            BRA   CMPLOOP
CMTIEBREAK: LDD   4,U
            CMPD  ,U
            BLO   CMLT
            BHI   CMGT
            LDD   #0
            BRA   CMOUT
CMLT:       LDD   #-1
            BRA   CMOUT
CMGT:       LDD   #1
CMOUT:      STD   6,U               ; result replaces c-addr1
            LEAU  6,U               ; drop the other three cells
            RTS

; ------------------------------------------------------------
; SEARCH  ( c-addr1 u1 c-addr2 u2 -- c-addr3 u3 flag )
; Search the string c-addr1 u1 for the string c-addr2 u2. If found,
; return the address and remaining length of the match and true;
; otherwise return the original string and false.
; ------------------------------------------------------------
SEARCHW:    LEAU  -6,U              ; locals: 0,U candidate address, 2,U positions
            LDD   6,U               ; left, 4,U end of the needle.  Then u2 at 6,
            BNE   SRCHNZ            ; c-addr2 at 8, u1 at 10, c-addr1 at 12
            LDD   12,U              ; an empty needle matches at the start
            STD   ,U
            BRA   SFOUND
SRCHNZ:     LDD   10,U
            SUBD  6,U
            BLT   SRCHNOTFOUND
            ADDD  #1
            STD   2,U
            LDD   12,U
            STD   ,U
            LDD   8,U
            ADDD  6,U
            STD   4,U
SPOSLOOP:   LDD   2,U
            BEQ   SRCHNOTFOUND
            LDX   ,U
            LDY   8,U
SMATCH:     LDA   ,X+
            CMPA  ,Y+
            BNE   SNOMATCH
            CMPY  4,U
            BNE   SMATCH
SFOUND:     LDD   12,U              ; u3 = (c-addr1 + u1) - match address,
            ADDD  10,U              ; the characters remaining. See shadow
            SUBD  ,U                ; SEARCHW.2
            STD   10,U
            LDD   ,U
            STD   12,U              ; c-addr3
            LDD   #TRUEV
            BRA   SRCHOUT
SRCHNOTFOUND:
            LDD   #FALSEV           ; c-addr1 and u1 are already in place
SRCHOUT:    STD   8,U               ; flag
            LEAU  8,U               ; drop the locals and u2
            RTS
SNOMATCH:   LDX   ,U
            LEAX  1,X
            STX   ,U
            LDD   2,U
            SUBD  #1
            STD   2,U
            BRA   SPOSLOOP

; ------------------------------------------------------------
; SNAME  ( xt -- c-addr u | 0 0 )
; Find the name of the word whose xt is given by searching every
; wordlist. Return the name or two zeros if not found.
; ------------------------------------------------------------
SNAMEW:     PULU  Y                 ; xt (5k: Y = target, X = header, no scratch)
            LDX   #WLHEADS
            PSHS  X                 ; 0,S = next wordlist cell
SNWL:       LDX   ,S
            CMPX  WLEND
            BHS   SNNOTFOUND
            LEAX  2,X
            STX   ,S
            LDX   -2,X              ; newest header of this wordlist
SNLOOP:     CMPX  #0
            BEQ   SNWL
            LDB   ,X
            ANDB  #$1F              ; name length
            CLRA
            LEAX  D,X               ; X = header + length
            CMPY  3,X               ; CFA field follows the name and link
            BEQ   SNFOUND
            LDX   1,X               ; LINK field
            BRA   SNLOOP
SNFOUND:    LEAS  2,S
            TFR   D,Y               ; Y = length
            TFR   X,D
            PSHS  Y
            SUBD  ,S++              ; header
            ADDD  #1                ; name address
            PSHU  D
            PSHU  Y
            RTS
SNNOTFOUND: LEAS  2,S
            LDD   #0
            PSHU  D
            PSHU  D
            RTS

; ------------------------------------------------------------
; UNESCAPE  ( c-addr1 u1 c-addr2 -- c-addr2 u2 )
; Copy the string c-addr1 u1 to c-addr2, doubling every "%" so that
; SUBSTITUTE turns it back into the original. u2 is the length of the
; result.
; ------------------------------------------------------------
UNESCAPEW:  LDX   4,U                ; c-addr1. Parameters stay on the data stack:
            LDY   ,U                ; c-addr2 at 0, u1 at 2. See bugfix:
                                    ; UNESCAPEW.1 (still applies) and
                                    ; shadow UNESCAPEW.5

            ; Double every %; copy all other characters unchanged.
            ; See bugfix: UNESCAPEW.2
UELOOP:     LDD   2,U
            BEQ   UEDONE
            LDA   ,X+
            CMPA  #'%'
            BNE   UENOTPCT
            LDB   #'%'              ; extra % written first
            STB   ,Y+
UENOTPCT:   STA   ,Y+               ; write the character
            LDD   2,U
            SUBD  #1
            STD   2,U
            BRA   UELOOP
UEDONE:     TFR   Y,D               ; See bugfix: UNESCAPEW.4
            SUBD  ,U                ; u2 = end - destination
            STD   2,U               ; result: c-addr2 u2
            LDD   ,U
            STD   4,U
            LEAU  2,U
            RTS

; ------------------------------------------------------------
; REPLACES  ( c-addr1 u1 c-addr2 u2 -- )
; Register the substitution text c-addr1 u1 for the name c-addr2 u2.
; Only one registration is kept (a single slot); a new call replaces
; the previous one. The strings are not copied.
; Original comment: shadow REPLACESW.0.
; ------------------------------------------------------------
REPLACESW:  LDD   ,U                ; Parameters stay on the data stack: u2 at
            CMPD  #255              ; 0, c-addr2 at 2, u1 at 4, c-addr1 at 6.
            BHI   REPLERR           ; Names and texts are limited to 255
            LDD   4,U               ; characters. See shadow REPLACES.1
            CMPD  #255
            BHI   REPLERR
            LDD   ,U
            LDX   2,U
            JSR   SUBFIND           ; X = existing entry, or 0
            CMPX  #0
            BEQ   REPLNEW
            LDB   5,U               ; the new text length
            CMPB  4,X               ; does it fit the old entry's space?
            BHI   REPLNEW
            STB   3,X               ; yes: replace the text in place
            LDB   2,X
            CLRA
            LEAY  5,X
            LEAY  D,Y               ; Y = the text field
            BRA   REPLTEXT
REPLNEW:    LDD   SUBFREE           ; no: add a new entry at the head
            BNE   REPLHAVE
            LDD   #SUBPOOL          ; first use: the pool is empty
REPLHAVE:   TFR   D,Y               ; Y = the new entry
            CLRA
            LDB   1,U
            ADDD  #5
            TFR   D,X
            LDB   5,U
            CLRA
            LEAX  D,X               ; X = entry size: 5 + name + text
            PSHS  X
            TFR   Y,D
            ADDD  ,S++              ; D = end of the entry
            CMPD  #SUBPOOL+SUBPOOLSZ
            BHI   REPLFULL
            STD   SUBFREE
            LDD   SUBHEAD
            STD   ,Y                ; link
            LDB   1,U
            STB   2,Y               ; name length
            LDB   5,U
            STB   3,Y               ; text length
            STB   4,Y               ; text capacity
            PSHS  Y
            LDX   2,U
            LEAY  5,Y
            LDB   1,U
            BEQ   REPLNAMED
REPLNLP:    LDA   ,X+
            STA   ,Y+
            DECB
            BNE   REPLNLP
REPLNAMED:  PULS  X
            STX   SUBHEAD           ; the new entry is now the newest
REPLTEXT:   LDX   6,U               ; copy the text to Y
            LDB   5,U
            BEQ   REPLDONE
REPLVLP:    LDA   ,X+
            STA   ,Y+
            DECB
            BNE   REPLVLP
REPLDONE:   LEAU  8,U
            RTS
REPLERR:    LDD   #-18              ; parsed string overflow: name or text
            BRA   REPLTHROW         ; longer than 255
REPLFULL:   LDD   #-8               ; dictionary overflow: SUBPOOL is full
REPLTHROW:  PSHU  D
            JMP   THROWW

; ------------------------------------------------------------
; CLR-REPLACES ( -- )  Empties the REPLACES table, freeing the whole pool.
; Not a standard word. See shadow CLRREPLACESW.1.
; ------------------------------------------------------------
CLRREPLACESW:
            CLRA
            CLRB
            STD   SUBHEAD
            STD   SUBFREE
            RTS

; ------------------------------------------------------------
; Find the REPLACES entry for a name, newest first.
; SUBFIND
;    Inputs:
;        RegD = name length, RegX = name address
;    Outputs:
;        RegX = entry address, or 0 if there is none. An entry is: 0 link,
;        2 name length, 3 text length, 4 text capacity, 5 name, then text.
;    Registers: RegA, RegB, RegX and RegY changed. A length over 255 is
;        never found.
; ------------------------------------------------------------
SUBFIND:    TSTA
            BNE   SFNONE            ; too long to be a name
            PSHS  D,X               ; 0,S length, 2,S name address
            LDY   SUBHEAD
SFLOOP:     CMPY  #0
            BEQ   SFEND
            LDB   2,Y
            CMPB  1,S
            BNE   SFNEXT
            LDX   2,S
            PSHS  Y
            LEAY  5,Y
SFCMP:      TSTB
            BEQ   SFMATCH
            LDA   ,X+
            CMPA  ,Y+
            BNE   SFDIFF
            DECB
            BRA   SFCMP
SFMATCH:    PULS  X                 ; the entry
            LEAS  4,S
            RTS
SFDIFF:     PULS  Y
SFNEXT:     LDY   ,Y
            BRA   SFLOOP
SFEND:      LEAS  4,S
SFNONE:     LDX   #0
            RTS

; ------------------------------------------------------------
; Append bytes to the SUBSTITUTE output buffer. THROW -1 if the buffer
; would overflow.
; SUBCOPY
;    Inputs:
;        RegD = byte count, RegX = source address, U = SUBSTITUTE's
;        frame (6,U output length, 8,U write pointer, 10,U capacity)
;    Outputs:
;        bytes appended at the write pointer; length and pointer advanced
;    Registers: RegA, RegD, RegX and RegY changed.
; ------------------------------------------------------------
SUBCOPY:    CMPD  #0
            BEQ   SUBCPDONE
            PSHS  D                 ; bytes still to copy
SUBCPLP:    LDD   6,U               ; SUBSTITUTE's frame (U is unchanged):
            CMPD  10,U              ; output length against capacity
            LBHS  SUBOVERFLOW       ; buffer full: THROW -1
            LDY   8,U               ; write pointer
            LDA   ,X+
            STA   ,Y+
            STY   8,U
            LDD   6,U
            ADDD  #1
            STD   6,U
            LDD   ,S
            SUBD  #1
            STD   ,S
            BNE   SUBCPLP
            LEAS  2,S
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
            LEAU  -10,U             ; frame: 0 read position, 2 substitution
                                    ; count, 4 closing '%' position, 6 output
                                    ; length, 8 write pointer; then the
                                    ; parameters: 10 u2 (capacity), 12 c-addr2,
                                    ; 14 u1, 16 c-addr1. See shadow SUBSTITUTEW.5
            LDD   16,U              ; the source must not be the destination
            CMPD  12,U
            LBEQ  SUBBAD
            LDD   #0
            STD   ,U
            STD   2,U
            STD   6,U
            LDD   12,U
            STD   8,U

SUBSCAN:    LDD   ,U
            CMPD  14,U
            LBHS  SUBSDONE
            LDX   16,U
            LEAX  D,X
            LDA   ,X
            CMPA  #$25              ; '%' delimiter
            BEQ   SUBPCT
            LDD   #1
            JSR   SUBCOPY
            LDD   ,U
            ADDD  #1
            STD   ,U
            LBRA  SUBSCAN

SUBPCT:     LDD   ,U
            ADDD  #1
            STD   4,U               ; scan for the closing '%'
SUBFINDCL:  LDD   4,U
            CMPD  14,U
            BLO   SUBFC2
            ; no closing delimiter found - residue passed unchanged
            LDD   ,U
            LDX   16,U
            LEAX  D,X
            LDD   14,U
            SUBD  ,U
            JSR   SUBCOPY
            LDD   14,U
            STD   ,U
            LBRA  SUBSCAN
SUBFC2:     LDD   4,U
            LDX   16,U
            LEAX  D,X
            LDA   ,X
            CMPA  #$25
            BEQ   SUBFOUNDCL
            LDD   4,U
            ADDD  #1
            STD   4,U
            LBRA  SUBFINDCL

SUBFOUNDCL: LDD   4,U
            SUBD  ,U
            SUBD  #1                ; enclosed name length
            LBNE  SUBHASNAME
            ; namelen 0: "%%" -> single '%' to output, count unchanged
            LDD   ,U
            LDX   16,U
            LEAX  D,X
            LDD   #1
            JSR   SUBCOPY
            LDD   4,U
            ADDD  #1
            STD   ,U
            LBRA  SUBSCAN

SUBHASNAME: LDD   ,U
            ADDD  #1
            LDX   16,U
            LEAX  D,X               ; X = the name
            LDD   4,U
            SUBD  ,U
            SUBD  #1                ; D = its length
            JSR   SUBFIND
            CMPX  #0
            BEQ   SUBNOMATCH
            ; valid name - replace the whole %name% span
            LDB   2,X               ; name length
            CLRA
            TFR   D,Y
            LDB   3,X               ; text length
            PSHS  B
            LEAX  5,X
            TFR   Y,D
            LEAX  D,X               ; X = the text
            PULS  B
            CLRA
            JSR   SUBCOPY
            LDD   2,U
            ADDD  #1
            STD   2,U
            LDD   4,U
            ADDD  #1
            STD   ,U
            LBRA  SUBSCAN

            ; Not a registered name: pass %name% through unchanged.
SUBNOMATCH:
            LDD   ,U
            LDX   16,U
            LEAX  D,X
            LDD   4,U
            SUBD  ,U
            ADDD  #1
            JSR   SUBCOPY
            LDD   4,U
            ADDD  #1
            STD   ,U
            LBRA  SUBSCAN

SUBSDONE:   LDD   12,U              ; result c-addr2 u3 n replaces the frame
            STD   16,U
            LDD   6,U
            STD   14,U
            LDD   2,U
            STD   12,U
            LEAU  12,U
            RTS

            ; The output buffer is too small: THROW -1.
SUBOVERFLOW:
            LEAS  4,S               ; SUBCOPY's count and return address
            LDD   #-18              ; parsed string overflow: output too long
            BRA   SUBFAIL
SUBBAD:     LDD   #-9               ; invalid address: source = destination
SUBFAIL:    TFR   D,X               ; error result c-addr2 0 n. See shadow
            LDD   12,U              ; SUBSTITUTEW.6
            STD   16,U
            LDD   #0
            STD   14,U
            STX   12,U
            LEAU  12,U
            RTS

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
HOLDSW:     LDD   ,U                ; u at 0, c-addr at 2
            BEQ   HSDONE
            SUBD  #1
            STD   ,U                ; remaining count
            LDX   2,U
            LDA   D,X               ; the last remaining character
            TFR   A,B
            CLRA
            PSHU  D
            JSR   HOLDW             ; consumes the character
            BRA   HOLDSW
HSDONE:     LEAU  4,U               ; drop the two parameters
            RTS

; ------------------------------------------------------------
; #  ( ud1 -- ud2 )
; Divide ud1 by BASE, add the remainder as a digit to the pictured
; numeric output string, and leave the quotient ud2.
; ------------------------------------------------------------
NUMW:       JSR   UDDIGIT           ; ud1 is divided in place on the data stack
            CMPA  #10
            BLO   NDIGIT
            ADDA  #'A'-10
            BRA   NHOLD
NDIGIT:     ADDA  #'0'
NHOLD:      TFR   A,B
            CLRA
            PSHU  D
            JMP   HOLDW

; ------------------------------------------------------------
; Divide the unsigned double on the data stack (high cell at 0,U, low
; cell at 2,U) by BASE (restoring division, 32 iterations). Only the
; low byte of BASE is used.
; UDDIGIT
;    Inputs:
;        ud on the data stack
;    Outputs:
;        ud replaced by the quotient; RegA = remainder
;    Registers: RegA and RegB changed (RegB is the loop counter).
; ------------------------------------------------------------
UDDIGIT:    CLRA                    ; A = remainder
            LDB   #32
UDDLOOP:    ASL   3,U
            ROL   2,U
            ROL   1,U
            ROL   ,U
            ROLA
            CMPA  BASE+1
            BLO   UDNEXT
            SUBA  BASE+1
            INC   3,U
UDNEXT:     DECB
            BNE   UDDLOOP
            RTS

; ------------------------------------------------------------
; #S  ( ud -- 0 0 )
; Convert digits with # until the quotient is zero (at least one digit
; is produced).
; ------------------------------------------------------------
NUMSW:      JSR   NUMW
            LDD   ,U
            BNE   NUMSW
            LDD   2,U
            BNE   NUMSW
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
            PSHS  D                 ; n kept on S for SIGN (5m)
            TSTA
            BPL   DABSOK
            COMA
            COMB
            ADDD  #1
DABSOK:     PSHU  D
            LDD   #0
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSW
            PULS  D
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
            JSR   NUMSW
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
            PSHS  D                 ; width waits on the return stack
            PULU  D                 ; n1
            PSHS  D                 ; kept on S for SIGN, above the width
            TSTA
            BPL   DRABSOK
            COMA
            COMB
            ADDD  #1
DRABSOK:    PSHU  D
            LDD   #0
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSW
            PULS  D
            PSHU  D
            JSR   SIGNW
            JSR   NUMGTW
            PULS  D                 ; width
            LBRA  RTYPE

; ------------------------------------------------------------
; Type the string c-addr u right-justified in a field of D characters.
; RTYPE   ( c-addr u -- )
;    Inputs:
;        RegD = field width; the string on the data stack
;    Outputs:
;        padding spaces, then the string
;    Registers: all changed.
; ------------------------------------------------------------
RTYPE:      SUBD  ,U                ; width - u
            BLE   RTNOPAD
            PSHS  D                 ; spaces still to send
RTPADLP:    LDD   #32
            PSHU  D
            JSR   EMITW
            LDD   ,S
            SUBD  #1
            STD   ,S
            BNE   RTPADLP
            LEAS  2,S
RTNOPAD:    JMP   TYPEW

; ------------------------------------------------------------
; U.R  ( u n -- )
; Display u right-justified in a field of n characters.
; ------------------------------------------------------------
UDOTRW:     PULU  D                 ; n (width)
            PSHS  D
            LDD   #0                ; ud high cell = 0
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSW
            JSR   NUMGTW
            PULS  D
            LBRA  RTYPE

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
            PSHS  D                 ; sign cell, kept on S
            BPL   DDPOS
            JSR   MNEG32
DDPOS:      LDD   PRODLO
            PSHU  D
            LDD   PRODHI
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSW
            PULS  D
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
            PSHS  D
            PULU  D                 ; d high
            STD   PRODHI
            PULU  D                 ; d low
            STD   PRODLO
            LDD   PRODHI
            PSHS  D                 ; sign cell, kept on S above the width
            BPL   DDRPOS
            JSR   MNEG32
DDRPOS:     LDD   PRODLO
            PSHU  D
            LDD   PRODHI
            PSHU  D
            JSR   LTNUMW
            JSR   NUMSW
            PULS  D
            PSHU  D
            JSR   SIGNW
            JSR   NUMGTW
            PULS  D
            LBRA  RTYPE

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
SPACESW:    LDD   ,U                ; n stays on the data stack
            BLE   SPDONE
SPLOOP:     LDD   #32
            PSHU  D
            JSR   EMITW
            LDD   ,U
            SUBD  #1
            STD   ,U
            BNE   SPLOOP
SPDONE:     LEAU  2,U               ; drop n
            RTS

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
; SAVE-INPUT  ( -- x1 x2 x3 3 )
; Save the source address, source length and >IN.
; ------------------------------------------------------------
SAVEINPUTW: LDD   SRCADDR
            PSHU  D
            LDD   SRCLEN
            PSHU  D
            LDD   TOIN
            PSHU  D
            LDD   #3
            PSHU  D
            RTS

; ------------------------------------------------------------
; RESTORE-INPUT  ( x1 x2 x3 3 -- flag )
; Restore >IN if the input source is the same one that was saved.
; Return false on success, true if the saved state is unusable (wrong
; cell count, or a different source address or length).
; ------------------------------------------------------------
RESTOREINPUTW:
            PULU  D                 ; n
            CMPD  #3
            BNE   RIBAD
            PULU  Y                 ; saved >IN
            PULU  D                 ; saved source length
            PULU  X                 ; saved source address
            CMPD  SRCLEN
            BNE   RIFAIL
            CMPX  SRCADDR
            BNE   RIFAIL
            STY   TOIN
            LDD   #FALSEV
            PSHU  D
            RTS
RIBAD:      ASLB                    ; drop n cells
            ROLA
            LEAU  D,U
RIFAIL:     LDD   #TRUEV
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
; the value and true; otherwise return false. WORDLISTS is 8, the
; number of wordlists that can exist. FLOORED is false because /, MOD and /MOD use symmetric
; division.
; Original comment: shadow ENVQW.0.
; ------------------------------------------------------------
ENVQW:      PULU  D                 ; u
            PSHS  D                 ; frame: 2,S = u, 0,S = c-addr (5k)
            PULU  D                 ; c-addr
            PSHS  D
            LDX   #ENVTABLE
ENVLOOP:    LDD   ,X
            CMPD  #0
            BEQ   ENV2START         ; end of table: try ENVTABLE2
            PSHS  X                 ; See bugfix: ENVQW.2 (frame now +2)
            PSHU  D
            LDD   2,X
            PSHU  D
            LDD   2,S               ; c-addr
            PSHU  D
            LDD   4,S               ; u
            PSHU  D
            JSR   COMPAREW
            PULS  X                 ; restore X before using it again
            PULU  D
            CMPD  #0
            BEQ   ENVFOUND
            LEAX  6,X
            BRA   ENVLOOP
ENVFOUND:   LEAS  4,S               ; drop frame
            LDD   4,X
            PSHU  D
            LDD   #TRUEV
            PSHU  D
            RTS

ENV2START:  LDX   #ENVTABLE2        ; double-cell table
ENV2LOOP:   LDD   ,X
            CMPD  #0
            BEQ   ENVNOTFOUND
            PSHS  X                 ; See bugfix: ENVQW.2
            PSHU  D
            LDD   2,X
            PSHU  D
            LDD   2,S               ; c-addr
            PSHU  D
            LDD   4,S               ; u
            PSHU  D
            JSR   COMPAREW
            PULS  X
            PULU  D
            CMPD  #0
            BEQ   ENV2FOUND
            LEAX  8,X               ; 8-byte entries
            BRA   ENV2LOOP
ENV2FOUND:  LEAS  4,S               ; drop frame
            LDD   4,X               ; low cell, pushed first
            PSHU  D
            LDD   6,X               ; high cell - pushed second/top
            PSHU  D
            LDD   #TRUEV
            PSHU  D
            RTS

ENVNOTFOUND:
            LEAS  4,S               ; drop frame
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
            FDB   EN15,EN15L,TRUEV  ; CORE (complete)
            FDB   EN16,EN16L,TRUEV  ; DOUBLE (complete)
            FDB   EN17,EN17L,TRUEV  ; DOUBLE-EXT (complete)
            FDB   EN18,EN18L,TRUEV  ; CORE-EXT (complete)
            FDB   EN19,EN19L,WLMAX  ; WORDLISTS
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
EN15:       FCC   "CORE"
EN15L       EQU   *-EN15
EN16:       FCC   "DOUBLE"
EN16L       EQU   *-EN16
EN17:       FCC   "DOUBLE-EXT"
EN17L       EQU   *-EN17
EN18:       FCC   "CORE-EXT"
EN18L       EQU   *-EN18
EN19:       FCC   "WORDLISTS"
EN19L       EQU   *-EN19

; ============================================================
; SECTION 25: TOOLS WORD SET (.S / WORDS / DUMP)
; ============================================================
; ------------------------------------------------------------
; .S  ( -- )
; Display every cell on the data stack, top first, each followed by a
; space, using ".". The stack is not changed.
; ------------------------------------------------------------
DOTSW:      PSHS  U                 ; walking pointer lives on the return stack
DSLOOP:     LDX   ,S
            CMPX  #SP0
            BEQ   DSDONE
            LDD   ,X++
            STX   ,S
            PSHU  D
            JSR   DOTW
            BRA   DSLOOP
DSDONE:     LEAS  2,S
            RTS

; ------------------------------------------------------------
; WORDS  ( -- )
; Display the names of the words of the first wordlist of the search
; order (ROOT if the order is empty), newest first, then a carriage
; return.
; ------------------------------------------------------------
WORDSW:     LDD   #BASEROOTLATEST
            LDX   #ORDER
            CMPX  ORDEND
            BHS   WW0
            LDX   ORDER             ; WID of the first wordlist
            LDD   ,X
WW0:        PSHS  D                 ; header being shown, on the return stack
WWLOOP:     LDX   ,S
            BEQ   WWDONE
            LDB   ,X
            ANDB  #$1F
            CLRA
            LEAX  1,X
            PSHU  X
            PSHU  D
            JSR   TYPEW
            JSR   SPACEW
            LDX   ,S
            LDB   ,X
            ANDB  #$1F
            CLRA
            LEAX  1,X
            LEAX  D,X
            LDD   ,X                ; LINK to the next header
            STD   ,S
            BRA   WWLOOP
WWDONE:     LEAS  2,S
            JSR   CRW
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
DUMPW:      JSR   CRW               ; leading CR
            LEAS  -4,S              ; locals: 0,S byte pointer, 2,S bytes on
                                    ; this line, 3,S column. u stays at 0,U
                                    ; and addr at 2,U. See shadow DUMPW.5
DULINE:     LDD   ,U
            LBEQ  DUDONE            ; no bytes left
            CMPD  #16
            BLS   DUN
            LDD   #16
DUN:        STB   2,S               ; n = bytes on this line
            LDD   2,U
            STD   ,S
            CLR   3,S
DUHEX:      LDB   3,S
            CMPB  2,S
            BEQ   DUHEXPAD
            LDX   ,S
            LDB   ,X+
            STX   ,S
            CLRA
            PSHU  D
            JSR   HEXBYTE
            LDD   #32
            PSHU  D
            JSR   EMITW
            INC   3,S
            BRA   DUHEX
DUHEXPAD:   LDB   3,S
            CMPB  #16
            BEQ   DUASCII
            LDD   #32               ; three spaces for each missing byte
            PSHU  D
            JSR   EMITW
            LDD   #32
            PSHU  D
            JSR   EMITW
            LDD   #32
            PSHU  D
            JSR   EMITW
            INC   3,S
            BRA   DUHEXPAD
DUASCII:    LDD   #32
            PSHU  D
            JSR   EMITW
            CLR   3,S
DUACHAR:    LDB   3,S
            CMPB  #16
            BEQ   DULEND
            CMPB  2,S
            BHS   DUABLANK
            LDX   2,U
            ABX                     ; X = line start + column
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
            INC   3,S
            BRA   DUACHAR
DUABLANK:   LDD   #32
            PSHU  D
            JSR   EMITW
            INC   3,S
            BRA   DUACHAR
DULEND:     JSR   CRW
            LDX   2,U               ; advance addr and reduce u by n
            LDB   2,S
            ABX
            STX   2,U
            LDD   ,U
            SUBB  2,S
            SBCA  #0
            STD   ,U
            LBRA  DULINE
DUDONE:     LEAS  4,S
            LEAU  4,U               ; drop addr and u
            RTS


; ------------------------------------------------------------
; [IF]  ( flag -- )     [ELSE]  ( -- )     [THEN]  ( -- )
; Programming-Tools conditional compilation. All three are
; immediate, so they work while interpreting and while compiling.
; [IF] with a true flag does nothing. With a false flag, and for
; [ELSE], the input is skipped word by word, counting nested
; [IF]s, up to the matching [ELSE] or [THEN]. The three names are
; matched exactly, as the dictionary matches every name. If the line
; runs out, the next line is read with REFILL; if no more input is
; available the skip ends.
; [THEN] is a marker and does nothing when it is executed.
; The nesting level is kept at 0,S.
; ------------------------------------------------------------
BRIFW:      PULU  D
            CMPD  #0
            BNE   BRTHENW           ; true: nothing to skip
BRELSEW:    LDD   #1
            PSHS  D                 ; level
BRNEXT:     JSR   PARSENAMEW
            PULU  D                 ; length
            PULU  X                 ; address
            CMPD  #0
            BEQ   BRREFILL
            CMPD  #4
            BEQ   BR4
            CMPD  #6
            BNE   BRNEXT
            LDB   #6
            LDY   #BRSELSE
            PSHS  X
            JSR   BRCMP
            PULS  X
            BNE   BR6B
            LDD   ,S                ; [ELSE]: ends the skip at level 1
            SUBD  #1
            BEQ   BRDONE
            BRA   BRNEXT
BR6B:       LDB   #6
            LDY   #BRSTHEN
            JSR   BRCMP
            BNE   BRNEXT
            LDD   ,S                ; [THEN]: one level less
            SUBD  #1
            STD   ,S
            BEQ   BRDONE
            BRA   BRNEXT
BR4:        LDB   #4
            LDY   #BRSIF
            JSR   BRCMP
            BNE   BRNEXT
            LDD   ,S                ; [IF]: one level more
            ADDD  #1
            STD   ,S
            BRA   BRNEXT
BRREFILL:   JSR   REFILLW
            PULU  D
            CMPD  #0
            BNE   BRNEXT
BRDONE:     LEAS  2,S
BRTHENW:    RTS

; Compare B characters at X with the pattern at Y. Case matters, as it
; does for every name in this system. Z is set if equal.
BRCMP:      LDA   ,X+
            CMPA  ,Y+
            BNE   BRCX
            DECB
            BNE   BRCMP
BRCX:       RTS

BRSIF:      FCC   "[IF]"
BRSELSE:    FCC   "[ELSE]"
BRSTHEN:    FCC   "[THEN]"

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

            JSR   WLINIT            ; FIND must work for the unit tests too

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
