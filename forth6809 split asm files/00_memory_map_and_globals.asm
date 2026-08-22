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
; BASEDICT now holds 1992 bytes ($D83F-$E006) - grown from the
; earlier exact-fit 1973 bytes when H_ABORT/H_QUIT (formerly
; ABORTHDR/QUITHDR) and BASELATEST moved in from their own
; section so every dictionary header lives in one contiguous
; block. BASECODE's start ($DFF4) did not move to match, since
; it's a fixed address, not derived from BASEDICT's real size -
; this reintroduces a real overlap, 19 bytes ($DFF4-$E006),
; between the two. Not resolved here; see the open-items
; checklist. USROMSTRT/USROMEND, INOUT, RSTACK, DSTACK, CODETOP,
; APPCODE, APPDICT, and APPVARS remain mutually consistent
; otherwise, with no other overlaps anywhere in the current
; memory map. See the ROM Size Required section of the
; documentation and the open-items checklist for real content
; totals and remaining margin.
;
; This file preserves the code exactly as derived and verified
; turn-by-turn in the conversation, including the corrected
; versions of every bug that was caught and fixed in place.
; SUBSTITUTE is complete but deliberately scoped to a single
; registered name/value pair, not a full table (see REPLACES).
; ENVTABLE's /HOLD and /PAD entries were both added this session
; (HOLDMINSIZE and PADMINSIZE respectively - see the entries
; themselves for why each uses its own, conceptually correct
; constant rather than the numerically-equal PADOFFSET). The
; DPHERE/CODEHERE/VARHERE boundary checks remain explicitly
; incomplete/absent - see the inline notes preserved from that
; discussion, and the open-items checklist.
; ============================================================

; ------------------------------------------------------------
; MEMORY MAP
; ------------------------------------------------------------
ROMSTRT  EQU $C000     ; true physical start of the 16K EPROM's own
                        ; address decode (distinct from USROMSTRT
                        ; below, which excludes INOUT's 256-byte
                        ; shadow) - see the ROM Size Required section
                        ; of the documentation, and the ROM: padding
                        ; block right before SECTION 27
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
INITCODE EQU  $FFA9     ; was $FFA2 - shifted up 7 bytes to reduce the
                         ; overlap with BASECODE's nominal end ($FFB4)
                         ; from 19 bytes to 12 - improved, not resolved.
                         ; CORRECTED: INITCODE's real content is 71
                         ; bytes ($47), confirmed by an actual assembler
                         ; run - not the 78-byte manual estimate relied
                         ; on for several turns, which was wrong by 7
                         ; bytes. At $FFA9, real content now ends at
                         ; $FFEF, exactly one byte below VECTORS - a
                         ; genuine, assembler-confirmed exact fit, zero
                         ; gap, zero overlap. A prior turn claimed this
                         ; shift created a new 7-byte VECTORS overlap;
                         ; that was based on the incorrect 78-byte
                         ; estimate and was wrong - retracted here. The
                         ; BASECODE overlap (12 bytes against its
                         ; nominal budget) is separate and unaffected
                         ; by this correction; not resolved. See the
                         ; open-items checklist.
BASECODE EQU  $DEEA     ; was $DF6A ($DF8A, $DFCA, $DFDA, $DFEA, $E02A
                         ; before that) - shifted down $80 (128 bytes)
                         ; this time, a larger jump than the prior
                         ; $40 and $20 shifts, since both of those
                         ; still proved insufficient (confirmed by
                         ; trial and error against the real
                         ; assembler). The exact gap against BASEDICT
                         ; below and the exact overlap against
                         ; INITCODE above depend on each section's
                         ; real, current assembled size - not
                         ; recomputed here without a real assembler
                         ; run; confirm on assembly/MAME rather than
                         ; trust a static estimate. See the open-items
                         ; checklist.
BASEDICT EQU  $D6FF     ; was $D77F ($D79F, $D7DF, $D7EF, $D7FF, $D83F
                         ; before that) - shifted down $80 (128 bytes)
                         ; this time, same reason as BASECODE above.
                         ; Not recomputed against real, current
                         ; assembled sizes here - confirm on
                         ; assembly/MAME. See the open-items checklist.
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

; ANS transient-region minimums (forth-standard.org/standard/usage,
; section 3.3.3.6 "Other transient regions"), verified against this
; system's actual layout and used to replace the bare "84" that used
; to sit directly inside PADW with a named, documented constant:
;   PADMINSIZE  - PAD's own scratch region, size in characters. WORD
;                 originally used a separate, fixed WORDBUF that
;                 happened to meet its own 33-character minimum
;                 exactly (WORDBUF's span up to where SIBUF used to
;                 begin was precisely 33 bytes, confirmed by address
;                 subtraction) - but WORD has since been redesigned
;                 (see below, and WORD itself in the Header/Compiling
;                 section) to use this same CODEHERE-to-PAD gap
;                 instead, matching the traditional fig-Forth layout,
;                 so WORDBUF itself is retired along with SIBUF.
;   HOLDMINSIZE - pictured numeric output buffer, size in characters,
;                 (2 * n) + 2 where n = bits per cell (16 here) = 34.
;                 LTNUM ("<#") anchors HLD to PADW's own return value
;                 and HOLD decrements before storing, so this buffer
;                 grows downward from PAD into the CODEHERE-to-PAD
;                 gap, not into PAD's own region above it - confirmed
;                 by tracing LTNUM/HOLD. The gap must be at least
;                 HOLDMINSIZE wide for this to fit.
; PADOFFSET (below) satisfies both: it equals PADMINSIZE, which is
; itself well above HOLDMINSIZE (84 vs 34, 50 bytes of margin) - kept
; as a single, larger-than-either-strict-minimum offset rather than
; two separately-tuned numbers, matching "larger than minimum is
; satisfactory" for a small system.
PADMINSIZE  EQU 84
WORDMINSIZE EQU 33
HOLDMINSIZE EQU 34
PADOFFSET   EQU PADMINSIZE  ; CODEHERE-to-PAD gap; also governs how
                            ; much of PAD's own upward-growing region
                            ; (now used by both the user and, per this
                            ; change, interpreted-mode S" text) is
                            ; guaranteed available before something
                            ; else might claim it
WORDMAXCHARS EQU PADOFFSET-HOLDMINSIZE-1-3  ; max characters WORD can
                            ; scan when using the CODEHERE-to-PAD gap
                            ; (see WORD, below) - reserves HOLDMINSIZE
                            ; bytes at the PAD end for the pictured
                            ; numeric output buffer (which grows
                            ; downward from PAD into this same gap),
                            ; using the remaining space at the
                            ; CODEHERE end, less 1 byte for WORD's own
                            ; leading count byte, less a further 3
                            ; bytes for the worst case: S"/."/ABORT"
                            ; all reserve 3 bytes ahead of CODEHERE
                            ; before calling WORD (see SQUOTE/
                            ; DOTQUOTE/AQSTOK), so their text lands 3
                            ; bytes further into this same gap than
                            ; plain WORD-parsing (e.g. a dictionary
                            ; name for FIND) does. Sized for that
                            ; worst case uniformly, rather than giving
                            ; different callers different effective
                            ; limits - simpler and safer than trying
                            ; to track which caller needs which cap.
                            ; 84-34-1-3 = 46.

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
; SIBUF EQU $01FB retired - was interpreted-mode S"'s fixed, dedicated
; 32-byte scratch buffer; S" now writes into PAD instead (see SQINTERP,
; String Words section), which is both larger and correctly per-call
; rather than a single buffer shared by every S" call in a session.
; The $01FB-$021A range it used to occupy is left unclaimed rather
; than reassigned - APPVARS below still starts at its own, unchanged
; address ($021B) - to avoid any risk to the rest of this carefully-
; verified memory map for the sake of reclaiming 32 bytes on a system
; with headroom to spare; reclaiming it would need APPVARS to move,
; a separate, larger change not undertaken here.
; WORDBUF EQU $01DA also retired, for the same reason as SIBUF above -
; WORD now uses the CODEHERE-to-PAD gap directly (see WORD in the
; Header/Compiling section, and WORDMAXCHARS above) rather than a
; fixed, separately-allocated buffer capped at 31 characters. The
; $01DA-$01FA range it used to occupy is left unclaimed, same
; reasoning as SIBUF's retirement above.
TIBBUF   EQU  $018A     ; was $0284
TIBBUFL  EQU  80
SERBUF   EQU  $0106     ; was $0200 - USER0/USER1 removed entirely (see
                         ; below); the 4 buffers (SERBUF's 4-byte index
                         ; block, INBUF, OUTBUF, TIBBUF) still sit
                         ; contiguously right after MVSCRATCH, with no
                         ; gap - WORDBUF and SIBUF, which used to sit
                         ; right after TIBBUF and WORDBUF respectively
                         ; (closing what was once an 11-byte gap,
                         ; $02F5-$02FF, in an earlier address scheme),
                         ; are now both retired (see above) rather than
                         ; part of this contiguous run
INHEAD   EQU  SERBUF
INTAIL   EQU  SERBUF+1
OUTHEAD  EQU  SERBUF+2
OUTTAIL  EQU  SERBUF+3
INBUFSZ  EQU  64
OUTBUFSZ EQU  64
INBUF    EQU  SERBUF+4
OUTBUF   EQU  SERBUF+4+INBUFSZ
GLOBALS  EQU  $0000

SP0      EQU  DSTACK+1
RP0      EQU  RSTACK+1

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
; ------------------------------------------------------------
SERIALPOLL EQU 1

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
CR_POLL  EQU  $15     ; bit7=0 (RX interrupt disabled), bits6-5=00 (RTS
                       ; low, TX interrupt disabled) - CR_RXON ($95) with
                       ; only the RX-interrupt-enable bit cleared. Used
                       ; only when SERIALPOLL=1; RTS stays permanently
                       ; low (asserted), since polling mode has no ring
                       ; buffer to overflow and so needs no flow control
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
; FILLCNT/FILLADDR (formerly aliasing MVCNT/MVDST) were removed once
; genuinely unused - FILLW now keeps its count and address directly
; in Y/X rather than round-tripping through memory each iteration.
; ------------------------------------------------------------
         ORG   $0100
MVCNT      RMB   2
MVDST      RMB   2
MVSRC      RMB   2
HSLEN    EQU  MVCNT
HSADDR   EQU  MVDST
MRESULT  EQU  MVSRC
FILLCHR  EQU  MVSRC

; Provide padding, to ensure the correct ROM & .bin file size (and
; opcode offsets) for the MAME emulation and flash memory burn.
         ORG USROMSTRT

; ============================================================
; UNIT TEST FRAMEWORK
;
; Self-checking assembly-level tests for this ROM's own
; primitives, gated by UNITTESTS below and run once at cold
; boot, right after INITSERIAL and before COLD (so U/S are
; already valid - COLDSTRT sets them at its very start - but
; nothing else has been initialized yet: APPVARS/DPHERE/
; CODEHERE/LATEST/BASE all still hold whatever COLD is about to
; set them to). Lives here, in previously-unused ROM space right
; after INOUT's shadow, since this was pure FILL padding before
; this existed - UNITTESTS=1 removes it entirely and this block
; reverts to exactly that padding, computed automatically below
; via the ROM label rather than a fixed byte count, so it's
; correct either way without needing to be hand-adjusted.
;
; Each test is independent by construction: it saves the data
; stack pointer (U) before touching anything, and unconditionally
; restores it at the end regardless of pass or fail - so one
; test's assertions failing can never leave stack residue for the
; next test to inherit. Test scratch variables live in the very
; start of APPVARS - safe only because tests run strictly before
; COLD initializes VARHERE to that same address; COLD immediately
; and correctly re-purposes that space afterward.
;
; Reporting: each test's name (a counted string, matching how
; BADWORD itself prints a failing word) is printed via COUNT+TYPE,
; followed by " OK" or " FAIL", followed by a CR - all via
; TSTREPORT, shared by every test rather than duplicated in each.
; ============================================================
UNITTESTS EQU 1   ; was 0 (included) - set to 1 (excluded) per explicit
                  ; request: unit tests don't work yet and resolution
                  ; has been postponed. 0 = included (matches this
                  ; file's established IFEQ convention, e.g.
                  ; SERIALPOLL); 1 = excluded entirely, reverting to
                  ; plain FILL padding.

         IFEQ  UNITTESTS  ; >>>>>>>>>>

TSTU0    EQU   APPVARS       ; saved U, before a test touches it
TSTUB4   EQU   APPVARS+2     ; U immediately before the op under test
TSTUAF   EQU   APPVARS+4     ; U immediately after the op under test
TSTFLAG  EQU   APPVARS+6     ; scratch for TSTREPORT's pass/fail arg

TSTGUARD EQU   $3C7A         ; sentinel value, pushed below the value
                              ; under test, to prove an operation
                              ; doesn't disturb what's beneath it
TSTVAL1  EQU   $59E1         ; the value under test itself - neither
                              ; constant is 0, 1, or -1, so a test
                              ; that only appears to pass due to a
                              ; trivial/special-cased value would be
                              ; caught rather than masked

; ------------------------------------------------------------
; TSTREPORT - ( testname-caddr passflag -- ) shared by every
; test. Prints the test's name (via COUNT+TYPE), then " OK" or
; " FAIL" depending on passflag (TRUEV = pass, FALSEV = fail),
; then a CR, readying the terminal for the next test's line.
; ------------------------------------------------------------
TSTREPORT: PULU  D
           STD   TSTFLAG
           JSR   COUNT
           JSR   TYPE
           LDD   TSTFLAG
           BEQ   TSTFAILR
           LDD   #TSTOKMSG
           PSHU  D
           LDD   #TSTOKMSGL
           PSHU  D
           BRA   TSTPRINT
TSTFAILR:  LDD   #TSTFAILMSG
           PSHU  D
           LDD   #TSTFAILMSGL
           PSHU  D
TSTPRINT:  JSR   TYPE
           JSR   CRW
           RTS

TSTOKMSG:    FCC " OK"
TSTOKMSGL    EQU  *-TSTOKMSG
TSTFAILMSG:  FCC " FAIL"
TSTFAILMSGL  EQU  *-TSTFAILMSG

; ------------------------------------------------------------
; TSTRUNNER - calls each test group in turn. Add new groups
; here as they're written.
; ------------------------------------------------------------
TSTRUNNER: JSR   TSTSTACK
           RTS

; ------------------------------------------------------------
; TSTSTACK - data stack operation tests. Add new tests here as
; they're written.
; ------------------------------------------------------------
TSTSTACK:  JSR   TSTDUP
           RTS

; ------------------------------------------------------------
; TSTDUP - unit test for DUP ( x -- x x ). Verifies both the
; stack's contents (the duplicate and the original both equal
; the pushed test value, and the guard beneath is undisturbed)
; and the data stack pointer's movement (exactly one cell, 2
; bytes - DUP's own net effect, not conflated with the two
; pushes that set the test up).
; ------------------------------------------------------------
TSTDUP:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   DUP

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
TDFAIL:    LDD   #FALSEV
TDDONE:    LDX   #TSTDUPNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDUPNAME: FCB  6
            FCC  "TSTDUP"

         ENDC  ; <<<<<<<<<<

ROM:
         FILL $FF,BASEDICT-ROM

