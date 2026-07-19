; ============================================================
; 6809 ANS FORTH - consolidated source
; Assembled from the full design conversation.
;
; GLOBALS LAYOUT: applied. Every scratch/global cell now has a
; fixed RMB-assigned address in page zero ($0000-$00FF, DP=$00
; at reset) - see the GLOBALS section below for the full layout
; and its byte budget (256 of 256 bytes used, 0 free - the page
; is now fully packed; any future scratch cell will need to
; reuse an existing one or move a cell out of page zero).
;
; SERIAL HANDSHAKING: RTS (hardware, output) is implemented -
; IRQH/KEY toggle it based on the input ring's fill level
; against INHIWATER/INLOWATER (see SECTION 3). CTS (input) needs
; no firmware logic at all: the 6850 hardware automatically
; inhibits TDRE while CTS is deasserted, and this system's
; existing TDRE-gated transmit logic already respects that with
; no code changes. Software (XON/XOFF) handshaking remains not
; implemented - this system still neither transmits nor
; recognizes those bytes.
;
; DICTIONARY: applied (SECTION 27), 219 entries (215 original +
; DOES> + TRUE + FALSE, added in later passes - see below).
; Every primitive with a real code label now has a real ROM
; header, chained via LINK, CFA pointing directly at its code.
; Building this surfaced two real findings, not just mechanical
; work: (1) the original 1024-byte BASEDICT could not hold the
; header table (1954 bytes needed) - BASEDICT was resized to
; 2048 bytes ($E000-$E7FF), taking the space from BASECODE (then
; $E800-$FFBF, 6080 bytes, was 7104). This resize was based on
; the header-table budget alone; the actual assembled byte size
; of BASECODE's code was never measured with a real 6809
; assembler, so whether 6080 bytes was enough for all ~530
; routine labels in this file was never verified before BASECODE
; moved again (below). (2) DOES>
; initially had no corresponding code anywhere in the file -
; SETDOES and the DOES> compiling word (code label DOESGT, since
; a literal ">" is not a valid 6809 assembler label) were added
; in a follow-up pass, alongside DODOES/DOESRT0, closing that
; gap; DOESBEH was added to the GLOBALS layout to support it,
; using 2 of the page's last 3 free bytes (1 now remains). TRUE
; and FALSE were added in a still later pass: CONSTANT TRUE -1
; and CONSTANT FALSE 0, the first CONSTANT-pattern ROM-resident
; words in this system (TRUEBODY/FALSEBODY, section 26) - every
; other ROM word's CFA is a plain code label, but a CONSTANT's
; CFA is the DODOES-trampoline pattern, built by hand here with
; fixed, assemble-time addresses since there is no interactive
; CREATE/CONSTANT phase for ROM content.
;
; BASEDICT holds exactly 1973 bytes ($D83F-$DFF3), an exact,
; zero-padding fit for SECTION 27's real dictionary content.
; BASECODE ($DFF4-$FFA1) is contiguous directly above it, sized
; to a nominal 8110-byte budget. BASECODE's end lands exactly
; one byte below INITCODE's start ($FFA2) - zero gap, zero
; overlap. USROMSTRT/USROMEND, INOUT, RSTACK, DSTACK, CODETOP,
; APPCODE, APPDICT, and APPVARS are all mutually consistent, with
; no overlaps anywhere in the current memory map. See the ROM
; Size Required section of the documentation and the open-items
; checklist for real content totals and remaining margin.
;
; This file preserves the code exactly as derived and verified
; turn-by-turn in the conversation, including the corrected
; versions of every bug that was caught and fixed in place.
; SUBSTITUTE is complete but deliberately scoped to a single
; registered name/value pair, not a full table (see REPLACES).
; ENVTABLE's /HOLD and /PAD entries, and the DPHERE/CODEHERE/
; VARHERE boundary checks, remain explicitly incomplete/absent -
; see the inline notes preserved from that discussion, and the
; open-items checklist.
; ============================================================

; ------------------------------------------------------------
; MEMORY MAP
; ------------------------------------------------------------
USROMSTRT EQU $C100     ; Usable ROM start. Beginning of the usable
                         ; EPROM address range. INITCODE, BASECODE,
                         ; and BASEDICT must all fall within
                         ; USROMSTRT..USROMEND - see the verification
                         ; note below each one's EQU.
USROMEND EQU  VECTORS-1 ; Usable ROM end. Corrected: 1 before VECTORS'
                         ; start ($FFEF), not one past VECTORS' end as
                         ; originally defined - this is a real 16-bit
                         ; address (the last byte available before the
                         ; reserved vector table), usable directly in
                         ; comparisons or as a memory operand, unlike
                         ; the previous $10000 definition
VECTORS  EQU  $FFF0
INITCODE EQU  $FFA2     ; was $FFA0, before that $FFC0 - now exactly 78
                         ; bytes, matching the ~78-byte COLDSTRT+WARM+
                         ; WARMMSG estimate with zero margin (was 80,
                         ; with 2 bytes of slack). UNRESOLVED: this is
                         ; a real, pre-existing overlap with BASECODE
                         ; (ends $FFBF), not something this change
                         ; introduced - $FFA0 already overlapped it by
                         ; 32 bytes before this change; $FFA2 overlaps
                         ; by 30 bytes - reduced, not resolved. See the
                         ; open-items checklist.
BASECODE EQU  $DFF4     ; was $E012 - shifted down 30 bytes so its
                         ; nominal end ($FFA1) lands exactly one byte
                         ; below INITCODE's start ($FFA2), resolving the
                         ; INITCODE/BASECODE overlap precisely: zero
                         ; gap, zero overlap. Nominal size (8110 bytes)
                         ; is unchanged, only the start address moved.
BASEDICT EQU  $D83F     ; was $D85D - shifted down the same 30 bytes as
                         ; BASECODE, preserving the exact, zero-padding
                         ; fit for its real 1973-byte dictionary content
                         ; (SECTION 27) and staying perfectly contiguous
                         ; with BASECODE's new start.
INOUT    EQU  $C000     ; was $DF00 - moved so INOUT (256 B) sits
                         ; directly below USROMSTRT ($C100), contiguous,
                         ; no gap. This also resolves the INOUT portion
                         ; of the collision flagged when BASEDICT moved
                         ; to $D85D: INOUT no longer overlaps BASEDICT
                         ; ($D85D-$E011), since $C0FF < $D85D. The
                         ; DSTACK and RSTACK portions of that same
                         ; collision were NOT touched by this specific
                         ; change, but were resolved separately when
                         ; those two regions moved (see below). This
                         ; move ALSO overlapped APPCODE at the time
                         ; ($7000-$D7FF then) - since resolved too, when
                         ; APPCODE moved down $2000 (see below).
INOUTEND EQU  INOUT+$FF
RSTACK   EQU  $BFFF     ; was $BEFF - occupied range is $BD00-$BFFF
                         ; (768 bytes, unchanged size). RESOLVED: once a
                         ; 512-byte gap sat between this and DSTACK
                         ; below; DSTACK moving up $200 closed it - now
                         ; exactly contiguous, no gap
DSTACK   EQU  $BCFF     ; was $BAFF - moved up $200. RESOLVED (both):
                         ; occupied range is now $B900-$BCFF, which
                         ; exactly matches CODETOP ($B900) as its true
                         ; bottom - the 512-byte mismatch is gone - and
                         ; is now exactly contiguous with RSTACK's
                         ; bottom ($BD00), closing that gap too
CODETOP  EQU  $B900     ; was $B800 - code space ceiling (data stack
                         ; begins here). RESOLVED: this once no longer
                         ; matched DSTACK's true occupied bottom (was
                         ; $B700, a 512-byte mismatch) - now that DSTACK
                         ; moved up $200 to $B900, CODETOP matches it
                         ; exactly again
APPCODE  EQU  $7000     ; was $5000 - back to its original address.
                         ; RESOLVED: this once overlapped DSTACK's true
                         ; range by 512 bytes ($B700-$B8FF), a direct
                         ; consequence of the CODETOP/DSTACK mismatch -
                         ; now that DSTACK moved and CODETOP matches it
                         ; again, APPCODE's nominal range (up to
                         ; CODETOP-1) no longer reaches into DSTACK
APPDICT  EQU  $2000     ; was $015B - moved up, size unchanged (20133
                         ; bytes, now $2000-$6EA4). REDUCED BUT NOT
                         ; RESOLVED: still overlaps APPVARS below by 347
                         ; bytes ($2000-$215A), though SIBUF/WORDBUF/
                         ; TIBBUF/OUTBUF (swallowed by the previous
                         ; APPDICT address) are now clear. See the
                         ; open-items checklist
APPVARS  EQU  $021B     ; grown from 256 to 8000 bytes (end now $215A,
                         ; was $031A), taking the space directly from
                         ; APPDICT above it; start address unchanged.
                         ; That 8000-byte figure describes the original
                         ; intent, not the current actual usable size -
                         ; see APPVARSEND below, which now tracks
                         ; APPDICT's real position instead
APPVARSEND EQU APPDICT-1 ; was APPVARS+8000 ($215B) - now derives
                         ; directly from wherever APPDICT actually
                         ; starts, currently $1FFF (7653 bytes usable,
                         ; down from the static 8000). Self-correcting:
                         ; this can no longer go stale if APPDICT moves
                         ; again, unlike the previous fixed-size
                         ; definition. VUNUSEDW (below) is unchanged -
                         ; it already computed against APPVARSEND
SIBUF    EQU  $01FB     ; was $0300
WORDBUF  EQU  $01DA     ; was $02D4
TIBBUF   EQU  $018A     ; was $0284
TIBBUFL  EQU  80
SERBUF   EQU  $0106     ; was $0200 - USER0/USER1 removed entirely (see
                         ; below); the 6 buffers (SERBUF's 4-byte index
                         ; block, INBUF, OUTBUF, TIBBUF, WORDBUF, SIBUF)
                         ; now sit contiguously right after MVSCRATCH,
                         ; with no gap - this also closes a pre-existing
                         ; 11-byte gap that used to sit between WORDBUF
                         ; and SIBUF ($02F5-$02FF), unrelated to USER0/
                         ; USER1 but caught while making this region
                         ; genuinely contiguous end to end
INHEAD   EQU  SERBUF
INTAIL   EQU  SERBUF+1
OUTHEAD  EQU  SERBUF+2
OUTTAIL  EQU  SERBUF+3
INBUFSZ  EQU  64
OUTBUFSZ EQU  64
INBUF    EQU  SERBUF+4
OUTBUF   EQU  SERBUF+4+INBUFSZ
GLOBALS  EQU  $0000

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
;     FILLCNT  EQU MVCNT   - FILL's remaining-byte count
;     HSLEN    EQU MVCNT   - HOLDS's remaining-char count
;   MVDST    - MOVE/CMOVE's destination address
;     FILLADDR EQU MVDST   - FILL's target address
;     HSADDR   EQU MVDST   - HOLDS's source address
;   MVSRC    - MOVE/CMOVE's source address
;     MRESULT  EQU MVSRC   - single-cell multiply's 16-bit result
;     FILLCHR  EQU MVSRC   - FILL's fill character (1 byte, uses
;                            MVSRC's first byte only)
; ------------------------------------------------------------
         ORG   $0100
MVCNT      RMB   2
MVDST      RMB   2
MVSRC      RMB   2
FILLCNT  EQU  MVCNT
HSLEN    EQU  MVCNT
FILLADDR EQU  MVDST
HSADDR   EQU  MVDST
MRESULT  EQU  MVSRC
FILLCHR  EQU  MVSRC

SP0      EQU  DSTACK+1
RP0      EQU  RSTACK+1

; ------------------------------------------------------------
; ACIA (6850) constants - the chip sits at INOUT+8, not at the
; base of the I/O block, leaving INOUT+0..INOUT+7 free for other
; memory-mapped devices sharing this 256-byte region
; ------------------------------------------------------------
ACIA     EQU  INOUT+8
ACIACR   EQU  ACIA
ACIASR   EQU  ACIA
ACIADR   EQU  ACIA+1
SR_RDRF  EQU  $01
SR_TDRE  EQU  $02
SR_IRQ   EQU  $80
CR_RESET EQU  $03
CR_RXON  EQU  $95
CR_RXTX  EQU  $B5
CR_RTSHI EQU  $D5     ; bits6-5=10: RTS high, TX int disabled, RX int enabled -
                       ; derived from CR_RXON ($95) with bits6-5 changed from
                       ; 00 to 10; the ACIA has no combination offering RTS
                       ; high AND TX interrupt enabled simultaneously (bits6-5
                       ; only has 00/01/10/11, and only 01 enables TX interrupt,
                       ; which always ties RTS low) - EMIT/IRQH's TXCHK must
                       ; respect this and defer transmission while RTS is high

INHIWATER EQU 48       ; input ring fill level (of 64) at/above which RTS is
                        ; asserted high, telling the remote device to pause
INLOWATER EQU 16        ; fill level at/below which RTS is reasserted low;
                         ; deliberately well below INHIWATER (hysteresis) so
                         ; RTS doesn't chatter right at a single threshold

; ------------------------------------------------------------
; Flag / opcode constants
; ------------------------------------------------------------
TRUEV    EQU  $FFFF
FALSEV   EQU  $0000
OPJSR    EQU  $BD
RTSOPC   EQU  $39

; ------------------------------------------------------------
; Control-flow compile-time tags
; ------------------------------------------------------------
TAGFWD   EQU  1
TAGBACK  EQU  2
TAGDO    EQU  3
TAGCASE  EQU  4
TAGOF    EQU  5
TAGENDOF EQU  6

; ============================================================
; GLOBALS - real layout, applied. Every scratch/state cell
; referenced across the whole build now has a fixed address
; in page zero (DP = $00 at reset, set in COLDSTRT), laid out
; in RMB order below. Total: 256 of 256 bytes used - the page
; is fully packed. (DOESBEH and RTSSTATE were added in later
; passes, after this comment was first written with 253/256;
; they used up the last 3 bytes of headroom entirely.)
;
; SNEND, which appeared in the original placeholder list
; (documented under S"/."/SLITERAL/ABORT"'s string runtime),
; was dropped here: a full pass over every reference confirmed
; it is never actually read or written anywhere - SCNT/SPTR
; alone carry that runtime. CSAVE was removed earlier (see the
; COMMA/CODECOMMA history) and was never part of this layout.
; ============================================================
         ORG   $0000        ; GLOBALS page - Direct Page (DP) set to $00 at reset
STATE      RMB   2   ; offset $00
BASE       RMB   2   ; offset $02
LATEST     RMB   2   ; offset $04
DPHERE     RMB   2   ; offset $06
CODEHERE   RMB   2   ; offset $08
VARHERE    RMB   2   ; offset $0A
HANDLER    RMB   2   ; offset $0C
THROWN     RMB   2   ; offset $0E
TOIN       RMB   2   ; offset $10
NTIB       RMB   2   ; offset $12
DELIM      RMB   1   ; offset $14
WSTART     RMB   2   ; offset $15
SLEN       RMB   1   ; offset $17
SNAMEP     RMB   2   ; offset $18
FNDPTR     RMB   2   ; offset $1A
HDRPTR     RMB   2   ; offset $1C
HDRFLAGS   RMB   1   ; offset $1E
CADDR      RMB   2   ; offset $1F
CNTREM     RMB   1   ; offset $21
NUMNEG     RMB   1   ; offset $22
NADDR      RMB   2   ; offset $23
NCNT       RMB   2   ; offset $25
MULBASE    RMB   1   ; offset $27
CARRY      RMB   1   ; offset $28
MSCR       RMB   2   ; offset $29    (shared: -, *, comparisons, WITHIN...)
MSCR2      RMB   2   ; offset $2B
MSCR3      RMB   2   ; offset $2D
MSCR4      RMB   2   ; offset $2F
HLD        RMB   2   ; offset $31
DEPTHTMP   RMB   2   ; offset $33
AMAX       RMB   2   ; offset $35
ABUFP      RMB   2   ; offset $37
ACNT       RMB   2   ; offset $39
ACH        RMB   1   ; offset $3B
EMITCH     RMB   1   ; offset $3C
NEWHDR     RMB   2   ; offset $3D
NAMEP      RMB   2   ; offset $3F
NAMELEN    RMB   1   ; offset $41
PTARGET    RMB   2   ; offset $42
PFIELD     RMB   2   ; offset $44
NEWFLD     RMB   2   ; offset $46
CSP        RMB   2   ; offset $48
EXITCNT    RMB   2   ; offset $4A
EXITPTR    RMB   2   ; offset $4C
HDRSMUDGE  RMB   1   ; offset $4E
SCNT       RMB   2   ; offset $4F
SPTR       RMB   2   ; offset $51
SAVEN      RMB   2   ; offset $53
DRWIDTH    RMB   2   ; offset $55
DRLEN      RMB   2   ; offset $57
DRADDR     RMB   2   ; offset $59
DRPAD      RMB   2   ; offset $5B
PRODHI     RMB   2   ; offset $5D
PRODLO     RMB   2   ; offset $5F
PSIGN      RMB   1   ; offset $61
DIVNUM     RMB   2   ; offset $62
DIVDEN     RMB   2   ; offset $64
DIVREM     RMB   2   ; offset $66
DIVCNT     RMB   1   ; offset $68
DNSIGN     RMB   1   ; offset $69
DVSIGN     RMB   1   ; offset $6A
DVOWNSIGN  RMB   1   ; offset $6B
MAHI       RMB   1   ; offset $6C
MALO       RMB   1   ; offset $6D
MBHI       RMB   1   ; offset $6E
MBLO       RMB   1   ; offset $6F
MSIGN      RMB   1   ; offset $70
REM        RMB   2   ; offset $71
DCNT       RMB   1   ; offset $73
UDHI       RMB   2   ; offset $74
UDLO       RMB   2   ; offset $76
PRSIGN     RMB   1   ; offset $78
R2A        RMB   2   ; offset $79
R2B        RMB   2   ; offset $7B
RDST       RMB   2   ; offset $7D
RVAL       RMB   2   ; offset $7F
TR1        RMB   2   ; offset $81
TR2        RMB   2   ; offset $83
SHCNT      RMB   1   ; offset $85
SHCNT2     RMB   2   ; offset $86
TYPECNT    RMB   2   ; offset $88
TYPEADDR   RMB   2   ; offset $8A
PDELIM     RMB   1   ; offset $8C
PSTART     RMB   2   ; offset $8D
PLEN       RMB   2   ; offset $8F
CMPA1      RMB   2   ; offset $91
CMPL1      RMB   2   ; offset $93
CMPA2      RMB   2   ; offset $95
CMPL2      RMB   2   ; offset $97
CMPMIN     RMB   2   ; offset $99
SRCH1      RMB   2   ; offset $9B
SRCH1L     RMB   2   ; offset $9D
SRCH2      RMB   2   ; offset $9F
SRCH2L     RMB   2   ; offset $A1
SRCHPOS    RMB   2   ; offset $A3
SRCHI      RMB   2   ; offset $A5
UEADDR     RMB   2   ; offset $A7
UESRCLEN   RMB   2   ; offset $A9
UEDST      RMB   2   ; offset $AB
UEOUTLEN   RMB   2   ; offset $AD
SNXT       RMB   2   ; offset $AF
SNTARGET   RMB   2   ; offset $B1
REPLNAME   RMB   2   ; offset $B3
REPLNLEN   RMB   2   ; offset $B5
REPLVAL    RMB   2   ; offset $B7
REPLVLEN   RMB   2   ; offset $B9
SUBDESTCAP RMB   2   ; offset $BB
SUBDESTADR RMB   2   ; offset $BD
SUBSRCADR  RMB   2   ; offset $BF
SUBSRCLEN  RMB   2   ; offset $C1
SUBOUTLEN  RMB   2   ; offset $C3
SUBWPTR    RMB   2   ; offset $C5
SUBCOPYCNT RMB   2   ; offset $C7
SUBCOPYSRC RMB   2   ; offset $C9
MKDP       RMB   2   ; offset $CB
MKCODE     RMB   2   ; offset $CD
MKVAR      RMB   2   ; offset $CF
MKLATEST   RMB   2   ; offset $D1
EVSAVEA    RMB   2   ; offset $D3
EVSAVEL    RMB   2   ; offset $D5
EVSAVEI    RMB   2   ; offset $D7
EVSAVET    RMB   2   ; offset $D9
SRCADDR    RMB   2   ; offset $DB
SRCLEN     RMB   2   ; offset $DD
SRCID      RMB   2   ; offset $DF
SPAN       RMB   2   ; offset $E1
DSPTMP     RMB   2   ; offset $E3
WWALK      RMB   2   ; offset $E5
DUMPADDR   RMB   2   ; offset $E7
DUMPCNT    RMB   2   ; offset $E9
DUMPCOL    RMB   1   ; offset $EB
HEXBUF     RMB   2   ; offset $EC
DUVALID    RMB   1   ; offset $EE
ENVLEN     RMB   2   ; offset $EF
ENVADDR    RMB   2   ; offset $F1
QSAVEDP    RMB   2   ; offset $F3
QSAVECODE  RMB   2   ; offset $F5
QSAVEVAR   RMB   2   ; offset $F7
QSAVELATEST RMB  2   ; offset $F9
QTHROWCODE RMB   2   ; offset $FB
DOESBEH    RMB   2   ; offset $FD - SETDOES scratch
RTSSTATE   RMB   1   ; offset $FF - 0 = RTS low (normal), nonzero = RTS
                      ; high (paused) - see CR_RTSHI. GLOBALS page is now
                      ; fully packed: 256 of 256 bytes used, 0 free.

GLOBALS_USED EQU 256  ; total bytes used, of 256 available - fully packed

; ============================================================
; SECTION 1: HARDWARE VECTOR TABLE
; ============================================================
         ORG   VECTORS       ; VECTORS is $FFF0
VRESV    FDB   $0000
VSWI3    FDB   SWI3H
VSWI2    FDB   SWI2H
VFIRQ    FDB   FIRQH
VIRQ     FDB   IRQH
VSWI     FDB   SWIH
VNMI     FDB   WARM            ; NMI -> warm restart
VRESET   FDB   COLDSTRT

VECTOREND  EQU   *          ; Verify vectors size, value should match $10.
VECTORSIZE EQU   VECTOREND-VECTORS

; ============================================================
; SECTION 2: INIT CODE (COLDSTRT / WARM)
; ============================================================
         ORG   INITCODE       ; INITCODE is $FFA2 (was INIT/$FFA0, before that literal $FFC0)
COLDSTRT:
         ORCC  #$50
         LDS   #RSTACK+1
         LDU   #DSTACK+1
         CLRA
         TFR   A,DP

         LDX   #GLOBALS
         LDB   #0
CLRGLOB: CLR   ,X+
         DECB
         BNE   CLRGLOB

         LDX   #SERBUF
         CLR   ,X+
         CLR   ,X

         LDA   #$03
         STA   ACIACR         ; was "STA ACIA" - only correct by
                               ; coincidence while ACIA and ACIACR were
                               ; the same address; now genuinely distinct
         LDA   #CR_RXON
         STA   ACIACR         ; was "STA ACIA" - same fix

         JMP   COLD

WARM:    ORCC  #$50
         CLRA
         TFR   A,DP
         LDU   #SP0
         LDS   #RP0
         LDX   #WARMMSG
         PSHU  X
         LDD   #WARMMSGL
         PSHU  D
         JSR   TYPE
         ANDCC #$AF
         JMP   ABORT

WARMMSG: FCC   "  warm"
WARMMSGL EQU   *-WARMMSG

INITEND  EQU   *          ; Verify no collision with vectors, value should match vector ORG
INITSIZE EQU   INITEND-INITCODE

; ============================================================
; SECTION 3: ACIA INTERRUPT HANDLER
; ============================================================
         ORG   BASECODE       ; BASECODE is $E800. This ORG was missing
                               ; entirely - every routine from here through
                               ; SECTION 26 (IRQH, COLD/ABORT/QUIT, and
                               ; every primitive) would otherwise have
                               ; continued growing from wherever SECTION 2's
                               ; WARM message left the location counter,
                               ; inside INIT's 48-byte $FFC0-$FFEF budget,
                               ; overflowing directly into VECTORS ($FFF0)
                               ; instead of landing in BASECODE at all

; ------------------------------------------------------------
; INFILL - ( -- A=fill level, 0-63 ) input ring's current fill
; level. INBUFSZ is a power of two, and both indices are always
; kept in 0..INBUFSZ-1, so a plain masked subtraction gives the
; true mod-64 distance even across the wrap point.
; ------------------------------------------------------------
INFILL:  LDA   INHEAD
         SUBA  INTAIL
         ANDA  #INBUFSZ-1
         RTS

; ------------------------------------------------------------
; RTSCHECKHI - called from IRQH's own RX path (interrupts
; already masked by hardware during ISR execution, so no
; explicit masking needed here). If the input ring has reached
; INHIWATER and RTS is not already asserted high, assert it -
; telling the remote device to pause sending. Per the 6850, RTS
; has no automatic tie to reception; this is ordinary firmware
; flow control, not a chip feature.
; ------------------------------------------------------------
RTSCHECKHI: JSR  INFILL
            CMPA #INHIWATER
            BLO  RTSCHIDONE
            TST  RTSSTATE
            BNE  RTSCHIDONE       ; already high - nothing to do
            LDA  #CR_RTSHI
            STA  ACIACR
            LDA  #1
            STA  RTSSTATE
RTSCHIDONE: RTS

; ------------------------------------------------------------
; RTSCHECKLO - called from mainline code (KEY), NOT from the
; ISR, so it must mask IRQ around its critical section: IRQH's
; own TXOFF path also writes ACIACR, and an interrupt landing
; mid-decision here could otherwise race it. If the ring has
; drained to INLOWATER or below and RTS is currently high,
; reassert RTS low - restoring TX-interrupt-enable too if
; output happens to be queued, since the ACIA has no control
; byte combination offering RTS-high with TX-interrupt-enabled
; simultaneously (see CR_RTSHI's comment).
; ------------------------------------------------------------
RTSCHECKLO: JSR  INFILL
            CMPA #INLOWATER
            BHI  RTSCLODONE
            TST  RTSSTATE
            BEQ  RTSCLODONE       ; already low - nothing to do
            ORCC #$10              ; mask IRQ for the critical section
            CLR  RTSSTATE
            LDB  OUTTAIL
            CMPB OUTHEAD
            BEQ  RTSCLONOTX
            LDA  #CR_RXTX
            STA  ACIACR
            BRA  RTSCLOUNMASK
RTSCLONOTX: LDA  #CR_RXON
            STA  ACIACR
RTSCLOUNMASK: ANDCC #$EF
RTSCLODONE: RTS

IRQH:    LDA   ACIASR
         BITA  #SR_IRQ
         BEQ   IRQDONE

         BITA  #SR_RDRF
         BEQ   TXCHK

         LDB   INHEAD
         LDA   ACIADR
         LDX   #INBUF
         STA   B,X
         INCB
         ANDB  #INBUFSZ-1
         CMPB  INTAIL
         BEQ   IRQDONE
         STB   INHEAD
         JSR   RTSCHECKHI
         BRA   IRQDONE

TXCHK:   LDB   OUTTAIL
         CMPB  OUTHEAD
         BEQ   TXOFF
         LDX   #OUTBUF
         LDA   B,X
         STA   ACIADR
         INCB
         ANDB  #OUTBUFSZ-1
         STB   OUTTAIL
         BRA   IRQDONE

TXOFF:   TST   RTSSTATE
         BNE   IRQDONE         ; RTS is asserted high - leave ACIACR alone,
                                ; or this would incorrectly drop it back low
         LDA   #CR_RXON
         STA   ACIACR

IRQDONE: RTI

SWI3H:   RTI
SWI2H:   RTI
FIRQH:   RTI
NMIH:    RTI                   ; unused now that NMI -> WARM
SWIH:    LDD   #-99             ; placeholder hardware-trap code; push and
         PSHU  D                 ; JMP THROW, per the CATCH/THROW turn
         JMP   THROW

; ============================================================
; SECTION 4: COLD / ABORT / QUIT  (with CATCH-wrapped INTERPRET)
; ============================================================
COLD:    LDD   #APPVARS
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
         PSHU  X
         LDD   #SIGNONL
         PSHU  D
         JSR   TYPE
         JSR   CRW
         ; falls through into ABORT

ABORT:   LDU   #SP0
         ; falls through into QUIT

QUIT:    LDS   #RP0

QLOOP:   LDD   #0
         STD   STATE

         JSR   QUERY

         LDD   DPHERE
         STD   QSAVEDP
         LDD   CODEHERE
         STD   QSAVECODE
         LDD   VARHERE
         STD   QSAVEVAR
         LDD   LATEST
         STD   QSAVELATEST

         LDD   #INTERPRET
         PSHU  D
         JSR   CATCH
         PULU  D
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

         JSR   CRW
         LDX   #ERRMSG
         PSHU  X
         LDD   #ERRMSGL
         PSHU  D
         JSR   TYPE
         LDD   QTHROWCODE
         PSHU  D
         JSR   DOT
         BRA   QLOOP

QOK:     LDD   STATE
         BNE   QLOOP
         JSR   CRW
         LDX   #OKMSG
         PSHU  X
         LDD   #OKMSGL
         PSHU  D
         JSR   TYPE
         BRA   QLOOP

SIGNON:  FCC   "6809 FORTH v1.0"
SIGNONL  EQU   *-SIGNON
OKMSG:   FCC   "  ok"
OKMSGL   EQU   *-OKMSG
ERRMSG:  FCC   "  ERROR "
ERRMSGL  EQU   *-ERRMSG

; ============================================================
; SECTION 5: INNER-INTERPRETER SUPPORT (LIT, ZBRANCH, BRANCH,
; DODOES, DODEFER, EXECUTE)
; ============================================================
LIT:     PULS  X
         LDD   ,X++
         PSHU  D
         PSHS  X
         RTS

ZBRANCH: PULU  D
         PULS  X
         CMPD  #0
         BNE   ZSKIP
         LDD   ,X
         LEAX  D,X
         PSHS  X
         RTS
ZSKIP:   LEAX  2,X
         PSHS  X
         RTS

BRANCH:  PULS  X
         LDD   ,X
         LEAX  D,X
         PSHS  X
         RTS

DODOES:  PULS  X
         LDY   ,X++
         LDD   ,X
         PSHU  D
         JMP   ,Y

DOESRT0: RTS

; ----------------------------------------------------------
; SETDOES - compiled via JSR by DOES>'s immediate action.
; Patches LATEST's trampoline BEHAVIOR field, then returns
; two levels up - skipping the rest of the defining word's
; body entirely, straight back to whoever invoked it.
; ----------------------------------------------------------
SETDOES: PULS  X               ; X = addr right after "JSR SETDOES" - new BEHAVIOR
         STX   DOESBEH

         LDX   LATEST
         LDA   ,X
         STA   HDRFLAGS
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X              ; skip name -> LINK field
         LEAX  2,X               ; skip LINK -> CFA field
         LDD   ,X                 ; D = CFA (trampoline address)
         ADDD  #3                  ; +3 -> BEHAVIOR field (past JSR DODOES)
         TFR   D,X

         LDD   DOESBEH
         STD   ,X                   ; patch it

         PULS  X                     ; X = the OUTER defining word's own return addr
         JMP   ,X                     ; jump there directly - "double RTS"

DODEFER: PULU  X
         LDD   ,X
         TFR   D,X
         JMP   ,X

DOABORTUNDEF: LDD #-21
              PSHU D
              JMP  THROW

DOMARKER: PULU  X
          LDD   ,X
          STD   DPHERE
          LDD   2,X
          STD   CODEHERE
          LDD   4,X
          STD   VARHERE
          LDD   6,X
          STD   LATEST
          RTS

EXECUTE: PULU  X
         JSR   ,X
         RTS

; ============================================================
; SECTION 6: COMMA FAMILY (factored via APPENDCELL/APPENDBYTE)
; ============================================================
APPENDCELL: PULU D
            LDY   ,X
            STD   ,Y++
            STY   ,X
            RTS

APPENDBYTE: PULU D
            LDY   ,X
            STB   ,Y+
            STY   ,X
            RTS

COMMA:      LDX   #CODEHERE
            JMP   APPENDCELL

CODECOMMA:  LDX   #CODEHERE
            JMP   APPENDCELL

CCOMMA:     LDX   #CODEHERE
            JMP   APPENDBYTE

CCOMMA1:    LDX   #CODEHERE
            JMP   APPENDBYTE

VCOMMA:     LDX   #VARHERE
            JMP   APPENDCELL

VCCOMMA:    LDX   #VARHERE
            JMP   APPENDBYTE

ALLOT:   PULU  D
         LDX   CODEHERE
         LEAX  D,X
         STX   CODEHERE
         RTS

VALLOT:  PULU  D
         LDX   VARHERE
         LEAX  D,X
         STX   VARHERE
         RTS

HEREW:   LDD   CODEHERE
         PSHU  D
         RTS

VHEREW:  LDD   VARHERE
         PSHU  D
         RTS

PADW:    LDD   CODEHERE
         ADDD  #84
         PSHU  D
         RTS

UNUSEDW: LDD   #CODETOP
         SUBD  CODEHERE
         PSHU  D
         RTS

VUNUSEDW: LDD  #APPVARSEND    ; was #APPCODE - a real bug, not just a
          SUBD VARHERE        ; missing check: computed a meaningless
          PSHU D              ; distance to an unrelated region instead
          RTS                 ; of remaining APPVARS space

; ============================================================
; SECTION 7: HEADER (factored from :/CREATE/VARIABLE)
; ============================================================
HEADER:  LDD   #32
         PSHU  D
         JSR   WORD
         PULU  X
         LDA   ,X
         STA   NAMELEN
         LEAX  1,X
         STX   NAMEP

         PULU  D
         STB   HDRSMUDGE

         LDD   DPHERE
         STD   NEWHDR
         LDX   DPHERE
         LDA   NAMELEN
         TST   HDRSMUDGE
         BEQ   HDNOSM
         ORA   #$40
HDNOSM:  STA   ,X+
         LDY   NAMEP
         LDB   NAMELEN
         BEQ   HDNONM
HDCPY:   LDA   ,Y+
         STA   ,X+
         DECB
         BNE   HDCPY
HDNONM:  LDD   LATEST
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
COLON:   LDD   #TRUEV
         PSHU  D
         JSR   HEADER
         TFR   U,D
         STD   CSP
         LDD   #-1
         STD   STATE
         RTS

SEMI:    LDD   #RTSOPC
         PSHU  D
         JSR   CCOMMA1
         TFR   U,D
         CMPD  CSP
         BEQ   SEMIOK
         JSR   CFERR
SEMIOK:  LDX   LATEST
         LDA   ,X
         ANDA  #$BF
         STA   ,X
         LDD   #0
         STD   STATE
         RTS

CREATE:  LDD   #0
         PSHU  D
         JSR   HEADER
         LDD   #DODOES
         PSHU  D
         JSR   CCALL
         LDD   #DOESRT0
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         PSHU  D
         JSR   CODECOMMA
         RTS

; ----------------------------------------------------------
; DOES> ( -- )  IMMEDIATE, compile-only. Compiles a call to
; SETDOES. Code label DOESGT, not "DOES>" - a literal ">" is
; not valid in a 6809 assembler label, same reason ?DUP/2DUP/
; etc. all use mnemonic labels rather than their literal names.
; ----------------------------------------------------------
DOESGT:  LDD   #SETDOES
         PSHU  D
         JSR   CCALL
         RTS

VARIABLE: LDD  #0
          PSHU D
          JSR  HEADER
          LDD  #DODOES
          PSHU D
          JSR  CCALL
          LDD  #DOESRT0
          PSHU D
          JSR  CODECOMMA
          LDD  VARHERE
          PSHU D
          JSR  CODECOMMA
          LDD  #0
          LDX  VARHERE
          STD  ,X++
          STX  VARHERE
          RTS

ATSIGN:  PULU  X
         LDD   ,X
         PSHU  D
         RTS

CONSTANT: LDD  #0
          PSHU D
          JSR  HEADER
          LDD  #DODOES
          PSHU D
          JSR  CCALL
          LDD  #ATSIGN
          PSHU D
          JSR  CODECOMMA
          LDD  CODEHERE
          PSHU D
          JSR  CODECOMMA
          JSR  COMMA
          RTS

DOVALUE: PULU  X
         LDD   ,X
         PSHU  D
         RTS

VALUEW:  LDD   #0
         PSHU  D
         JSR   HEADER          ; not smudged - immediately findable
         LDD   #DODOES
         PSHU  D
         JSR   CCALL
         LDD   #DOVALUE
         PSHU  D
         JSR   CODECOMMA         ; trampoline itself is still code
         LDD   VARHERE            ; PFA = VARHERE, mutable space - was
         PSHU  D                   ; CODEHERE; TO writes through this PFA,
         JSR   CODECOMMA            ; so it must live in mutable space
         JSR   VCOMMA                ; store x into VARHERE via VCOMMA,
                                       ; not COMMA (which targets CODEHERE)
         RTS

TOW:     LDD   #32
         PSHU  D
         JSR   WORD
         JSR   FIND
         PULU  D
         CMPD  #0
         BNE   TOFOUND
         PULU  D
         LDD   #-13
         PSHU  D
         JSR   THROW
TOFOUND: JSR   TOBODY
         LDD   STATE
         BEQ   TOIMMED
         JSR   LITERALW
         LDD   #STOREW
         PSHU  D
         JSR   CCALL
         RTS
TOIMMED: PULU  X
         PULU  D
         STD   ,X
         RTS

TWOVARIABLE: LDD #0
             PSHU D
             JSR HEADER
             LDD #DODOES
             PSHU D
             JSR CCALL
             LDD #DOESRT0
             PSHU D
             JSR CODECOMMA
             LDD VARHERE
             PSHU D
             JSR CODECOMMA
             LDD #0
             LDX VARHERE
             STD ,X++
             STD ,X++
             STX VARHERE
             RTS

TWOCONSTANT: LDD #0
             PSHU D
             JSR HEADER
             LDD #DODOES
             PSHU D
             JSR CCALL
             LDD #DFETCH
             PSHU D
             JSR CODECOMMA
             LDD CODEHERE
             PSHU D
             JSR CODECOMMA
             PULU D              ; x2, off the top
             STD  MSCR
             JSR  COMMA            ; x1 -> lower address
             LDD  MSCR
             PSHU D
             JSR  COMMA              ; x2 -> higher address
             RTS

BUFFERCOLON: PULU D
             STD  MSCR2
             LDD  #0
             PSHU D
             JSR  HEADER
             LDD  #DODOES
             PSHU D
             JSR  CCALL
             LDD  #DOESRT0
             PSHU D
             JSR  CODECOMMA
             LDD  VARHERE
             PSHU D
             JSR  CODECOMMA
             LDD  MSCR2
             PSHU D
             JSR  VALLOT
             RTS

DEFERW:  LDD   #0
         PSHU  D
         JSR   HEADER
         LDD   #DODOES
         PSHU  D
         JSR   CCALL
         LDD   #DODEFER
         PSHU  D
         JSR   CODECOMMA
         LDD   CODEHERE
         PSHU  D
         JSR   CODECOMMA
         LDD   #DOABORTUNDEF
         PSHU  D
         JSR   COMMA
         RTS

DEFERFETCH: JSR TOBODY
            PULU X
            LDD  ,X
            PSHU D
            RTS

DEFERSTORE: JSR TOBODY
            PULU X
            PULU D
            STD  ,X
            RTS

ISW:     LDD   #32
         PSHU  D
         JSR   WORD
         JSR   FIND
         PULU  D
         CMPD  #0
         BNE   ISFOUND
         PULU  D
         LDD   #-13
         PSHU  D
         JSR   THROW
ISFOUND: PULU  X
         LDD   STATE
         BEQ   ISIMMED
         PSHU  X
         JSR   LITERALW
         LDD   #DEFERSTORE
         PSHU  D
         JSR   CCALL
         RTS
ISIMMED: PSHU  X
         JSR   DEFERSTORE
         RTS

ACTIONOF: LDD  #32
          PSHU D
          JSR  WORD
          JSR  FIND
          PULU D
          CMPD #0
          BNE  AOFOUND
          PULU D
          LDD  #-13
          PSHU D
          JSR  THROW
AOFOUND:  PULU X
          LDD  STATE
          BEQ  AOIMMED
          PSHU X
          JSR  LITERALW
          LDD  #DEFERFETCH
          PSHU D
          JSR  CCALL
          RTS
AOIMMED:  PSHU X
          JSR  DEFERFETCH
          RTS

MARKERW: LDD   DPHERE
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
         LDD   CODEHERE
         PSHU  D
         JSR   CODECOMMA
         LDD   MKDP
         PSHU  D
         JSR   COMMA
         LDD   MKCODE
         PSHU  D
         JSR   COMMA
         LDD   MKVAR
         PSHU  D
         JSR   COMMA
         LDD   MKLATEST
         PSHU  D
         JSR   COMMA
         RTS

; ============================================================
; SECTION 9: OUTER INTERPRETER (INTERPRET / WORD / FIND / NUMBER?)
; ============================================================
INTERPRET:
ILOOP:   JSR   WORD
         LDX   ,U
         LDA   ,X
         BEQ   IDONE

         JSR   FIND
         PULU  D
         TSTB
         LBEQ  TRYNUM

         LDA   STATE+1
         BEQ   DOEXEC
         TSTB
         BPL   DOEXEC
         JSR   CCALL
         BRA   ILOOP

DOEXEC:  JSR   EXECUTE
         BRA   ILOOP

TRYNUM:  JSR   NUMBERQ
         PULU  D
         CMPD  #0            ; was TSTD (6309-only) - PULU doesn't set CC on
                              ; genuine 6809, so compare D against 0 directly
         BEQ   BADWORD

         LDD   STATE
         BEQ   ILOOP
         LDD   #LIT
         PSHU  D
         JSR   CCALL
         JSR   CODECOMMA
         BRA   ILOOP

BADWORD: JSR   COUNT
         JSR   TYPE
         LDD   #-13
         PSHU  D
         JSR   THROW

IDONE:   RTS

WORD:    PULU  D
         STB   DELIM
         LDD   TOIN
         LDX   SRCADDR
         LEAX  D,X
         LDD   SRCLEN
         SUBD  TOIN
         TFR   D,Y

SKIPLP:  CMPY  #0
         BEQ   EMPTY
         LDA   ,X
         CMPA  DELIM
         BNE   STARTW
         LEAX  1,X
         LEAY  -1,Y
         BRA   SKIPLP

STARTW:  STX   WSTART
         LDB   #0

SCANLP:  CMPY  #0
         BEQ   ENDW
         LDA   ,X
         CMPA  DELIM
         BEQ   CONSUME
         CMPB  #31
         BEQ   ENDW
         LEAX  1,X
         LEAY  -1,Y
         INCB
         BRA   SCANLP

CONSUME: LEAX  1,X
         LEAY  -1,Y
ENDW:    TFR   X,D
         SUBD  SRCADDR
         STD   TOIN

         LDX   #WORDBUF
         STB   ,X+
         LDY   WSTART
COPYLP:  TSTB
         BEQ   COPYDONE
         LDA   ,Y+
         STA   ,X+
         DECB
         BRA   COPYLP
COPYDONE: LDX  #WORDBUF
          PSHU X
          RTS

EMPTY:   LDX   #WORDBUF
         CLR   ,X
         PSHU  X
         RTS

FIND:    PULU  X
         LDA   ,X
         STA   SLEN
         LEAX  1,X
         STX   SNAMEP

         LDD   LATEST
         STD   FNDPTR

FFLOOP:  LDD   FNDPTR
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
CMPLP:   LDA   ,X+
         CMPA  ,Y+
         BNE   FNEXT
         DECB
         BNE   CMPLP

FMATCH:  LDX   HDRPTR
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LEAX  2,X
         LDD   ,X
         PSHU  D
         LDA   HDRFLAGS
         BITA  #$80
         BEQ   FISNORM
         LDD   #1
         BRA   FPUSH
FISNORM: LDD   #-1
FPUSH:   PSHU  D
         RTS

FNEXT:   LDX   HDRPTR
         LEAX  1,X
         LDB   HDRFLAGS
         ANDB  #$1F
         CLRA
         LEAX  D,X
         LDD   ,X
         STD   FNDPTR
         BRA   FFLOOP

NOTFOUND: LDX  SNAMEP
          LEAX -1,X
          PSHU X
          LDD  #0
          PSHU D
          RTS

UDMULADD: STB  CARRY
          LDA  BASE+1
          STA  MULBASE
          LDA  UDLO+1
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM0
          INCA
UM0:      STB  UDLO+1
          STA  CARRY
          LDA  UDLO
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM1
          INCA
UM1:      STB  UDLO
          STA  CARRY
          LDA  UDHI+1
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM2
          INCA
UM2:      STB  UDHI+1
          STA  CARRY
          LDA  UDHI
          LDB  MULBASE
          MUL
          ADDB CARRY
          BCC  UM3
          INCA
UM3:      STB  UDHI
          RTS

NUMLOOP: LDD   NCNT
         BEQ   NLDONE
         LDX   NADDR
         LDA   ,X
         CMPA  #'0'
         BLO   NLDONE
         CMPA  #'9'
         BHI   NLALPHA
         SUBA  #'0'
         BRA   NLGOT
NLALPHA: ANDA  #$DF
         CMPA  #'A'
         BLO   NLDONE
         CMPA  #'Z'
         BHI   NLDONE
         SUBA  #'A'-10
NLGOT:   CMPA  BASE+1
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
NLDONE:  RTS

TONUMBER: PULU D
          STD  NCNT
          PULU D
          STD  NADDR
          PULU D
          STD  UDHI
          PULU D
          STD  UDLO
          JSR  NUMLOOP
          LDD  UDLO
          PSHU D
          LDD  UDHI
          PSHU D
          LDX  NADDR
          PSHU X
          LDD  NCNT
          PSHU D
          RTS

NUMBERQ: PULU  X
         STX   CADDR
         LDA   ,X
         BEQ   NQBAD
         STA   CNTREM
         LEAX  1,X

         CLR   NUMNEG
         LDA   ,X
         CMPA  #'-'
         BNE   NQNOSIGN
         COM   NUMNEG
         LEAX  1,X
         DEC   CNTREM
         BEQ   NQBAD

NQNOSIGN: STX  NADDR
          CLRA
          LDB   CNTREM
          STD   NCNT
          LDD   #0
          STD   UDHI
          STD   UDLO

          JSR   NUMLOOP

          LDD   NCNT
          BNE   NQBAD

          LDD   UDLO
          TST   NUMNEG
          BEQ   NQPOS
          COMA
          COMB
          ADDD  #1
NQPOS:    PSHU  D
          LDD   #-1
          PSHU  D
          RTS

NQBAD:    LDX   CADDR
          PSHU  X
          LDD   #0
          PSHU  D
          RTS

; ============================================================
; SECTION 10: QUERY / ACCEPT / EXPECT / KEY / KEY? / EMIT
; ============================================================
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

; ============================================================
; SECTION 11: COLON / SEMICOLON support already in section 8
; (COLON/SEMI) - CATCH/THROW, CFERR
; ============================================================
CFERR:   LDD   #-22
         PSHU  D
         JSR   THROW
         RTS

CATCH:   PULU  X
         LDD   HANDLER
         PSHS  D
         PSHS  U
         TFR   S,D
         STD   HANDLER

         JSR   ,X

         LEAS  2,S
         PULS  D
         STD   HANDLER
         LDD   #0
         PSHU  D
         RTS

THROW:   PULU  D
         CMPD  #0
         BEQ   THDONE

         STD   THROWN
         LDX   HANDLER
         BEQ   THUNCAU

         TFR   X,S
         PULS  D
         TFR   D,U
         PULS  D
         STD   HANDLER

         LDD   THROWN
         PSHU  D
         RTS
THDONE:  RTS

THUNCAU: LDD   THROWN
         PSHU  D
         JMP   ABORT

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
; SECTION 13: COMPILING WORDS (IMMEDIATE/[/]/'/COMPILE,/
; LITERAL/[']/POSTPONE/>BODY, SLITERAL, ABORT")
; ============================================================
STATEW:     LDD  #STATE
            PSHU D
            RTS

IMMEDIATE:  LDX  LATEST
            LDA  ,X
            ORA  #$80
            STA  ,X
            RTS

LBRACKET: LDD  #0
          STD  STATE
          RTS

RBRACKET: LDD  #-1
          STD  STATE
          RTS

TICK:    LDD  #32
         PSHU D
         JSR  WORD
         JSR  FIND
         PULU D
         CMPD #0
         BNE  TICKOK
         PULU D
         LDD  #-13
         PSHU D
         JSR  THROW
TICKOK:  RTS

COMPILECOMMA: JMP  CCALL

CCALL:   PULU  D
         LDX   CODEHERE
         LDA   #OPJSR
         STA   ,X+
         STD   ,X++
         STX   CODEHERE
         RTS

LITERALW: LDD  #LIT
          PSHU D
          JSR  CCALL
          JSR  CODECOMMA
          RTS

BRACKTICK: LDD  STATE
           BNE  BTSTOK
           LDD  #-14
           PSHU D
           JSR  THROW
BTSTOK:    LDD  #32
           PSHU D
           JSR  WORD
           JSR  FIND
           PULU D
           CMPD #0
           BNE  BTOK
           PULU D
           LDD  #-13
           PSHU D
           JSR  THROW
BTOK:      JSR  LITERALW
           RTS

POSTPONEW: LDD  STATE
           BNE  PPSTOK
           LDD  #-14
           PSHU D
           JSR  THROW
PPSTOK:    LDD  #32
           PSHU D
           JSR  WORD
           JSR  FIND
           PULU D
           CMPD #0
           BNE  PPFOUND
           PULU D
           LDD  #-13
           PSHU D
           JSR  THROW
PPFOUND:   CMPD #1
           BEQ  PPIMM
           JSR  LITERALW
           LDD  #COMPILECOMMA
           PSHU D
           JSR  CCALL
           RTS
PPIMM:     JSR  COMPILECOMMA
           RTS

TOBODY:  PULU D
         ADDD #5
         TFR  D,X
         LDD  ,X
         PSHU D
         RTS

SLITERALW: LDD  STATE
           BNE  SLSTOK
           LDD  #-14
           PSHU D
           JSR  THROW
SLSTOK:    PULU D
           STD  SCNT
           PULU D
           STD  SPTR
           LDD  #DOSTR
           PSHU D
           JSR  CCALL
           LDX  CODEHERE
           LDB  SCNT+1
           STB  ,X+
           LDY  SPTR
           LDB  SCNT+1
           BEQ  SLEND
SLCPY:     LDA  ,Y+
           STA  ,X+
           DECB
           BNE  SLCPY
SLEND:     STX  CODEHERE
           RTS

DOABORTQUOTE: PULS X
              LDB  ,X
              LEAX 1,X
              STX  SPTR
              CLRA
              STD  SCNT
              LDX  SPTR
              LDB  SCNT+1
              LEAX B,X
              PULU D
              CMPD #0
              BNE  AQTHROW
              PSHS X
              RTS
AQTHROW:      LDD  SPTR
              PSHU D
              LDD  SCNT
              PSHU D
              JSR  TYPE
              PSHS X
              LDD  #-2
              PSHU D
              JMP  THROW

ABORTQUOTE: LDD  STATE
            BNE  AQSTOK
            LDD  #-14
            PSHU D
            JSR  THROW
AQSTOK:     LDD  #34
            PSHU D
            JSR  WORD
            PULU X
            LDA  ,X
            STA  SCNT
            LEAX 1,X
            STX  SPTR
            LDD  #DOABORTQUOTE
            PSHU D
            JSR  CCALL
            LDX  CODEHERE
            LDA  SCNT
            STA  ,X+
            LDY  SPTR
            LDB  SCNT
            BEQ  AQEND
AQCPY:      LDA  ,Y+
            STA  ,X+
            DECB
            BNE  AQCPY
AQEND:      STX  CODEHERE
            RTS

BLW:     LDD   #32
         PSHU  D
         RTS

TOINW:   LDD   #TOIN
         PSHU  D
         RTS

SPANW:   LDD   #SPAN
         PSHU  D
         RTS

TIBW:    LDD   #TIBBUF
         PSHU  D
         RTS

NTIBW:   LDD   #NTIB
         PSHU  D
         RTS

; ============================================================
; SECTION 14: STACK MANIPULATION (Core + Core Ext + return stack)
; ============================================================
DUP:     LDD   ,U
         PSHU  D
         RTS

DROP:    LEAU  2,U
         RTS

SWAP:    LDD   ,U
         LDX   2,U
         STX   ,U
         STD   2,U
         RTS

OVER:    LDD   2,U
         PSHU  D
         RTS

ROT:     LDD   ,U
         LDX   2,U
         LDY   4,U
         STY   ,U
         STD   2,U
         STX   4,U
         RTS

QDUP:    LDD   ,U
         CMPD  #0
         BEQ   QDUPDONE
         PSHU  D
QDUPDONE: RTS

DEPTH:   TFR   U,D
         STD   DEPTHTMP
         LDD   #SP0
         SUBD  DEPTHTMP
         LSRA
         RORB
         PSHU  D
         RTS

DDUP:    LDD   2,U
         LDX   ,U
         PSHU  D
         PSHU  X
         RTS

DDROP:   LEAU  4,U
         RTS

DSWAP:   LDD   ,U
         STD   MSCR
         LDD   2,U
         LDX   4,U
         LDY   6,U
         STD   6,U
         STX   ,U
         STY   2,U
         LDD   MSCR
         STD   4,U
         RTS

DOVER:   LDD   6,U
         LDX   4,U
         PSHU  D
         PSHU  X
         RTS

NIP:     LDD   ,U
         STD   2,U
         LEAU  2,U
         RTS

TUCK:    LDD   ,U
         LDX   2,U
         PSHU  D
         STX   2,U
         STD   4,U
         RTS

PICK:    PULU  D
         LSLB
         ROLA
         LDD   D,U
         PSHU  D
         RTS

ROLL:    PULU  D
         CMPD  #0
         BEQ   ROLLDONE
         LSLB
         ROLA
         STD   RDST
         LEAX  D,U
         LDD   ,X
         STD   RVAL
RLOOP:   LDD   RDST
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
RSTORE:  LDD   RVAL
         STD   ,U
ROLLDONE: RTS

DROT:    LDD   10,U
         STD   TR1
         LDD   8,U
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

TOR:     PULU  D
         PULS  X
         PSHS  D
         PSHS  X
         RTS

FROMR:   PULS  X
         PULS  D
         PSHS  X
         PSHU  D
         RTS

RFETCH:  PULS  X
         LDD   ,S
         PSHS  X
         PSHU  D
         RTS

TWOTOR:  PULU  D
         STD   R2A
         PULU  D
         STD   R2B
         PULS  X
         LDD   R2B
         PSHS  D
         LDD   R2A
         PSHS  D
         PSHS  X
         RTS

TWOFROMR: PULS X
          PULS D
          STD  R2A
          PULS D
          STD  R2B
          PSHS X
          LDD  R2B
          PSHU D
          LDD  R2A
          PSHU D
          RTS

TWORFETCH: PULS X
           LDD  ,S
           STD  R2A
           LDD  2,S
           STD  R2B
           PSHS X
           LDD  R2B
           PSHU D
           LDD  R2A
           PSHU D
           RTS

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
; SECTION 16: LOGIC / SHIFTS / ADDRESS ARITHMETIC
; ============================================================
ANDW:    PULU  D
         ANDA  ,U
         ANDB  1,U
         STD   ,U
         RTS

ORW:     PULU  D
         ORA   ,U
         ORB   1,U
         STD   ,U
         RTS

XORW:    PULU  D
         EORA  ,U
         EORB  1,U
         STD   ,U
         RTS

INVERT:  LDD   ,U
         COMA
         COMB
         STD   ,U
         RTS

LSHIFT:  PULU  D
         STB   SHCNT
         LDD   ,U
LSLOOP:  LDB   SHCNT
         BEQ   LSDONE
         ASL   1,U
         ROL   ,U
         DEC   SHCNT
         BRA   LSLOOP
LSDONE:  RTS

RSHIFT:  PULU  D
         STB   SHCNT
RSLOOP:  LDB   SHCNT
         BEQ   RSDONE
         LSR   ,U
         ROR   1,U
         DEC   SHCNT
         BRA   RSLOOP
RSDONE:  RTS

CELLSW:  LDD   ,U
         ASLB
         ROLA
         STD   ,U
         RTS

CELLPLUS: LDD  ,U
          ADDD #2
          STD  ,U
          RTS

CHARSW:  RTS

CHARPLUS: LDD  ,U
          ADDD #1
          STD  ,U
          RTS

ALIGNW:  RTS
ALIGNEDW: RTS

; ============================================================
; SECTION 17: COMPARISON
; ============================================================
EQUALW:  PULU  D
         CMPD  ,U
         BEQ   EQTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
EQTRUE:  LDD   #TRUEV
         STD   ,U
         RTS

LESSW:   PULU  D
         STD   MSCR
         LDD   ,U
         CMPD  MSCR
         BLT   LTTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
LTTRUE:  LDD   #TRUEV
         STD   ,U
         RTS

GREATERW: PULU D
          STD  MSCR
          LDD  ,U
          CMPD MSCR
          BGT  GTTRUE
          LDD  #FALSEV
          STD  ,U
          RTS
GTTRUE:   LDD  #TRUEV
          STD  ,U
          RTS

ZEROEQ:  LDD   ,U
         BEQ   ZEQTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
ZEQTRUE: LDD   #TRUEV
         STD   ,U
         RTS

ZEROLT:  LDD   ,U
         BMI   ZLTTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
ZLTTRUE: LDD   #TRUEV
         STD   ,U
         RTS

ULESSW:  PULU  D
         STD   MSCR
         LDD   ,U
         CMPD  MSCR
         BLO   ULTRUE
         LDD   #FALSEV
         STD   ,U
         RTS
ULTRUE:  LDD   #TRUEV
         STD   ,U
         RTS

NOTEQUAL: JSR  EQUALW
          LDD  ,U
          COMA
          COMB
          STD  ,U
          RTS

ZERONE:  JSR   ZEROEQ
         LDD   ,U
         COMA
         COMB
         STD   ,U
         RTS

ZEROGT:  LDD   ,U
         BEQ   ZGTFALSE
         BMI   ZGTFALSE
         LDD   #TRUEV
         STD   ,U
         RTS
ZGTFALSE: LDD  #FALSEV
          STD  ,U
          RTS

UGREATER: PULU D
          STD  MSCR
          LDD  ,U
          CMPD MSCR
          BLO  UGFALSE
          BEQ  UGFALSE
          LDD  #TRUEV
          STD  ,U
          RTS
UGFALSE:  LDD  #FALSEV
          STD  ,U
          RTS

WITHINW: PULU  D
         STD   MSCR
         PULU  D
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
WITHTRUE: LDD  #TRUEV
          STD  ,U
          RTS

DEQUAL:  PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         CMPD  MSCR2
         BNE   DEQFALSE
         LDD   MSCR3
         CMPD  MSCR
         BNE   DEQFALSE
         LDD   #TRUEV
         PSHU  D
         RTS
DEQFALSE: LDD  #FALSEV
          PSHU D
          RTS

DLESSW:  PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         STD   MSCR4
         LDD   MSCR3
         CMPD  MSCR
         BLT   DLTRUE
         BGT   DLFALSE
         LDD   MSCR4
         CMPD  MSCR2
         BLO   DLTRUE
DLFALSE: LDD   #FALSEV
         PSHU  D
         RTS
DLTRUE:  LDD   #TRUEV
         PSHU  D
         RTS

DULESSW: PULU  D
         STD   MSCR
         PULU  D
         STD   MSCR2
         PULU  D
         STD   MSCR3
         PULU  D
         STD   MSCR4
         LDD   MSCR3
         CMPD  MSCR
         BLO   DULTRUE
         BHI   DULFALSE
         LDD   MSCR4
         CMPD  MSCR2
         BLO   DULTRUE
DULFALSE: LDD  #FALSEV
          PSHU D
          RTS
DULTRUE:  LDD  #TRUEV
          PSHU D
          RTS

; ============================================================
; SECTION 18: MEMORY (fetch/store, block ops)
; ============================================================
STOREW:  PULU  X
         PULU  D
         STD   ,X
         RTS

CFETCH:  PULU  X
         LDB   ,X
         CLRA
         PSHU  D
         RTS

CSTOREW: PULU  X
         PULU  D
         STB   ,X
         RTS

PLUSSTORE: PULU X
           PULU D
           ADDD ,X
           STD  ,X
           RTS

DFETCH:  PULU  X
         LDD   2,X
         PSHU  D
         LDD   ,X
         PSHU  D
         RTS

DSTORE:  PULU  X
         PULU  D
         STD   2,X
         PULU  D
         STD   ,X
         RTS

CMOVEW:  PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDX   MVSRC
         LDY   MVDST
CMVLOOP: LDD   MVCNT
         BEQ   CMDONE
         LDA   ,X+
         STA   ,Y+
         SUBD  #1
         STD   MVCNT
         BRA   CMVLOOP
CMDONE:  RTS

CMOVEGT: PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDD   MVCNT
         BEQ   CGDONE
         LDX   MVSRC
         LEAX  D,X
         LEAX  -1,X
         LDY   MVDST
         LEAY  D,Y
         LEAY  -1,Y
CGLOOP:  LDA   ,X
         STA   ,Y
         LEAX  -1,X
         LEAY  -1,Y
         LDD   MVCNT
         SUBD  #1
         STD   MVCNT
         BNE   CGLOOP
CGDONE:  RTS

MOVEW:   PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
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
         JMP   CMOVEGT
MVLOW:   LDD   MVSRC
         PSHU  D
         LDD   MVDST
         PSHU  D
         LDD   MVCNT
         PSHU  D
         JMP   CMOVEW

FILLW:   PULU  D
         STB   FILLCHR
         PULU  D
         STD   FILLCNT
         PULU  D
         STD   FILLADDR
         LDX   FILLADDR
FILLOOP: LDD   FILLCNT
         BEQ   FDONE
         LDA   FILLCHR
         STA   ,X+
         SUBD  #1
         STD   FILLCNT
         BRA   FILLOOP
FDONE:   RTS

ERASEW:  LDD   #0
         PSHU  D
         JMP   FILLW

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

UDOT:    PULU  D
         PSHU  D
         LDD   #0
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
         PULU  D
         PSHU  D
         LDD   #0
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

; ============================================================
; SECTION 21: BASE / RADIX CONTROL
; ============================================================
BASEW:   LDD  #BASE
         PSHU D
         RTS

DECIMAL: LDD  #10
         STD  BASE
         RTS

HEXW:    LDD  #16
         STD  BASE
         RTS

BINARYW: LDD  #2
         STD  BASE
         RTS

; ============================================================
; SECTION 22: OUTPUT FORMATTING (CR/SPACE/SPACES)
; ============================================================
CRW:     LDD   #13
         PSHU  D
         JSR   EMIT
         LDD   #10
         PSHU  D
         JSR   EMIT
         RTS

SPACEW:  LDD   #32
         PSHU  D
         JSR   EMIT
         RTS

SPACESW: PULU  D
         STD   SHCNT2
SPLOOP:  LDD   SHCNT2
         BLE   SPDONE
         LDD   #32
         PSHU  D
         JSR   EMIT
         LDD   SHCNT2
         SUBD  #1
         STD   SHCNT2
         BRA   SPLOOP
SPDONE:  RTS

; ============================================================
; SECTION 23: COMMENT WORDS
; ============================================================
LPAREN:  LDD   #')'
         PSHU  D
         JSR   WORD
         RTS

BACKSLASH: LDD  SRCLEN
           STD  TOIN
           RTS

; ============================================================
; SECTION 24: ENVIRONMENTAL QUERY / SOURCE / REFILL / EVALUATE
; ============================================================
SOURCEW: LDD   SRCADDR
         PSHU  D
         LDD   SRCLEN
         PSHU  D
         RTS

SOURCEID: LDD  SRCID
          PSHU D
          RTS

REFILLW: LDD   SRCID
         BEQ   RFTERM
         LDD   #FALSEV
         PSHU  D
         RTS
RFTERM:  JSR   QUERY
         LDD   #TRUEV
         PSHU  D
         RTS

EVALUATEW: LDD  SRCADDR
           STD  EVSAVEA
           LDD  SRCLEN
           STD  EVSAVEL
           LDD  SRCID
           STD  EVSAVEI
           LDD  TOIN
           STD  EVSAVET
           PULU D
           STD  SRCLEN
           PULU D
           STD  SRCADDR
           LDD  #-1
           STD  SRCID
           LDD  #0
           STD  TOIN
           JSR  INTERPRET
           LDD  EVSAVEA
           STD  SRCADDR
           LDD  EVSAVEL
           STD  SRCLEN
           LDD  EVSAVEI
           STD  SRCID
           LDD  EVSAVET
           STD  TOIN
           RTS

; ENVIRONMENT? - dispatcher complete; table has only the
; entries that could be derived without fabricating unfixed
; capacities (/HOLD, /PAD were explicitly left out - see the
; source conversation's ENVTABLE discussion). MAX-D/MAX-UD
; and WORDLISTS/FLOORED need dispatcher extensions not yet
; built (single-cell-only ENVFOUND path).
ENVQUERY: PULU D
          STD  ENVLEN
          PULU D
          STD  ENVADDR
          LDX  #ENVTABLE
ENVLOOP:  LDD  ,X
          CMPD #0
          BEQ  ENVNOTFOUND
          PSHU D
          LDD  2,X
          PSHU D
          LDD  ENVADDR
          PSHU D
          LDD  ENVLEN
          PSHU D
          JSR  COMPAREW
          PULU D
          CMPD #0
          BEQ  ENVFOUND
          LEAX 6,X
          BRA  ENVLOOP
ENVFOUND: LDD  4,X
          PSHU D
          LDD  #TRUEV
          PSHU D
          RTS
ENVNOTFOUND: LDD #FALSEV
             PSHU D
             RTS

ENVTABLE:
         FDB   EN1,EN1L,31
         FDB   EN2,EN2L,32767
         FDB   EN3,EN3L,65535
         FDB   EN6,EN6L,8
         FDB   0
EN1:     FCC   "/COUNTED-STRING"
EN1L     EQU   *-EN1
EN2:     FCC   "MAX-N"
EN2L     EQU   *-EN2
EN3:     FCC   "MAX-U"
EN3L     EQU   *-EN3
EN6:     FCC   "ADDRESS-UNIT-BITS"
EN6L     EQU   *-EN6

; ============================================================
; SECTION 25: TOOLS WORD SET (.S / WORDS / DUMP)
; ============================================================
DOTS:    TFR   U,D
         STD   DSPTMP
DSLOOP:  LDD   DSPTMP
         CMPD  #SP0
         BEQ   DSDONE
         LDX   DSPTMP
         LDD   ,X
         PSHU  D
         JSR   DOT
         LDD   DSPTMP
         ADDD  #2
         STD   DSPTMP
         BRA   DSLOOP
DSDONE:  RTS

WORDSW:  LDD   LATEST
         STD   WWALK
WWLOOP:  LDD   WWALK
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
         JSR   TYPE
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
WWDONE:  JSR   CRW
         RTS

HEXDIGIT: PULU D
          CMPD #10
          BLO  HDDIGIT
          ADDD #'A'-10
          BRA  HDEMIT
HDDIGIT:  ADDD #'0'
HDEMIT:   PSHU D
          JSR  EMIT
          RTS

HEXBYTE: PULU  D
         STB   MSCR
         LDB   MSCR+1
         LSRB
         LSRB
         LSRB
         LSRB
         CLRA
         PSHU  D
         JSR   HEXDIGIT
         LDB   MSCR+1
         ANDB  #$0F
         CLRA
         PSHU  D
         JSR   HEXDIGIT
         RTS

; DUMP - includes the partial-final-line ASCII fix
DUMPW:   PULU  D
         STD   DUMPCNT
         PULU  D
         STD   DUMPADDR
DULINE:  LDD   DUMPCNT
         LBEQ  DUDONE          ; was BEQ - out of short-branch range
         LDD   DUMPADDR
         STD   HEXBUF
         CLR   DUMPCOL
         LDA   #16
         STA   DUVALID
DUHEX:   LDB   DUMPCOL
         CMPB  #16
         BEQ   DUASCII
         LDD   DUMPCNT
         BNE   DUHEXBYTE
         LDA   DUMPCOL
         STA   DUVALID
         BRA   DUHEXPAD
DUHEXBYTE: LDX  DUMPADDR
           LDB  ,X
           CLRA
           PSHU D
           JSR  HEXBYTE
           LDD  #32
           PSHU D
           JSR  EMIT
           LDX  DUMPADDR
           LEAX 1,X
           STX  DUMPADDR
           LDD  DUMPCNT
           SUBD #1
           STD  DUMPCNT
           INC  DUMPCOL
           BRA  DUHEX
DUHEXPAD: LDD  #32
          PSHU D
          JSR  EMIT
          PSHU D
          JSR  EMIT
          PSHU D
          JSR  EMIT
          INC  DUMPCOL
          LDB  DUMPCOL
          CMPB #16
          BNE  DUHEXPAD
          BRA  DUASCII
DUASCII: LDD  #32
         PSHU D
         JSR  EMIT
         CLR  DUMPCOL
DUACHAR: LDB  DUMPCOL
         CMPB #16
         BEQ  DULEND
         CMPB DUVALID
         BHS  DUABLANK
         LDX  HEXBUF
         LDB  DUMPCOL
         CLRA
         LEAX D,X
         LDA  ,X
         CMPA #32
         BLO  DUDOT
         CMPA #127
         BHS  DUDOT
         BRA  DUPRINT
DUDOT:   LDA  #'.'
DUPRINT: TFR  A,B
         CLRA
         PSHU D
         JSR  EMIT
         INC  DUMPCOL
         BRA  DUACHAR
DUABLANK: LDD #32
          PSHU D
          JSR EMIT
          INC DUMPCOL
          BRA DUACHAR
DULEND:  JSR  CRW
         LDD  DUMPCNT
         LBNE DULINE           ; was BNE - out of short-branch range
DUDONE:  RTS

; ============================================================
; SECTION 26: ABORT / QUIT hand-built headers (findable at
; the prompt) - see source conversation for why HEADER/CREATE
; couldn't be used directly for these two.
; ============================================================
ABORTHDR: FCB   5
          FCC   "ABORT"
          FDB   H_FALSE        ; resolved - was placeholder 0, then H_DUMPW,
                                ; then H_DOESGT, then H_DUMPW again once
                                ; DOES> moved out of the chain's newest slot;
                                ; now H_FALSE, the chain's newest entry
          FDB   ABORT

QUITHDR:  FCB   4
          FCC   "QUIT"
          FDB   ABORTHDR
          FDB   QUIT

BASELATEST EQU  QUITHDR  ; the ROM dictionary's true head - referenced by
                          ; COLD to initialize LATEST, and asserted in the
                          ; SECTION 27 header comment below, but never
                          ; actually defined anywhere until now: an
                          ; undefined-symbol bug, not a placeholder

; ------------------------------------------------------------
; TRUE / FALSE - CONSTANT TRUE -1 / CONSTANT FALSE 0. The first
; CONSTANT-pattern ROM-resident words in this system: every
; other ROM word's CFA is a plain code label (a real routine),
; but a CONSTANT's CFA is the DODOES trampoline pattern (JSR
; DODOES + FDB ATSIGN + FDB <value-cell-address>), matching
; exactly what interactive CONSTANT compiles at runtime - the
; only difference is the value-cell address is a fixed, known-
; at-assemble-time label here (TRUEVAL/FALSEVAL) rather than a
; CODEHERE snapshot captured dynamically. DODOES pushes the
; value stored at the PFA field (the address in TRUEVAL/
; FALSEVAL); ATSIGN then fetches through that address, yielding
; the actual -1 / 0 - the same indirection interactive CONSTANT
; relies on, just with fixed addresses instead of a runtime one.
; ------------------------------------------------------------
TRUEBODY:  JSR   DODOES
           FDB   ATSIGN
           FDB   TRUEVAL
TRUEVAL:   FDB   -1

FALSEBODY: JSR   DODOES
           FDB   ATSIGN
           FDB   FALSEVAL
FALSEVAL:  FDB   0

; Verify no collision with init code,
; value should match ORG INITCODE.
BASECODEEND  EQU   *
BASECODESIZE EQU   BASECODEEND-BASECODE

; ============================================================
; SECTION 27: FORTH DICTIONARY (ROM base dictionary headers)
; Every primitive word in the Glossary gets a real header here,
; chained via LINK, living in BASEDICT ($D85D-$E011, an exact fit
; for this dictionary's 1973 bytes - was $E000-$E7FF). CFA points
; directly at each primitive's own code label for almost every
; entry - these are raw code entries, not DODOES trampolines, so
; CFA = the label itself. The two exceptions are TRUE and FALSE
; (added in a later pass, chain's newest entries): their CFA is
; the DODOES-trampoline pattern instead, matching what CONSTANT
; would compile interactively - see TRUEBODY/FALSEBODY, section
; 26, for why and how.
;
; DOES> is included (H_DOESGT) - added in a follow-up pass after
; the original 214-entry generation flagged it as missing, then
; moved again so it sits immediately after CREATE in the chain
; (H_CREATE -> H_DOESGT -> H_VARIABLE) rather than at the chain's
; newest end, since the two words are tightly coupled and read
; better adjacent. SETDOES (the runtime it compiles a call to)
; lives beside DODOES/DOESRT0; DOESGT is DOES>'s code label,
; since a literal ">" is not valid in a 6809 assembler label.
;
; ABORT and QUIT already have hand-built headers (ABORTHDR/
; QUITHDR, section 26) and are NOT duplicated here. This chain
; is spliced in below them: QUITHDR -> ABORTHDR -> (newest entry
; below) -> ... -> (oldest entry) -> 0. BASELATEST remains QUITHDR.
;
; ABORTHDR's LINK field, a placeholder 0 since it was first built,
; is resolved here: it now points to this chain's newest entry.
;
; Names containing a literal double-quote (S", .", ABORT") have
; that character split into a standalone FCB $22 rather than
; escaped inside FCC - see emit_name's comment for why.
; ============================================================

         ORG   BASEDICT       ; BASEDICT is $E000

H_KEY:
         FCB   $03
         FCC   "KEY"
         FDB   0
         FDB   KEY
H_KEYQ:
         FCB   $04
         FCC   "KEY?"
         FDB   H_KEY
         FDB   KEYQ
H_EMIT:
         FCB   $04
         FCC   "EMIT"
         FDB   H_KEYQ
         FDB   EMIT
H_ACCEPT:
         FCB   $06
         FCC   "ACCEPT"
         FDB   H_EMIT
         FDB   ACCEPT
H_EXPECTW:
         FCB   $06
         FCC   "EXPECT"
         FDB   H_ACCEPT
         FDB   EXPECTW
H_QUERY:
         FCB   $05
         FCC   "QUERY"
         FDB   H_EXPECTW
         FDB   QUERY
H_TYPE:
         FCB   $04
         FCC   "TYPE"
         FDB   H_QUERY
         FDB   TYPE
H_CRW:
         FCB   $02
         FCC   "CR"
         FDB   H_TYPE
         FDB   CRW
H_SPACEW:
         FCB   $05
         FCC   "SPACE"
         FDB   H_CRW
         FDB   SPACEW
H_SPACESW:
         FCB   $06
         FCC   "SPACES"
         FDB   H_SPACEW
         FDB   SPACESW
H_DUP:
         FCB   $03
         FCC   "DUP"
         FDB   H_SPACESW
         FDB   DUP
H_DROP:
         FCB   $04
         FCC   "DROP"
         FDB   H_DUP
         FDB   DROP
H_SWAP:
         FCB   $04
         FCC   "SWAP"
         FDB   H_DROP
         FDB   SWAP
H_OVER:
         FCB   $04
         FCC   "OVER"
         FDB   H_SWAP
         FDB   OVER
H_ROT:
         FCB   $03
         FCC   "ROT"
         FDB   H_OVER
         FDB   ROT
H_QDUP:
         FCB   $04
         FCC   "?DUP"
         FDB   H_ROT
         FDB   QDUP
H_DEPTH:
         FCB   $05
         FCC   "DEPTH"
         FDB   H_QDUP
         FDB   DEPTH
H_DDUP:
         FCB   $04
         FCC   "2DUP"
         FDB   H_DEPTH
         FDB   DDUP
H_DDROP:
         FCB   $05
         FCC   "2DROP"
         FDB   H_DDUP
         FDB   DDROP
H_DSWAP:
         FCB   $05
         FCC   "2SWAP"
         FDB   H_DDROP
         FDB   DSWAP
H_DOVER:
         FCB   $05
         FCC   "2OVER"
         FDB   H_DSWAP
         FDB   DOVER
H_NIP:
         FCB   $03
         FCC   "NIP"
         FDB   H_DOVER
         FDB   NIP
H_TUCK:
         FCB   $04
         FCC   "TUCK"
         FDB   H_NIP
         FDB   TUCK
H_PICK:
         FCB   $04
         FCC   "PICK"
         FDB   H_TUCK
         FDB   PICK
H_ROLL:
         FCB   $04
         FCC   "ROLL"
         FDB   H_PICK
         FDB   ROLL
H_DROT:
         FCB   $04
         FCC   "2ROT"
         FDB   H_ROLL
         FDB   DROT
H_TOR:
         FCB   $02
         FCC   ">R"
         FDB   H_DROT
         FDB   TOR
H_FROMR:
         FCB   $02
         FCC   "R>"
         FDB   H_TOR
         FDB   FROMR
H_RFETCH:
         FCB   $02
         FCC   "R@"
         FDB   H_FROMR
         FDB   RFETCH
H_TWOTOR:
         FCB   $03
         FCC   "2>R"
         FDB   H_RFETCH
         FDB   TWOTOR
H_TWOFROMR:
         FCB   $03
         FCC   "2R>"
         FDB   H_TWOTOR
         FDB   TWOFROMR
H_TWORFETCH:
         FCB   $03
         FCC   "2R@"
         FDB   H_TWOFROMR
         FDB   TWORFETCH
H_PLUS:
         FCB   $01
         FCC   "+"
         FDB   H_TWORFETCH
         FDB   PLUS
H_MINUS:
         FCB   $01
         FCC   "-"
         FDB   H_PLUS
         FDB   MINUS
H_STAR:
         FCB   $01
         FCC   "*"
         FDB   H_MINUS
         FDB   STAR
H_SLASH:
         FCB   $01
         FCC   "/"
         FDB   H_STAR
         FDB   SLASH
H_MODW:
         FCB   $03
         FCC   "MOD"
         FDB   H_SLASH
         FDB   MODW
H_SLASHMOD:
         FCB   $04
         FCC   "/MOD"
         FDB   H_MODW
         FDB   SLASHMOD
H_NEGATE:
         FCB   $06
         FCC   "NEGATE"
         FDB   H_SLASHMOD
         FDB   NEGATE
H_ABSW:
         FCB   $03
         FCC   "ABS"
         FDB   H_NEGATE
         FDB   ABSW
H_MIN:
         FCB   $03
         FCC   "MIN"
         FDB   H_ABSW
         FDB   MIN
H_MAX:
         FCB   $03
         FCC   "MAX"
         FDB   H_MIN
         FDB   MAX
H_ONEPLUS:
         FCB   $02
         FCC   "1+"
         FDB   H_MAX
         FDB   ONEPLUS
H_ONEMINUS:
         FCB   $02
         FCC   "1-"
         FDB   H_ONEPLUS
         FDB   ONEMINUS
H_TWOPLUS:
         FCB   $02
         FCC   "2+"
         FDB   H_ONEMINUS
         FDB   TWOPLUS
H_TWOSTAR:
         FCB   $02
         FCC   "2*"
         FDB   H_TWOPLUS
         FDB   TWOSTAR
H_TWOSLASH:
         FCB   $02
         FCC   "2/"
         FDB   H_TWOSTAR
         FDB   TWOSLASH
H_STARSLASH:
         FCB   $02
         FCC   "*/"
         FDB   H_TWOSLASH
         FDB   STARSLASH
H_STARSLASHMOD:
         FCB   $05
         FCC   "*/MOD"
         FDB   H_STARSLASH
         FDB   STARSLASHMOD
H_UMSTAR:
         FCB   $03
         FCC   "UM*"
         FDB   H_STARSLASHMOD
         FDB   UMSTAR
H_UMSLASHMOD:
         FCB   $06
         FCC   "UM/MOD"
         FDB   H_UMSTAR
         FDB   UMSLASHMOD
H_MSTAR:
         FCB   $02
         FCC   "M*"
         FDB   H_UMSLASHMOD
         FDB   MSTAR
H_FMSLASHMOD:
         FCB   $06
         FCC   "FM/MOD"
         FDB   H_MSTAR
         FDB   FMSLASHMOD
H_SMSLASHREM:
         FCB   $06
         FCC   "SM/REM"
         FDB   H_FMSLASHMOD
         FDB   SMSLASHREM
H_DPLUS:
         FCB   $02
         FCC   "D+"
         FDB   H_SMSLASHREM
         FDB   DPLUS
H_DMINUS:
         FCB   $02
         FCC   "D-"
         FDB   H_DPLUS
         FDB   DMINUS
H_DNEGATEW:
         FCB   $07
         FCC   "DNEGATE"
         FDB   H_DMINUS
         FDB   DNEGATEW
H_DABSW:
         FCB   $04
         FCC   "DABS"
         FDB   H_DNEGATEW
         FDB   DABSW
H_MPLUS:
         FCB   $02
         FCC   "M+"
         FDB   H_DABSW
         FDB   MPLUS
H_STOD:
         FCB   $03
         FCC   "S>D"
         FDB   H_MPLUS
         FDB   STOD
H_DTOS:
         FCB   $03
         FCC   "D>S"
         FDB   H_STOD
         FDB   DTOS
H_DMAXW:
         FCB   $04
         FCC   "DMAX"
         FDB   H_DTOS
         FDB   DMAXW
H_DMINW:
         FCB   $04
         FCC   "DMIN"
         FDB   H_DMAXW
         FDB   DMINW
H_ANDW:
         FCB   $03
         FCC   "AND"
         FDB   H_DMINW
         FDB   ANDW
H_ORW:
         FCB   $02
         FCC   "OR"
         FDB   H_ANDW
         FDB   ORW
H_XORW:
         FCB   $03
         FCC   "XOR"
         FDB   H_ORW
         FDB   XORW
H_INVERT:
         FCB   $06
         FCC   "INVERT"
         FDB   H_XORW
         FDB   INVERT
H_LSHIFT:
         FCB   $06
         FCC   "LSHIFT"
         FDB   H_INVERT
         FDB   LSHIFT
H_RSHIFT:
         FCB   $06
         FCC   "RSHIFT"
         FDB   H_LSHIFT
         FDB   RSHIFT
H_CELLSW:
         FCB   $05
         FCC   "CELLS"
         FDB   H_RSHIFT
         FDB   CELLSW
H_CELLPLUS:
         FCB   $05
         FCC   "CELL+"
         FDB   H_CELLSW
         FDB   CELLPLUS
H_CHARSW:
         FCB   $05
         FCC   "CHARS"
         FDB   H_CELLPLUS
         FDB   CHARSW
H_CHARPLUS:
         FCB   $05
         FCC   "CHAR+"
         FDB   H_CHARSW
         FDB   CHARPLUS
H_ALIGNW:
         FCB   $05
         FCC   "ALIGN"
         FDB   H_CHARPLUS
         FDB   ALIGNW
H_ALIGNEDW:
         FCB   $07
         FCC   "ALIGNED"
         FDB   H_ALIGNW
         FDB   ALIGNEDW
H_EQUALW:
         FCB   $01
         FCC   "="
         FDB   H_ALIGNEDW
         FDB   EQUALW
H_LESSW:
         FCB   $01
         FCC   "<"
         FDB   H_EQUALW
         FDB   LESSW
H_GREATERW:
         FCB   $01
         FCC   ">"
         FDB   H_LESSW
         FDB   GREATERW
H_ZEROEQ:
         FCB   $02
         FCC   "0="
         FDB   H_GREATERW
         FDB   ZEROEQ
H_ZEROLT:
         FCB   $02
         FCC   "0<"
         FDB   H_ZEROEQ
         FDB   ZEROLT
H_ULESSW:
         FCB   $02
         FCC   "U<"
         FDB   H_ZEROLT
         FDB   ULESSW
H_NOTEQUAL:
         FCB   $02
         FCC   "<>"
         FDB   H_ULESSW
         FDB   NOTEQUAL
H_ZERONE:
         FCB   $03
         FCC   "0<>"
         FDB   H_NOTEQUAL
         FDB   ZERONE
H_ZEROGT:
         FCB   $02
         FCC   "0>"
         FDB   H_ZERONE
         FDB   ZEROGT
H_UGREATER:
         FCB   $02
         FCC   "U>"
         FDB   H_ZEROGT
         FDB   UGREATER
H_WITHINW:
         FCB   $06
         FCC   "WITHIN"
         FDB   H_UGREATER
         FDB   WITHINW
H_DEQUAL:
         FCB   $02
         FCC   "D="
         FDB   H_WITHINW
         FDB   DEQUAL
H_DLESSW:
         FCB   $02
         FCC   "D<"
         FDB   H_DEQUAL
         FDB   DLESSW
H_DULESSW:
         FCB   $03
         FCC   "DU<"
         FDB   H_DLESSW
         FDB   DULESSW
H_IF:
         FCB   $82
         FCC   "IF"
         FDB   H_DULESSW
         FDB   IF
H_THEN:
         FCB   $84
         FCC   "THEN"
         FDB   H_IF
         FDB   THEN
H_ELSE:
         FCB   $84
         FCC   "ELSE"
         FDB   H_THEN
         FDB   ELSE
H_BEGIN:
         FCB   $85
         FCC   "BEGIN"
         FDB   H_ELSE
         FDB   BEGIN
H_UNTIL:
         FCB   $85
         FCC   "UNTIL"
         FDB   H_BEGIN
         FDB   UNTIL
H_AGAIN:
         FCB   $85
         FCC   "AGAIN"
         FDB   H_UNTIL
         FDB   AGAIN
H_WHILE:
         FCB   $85
         FCC   "WHILE"
         FDB   H_AGAIN
         FDB   WHILE
H_REPEAT:
         FCB   $86
         FCC   "REPEAT"
         FDB   H_WHILE
         FDB   REPEAT
H_RECURSE:
         FCB   $87
         FCC   "RECURSE"
         FDB   H_REPEAT
         FDB   RECURSE
H_DO:
         FCB   $82
         FCC   "DO"
         FDB   H_RECURSE
         FDB   DO
H_QDO:
         FCB   $83
         FCC   "?DO"
         FDB   H_DO
         FDB   QDO
H_LOOP:
         FCB   $84
         FCC   "LOOP"
         FDB   H_QDO
         FDB   LOOP
H_PLUSLOOP:
         FCB   $85
         FCC   "+LOOP"
         FDB   H_LOOP
         FDB   PLUSLOOP
H_IWORD:
         FCB   $01
         FCC   "I"
         FDB   H_PLUSLOOP
         FDB   IWORD
H_JWORD:
         FCB   $01
         FCC   "J"
         FDB   H_IWORD
         FDB   JWORD
H_LEAVE:
         FCB   $05
         FCC   "LEAVE"
         FDB   H_JWORD
         FDB   LEAVE
H_UNLOOP:
         FCB   $06
         FCC   "UNLOOP"
         FDB   H_LEAVE
         FDB   UNLOOP
H_EXIT:
         FCB   $84
         FCC   "EXIT"
         FDB   H_UNLOOP
         FDB   EXIT
H_CASEW:
         FCB   $84
         FCC   "CASE"
         FDB   H_EXIT
         FDB   CASEW
H_OF:
         FCB   $82
         FCC   "OF"
         FDB   H_CASEW
         FDB   OF
H_ENDOF:
         FCB   $85
         FCC   "ENDOF"
         FDB   H_OF
         FDB   ENDOF
H_ENDCASE:
         FCB   $87
         FCC   "ENDCASE"
         FDB   H_ENDOF
         FDB   ENDCASE
H_COLON:
         FCB   $01
         FCC   ":"
         FDB   H_ENDCASE
         FDB   COLON
H_SEMI:
         FCB   $81
         FCC   ";"
         FDB   H_COLON
         FDB   SEMI
H_CREATE:
         FCB   $06
         FCC   "CREATE"
         FDB   H_SEMI
         FDB   CREATE
H_DOESGT:
         FCB   $85          ; $80 IMMEDIATE | 5 (length of "DOES>")
         FCC   "DOES>"
         FDB   H_CREATE
         FDB   DOESGT
H_VARIABLE:
         FCB   $08
         FCC   "VARIABLE"
         FDB   H_DOESGT
         FDB   VARIABLE
H_CONSTANT:
         FCB   $08
         FCC   "CONSTANT"
         FDB   H_VARIABLE
         FDB   CONSTANT
H_VALUEW:
         FCB   $05
         FCC   "VALUE"
         FDB   H_CONSTANT
         FDB   VALUEW
H_TOW:
         FCB   $82
         FCC   "TO"
         FDB   H_VALUEW
         FDB   TOW
H_TWOVARIABLE:
         FCB   $09
         FCC   "2VARIABLE"
         FDB   H_TOW
         FDB   TWOVARIABLE
H_TWOCONSTANT:
         FCB   $09
         FCC   "2CONSTANT"
         FDB   H_TWOVARIABLE
         FDB   TWOCONSTANT
H_BUFFERCOLON:
         FCB   $07
         FCC   "BUFFER:"
         FDB   H_TWOCONSTANT
         FDB   BUFFERCOLON
H_DEFERW:
         FCB   $05
         FCC   "DEFER"
         FDB   H_BUFFERCOLON
         FDB   DEFERW
H_DEFERFETCH:
         FCB   $06
         FCC   "DEFER@"
         FDB   H_DEFERW
         FDB   DEFERFETCH
H_DEFERSTORE:
         FCB   $06
         FCC   "DEFER!"
         FDB   H_DEFERFETCH
         FDB   DEFERSTORE
H_ISW:
         FCB   $82
         FCC   "IS"
         FDB   H_DEFERSTORE
         FDB   ISW
H_ACTIONOF:
         FCB   $89
         FCC   "ACTION-OF"
         FDB   H_ISW
         FDB   ACTIONOF
H_MARKERW:
         FCB   $06
         FCC   "MARKER"
         FDB   H_ACTIONOF
         FDB   MARKERW
H_IMMEDIATE:
         FCB   $09
         FCC   "IMMEDIATE"
         FDB   H_MARKERW
         FDB   IMMEDIATE
H_STATEW:
         FCB   $05
         FCC   "STATE"
         FDB   H_IMMEDIATE
         FDB   STATEW
H_LBRACKET:
         FCB   $81
         FCC   "["
         FDB   H_STATEW
         FDB   LBRACKET
H_RBRACKET:
         FCB   $81
         FCC   "]"
         FDB   H_LBRACKET
         FDB   RBRACKET
H_TICK:
         FCB   $01
         FCC   "'"
         FDB   H_RBRACKET
         FDB   TICK
H_COMPILECOMMA:
         FCB   $08
         FCC   "COMPILE,"
         FDB   H_TICK
         FDB   COMPILECOMMA
H_LITERALW:
         FCB   $87
         FCC   "LITERAL"
         FDB   H_COMPILECOMMA
         FDB   LITERALW
H_BRACKTICK:
         FCB   $83
         FCC   "[']"
         FDB   H_LITERALW
         FDB   BRACKTICK
H_POSTPONEW:
         FCB   $88
         FCC   "POSTPONE"
         FDB   H_BRACKTICK
         FDB   POSTPONEW
H_TOBODY:
         FCB   $05
         FCC   ">BODY"
         FDB   H_POSTPONEW
         FDB   TOBODY
H_EXECUTE:
         FCB   $07
         FCC   "EXECUTE"
         FDB   H_TOBODY
         FDB   EXECUTE
H_SLITERALW:
         FCB   $88
         FCC   "SLITERAL"
         FDB   H_EXECUTE
         FDB   SLITERALW
H_ABORTQUOTE:
         FCB   $86
         FCC   "ABORT"
         FCB   $22        ; '"' - split out of FCC, not escaped within it
         FDB   H_SLITERALW
         FDB   ABORTQUOTE
H_ATSIGN:
         FCB   $01
         FCC   "@"
         FDB   H_ABORTQUOTE
         FDB   ATSIGN
H_STOREW:
         FCB   $01
         FCC   "!"
         FDB   H_ATSIGN
         FDB   STOREW
H_CFETCH:
         FCB   $02
         FCC   "C@"
         FDB   H_STOREW
         FDB   CFETCH
H_CSTOREW:
         FCB   $02
         FCC   "C!"
         FDB   H_CFETCH
         FDB   CSTOREW
H_PLUSSTORE:
         FCB   $02
         FCC   "+!"
         FDB   H_CSTOREW
         FDB   PLUSSTORE
H_DFETCH:
         FCB   $02
         FCC   "2@"
         FDB   H_PLUSSTORE
         FDB   DFETCH
H_DSTORE:
         FCB   $02
         FCC   "2!"
         FDB   H_DFETCH
         FDB   DSTORE
H_COMMA:
         FCB   $01
         FCC   ","
         FDB   H_DSTORE
         FDB   COMMA
H_CCOMMA:
         FCB   $02
         FCC   "C,"
         FDB   H_COMMA
         FDB   CCOMMA
H_ALLOT:
         FCB   $05
         FCC   "ALLOT"
         FDB   H_CCOMMA
         FDB   ALLOT
H_HEREW:
         FCB   $04
         FCC   "HERE"
         FDB   H_ALLOT
         FDB   HEREW
H_VCOMMA:
         FCB   $02
         FCC   "V,"
         FDB   H_HEREW
         FDB   VCOMMA
H_VCCOMMA:
         FCB   $03
         FCC   "VC,"
         FDB   H_VCOMMA
         FDB   VCCOMMA
H_VALLOT:
         FCB   $06
         FCC   "VALLOT"
         FDB   H_VCCOMMA
         FDB   VALLOT
H_VHEREW:
         FCB   $05
         FCC   "VHERE"
         FDB   H_VALLOT
         FDB   VHEREW
H_PADW:
         FCB   $03
         FCC   "PAD"
         FDB   H_VHEREW
         FDB   PADW
H_UNUSEDW:
         FCB   $06
         FCC   "UNUSED"
         FDB   H_PADW
         FDB   UNUSEDW
H_VUNUSEDW:
         FCB   $07
         FCC   "VUNUSED"
         FDB   H_UNUSEDW
         FDB   VUNUSEDW
H_MOVEW:
         FCB   $04
         FCC   "MOVE"
         FDB   H_VUNUSEDW
         FDB   MOVEW
H_FILLW:
         FCB   $04
         FCC   "FILL"
         FDB   H_MOVEW
         FDB   FILLW
H_ERASEW:
         FCB   $05
         FCC   "ERASE"
         FDB   H_FILLW
         FDB   ERASEW
H_CMOVEW:
         FCB   $05
         FCC   "CMOVE"
         FDB   H_ERASEW
         FDB   CMOVEW
H_CMOVEGT:
         FCB   $06
         FCC   "CMOVE>"
         FDB   H_CMOVEW
         FDB   CMOVEGT
H_COUNT:
         FCB   $05
         FCC   "COUNT"
         FDB   H_CMOVEGT
         FDB   COUNT
H_WORD:
         FCB   $04
         FCC   "WORD"
         FDB   H_COUNT
         FDB   WORD
H_CHARW:
         FCB   $04
         FCC   "CHAR"
         FDB   H_WORD
         FDB   CHARW
H_BRACKCHAR:
         FCB   $86
         FCC   "[CHAR]"
         FDB   H_CHARW
         FDB   BRACKCHAR
H_PARSEW:
         FCB   $05
         FCC   "PARSE"
         FDB   H_BRACKCHAR
         FDB   PARSEW
H_PARSENAME:
         FCB   $0A
         FCC   "PARSE-NAME"
         FDB   H_PARSEW
         FDB   PARSENAME
H_SQUOTE:
         FCB   $82
         FCC   "S"
         FCB   $22        ; '"' - split out of FCC, not escaped within it
         FDB   H_PARSENAME
         FDB   SQUOTE
H_DOTQUOTE:
         FCB   $82
         FCC   "."
         FCB   $22        ; '"' - split out of FCC, not escaped within it
         FDB   H_SQUOTE
         FDB   DOTQUOTE
H_COMPAREW:
         FCB   $07
         FCC   "COMPARE"
         FDB   H_DOTQUOTE
         FDB   COMPAREW
H_SEARCHW:
         FCB   $06
         FCC   "SEARCH"
         FDB   H_COMPAREW
         FDB   SEARCHW
H_DASHTRAILING:
         FCB   $09
         FCC   "-TRAILING"
         FDB   H_SEARCHW
         FDB   DASHTRAILING
H_SLASHSTRING:
         FCB   $07
         FCC   "/STRING"
         FDB   H_DASHTRAILING
         FDB   SLASHSTRING
H_REPLACESW:
         FCB   $08
         FCC   "REPLACES"
         FDB   H_SLASHSTRING
         FDB   REPLACESW
H_SUBSTITUTEW:
         FCB   $0A
         FCC   "SUBSTITUTE"
         FDB   H_REPLACESW
         FDB   SUBSTITUTEW
H_SNAMEW:
         FCB   $05
         FCC   "SNAME"
         FDB   H_SUBSTITUTEW
         FDB   SNAMEW
H_UNESCAPEW:
         FCB   $08
         FCC   "UNESCAPE"
         FDB   H_SNAMEW
         FDB   UNESCAPEW
H_LTNUM:
         FCB   $02
         FCC   "<#"
         FDB   H_UNESCAPEW
         FDB   LTNUM
H_NUMSIGN:
         FCB   $01
         FCC   "#"
         FDB   H_LTNUM
         FDB   NUMSIGN
H_NUMSIGNS:
         FCB   $02
         FCC   "#S"
         FDB   H_NUMSIGN
         FDB   NUMSIGNS
H_NUMGT:
         FCB   $02
         FCC   "#>"
         FDB   H_NUMSIGNS
         FDB   NUMGT
H_HOLD:
         FCB   $04
         FCC   "HOLD"
         FDB   H_NUMGT
         FDB   HOLD
H_HOLDS:
         FCB   $05
         FCC   "HOLDS"
         FDB   H_HOLD
         FDB   HOLDS
H_SIGN:
         FCB   $04
         FCC   "SIGN"
         FDB   H_HOLDS
         FDB   SIGN
H_DOT:
         FCB   $01
         FCC   "."
         FDB   H_SIGN
         FDB   DOT
H_UDOT:
         FCB   $02
         FCC   "U."
         FDB   H_DOT
         FDB   UDOT
H_DOTR:
         FCB   $02
         FCC   ".R"
         FDB   H_UDOT
         FDB   DOTR
H_UDOTR:
         FCB   $03
         FCC   "U.R"
         FDB   H_DOTR
         FDB   UDOTR
H_QMARK:
         FCB   $01
         FCC   "?"
         FDB   H_UDOTR
         FDB   QMARK
H_DDOT:
         FCB   $02
         FCC   "D."
         FDB   H_QMARK
         FDB   DDOT
H_DDOTR:
         FCB   $03
         FCC   "D.R"
         FDB   H_DDOT
         FDB   DDOTR
H_BASEW:
         FCB   $04
         FCC   "BASE"
         FDB   H_DDOTR
         FDB   BASEW
H_DECIMAL:
         FCB   $07
         FCC   "DECIMAL"
         FDB   H_BASEW
         FDB   DECIMAL
H_HEXW:
         FCB   $03
         FCC   "HEX"
         FDB   H_DECIMAL
         FDB   HEXW
H_BINARYW:
         FCB   $06
         FCC   "BINARY"
         FDB   H_HEXW
         FDB   BINARYW
H_CATCH:
         FCB   $05
         FCC   "CATCH"
         FDB   H_BINARYW
         FDB   CATCH
H_THROW:
         FCB   $05
         FCC   "THROW"
         FDB   H_CATCH
         FDB   THROW
H_LPAREN:
         FCB   $81
         FCC   "("
         FDB   H_THROW
         FDB   LPAREN
H_BACKSLASH:
         FCB   $81
         FCC   "\"
         FDB   H_LPAREN
         FDB   BACKSLASH
H_ENVQUERY:
         FCB   $0C
         FCC   "ENVIRONMENT?"
         FDB   H_BACKSLASH
         FDB   ENVQUERY
H_SOURCEW:
         FCB   $06
         FCC   "SOURCE"
         FDB   H_ENVQUERY
         FDB   SOURCEW
H_SOURCEID:
         FCB   $09
         FCC   "SOURCE-ID"
         FDB   H_SOURCEW
         FDB   SOURCEID
H_REFILLW:
         FCB   $06
         FCC   "REFILL"
         FDB   H_SOURCEID
         FDB   REFILLW
H_EVALUATEW:
         FCB   $08
         FCC   "EVALUATE"
         FDB   H_REFILLW
         FDB   EVALUATEW
H_TIBW:
         FCB   $03
         FCC   "TIB"
         FDB   H_EVALUATEW
         FDB   TIBW
H_NTIBW:
         FCB   $04
         FCC   "#TIB"
         FDB   H_TIBW
         FDB   NTIBW
H_TOINW:
         FCB   $03
         FCC   ">IN"
         FDB   H_NTIBW
         FDB   TOINW
H_SPANW:
         FCB   $04
         FCC   "SPAN"
         FDB   H_TOINW
         FDB   SPANW
H_BLW:
         FCB   $02
         FCC   "BL"
         FDB   H_SPANW
         FDB   BLW
H_DOTS:
         FCB   $02
         FCC   ".S"
         FDB   H_BLW
         FDB   DOTS
H_WORDSW:
         FCB   $05
         FCC   "WORDS"
         FDB   H_DOTS
         FDB   WORDSW
H_DUMPW:
         FCB   $04
         FCC   "DUMP"
         FDB   H_WORDSW
         FDB   DUMPW

H_TRUE:
         FCB   $04
         FCC   "TRUE"
         FDB   H_DUMPW
         FDB   TRUEBODY

H_FALSE:
         FCB   $05
         FCC   "FALSE"
         FDB   H_TRUE
         FDB   FALSEBODY

DICTTOP  EQU   H_FALSE   ; newest entry in this base chain

; Verify no collision with base code.
; Value should match ORG BASECODE
BASEDICTEND  EQU   *
BASEDICTSIZE EQU   BASEDICTEND-BASEDICT

; ============================================================
; END OF CONSOLIDATED SOURCE
; ============================================================
