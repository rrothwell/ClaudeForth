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
INITCODE EQU  $FFA6     ; was $FFA9 - shifted down 3 bytes, per
                         ; explicit request, to make room for the
                         ; UNITTESTS call site's own fix (below):
                         ; that site now always emits exactly 3 bytes
                         ; (either the real JSR TSTRUNNER, or 3 NOPs
                         ; as a placeholder when the test framework is
                         ; excluded), so COLDSTRT's total size no
                         ; longer depends on UNITTESTS at all -
                         ; previously it did (JSR TSTRUNNER only
                         ; existed when included, with nothing emitted
                         ; when excluded - using this file's original,
                         ; since-reversed UNITTESTS convention at the
                         ; time this fix was made), meaning INITCODE's
                         ; fixed position here could be correct for
                         ; one setting and wrong for the other, risking
                         ; an overflow into VECTORS when tests were
                         ; compiled in. Prior
                         ; history: was $FFA2 - shifted up 7 bytes to
                         ; reduce the overlap with BASECODE's nominal
                         ; end ($FFB4) from 19 bytes to 12 - improved,
                         ; not resolved. CORRECTED: INITCODE's real
                         ; content is 71 bytes ($47), confirmed by an
                         ; actual assembler run - not the 78-byte
                         ; manual estimate relied on for several
                         ; turns, which was wrong by 7 bytes. That
                         ; 71-byte figure was measured with the old
                         ; structure (test framework excluded emitting
                         ; 0 bytes for
                         ; the TSTRUNNER call site) - with the fix
                         ; above, that site now always emits 3 bytes
                         ; either way, so real content is reasoned to
                         ; be 74 bytes now (71+3), not yet re-measured
                         ; by a real assembler run. At $FFA6, that
                         ; reasoned end is $FFEF - unchanged, since
                         ; the 3-byte shift in INITCODE's own start
                         ; and the 3-byte growth in content offset
                         ; exactly - still one byte below VECTORS, if
                         ; the reasoning above holds; confirm on
                         ; assembly. A prior turn claimed this general
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
; this existed - the default build (UNITTESTS undefined, or
; defined as 0) removes it entirely and this block reverts to
; exactly that padding, computed automatically below via the ROM
; label rather than a fixed byte count, so it's correct either
; way without needing to be hand-adjusted. Pass
; --define=UNITTESTS on the lwasm command line (see the example
; at the end of this comment) to include it.
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
;
; Test groups are further gated by TSTSELECTOR (see below), one
; group at a time, since assembling every group together exhausts
; the available unused ROM space. Example command line, testing
; group 2 with tests included:
;
;   lwasm --6809 --format=raw \
;   --output=forth6809.bin --list=forth6809.lst \
;   --define=UNITTESTS --define=TSTSELECTOR=2 \
;   forth6809.asm
; ============================================================
           IFNDEF UNITTESTS
UNITTESTS SET 0   ; Fallback default value if -D wasn't passed.
                  ; Flag meaning reversed from this file's original
                  ; UNITTESTS convention (0=included,1=excluded under
                  ; IFEQ) to support overriding via lwasm's -D command
                  ; line option: default (0, no -D given) now means
                  ; EXCLUDED - production builds get plain FILL
                  ; padding here with no test-framework code, by
                  ; default. Pass -DUNITTESTS=1 (or any nonzero value)
                  ; to INCLUDE the test framework - tested and
                  ; confirmed working on real MAME hardware under the
                  ; old convention; this reversal only changes how the
                  ; choice is made, not what including it does.
           ENDC

           IFNDEF TSTSELECTOR
TSTSELECTOR SET 2   ; Fallback default value if -D wasn't passed.
           ENDC

         IFNE  UNITTESTS  ; >>>>>>>>>>

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
TSTVAL2  EQU   $2468         ; additional distinct, non-trivial
TSTVAL3  EQU   $7B3D         ; values for multi-item tests (SWAP,
TSTVAL4  EQU   $4E2C         ; OVER, ROT, 2DUP, 2ROT, etc) - none are
TSTVAL5  EQU   $19A7         ; 0, 1, -1, TSTGUARD, or any of each
TSTVAL6  EQU   $6D95         ; other

TSTSCR   EQU   APPVARS+8     ; extra scratch cell - for tests (DEPTH)
                              ; that need to compute an expected value
                              ; independently before comparing

TSTNEG1  EQU   $CFC7         ; -12345 - distinct, non-trivial negative
                              ; test values, needed for arithmetic
                              ; tests (ABS, NEGATE, MIN/MAX, signed
                              ; division, 2/) whose logic genuinely
                              ; branches on sign - TSTVAL1-6 above are
                              ; all positive, which wouldn't exercise
                              ; those branches
TSTNEG2  EQU   $FEBF         ; -321

TSTD1HI  EQU   $0001         ; TSTDBL1 = 70000 (positive, exceeds 16
TSTD1LO  EQU   $1170         ; bits - exercises real double-cell width,
                              ; not just a sign-extended single)
TSTD2HI  EQU   $FFFE         ; TSTDBL2 = -70000
TSTD2LO  EQU   $EE90
TSTD3HI  EQU   $00BC         ; TSTDBL3 = 12345678
TSTD3LO  EQU   $614E
TSTDSHI  EQU   $0000         ; TSTDBLSMALL = 500 - small enough to fit
TSTDSLO  EQU   $01F4         ; in a single cell, for D>S

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
           JSR   TSTSARITH
           JSR   TSTDARITH
           JSR   TSTLOGIC
           RTS

; ------------------------------------------------------------
; TSTSTACK - data stack operation tests. Add new tests here as
; they're written.
; ------------------------------------------------------------
TSTSTACK:  JSR   CRW
           LDX   #TSTSTACKMSG
           PSHU  X
           LDD   #5
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-0  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTSTACKMSG: FCC "Stack"

           IFEQ TSTSELECTOR-0  ; >>>>

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

; ------------------------------------------------------------
; TSTDROP - unit test for DROP ( x -- ). Verifies both the
; stack's contents (the guard beneath the dropped value is left
; undisturbed, and is now the new top) and the data stack
; pointer's movement (exactly one cell, 2 bytes, freed - DROP's
; own net effect, not conflated with the two pushes that set the
; test up).
; ------------------------------------------------------------
TSTDROP:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   DROP

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
DPFAIL:    LDD   #FALSEV
DPDONE:    LDX   #TSTDROPNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDROPNAME: FCB  7
             FCC  "TSTDROP"

; ------------------------------------------------------------
; TSTSWAP - unit test for SWAP ( n1 n2 -- n2 n1 ). Verifies the
; two items exchange places, the guard beneath is undisturbed,
; and the net stack depth is unchanged.
; ------------------------------------------------------------
TSTSWAP:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   SWAP

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
SWFAIL:    LDD   #FALSEV
SWDONE:    LDX   #TSTSWAPNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTSWAPNAME: FCB  7
             FCC  "TSTSWAP"

; ------------------------------------------------------------
; TSTOVER - unit test for OVER ( n1 n2 -- n1 n2 n1 ). Verifies
; the copy of n1 is correct, the originals and guard are
; undisturbed, and exactly one cell was added.
; ------------------------------------------------------------
TSTOVER:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   OVER

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
OVFAIL:    LDD   #FALSEV
OVDONE:    LDX   #TSTOVERNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTOVERNAME: FCB  7
             FCC  "TSTOVER"

; ------------------------------------------------------------
; TSTROT - unit test for ROT ( n1 n2 n3 -- n2 n3 n1 ). Verifies
; the rotation order, the guard beneath is undisturbed, and the
; net stack depth is unchanged.
; ------------------------------------------------------------
TSTROT:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           LDD   #TSTVAL3
           PSHU  D
           STU   TSTUB4

           JSR   ROT

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
RTFAIL:    LDD   #FALSEV
RTDONE:    LDX   #TSTROTNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTROTNAME: FCB  6
            FCC  "TSTROT"

; ------------------------------------------------------------
; TSTQDUPNZ - unit test for ?DUP ( n -- n n | 0 ), nonzero case.
; Verifies the nonzero value is duplicated, the guard beneath is
; undisturbed, and exactly one cell was added - same as DUP's
; own behavior for this case. ?DUP needs two tests, one per
; condition, since DUP-like and no-op are genuinely different
; code paths (QDUP branches on the popped value).
; ------------------------------------------------------------
TSTQDUPNZ: STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   QDUP

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
QNFAIL:    LDD   #FALSEV
QNDONE:    LDX   #TSTQNNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTQNNAME: FCB  9
           FCC  "TSTQDUPNZ"

; ------------------------------------------------------------
; TSTQDUPZ - unit test for ?DUP ( n -- n n | 0 ), zero case.
; Verifies zero is left alone - no duplicate is pushed - the
; guard beneath is undisturbed, and the net stack depth is
; unchanged.
; ------------------------------------------------------------
TSTQDUPZ:  STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #0
           PSHU  D
           STU   TSTUB4

           JSR   QDUP

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
QZFAIL:    LDD   #FALSEV
QZDONE:    LDX   #TSTQZNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTQZNAME: FCB  8
           FCC  "TSTQDUPZ"

; ------------------------------------------------------------
; TSTDEPTH - unit test for DEPTH ( -- n ). Independently
; computes the expected depth via the same (SP0-U)/2 formula
; DEPTH itself uses, rather than assuming a fixed starting
; depth - robust regardless of whatever is already on the stack
; when this test runs. Also verifies DEPTH's own net effect
; (exactly one cell pushed) and that the three items pushed to
; set up the test are left undisturbed.
; ------------------------------------------------------------
TSTDEPTH:  STU   TSTU0

           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           LDD   #TSTVAL3
           PSHU  D
           STU   TSTUB4

           JSR   DEPTH

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
DHFAIL:    LDD   #FALSEV
DHDONE:    LDX   #TSTDEPTHNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDEPTHNAME: FCB  8
              FCC  "TSTDEPTH"

; ------------------------------------------------------------
; TSTDDUP - unit test for 2DUP ( x1 x2 -- x1 x2 x1 x2 ).
; Verifies the duplicated pair, the originals and guard are
; undisturbed, and exactly two cells were added.
; ------------------------------------------------------------
TSTDDUP:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   DDUP

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
DU2FAIL:   LDD   #FALSEV
DU2DONE:   LDX   #TSTDDUPNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDDUPNAME: FCB  7
             FCC  "TSTDDUP"

; ------------------------------------------------------------
; TSTDDROP - unit test for 2DROP ( x1 x2 -- ). Verifies both
; items are removed, the guard beneath is undisturbed, and
; exactly two cells were freed.
; ------------------------------------------------------------
TSTDDROP:  STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   DDROP

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
DR2FAIL:   LDD   #FALSEV
DR2DONE:   LDX   #TSTDDROPNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDDROPNAME: FCB  8
              FCC  "TSTDDROP"

; ------------------------------------------------------------
; TSTDSWAP - unit test for 2SWAP ( x1 x2 x3 x4 -- x3 x4 x1 x2 ).
; Verifies the two pairs exchange places, the guard beneath is
; undisturbed, and the net stack depth is unchanged.
; ------------------------------------------------------------
TSTDSWAP:  STU   TSTU0

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

           JSR   DSWAP

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
SW2FAIL:   LDD   #FALSEV
SW2DONE:   LDX   #TSTDSWAPNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDSWAPNAME: FCB  8
              FCC  "TSTDSWAP"

; ------------------------------------------------------------
; TSTDOVER - unit test for 2OVER
; ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 ). Verifies the copied
; pair, the originals and guard are undisturbed, and exactly
; two cells were added.
; ------------------------------------------------------------
TSTDOVER:  STU   TSTU0

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

           JSR   DOVER

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
OV2FAIL:   LDD   #FALSEV
OV2DONE:   LDX   #TSTDOVERNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDOVERNAME: FCB  8
              FCC  "TSTDOVER"

; ------------------------------------------------------------
; TSTNIP - unit test for NIP ( x1 x2 -- x2 ). Verifies the
; second item is discarded, x2 is left on top, the guard beneath
; is undisturbed, and exactly one cell was freed.
; ------------------------------------------------------------
TSTNIP:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   NIP

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
NPFAIL:    LDD   #FALSEV
NPDONE:    LDX   #TSTNIPNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTNIPNAME: FCB  6
            FCC  "TSTNIP"

; ------------------------------------------------------------
; TSTTUCK - unit test for TUCK ( x1 x2 -- x2 x1 x2 ). Verifies
; the copy of x2 is tucked correctly beneath x1, the guard
; beneath is undisturbed, and exactly one cell was added.
; ------------------------------------------------------------
TSTTUCK:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   TUCK

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
TKFAIL:    LDD   #FALSEV
TKDONE:    LDX   #TSTTUCKNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTTUCKNAME: FCB  7
             FCC  "TSTTUCK"

; ------------------------------------------------------------
; TSTPICK - unit test for PICK ( xu ... x0 u -- xu ... x0 xu ),
; using u=2 as a concrete representative case (0 PICK is DUP,
; 1 PICK is OVER; 2 PICK is the first case distinct from both).
; Verifies the correct item (the one 2 cells deep after u itself
; is popped) is copied to the top, everything beneath is
; undisturbed, and the net stack depth is unchanged (u popped,
; one copy pushed).
; ------------------------------------------------------------
TSTPICK:   STU   TSTU0

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

           JSR   PICK

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
PKFAIL:    LDD   #FALSEV
PKDONE:    LDX   #TSTPICKNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTPICKNAME: FCB  7
             FCC  "TSTPICK"

; ------------------------------------------------------------
; TSTROLL - unit test for ROLL
; ( xu ... x0 u -- xu-1 ... x0 xu ), using u=2 as a concrete
; representative case (matches TSTPICK's own choice of u, so
; the two tests are directly comparable). Verifies the item 2
; cells deep is removed and moved to the top, the items above it
; shift down by one slot each, the guard beneath is undisturbed,
; and exactly one cell was freed (u popped, nothing replaces it
; numerically - the rolled item moves within the existing space).
; ------------------------------------------------------------
TSTROLL:   STU   TSTU0

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

           JSR   ROLL

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
RLFAIL:    LDD   #FALSEV
RLDONE:    LDX   #TSTROLLNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTROLLNAME: FCB  7
             FCC  "TSTROLL"

; ------------------------------------------------------------
; TSTDROT - unit test for 2ROT
; ( x1 x2 x3 x4 x5 x6 -- x3 x4 x5 x6 x1 x2 ). Verifies the
; rotation order of all three cell pairs, the guard beneath is
; undisturbed, and the net stack depth is unchanged.
; ------------------------------------------------------------
TSTDROT:   STU   TSTU0

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

           JSR   DROT

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
RO2FAIL:   LDD   #FALSEV
RO2DONE:   LDX   #TSTDROTNAME
           PSHU  X
           PSHU  D
           JSR   TSTREPORT

           LDU   TSTU0
           RTS

TSTDROTNAME: FCB  7
             FCC  "TSTDROT"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTSARITH - single-cell arithmetic tests (glossary section 3.4).
; Covers every word in that section, with representative
; positive/negative/zero cases per word - not an exhaustive sign
; combination sweep, but enough to exercise each word's actual
; branches (sign handling, division's throw-on-zero, multiply's
; defined-truncation-not-error overflow behavior). See the
; open-items checklist for the full reasoning behind the specific
; cases chosen.
; ------------------------------------------------------------
TSTSARITH: JSR   CRW
           LDX   #TSTSARITHMSG
           PSHU  X
           LDD   #11
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-1  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTSARITHMSG: FCC "SArithmetic"

           IFEQ TSTSELECTOR-1  ; >>>>

; ------------------------------------------------------------
; TSTPLUS - unit test for PLUS. n1 + n2, mixed signs.
; ------------------------------------------------------------
TSTPLUS:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           STU   TSTUB4

           JSR   PLUS

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

TSTPLUSNAME: FCB  7
               FCC  "TSTPLUS"

; ------------------------------------------------------------
; TSTMINUS - unit test for MINUS. n1 - n2 (operand order matters).
; ------------------------------------------------------------
TSTMINUS:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   MINUS

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

TSTMINUSNAME: FCB  8
                FCC  "TSTMINUS"

; ------------------------------------------------------------
; TSTSTAR1 - unit test for STAR. normal signed multiply.
; ------------------------------------------------------------
TSTSTAR1:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           LDD   #TSTNEG2
           PSHU  D
           STU   TSTUB4

           JSR   STAR

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

TSTSTAR1NAME: FCB  8
                FCC  "TSTSTAR1"

; ------------------------------------------------------------
; TSTSTAR2 - unit test for STAR. overflow case - product exceeds 16-bit range; ANS defines * as truncating, not erroring.
; ------------------------------------------------------------
TSTSTAR2:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #$03E8
           PSHU  D
           LDD   #$03E8
           PSHU  D
           STU   TSTUB4

           JSR   STAR

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

TSTSTAR2NAME: FCB  8
                FCC  "TSTSTAR2"

; ------------------------------------------------------------
; TSTSLASH1 - unit test for SLASH. normal signed symmetric division (quotient only - SLASH pushes DIVNUM, not the remainder too).
; ------------------------------------------------------------
TSTSLASH1:  STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   SLASH

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

TSTSLASH1NAME: FCB  9
                 FCC  "TSTSLASH1"

; ------------------------------------------------------------
; TSTSLASH2 - unit test for SLASH. negative dividend, symmetric division.
; ------------------------------------------------------------
TSTSLASH2:  STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   SLASH

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

TSTSLASH2NAME: FCB  9
                 FCC  "TSTSLASH2"

; ------------------------------------------------------------
; TSTSLASHZ - unit test for SLASH, divide-by-zero case. n2 = 0.
; Verifies THROW -10 fires (per this system's documented ANS
; behavior for a zero divisor) and that CATCH's own depth-
; restoration contract holds (net 0 change across the JSR CATCH,
; xt's slot effectively replaced by the throw code). Per CATCH's
; own spec, the i*x arguments' VALUES are explicitly unspecified
; after a catch, not just untested here - the final, unconditional
; stack restore discards them without needing to know how many
; there are.
; ------------------------------------------------------------
TSTSLASHZ:  STU   TSTU0

           LDD   #TSTVAL1
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #SLASH
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTSLASHZNAME: FCB  9
                 FCC  "TSTSLASHZ"

; ------------------------------------------------------------
; TSTMODW - unit test for MODW. negative dividend, symmetric remainder.
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

TSTMODWNAME: FCB  7
               FCC  "TSTMODW"

; ------------------------------------------------------------
; TSTMODZ - unit test for MODW, divide-by-zero case. n2 = 0.
; Verifies THROW -10 fires (per this system's documented ANS
; behavior for a zero divisor) and that CATCH's own depth-
; restoration contract holds (net 0 change across the JSR CATCH,
; xt's slot effectively replaced by the throw code). Per CATCH's
; own spec, the i*x arguments' VALUES are explicitly unspecified
; after a catch, not just untested here - the final, unconditional
; stack restore discards them without needing to know how many
; there are.
; ------------------------------------------------------------
TSTMODZ:    STU   TSTU0

           LDD   #TSTVAL1
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #MODW
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTMODZNAME: FCB  7
               FCC  "TSTMODZ"

; ------------------------------------------------------------
; TSTSLMOD - unit test for SLASHMOD. /MOD together - both remainder and quotient.
; ------------------------------------------------------------
TSTSLMOD:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTNEG2
           PSHU  D
           STU   TSTUB4

           JSR   SLASHMOD

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

TSTSLMODNAME: FCB  8
                FCC  "TSTSLMOD"

; ------------------------------------------------------------
; TSTSLMODZ - unit test for SLASHMOD, divide-by-zero case. n2 = 0.
; Verifies THROW -10 fires (per this system's documented ANS
; behavior for a zero divisor) and that CATCH's own depth-
; restoration contract holds (net 0 change across the JSR CATCH,
; xt's slot effectively replaced by the throw code). Per CATCH's
; own spec, the i*x arguments' VALUES are explicitly unspecified
; after a catch, not just untested here - the final, unconditional
; stack restore discards them without needing to know how many
; there are.
; ------------------------------------------------------------
TSTSLMODZ:  STU   TSTU0

           LDD   #TSTVAL1
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #SLASHMOD
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTSLMODZNAME: FCB  9
                 FCC  "TSTSLMODZ"

; ------------------------------------------------------------
; TSTNEGATE - unit test for NEGATE. two's-complement negate.
; ------------------------------------------------------------
TSTNEGATE:  STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   NEGATE

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

TSTNEGATENAME: FCB  9
                 FCC  "TSTNEGATE"

; ------------------------------------------------------------
; TSTABS1 - unit test for ABSW. positive input - already non-negative, unchanged.
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

TSTABS1NAME: FCB  7
               FCC  "TSTABS1"

; ------------------------------------------------------------
; TSTABS2 - unit test for ABSW. negative input - the branch that actually negates.
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

TSTABS2NAME: FCB  7
               FCC  "TSTABS2"

; ------------------------------------------------------------
; TSTMIN1 - unit test for MIN. n1 < n2 - n1 is the min, left unchanged.
; ------------------------------------------------------------
TSTMIN1:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   MIN

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

TSTMIN1NAME: FCB  7
               FCC  "TSTMIN1"

; ------------------------------------------------------------
; TSTMIN2 - unit test for MIN. n1 > n2 - n2 is the min, replaces n1.
; ------------------------------------------------------------
TSTMIN2:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           STU   TSTUB4

           JSR   MIN

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

TSTMIN2NAME: FCB  7
               FCC  "TSTMIN2"

; ------------------------------------------------------------
; TSTMAX1 - unit test for MAX. n1 < n2 - n2 is the max, replaces n1.
; ------------------------------------------------------------
TSTMAX1:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   MAX

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

TSTMAX1NAME: FCB  7
               FCC  "TSTMAX1"

; ------------------------------------------------------------
; TSTMAX2 - unit test for MAX. n1 > n2 - n1 is the max, left unchanged.
; ------------------------------------------------------------
TSTMAX2:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           STU   TSTUB4

           JSR   MAX

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

TSTMAX2NAME: FCB  7
               FCC  "TSTMAX2"

; ------------------------------------------------------------
; TSTONEP - unit test for ONEPLUS. add one.
; ------------------------------------------------------------
TSTONEP:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   ONEPLUS

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

TSTONEPNAME: FCB  7
               FCC  "TSTONEP"

; ------------------------------------------------------------
; TSTONEM - unit test for ONEMINUS. subtract one.
; ------------------------------------------------------------
TSTONEM:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   ONEMINUS

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

TSTONEMNAME: FCB  7
               FCC  "TSTONEM"

; ------------------------------------------------------------
; TSTTWOP - unit test for TWOPLUS. add two (not ANS-standard).
; ------------------------------------------------------------
TSTTWOP:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   TWOPLUS

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

TSTTWOPNAME: FCB  7
               FCC  "TSTTWOP"

; ------------------------------------------------------------
; TSTTWOS - unit test for TWOSTAR. arithmetic shift left one bit.
; ------------------------------------------------------------
TSTTWOS:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   TWOSTAR

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

TSTTWOSNAME: FCB  7
               FCC  "TSTTWOS"

; ------------------------------------------------------------
; TSTTWOD1 - unit test for TWOSLASH. positive input, arithmetic shift right.
; ------------------------------------------------------------
TSTTWOD1:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   TWOSLASH

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

TSTTWOD1NAME: FCB  8
                FCC  "TSTTWOD1"

; ------------------------------------------------------------
; TSTTWOD2 - unit test for TWOSLASH. negative input - the case that actually tests sign-preservation.
; ------------------------------------------------------------
TSTTWOD2:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           STU   TSTUB4

           JSR   TWOSLASH

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

TSTTWOD2NAME: FCB  8
                FCC  "TSTTWOD2"

; ------------------------------------------------------------
; TSTSTSL - unit test for STARSLASH. n1*n2/n3 via double-cell intermediate, no truncation until final divide.
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

           JSR   STARSLASH

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

TSTSTSLNAME: FCB  7
               FCC  "TSTSTSL"

; ------------------------------------------------------------
; TSTSTSLZ - unit test for STARSLASH, divide-by-zero case. n3 = 0.
; Verifies THROW -10 fires (per this system's documented ANS
; behavior for a zero divisor) and that CATCH's own depth-
; restoration contract holds (net 0 change across the JSR CATCH,
; xt's slot effectively replaced by the throw code). Per CATCH's
; own spec, the i*x arguments' VALUES are explicitly unspecified
; after a catch, not just untested here - the final, unconditional
; stack restore discards them without needing to know how many
; there are.
; ------------------------------------------------------------
TSTSTSLZ:   STU   TSTU0

           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #STARSLASH
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTSTSLZNAME: FCB  8
                FCC  "TSTSTSLZ"

; ------------------------------------------------------------
; TSTSTSM - unit test for STARSLASHMOD. */MOD together - remainder and quotient.
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

           JSR   STARSLASHMOD

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

TSTSTSMNAME: FCB  7
               FCC  "TSTSTSM"

; ------------------------------------------------------------
; TSTSTSMZ - unit test for STARSLASHMOD, divide-by-zero case. n3 = 0.
; Verifies THROW -10 fires (per this system's documented ANS
; behavior for a zero divisor) and that CATCH's own depth-
; restoration contract holds (net 0 change across the JSR CATCH,
; xt's slot effectively replaced by the throw code). Per CATCH's
; own spec, the i*x arguments' VALUES are explicitly unspecified
; after a catch, not just untested here - the final, unconditional
; stack restore discards them without needing to know how many
; there are.
; ------------------------------------------------------------
TSTSTSMZ:   STU   TSTU0

           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #STARSLASHMOD
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTSTSMZNAME: FCB  8
                FCC  "TSTSTSMZ"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTDARITH - mixed & double-precision arithmetic tests (glossary
; section 3.5). Covers every word in that section. All 14 words
; traced by hand against their real implementations before any
; test was written - push/pop order for double-cell values (low
; cell pushed first, high cell last/on top - confirmed identical
; across every word here), and which of two operands is which
; (d1 vs d2, dividend vs divisor) - not assumed from the glossary
; stack-effect notation alone. FM/MOD (floored) and SM/REM
; (symmetric) tested against the same negative-dividend case
; specifically because that's where the two conventions actually
; diverge - confirmed distinct expected results for each.
; ------------------------------------------------------------
TSTDARITH: JSR   CRW
           LDX   #TSTDARITHMSG
           PSHU  X
           LDD   #11
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-2  ; >>>>

           JSR   TSTUMST
           JSR   TSTUMSM
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

           ENDC ; <<<<

           RTS

TSTDARITHMSG: FCC "DArithmetic"

           IFEQ TSTSELECTOR-2  ; >>>>

; ------------------------------------------------------------
; TSTUMST - unit test for UMSTAR. unsigned single*single->double.
; Arity: 2 cell(s) in, 2 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTUMST:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   UMSTAR

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

TSTUMSTNAME: FCB  7
               FCC  "TSTUMST"

; ------------------------------------------------------------
; TSTUMSM - unit test for UMSLASHMOD. unsigned double/single -> remainder, quotient.
; Arity: 3 cell(s) in, 2 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

           JSR   UMSLASHMOD

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

TSTUMSMNAME: FCB  7
               FCC  "TSTUMSM"

; ------------------------------------------------------------
; TSTMSTAR - unit test for MSTAR. signed single*single->double.
; Arity: 2 cell(s) in, 2 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTMSTAR:   STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   MSTAR

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

TSTMSTARNAME: FCB  8
                FCC  "TSTMSTAR"

; ------------------------------------------------------------
; TSTFMSM - unit test for FMSLASHMOD. floored double/single division.
; Arity: 3 cell(s) in, 2 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

           JSR   FMSLASHMOD

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

TSTFMSMNAME: FCB  7
               FCC  "TSTFMSM"

; ------------------------------------------------------------
; TSTSMRM - unit test for SMSLASHREM. symmetric double/single division.
; Arity: 3 cell(s) in, 2 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

           JSR   SMSLASHREM

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

TSTSMRMNAME: FCB  7
               FCC  "TSTSMRM"

; ------------------------------------------------------------
; TSTDPLUS - unit test for DPLUS. double-cell add, with carry propagation.
; Arity: 4 cell(s) in, 2 cell(s) out -> depth check
; -4 (derived, not hand-typed).
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

           JSR   DPLUS

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

TSTDPLUSNAME: FCB  8
                FCC  "TSTDPLUS"

; ------------------------------------------------------------
; TSTDMIN2 - unit test for DMINUS. double-cell subtract, with borrow propagation.
; Arity: 4 cell(s) in, 2 cell(s) out -> depth check
; -4 (derived, not hand-typed).
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

           JSR   DMINUS

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

TSTDMIN2NAME: FCB  8
                FCC  "TSTDMIN2"

; ------------------------------------------------------------
; TSTDNEG - unit test for DNEGATEW. double-cell two's-complement negate.
; Arity: 2 cell(s) in, 2 cell(s) out -> depth check
; 0 (derived, not hand-typed).
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

TSTDNEGNAME: FCB  7
               FCC  "TSTDNEG"

; ------------------------------------------------------------
; TSTDABS1 - unit test for DABSW. positive double - already non-negative, unchanged.
; Arity: 2 cell(s) in, 2 cell(s) out -> depth check
; 0 (derived, not hand-typed).
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

TSTDABS1NAME: FCB  8
                FCC  "TSTDABS1"

; ------------------------------------------------------------
; TSTDABS2 - unit test for DABSW. negative double - the branch that actually negates.
; Arity: 2 cell(s) in, 2 cell(s) out -> depth check
; 0 (derived, not hand-typed).
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

TSTDABS2NAME: FCB  8
                FCC  "TSTDABS2"

; ------------------------------------------------------------
; TSTMPLUS - unit test for MPLUS. add a single-cell value into a double.
; Arity: 3 cell(s) in, 2 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

           JSR   MPLUS

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

TSTMPLUSNAME: FCB  8
                FCC  "TSTMPLUS"

; ------------------------------------------------------------
; TSTSTOD - unit test for STOD. sign-extend a negative single to double (this word's own documented bug history was in this exact case).
; Arity: 1 cell(s) in, 2 cell(s) out -> depth check
; 2 (derived, not hand-typed).
; ------------------------------------------------------------
TSTSTOD:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           STU   TSTUB4

           JSR   STOD

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

TSTSTODNAME: FCB  7
               FCC  "TSTSTOD"

; ------------------------------------------------------------
; TSTDTOS - unit test for DTOS. narrow a double that fits to a single cell.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
; ------------------------------------------------------------
TSTDTOS:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTDSLO
           PSHU  D
           LDD   #TSTDSHI
           PSHU  D
           STU   TSTUB4

           JSR   DTOS

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

TSTDTOSNAME: FCB  7
               FCC  "TSTDTOS"

; ------------------------------------------------------------
; TSTDMAX - unit test for DMAXW. double-cell signed maximum, cross-sign case.
; Arity: 4 cell(s) in, 2 cell(s) out -> depth check
; -4 (derived, not hand-typed).
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

TSTDMAXNAME: FCB  7
               FCC  "TSTDMAX"

; ------------------------------------------------------------
; TSTDMIN - unit test for DMINW. double-cell signed minimum, cross-sign case.
; Arity: 4 cell(s) in, 2 cell(s) out -> depth check
; -4 (derived, not hand-typed).
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

TSTDMINNAME: FCB  7
               FCC  "TSTDMIN"

; ------------------------------------------------------------
; TSTUMSZ - unit test for UMSLASHMOD, divide-by-zero case. u1 = 0.
; Verifies THROW -10 and CATCH's own depth-restoration contract
; (net 0 change across the JSR CATCH) - same pattern established
; in the section 3.4 tests.
; ------------------------------------------------------------
TSTUMSZ:    STU   TSTU0

           LDD   #TSTD1LO
           PSHU  D
           LDD   #TSTD1HI
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #UMSLASHMOD
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTUMSZNAME: FCB  7
               FCC  "TSTUMSZ"

; ------------------------------------------------------------
; TSTFMSZ - unit test for FMSLASHMOD, divide-by-zero case. n1 = 0.
; Verifies THROW -10 and CATCH's own depth-restoration contract
; (net 0 change across the JSR CATCH) - same pattern established
; in the section 3.4 tests.
; ------------------------------------------------------------
TSTFMSZ:    STU   TSTU0

           LDD   #TSTD2LO
           PSHU  D
           LDD   #TSTD2HI
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #FMSLASHMOD
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTFMSZNAME: FCB  7
               FCC  "TSTFMSZ"

; ------------------------------------------------------------
; TSTSMRZ - unit test for SMSLASHREM, divide-by-zero case. n1 = 0.
; Verifies THROW -10 and CATCH's own depth-restoration contract
; (net 0 change across the JSR CATCH) - same pattern established
; in the section 3.4 tests.
; ------------------------------------------------------------
TSTSMRZ:    STU   TSTU0

           LDD   #TSTD2LO
           PSHU  D
           LDD   #TSTD2HI
           PSHU  D
           LDD   #$0000
           PSHU  D
           LDX   #SMSLASHREM
           PSHU  X
           STU   TSTUB4

           JSR   CATCH

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

TSTSMRZNAME: FCB  7
               FCC  "TSTSMRZ"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTLOGIC - logic, shift, and address-arithmetic tests (glossary
; section 3.6). Covers every word in that section. Several of
; these (INVERT, CELLS, CELL+, CHARS, CHAR+, ALIGNED) modify the
; top of stack in place (LDD/op/STD) rather than PULU/PSHU - the
; tests verify what's observable via the stack either way, not
; how each implementation gets there. Three words (CHARS, ALIGN,
; ALIGNED) are documented no-ops on this system; CHARS/ALIGNED
; still get a normal single-value test (verifying identity),
; while ALIGN - which takes no stack arguments at all - gets a
; dedicated test pushing decoy values to confirm the whole stack,
; not just one value, is genuinely undisturbed. RSHIFT tested
; against a negative input specifically, since it's documented
; logical (zero-fill), not arithmetic (sign-preserving) - the
; case that actually distinguishes the two conventions, same
; reasoning already applied to 2/ and FM/MOD vs SM/REM earlier.
; ------------------------------------------------------------
TSTLOGIC:  JSR   CRW
           LDX   #TSTLOGICMSG
           PSHU  X
           LDD   #5
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-3  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTLOGICMSG: FCC "Logic"

           IFEQ TSTSELECTOR-3  ; >>>>

; ------------------------------------------------------------
; TSTAND - unit test for ANDW. bitwise AND.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

TSTANDNAME: FCB  6
              FCC  "TSTAND"

; ------------------------------------------------------------
; TSTOR - unit test for ORW. bitwise OR.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

TSTORNAME: FCB  5
             FCC  "TSTOR"

; ------------------------------------------------------------
; TSTXOR - unit test for XORW. bitwise exclusive OR.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

TSTXORNAME: FCB  6
              FCC  "TSTXOR"

; ------------------------------------------------------------
; TSTINV - unit test for INVERT. one's-complement, in-place (never touches U itself, unlike most words - the test only cares what's observable via the stack, not how the implementation gets there).
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTINV:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   INVERT

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

TSTINVNAME: FCB  6
              FCC  "TSTINV"

; ------------------------------------------------------------
; TSTLSH - unit test for LSHIFT. logical shift left, zero-fill, truncated to 16 bits.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
; ------------------------------------------------------------
TSTLSH:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           LDD   #$0004
           PSHU  D
           STU   TSTUB4

           JSR   LSHIFT

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

TSTLSHNAME: FCB  6
              FCC  "TSTLSH"

; ------------------------------------------------------------
; TSTRSH - unit test for RSHIFT. logical shift right, zero-fill (not arithmetic/sign-preserving) - negative input is the case that actually distinguishes this from an arithmetic shift.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
; ------------------------------------------------------------
TSTRSH:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           LDD   #$0004
           PSHU  D
           STU   TSTUB4

           JSR   RSHIFT

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

TSTRSHNAME: FCB  6
              FCC  "TSTRSH"

; ------------------------------------------------------------
; TSTCELS - unit test for CELLSW. convert a cell count to a byte offset (x2, this system's cell size).
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
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

TSTCELSNAME: FCB  7
               FCC  "TSTCELS"

; ------------------------------------------------------------
; TSTCELP - unit test for CELLPLUS. add one cell's size (2 bytes).
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTCELP:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   CELLPLUS

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

TSTCELPNAME: FCB  7
               FCC  "TSTCELP"

; ------------------------------------------------------------
; TSTCHRS - unit test for CHARSW. convert a character count to a byte offset - documented no-op on this system (1 byte per character already).
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
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

TSTCHRSNAME: FCB  7
               FCC  "TSTCHRS"

; ------------------------------------------------------------
; TSTCHRP - unit test for CHARPLUS. add one character's size (1 byte).
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTCHRP:    STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   CHARPLUS

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

TSTCHRPNAME: FCB  7
               FCC  "TSTCHRP"

; ------------------------------------------------------------
; TSTALGD - unit test for ALIGNEDW. align a given address - documented no-op on the 6809 (no alignment restrictions to enforce).
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
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

TSTALGDNAME: FCB  7
               FCC  "TSTALGD"

; ------------------------------------------------------------
; TSTALGN - unit test for ALIGNW. align HERE to a cell boundary - documented no-op on the 6809, and takes no stack arguments at all. Verifies pushed decoy values are entirely undisturbed, not just a single value's persistence.
; Arity: 0 cell(s) in, 0 cell(s) out -> depth check
; 0 (derived, not hand-typed).
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

TSTALGNNAME: FCB  7
               FCC  "TSTALGN"

           ENDC ; <<<<

         ENDC  ; <<<<<<<<<<

ROM:
         FILL $FF,BASEDICT-ROM

; ============================================================
; SECTION 27: FORTH DICTIONARY (ROM base dictionary headers)
; Every primitive word in the Glossary gets a real header here,
; chained via LINK, living in BASEDICT ($D83F-$E006, an exact fit
; for this dictionary's 1992 bytes - was $E000-$E7FF). CFA points
; directly at each primitive's own code label for every entry -
; these are all raw code entries, CFA = the label itself,
; including TRUE and FALSE (added in a later pass, chain's newest
; entries before H_ABORT/H_QUIT below), which originally used the
; DODOES-trampoline pattern matching interactive CONSTANT, but are
; now simple LDD/PSHU/RTS subroutines like everything else here -
; see TRUEBODY/FALSEBODY, section 26, for the current code and why
; they no longer need indirection.
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
; H_ABORT and H_QUIT (formerly ABORTHDR/QUITHDR, renamed to match
; this file's H_ naming convention) are hand-built, not produced
; by the same generation pass as the other 217 entries - see the
; note where they're defined, at the end of this section, for why
; HEADER/CREATE couldn't be used directly for these two. They used
; to live physically apart from the rest of the dictionary, inside
; BASECODE rather than BASEDICT, despite being header data rather
; than code - moved here so every header lives in one place and
; the chain (H_QUIT -> H_ABORT -> (newest entry below) -> ... ->
; (oldest entry) -> 0) is visible in one block. BASELATEST remains
; H_QUIT, the chain's true overall head.
;
; H_ABORT's LINK field, a placeholder 0 since it was first built,
; is resolved here: it now points to this chain's newest entry.
;
; Names containing a literal double-quote (S", .", ABORT") have
; that character split into a standalone FCB $22 rather than
; escaped inside FCC - see emit_name's comment for why.
; ============================================================

         ORG   BASEDICT       ; BASEDICT is $D83F

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

; H_ABORT and H_QUIT are hand-built, not produced by the same
; generation pass as the 217 entries above - ABORT and QUIT need
; to be findable at the prompt, but HEADER/CREATE couldn't be used
; directly for these two (see the source conversation this file
; was derived from for why). Moved here from their own separate
; section so every header in this ROM lives in one contiguous
; block, with the chain visible end to end: H_M2 -> H_2 -> H_M1 ->
; H_1 -> H_FIND -> H_QUIT -> H_ABORT -> H_FALSE (the newest of the
; 217 generated entries) -> ... -> H_KEY -> 0. H_M2 is now the true
; head (see BASELATEST below) - H_FIND and the four number words
; were chained on after H_QUIT in a later turn.
H_ABORT: FCB   5
         FCC   "ABORT"
         FDB   H_FALSE        ; resolved - was placeholder 0, then H_DUMPW,
                               ; then H_DOESGT, then H_DUMPW again once
                               ; DOES> moved out of the chain's newest slot;
                               ; now H_FALSE, the chain's newest entry
         FDB   ABORT

H_QUIT:  FCB   4
         FCC   "QUIT"
         FDB   H_ABORT
         FDB   QUIT

; FIND had no dictionary entry at all - confirmed by checking for
; any H_FIND label or FCC "FIND" string anywhere in this file
; before adding this. Its actual implementation (verified before
; exposing it) already matches the standard stack effect exactly:
; success pushes xt then 1 (immediate) or -1 (normal); failure
; reconstructs and pushes the original c-addr, then 0.
H_FIND:  FCB   4
         FCC   "FIND"
         FDB   H_QUIT
         FDB   FIND

H_1:     FCB   1
         FCC   "1"
         FDB   H_FIND
         FDB   ONEBODY

H_M1:    FCB   2
         FCC   "-1"
         FDB   H_1
         FDB   MONEBODY

H_2:     FCB   1
         FCC   "2"
         FDB   H_M1
         FDB   TWOBODY

H_M2:    FCB   2
         FCC   "-2"
         FDB   H_2
         FDB   MTWOBODY

BASELATEST EQU  H_M2   ; the ROM dictionary's true head - referenced by
                          ; COLD to initialize LATEST. Was H_QUIT before
                          ; FIND and the four number words (1/-1/2/-2)
                          ; were chained on after it; before that,
                          ; QUITHDR before the H_QUIT rename; before
                          ; that, undefined entirely - a real bug, not
                          ; a placeholder, found and fixed several turns
                          ; before this one.

; Verify no collision with base code.
; Value should match ORG BASECODE
BASEDICTEND  EQU   *
BASEDICTSIZE EQU   BASEDICTEND-BASEDICT

; ============================================================
; SECTION 3: ACIA INTERRUPT HANDLER
; ============================================================
         ORG   BASECODE       ; BASECODE is $E02A. This ORG was missing
                               ; entirely - every routine from here through
                               ; SECTION 26 (IRQH, COLD/ABORT/QUIT, and
                               ; every primitive) would otherwise have
                               ; continued growing from wherever SECTION 2's
                               ; WARM message left the location counter,
                               ; inside INIT's 48-byte $FFC0-$FFEF budget,
                               ; overflowing directly into VECTORS ($FFF0)
                               ; instead of landing in BASECODE at all

; ------------------------------------------------------------
; INITSERIAL - initializes the ACIA: master reset, then selects
; interrupt-driven or polling operation depending on SERIALPOLL.
; Extracted from COLDSTRT, which now just JSRs here - moved into
; this section so the ACIA's own init code sits next to the rest
; of its interrupt/polling logic rather than inline in COLDSTRT.
; ------------------------------------------------------------
INITSERIAL: LDA   #$03
         STA   ACIACR         ; was "STA ACIA" - only correct by
                               ; coincidence while ACIA and ACIACR were
                               ; the same address; now genuinely distinct
         IFEQ SERIALPOLL  ; >>>>>>>>>>
         LDA   #CR_RXON        ; interrupt-driven mode: RX interrupt on
         ELSE  ; <<<<<>>>>>
         LDA   #CR_POLL        ; polling mode: no interrupts, RTS held low
         ENDC  ; <<<<<<<<<<
         STA   ACIACR         ; was "STA ACIA" - same fix
         RTS

         IFEQ SERIALPOLL  ; >>>>>>>>>>
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

         ELSE  ; <<<<<>>>>>
IRQH:    RTI                 ; polling mode (SERIALPOLL=1) - ACIA
                              ; interrupts are never enabled (see
                              ; COLDSTRT's CR_POLL init), so this should
                              ; never fire; kept as a safe stub matching
                              ; the other unused vectors below
         ENDC  ; <<<<<<<<<<

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
         LDD   #0        ; BUG FIX: this reset used to live at QLOOP
         STD   STATE     ; below, running on EVERY line - including
                          ; lines in the middle of a colon definition
                          ; that spans more than one line of input.
                          ; COLON (sets STATE=-1) and SEMI (sets
                          ; STATE=0, after checking CSP) are the
                          ; correct, sole places STATE should change
                          ; during normal operation - the old QLOOP
                          ; reset was a third, redundant one that
                          ; silently dropped back to interpret mode
                          ; every time QUERY read a new line,
                          ; regardless of whether ";" had actually
                          ; been reached. A colon definition split
                          ; across multiple lines would have every
                          ; word on every line after the first
                          ; interpreted (and, for anything with a
                          ; stack effect, executed) instead of
                          ; compiled - "TRUE" pushing TRUEV onto the
                          ; data stack instead of being compiled,
                          ; leaving a stray cell CSP would correctly
                          ; catch as a mismatch at ";" (-22). Moved
                          ; here rather than removed outright: QUIT is
                          ; only re-entered on cold boot or an
                          ; uncaught error routing back through ABORT
                          ; (confirmed - ordinary successful lines
                          ; loop back to QLOOP directly, never QUIT),
                          ; so this still correctly forces interpret
                          ; state exactly when ANS's own QUIT
                          ; semantics call for it - just not on every
                          ; single line of an otherwise-uninterrupted
                          ; session. Confirmed via MAME debugger.

QLOOP:   JSR   QUERY

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

QOK:     JSR   CRW        ; BUG FIX: was JSR CRW AFTER the STATE check
                          ; below, so "BNE QLOOP" (still compiling)
                          ; skipped both the CR echo and the ok
                          ; message together. The CR reflects a real
                          ; keystroke - the user genuinely pressed
                          ; Enter for that line - and should echo
                          ; regardless of interpret/compile state;
                          ; only the "ok" message itself should stay
                          ; conditional (correctly not shown mid-
                          ; definition). Previously, every line of a
                          ; multi-line colon definition after the
                          ; first had its line ending silently
                          ; dropped, so the echoed source ran
                          ; together onto one line with no
                          ; resemblance to what was actually typed.
                          ; Confirmed via MAME debugger.
         LDD   STATE
         BNE   QLOOP
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
         ADDD  #PADOFFSET
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
         LDD   CODEHERE  ; BUG FIX: same self-referential PFA bug as
         ADDD  #2        ; CONSTANT/DEFER/2CONSTANT/MARKER (CONSTANT's
         PSHU  D         ; instance confirmed via MAME debugger) -
         JSR   CODECOMMA ; without +2 this pointed at itself instead
                          ; of the value cell that "," appends next.
                          ; Never on the previously-flagged list (only
                          ; DEFER/2CONSTANT/MARKER were), so it went
                          ; unfixed until confirmed by inspection here.
                          ; Confirmed via MAME: ": ENUM CREATE , DOES>
                          ; @ ;" returned the PFA-pointer field's own
                          ; address instead of the value COMMA stored
                          ; one cell further on - exactly "the address
                          ; before the 16-bit constant" instead of the
                          ; address 1 cell further on, matching a
                          ; user-reported MAME trace precisely.
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
          LDD  CODEHERE   ; BUG FIX: was storing CODEHERE's value as-is,
          ADDD #2         ; but at this point CODEHERE points at THIS
          PSHU D          ; very cell, about to be written by the next
          JSR  CODECOMMA  ; CODECOMMA - self-referential, not pointing
                          ; at the value cell 2 bytes further on where
                          ; the JSR COMMA below actually appends 1234.
                          ; +2 accounts for this FDB field's own width,
                          ; landing correctly on the value that follows.
                          ; Confirmed via MAME debugger: executing the
                          ; constant returned its own compile-time
                          ; CODEHERE address instead of the real value.
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
             LDD CODEHERE  ; BUG FIX: same self-referential PFA bug as
             ADDD #2       ; CONSTANT (confirmed via MAME debugger) -
             PSHU D        ; without +2 this pointed at itself instead
             JSR CODECOMMA ; of the two-cell value that COMMA appends
                            ; below.
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
         LDD   CODEHERE  ; BUG FIX: same self-referential PFA bug as
         ADDD  #2        ; CONSTANT (confirmed via MAME debugger) -
         PSHU  D         ; without +2 this pointed at itself instead
         JSR   CODECOMMA ; of the value cell DOABORTUNDEF lands in
                          ; below. Confirmed by inspection: DODEFER's
                          ; own "LDD ,X" would have read the PFA's own
                          ; address and jumped there, crashing on
                          ; execution of any newly-DEFER'd word.
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
         LDD   CODEHERE  ; BUG FIX: same self-referential PFA bug as
         ADDD  #2        ; CONSTANT (confirmed via MAME debugger) -
         PSHU  D         ; without +2 this pointed at itself instead
         JSR   CODECOMMA ; of the four snapshot cells COMMA appends
                          ; below. Confirmed by inspection: DOMARKER's
                          ; own fixed-offset reads (,X / 2,X / 4,X /
                          ; 6,X) would have read garbage relative to
                          ; the intended MKDP/MKCODE/MKVAR/MKLATEST -
                          ; the most severe of the three, since using
                          ; a MARKER-created word would restore
                          ; corrupted dictionary-state pointers.
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
ILOOP:   LDD   #32            ; BUG FIX: WORD expects a delimiter char
         PSHU  D              ; pushed by its caller (PULU D/STB DELIM)
                               ; - nothing pushed one here before, so
                               ; WORD pulled from an empty U stack,
                               ; landing on live RSTACK content (SP0 is
                               ; RSTACK's own first byte) instead of a
                               ; real delimiter. Confirmed present in
                               ; both SERIALPOLL branches - IRQH never
                               ; touches U, so interrupt-driven mode
                               ; had no incidental workaround either.
         JSR   WORD
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

         CMPD  #1            ; NEW: distinguishes NUMBERQ's double-number
         BEQ   TNDOUBLE      ; success code (1) from single (-1), added
                              ; to support ANS's double-number input
                              ; convention (forth-standard.org/standard/
                              ; usage#usage:numbers) - "123." parses as
                              ; a double-cell number, "123" as single.

         LDD   STATE
         BEQ   ILOOP
         LDD   #LIT
         PSHU  D
         JSR   CCALL
         JSR   CODECOMMA
         BRA   ILOOP

TNDOUBLE: ; U currently holds [UDLO(bottom), UDHI(top)], matching
                              ; ANS's (ud1) stack order directly.
         LDD   STATE
         BEQ   ILOOP          ; interpreting: already correctly placed,
                              ; nothing more to do
         ; compiling: need two literals compiled in the order they
         ; must execute at runtime - low first (lands deep), high
         ; second (lands on top). UDHI is currently on top of U, so
         ; pop it aside first, freeing UDLO to be compiled first.
         PULU  D
         STD   MSCR4          ; stash UDHI - confirmed safe scratch,
                              ; untouched by CCALL/CODECOMMA
         LDD   #LIT
         PSHU  D
         JSR   CCALL
         JSR   CODECOMMA      ; compiles UDLO (still on U underneath)
         LDD   #LIT
         PSHU  D
         JSR   CCALL
         LDD   MSCR4
         PSHU  D
         JSR   CODECOMMA      ; compiles UDHI
         BRA   ILOOP

BADWORD: JSR   COUNT
         JSR   TYPE
         LDD   #-13
         PSHU  D
         JSR   THROW

IDONE:   PULU  X         ; BUG FIX: WORD always pushes a c-addr (WORDBUF),
                          ; even via its EMPTY branch - this path used to
                          ; branch straight here via a bare peek (LDX ,U,
                          ; never popped), stranding that address on U.
                          ; JSR FIND (the other path) consumes it via its
                          ; own PULU X; this does the same here, matching
                          ; that same convention rather than inventing a
                          ; different one. Confirmed via MAME debugger:
                          ; a spurious WORDBUF address was found sitting
                          ; on top of otherwise-correct stack contents.
         RTS

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
         CMPB  #WORDMAXCHARS  ; REDESIGN: was "CMPB #31", capping WORD
                          ; at 31 characters regardless of what it was
                          ; parsing - a plain word, a defined name, or
                          ; the text of a compiled/interpreted S"
                          ; string, all fed through the same scan.
                          ; That cap came from WORDBUF's own fixed
                          ; 33-byte allocation (1 count byte + 32 data
                          ; bytes, with 1 byte of that never actually
                          ; used by this check), entirely unrelated to
                          ; CODEHERE or PAD. Traced via MAME: a longer
                          ; S" string was truncated during WORD's own
                          ; scan, before either S"'s interpreted-mode
                          ; (PAD) or compiled-mode (CODEHERE) storage
                          ; path ever got a chance to matter - the
                          ; PAD-based S" redesign a few turns ago
                          ; didn't help here because this is an
                          ; earlier stage entirely. Now uses the
                          ; CODEHERE-to-PAD gap directly, matching the
                          ; traditional fig-Forth layout (WORD's own
                          ; buffer at HERE, growing toward PAD, with
                          ; the pictured numeric output buffer at the
                          ; opposite end growing back toward HERE) -
                          ; WORDMAXCHARS reserves HOLDMINSIZE bytes at
                          ; the PAD end for that buffer, so the two
                          ; don't collide even though ANS itself would
                          ; permit them to (3.3.3.6: "the regions
                          ; returned by WORD and #> may overlap in
                          ; memory"). Confirmed via MAME debugger.
         BEQ   ENDW
         LEAX  1,X
         LEAY  -1,Y
         INCB
         BRA   SCANLP

CONSUME: LEAX  1,X
         LEAY  -1,Y
ENDW:    PSHS  B          ; BUG FIX: B holds the true character count from
                          ; SCANLP's own INCB loop, but B is D's low byte -
                          ; TFR X,D below would silently destroy it before
                          ; it's stored as the length byte. Save it here,
                          ; restore it right before STB ,X+. Affects every
                          ; token followed by more input on the same line
                          ; (terminated via CONSUME, not by running out of
                          ; buffer) - the stored length was TOIN's delta
                          ; instead of the true count, one too many (the
                          ; consumed delimiter), so the copy loop below
                          ; would also copy one byte past the token's real
                          ; end. Confirmed via MAME debugger.
         TFR   X,D
         SUBD  SRCADDR
         STD   TOIN
         PULS  B

         LDX   CODEHERE   ; REDESIGN: was "LDX #WORDBUF" - now writes
                          ; at CODEHERE directly (see SCANLP above for
                          ; the full reasoning). CODEHERE itself is
                          ; NOT advanced by this - matches the ANS
                          ; transient-region contract, where WORD's
                          ; region is expected to be overwritten by
                          ; whatever gets compiled/allocated next.
         STB   ,X+
         LDY   WSTART
COPYLP:  TSTB
         BEQ   COPYDONE
         LDA   ,Y+
         STA   ,X+
         DECB
         BRA   COPYLP
COPYDONE: LDX  CODEHERE   ; REDESIGN: was "LDX #WORDBUF", matching
                          ; the copy destination above.
          PSHU X
          RTS

EMPTY:   LDX   CODEHERE   ; REDESIGN: was "LDX #WORDBUF" - same reason.
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

         ; NEW: ANS double-number input convention (forth-standard.org/
         ; standard/usage#usage:numbers, 3.4.1.3) - a number immediately
         ; followed by a decimal point converts to a double-cell number
         ; instead of single-cell ("1234" -> 1234; "1234." -> 1234 0).
         ; Detected here to exclude the trailing '.' from CNTREM before
         ; NUMLOOP runs, so it isn't mistaken for a digit. The decision
         ; itself is re-derived independently at the end of this routine
         ; (from CADDR and the original count, both still unchanged at
         ; that point - confirmed nothing else in this routine, including
         ; NUMLOOP/UDMULADD, ever touches CADDR) rather than remembered
         ; in a new persistent flag here - GLOBALS is fully packed at
         ; 256/256 bytes, and this avoids needing to carve out a byte
         ; for it.
         LDB   CNTREM
         DECB
         LDA   B,X
         CMPA  #'.'
         BNE   NQNOSIGN
         DEC   CNTREM
         BEQ   NQBAD          ; lone "." with nothing before it

NQNOSIGN: CLR   NUMNEG
         LDA   ,X
         CMPA  #'-'
         BNE   NQNOSIGN2
         COM   NUMNEG
         LEAX  1,X
         DEC   CNTREM
         BEQ   NQBAD

NQNOSIGN2: STX  NADDR
          CLRA
          LDB   CNTREM
          STD   NCNT
          LDD   #0
          STD   UDHI
          STD   UDLO

          JSR   NUMLOOP

          LDD   NCNT
          BNE   NQBAD

          ; BUG FIX (as part of this same change): was "LDD UDLO / TST
          ; NUMNEG / BEQ NQPOS / COMA / COMB / ADDD #1" - negated only
          ; the low 16 bits. Harmless for single-cell numbers (the high
          ; cell was never returned before), but wrong once returning a
          ; genuine 32-bit value for the double case - a negative double
          ; needs the full 32-bit two's-complement negation, with any
          ; carry out of the low-cell increment propagated into the
          ; high cell.
          TST   NUMNEG
          BEQ   NQPOS32
          LDD   UDLO
          COMA
          COMB
          ADDD  #1
          STD   UDLO
          PSHS  CC          ; BUG FIX: save the TRUE carry from the
                             ; addition above, before it gets destroyed.
                             ; COM (used on UDHI just below) unconditionally
                             ; SETS carry=1 on the 6809, regardless of its
                             ; operand - a documented quirk, but one that
                             ; silently overwrote the real carry here
                             ; before the BCC check could ever read it,
                             ; making the high-cell increment run
                             ; UNCONDITIONALLY instead of only when the
                             ; low-cell addition actually overflowed.
                             ; Confirmed via MAME: "-123." returned high
                             ; cell 0 instead of -1, and "-123456."
                             ; returned -1 instead of -2 - both exactly
                             ; matching "always increment" rather than
                             ; "increment only on genuine carry".
          LDD   UDHI
          COMA
          COMB
          PULS  CC          ; restore the TRUE carry
          BCC   NQSTOREHI   ; BUG FIX: this used to be "BCC NQPOS32",
                             ; branching all the way PAST "STD UDHI"
                             ; when there's no carry - the complemented
                             ; value was computed in D but never
                             ; actually stored back to UDHI in that
                             ; case, leaving it at its stale, pre-
                             ; negation value. Masked by the carry bug
                             ; above in practice (that bug meant carry
                             ; was always seen as set, so this branch
                             ; was never actually taken, and STD UDHI
                             ; always ran) - fixing the carry check
                             ; alone would have made this second,
                             ; previously-latent bug live. Now branches
                             ; only past the "+1", never past the
                             ; store itself - the store always runs,
                             ; either way.
          ADDD  #1
NQSTOREHI: STD  UDHI

NQPOS32:  ; re-derive from CADDR whether the ORIGINAL last character
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

NQSINGLE: ; SINGLE success - unchanged from the original convention
          LDD   UDLO
          PSHU  D
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

JWORD:   LDD   8,S        ; CORRECTION: an earlier turn changed this to
         PSHU  D          ; 10,S, which was itself wrong - it assumed
         RTS              ; DOSETUP's own JSR-pushed return address
                          ; persists on S once each DOSETUP finishes.
                          ; It doesn't: DOSETUP's own RTS pops and
                          ; consumes it to jump into the loop body, so
                          ; it never actually sits on S for J to count
                          ; past. Re-traced by counting every real
                          ; push/pop across a nested DO: after the
                          ; inner DOSETUP finishes, S is [inner-index@0]
                          ; [inner-limit@2][inner-leave@4][outer-
                          ; index@6][outer-limit@8][outer-leave@10] -
                          ; J's own JSR pushes one more cell on top,
                          ; landing outer-index at 8, not 10. Offset 10
                          ; read the outer loop's limit instead - a
                          ; fixed value every iteration, exactly
                          ; matching the observed bug (J stuck at the
                          ; limit, never progressing). Confirmed via a
                          ; real MULT-TABLE test on MAME.

LEAVE:   LDD   #TRUEV    ; BUG FIX (earlier): was PULS X first, shifting
         STD   6,S       ; S by 2 before this write, landing 2 bytes
         RTS             ; past the LEAVE flag DOSETUP actually pushed.
                          ; Fixed by deferring PULS X to after the
                          ; write - but that left a PULS X/PSHS X pair
                          ; that had become a genuine no-op (nothing
                          ; between them touches S or X, and this
                          ; routine never uses X's value for anything,
                          ; unlike DOTEST's own deferred PULS X, which
                          ; feeds LDD ,X/LEAX D,X afterward). Removed,
                          ; per the parallel 68000 port's observation,
                          ; confirmed by inspection.

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

UNLOOP:  RTS             ; DESIGN CHANGE: was PULS X/LEAS 6,S/PSHS X/RTS
                          ; (a real discard of the loop-control frame).
                          ; EXIT's own EXITUNLOOP mechanism already
                          ; discards the frame automatically and
                          ; correctly on every path - traced and
                          ; confirmed: with no enclosing DO (compiled
                          ; count 0), with one enclosing DO and no
                          ; prior UNLOOP (discards the full 8-byte
                          ; frame correctly). The one combination that
                          ; broke was UNLOOP immediately before EXIT -
                          ; UNLOOP discarding 6 of the 8 bytes itself,
                          ; then EXITUNLOOP unconditionally discarding
                          ; a full 8 more, overshooting into whatever
                          ; sat below (typically the caller's own
                          ; return address) and branching into random
                          ; memory on return. Since UNLOOP has no
                          ; other legitimate use than immediately
                          ; preceding an exit from the definition, and
                          ; EXIT already handles that correctly on its
                          ; own, UNLOOP is now a true no-op rather than
                          ; a second, conflicting discard mechanism.

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

CASEW:   LDD   #TAGCASE  ; BUG FIX: was LDD #0/PSHU D here first, pushing
         PSHU  D         ; a value nothing downstream ever consumes -
         RTS             ; OF/ENDOF never read this deep, and ENDCASE's
                          ; scan loop stops the instant it sees TAGCASE,
                          ; never popping past it. Left one cell
                          ; permanently stranded below CSP's expected
                          ; depth, so ";" always saw a mismatch and
                          ; threw -22, even for the simplest CASE...
                          ; ENDCASE with no OF clauses at all. Removed;
                          ; confirmed by inspection that nothing reads
                          ; or depends on it anywhere in OF/ENDOF/
                          ; ENDCASE's logic.

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

CCALL:   LDX   CODEHERE   ; BUG FIX: was PULU D first, then LDA #OPJSR -
         LDA   #OPJSR     ; but A is D's high byte, so that LDA silently
         STA   ,X+        ; destroyed the top byte of the address PULU D
         PULU  D          ; had just pulled, and the STD below wrote out
         STD   ,X++       ; the corrupted result - a JSR to a garbage
                          ; target address. Deferring PULU D until after
                          ; STA ,X+ means D is never live at the same time
                          ; A gets reused for the opcode, so nothing
                          ; clobbers it. Confirmed via MAME debugger:
                          ; execution jumped to random memory.
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
            LDD  CODEHERE  ; BUG FIX: same class as SQUOTE/DOTQUOTE -
            ADDD #3        ; reserve 3 bytes ahead of WORD's write so
            STD  CODEHERE  ; the trampoline compiled below doesn't
                          ; overwrite the text it's about to stage.
            JSR  WORD
            PULU X
            LDA  ,X
            STA  SCNT
            LEAX 1,X
            STX  SPTR
            LDD  CODEHERE  ; restore
            SUBD #3
            STD  CODEHERE
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
         TSTA            ; BUG FIX: CLR MSIGN unconditionally sets N=0
                         ; (CLR always clears to 0), overwriting D's
                         ; own flags from the PULU above - and PULU
                         ; doesn't set flags on genuine 6809 anyway
                         ; (same class as TRYNUM/STOD/SIGN's own fixes
                         ; elsewhere in this file), so BPL was always
                         ; testing CLR's result, not n1's actual sign.
                         ; BPL always branched, meaning n1 was NEVER
                         ; negated even when genuinely negative - found
                         ; via MAME: TSTMSTAR's two returned values
                         ; came back wrong, which turned out to be
                         ; this, not a push-order swap in the test
                         ; itself. FMSLASHMOD/SMSLASHREM already do
                         ; this correctly (explicit TST PRODHI between
                         ; their own CLR calls and the branch) - MSTAR
                         ; was simply missing the equivalent re-test.
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
         TSTA          ; BUG FIX: was a bare "BPL SDPOS" right after
                         ; PULU - PULU doesn't affect condition codes
                         ; on genuine 6809 (same class as TRYNUM's own
                         ; PULU-then-compare fix elsewhere in this
                         ; file), so BPL was testing whatever flags an
                         ; unrelated, earlier instruction happened to
                         ; leave set, not the sign of the value just
                         ; popped. TSTA explicitly tests D's high byte
                         ; (bit 7 of A reflects the full 16-bit value's
                         ; sign) immediately before the branch that
                         ; depends on it. Confirmed via MAME debugger:
                         ; "-123 S>D" returned high cell 0 instead of
                         ; -1 - no sign extension was happening at all.
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

DFETCH:  PULU  X          ; BUG FIX: was reading high address first
         LDD   ,X         ; (pushed deep) then low address second
         PSHU  D          ; (pushed on top) - the reverse of what
         LDD   2,X        ; DSTORE actually writes (x1 low, x2 high),
         PSHU  D          ; so a 2! 2@ round trip swapped the two
         RTS              ; values. Now reads low first (x1, pushed
                          ; deep) then high second (x2, pushed on
                          ; top), matching DSTORE and correctly
                          ; round-tripping. Flagged by the parallel
                          ; 68000 port, confirmed by inspection.

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
         SUBD  #1         ; BUG FIX: was after the byte copy below -
         STD   MVCNT      ; LDA ,X+ (needed for the byte itself)
                          ; clobbers A, D's high byte, corrupting the
                          ; count before SUBD used it. Unlike FILL,
                          ; there's no spare 16-bit register to keep
                          ; the count in instead - X and Y are both
                          ; already committed to the source and
                          ; destination addresses - so the fix here is
                          ; reordering: decrement and store while D
                          ; still holds the true count, before the
                          ; copy is free to clobber A. Confirmed via
                          ; MAME debugger: the loop never terminated.
         LDA   ,X+
         STA   ,Y+
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
         TFR   D,Y        ; BUG FIX: was STD FILLCNT/LDD FILLCNT each
                          ; iteration - and inside the loop, LDA
                          ; FILLCHR (needed for the fill byte) clobbers
                          ; A, which is D's high byte, corrupting the
                          ; count that SUBD #1 then decremented from.
                          ; The high byte took on the fill character's
                          ; value instead of the count's real high
                          ; byte, so the count almost never reached
                          ; zero at the intended point - FILL ran far
                          ; past the requested length. Keeping the
                          ; count in Y instead removes the conflict
                          ; entirely (Y is untouched by loading the
                          ; fill character into A) and removes the
                          ; per-iteration memory round-trip - also
                          ; addresses the redundant scratch usage
                          ; flagged alongside this bug. Confirmed via
                          ; MAME debugger.
         PULU  D
         TFR   D,X        ; address, kept directly in X rather than
                          ; round-tripping through FILLADDR too
FILLOOP: CMPY  #0
         BEQ   FDONE
         LDA   FILLCHR
         STA   ,X+
         LEAY  -1,Y
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
         LDD   CODEHERE   ; BUG FIX (caught while verifying the WORD
         ADDD  #3         ; redesign above): reserve 3 bytes ahead of
         STD   CODEHERE   ; where WORD is about to write its parsed
                          ; text. Without this, the compiled path
                          ; below would compile "JSR DOSTR" (3 bytes)
                          ; directly at CODEHERE - the same address
                          ; WORD just used - overwriting the first 2
                          ; characters of the very text being staged,
                          ; before the copy loop even runs. Reserving
                          ; the gap first means the text lands exactly
                          ; where it needs to end up, and the trampoline
                          ; safely goes in front of it instead of on
                          ; top of it.
         JSR   WORD
         PULU  X
         LDA   ,X
         STA   SCNT
         LEAX  1,X
         STX   SPTR
         LDD   CODEHERE   ; restore - undo the temporary reserve
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
SQCPY:   LDA   ,Y+
         STA   ,X+
         DECB
         BNE   SQCPY
SQEND:   STX   CODEHERE
         RTS

SQINTERP: ; REDESIGN: was a fixed "LDX #SIBUF" here and at SQIEND -
                          ; SIBUF was a dedicated, fixed 32-byte buffer,
                          ; capping every interpreted S" string at 32
                          ; characters and (worse) shared identically
                          ; by every S" call, so a second S" call before
                          ; the first string was actually used (e.g.
                          ; registering two REPLACES strings, or a
                          ; SUBSTITUTE template argument) silently
                          ; overwrote the first - confirmed via MAME
                          ; testing and traced precisely earlier this
                          ; session. Retired per user's own follow-up
                          ; testing/design decision: rather than give
                          ; REPLACES its own dedicated copy-on-register
                          ; storage, wrap each string in its own colon
                          ; definition for stable storage instead - but
                          ; that still leaves interpreted S" itself
                          ; capped at SIBUF's 32 characters for any
                          ; single string. Now computes PAD's current
                          ; address fresh via PADW (dynamic - depends
                          ; on CODEHERE, per ANS's own transient-region
                          ; semantics) and writes there instead, giving
                          ; interpreted S" access to PAD's full
                          ; PADMINSIZE-character region (84, comfortably
                          ; above the old 32-character SIBUF limit) -
                          ; SIBUF itself is now unused and retired (see
                          ; the GLOBALS layout notes above).
          JSR  PADW
          PULU X
          STX  MSCR4        ; save PAD's own address - X gets advanced
                             ; by the copy loop below, need the
                             ; original back for the return value
          LDY  SPTR
          LDB  SCNT
          BEQ  SQIEND
SQICPY:   LDA  ,Y+
          STA  ,X+
          DECB
          BNE  SQICPY
SQIEND:   LDX  MSCR4
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
          LDD  CODEHERE   ; BUG FIX: same class as SQUOTE above -
          ADDD #3         ; reserve 3 bytes ahead of WORD's write so
          STD  CODEHERE   ; the trampoline compiled below doesn't
                          ; overwrite the text it's about to stage.
          JSR  WORD
          PULU X
          LDA  ,X
          STA  SCNT
          LEAX 1,X
          STX  SPTR
          LDD  CODEHERE   ; restore
          SUBD #3
          STD  CODEHERE
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

UNESCAPEW: PULU D        ; BUG FIX: was PULU D/STD UESRCLEN (storing
           STD  UEDST     ; the popped dest-addr into the SOURCE-
                          ; length variable), then LDD ,U (a PEEK, not
                          ; a pop) into BOTH UEADDR and UEDST - so the
                          ; real source length was misread as an
                          ; address, the real source address was never
                          ; popped at all, and the true destination
                          ; address never reached UEDST. Correct
                          ; ANS order is ( c-addr1 u1 c-addr2 -- ):
                          ; c-addr2 (dest) is on top, popped first.
           PULU D         ; next: u1 (source length)
           STD  UESRCLEN
           PULU D         ; next: c-addr1 (source address)
           STD  UEADDR
           LDD  #0
           STD  UEOUTLEN
           LDX  UEADDR
           LDY  UEDST

           ; ALGORITHM REPLACED (caught by MAME testing after the
           ; argument-order fix above): the entire body below used
           ; to decode backslash escape sequences (\n, \t, \\, \") -
           ; a plausible-looking but entirely wrong reading of what
           ; ANS UNESCAPE does. Confirmed against the actual spec and
           ; its canonical reference implementation (forth-standard.
           ; org/standard/string/UNESCAPE and complang.tuwien.ac.at's
           ; ANS Forth reference text): UNESCAPE has nothing to do
           ; with backslash sequences at all - it replaces every '%'
           ; character with two '%' characters, and nothing else, so
           ; that a literal '%' in text survives an eventual
           ; SUBSTITUTE pass unchanged ("If you pass a string through
           ; UNESCAPE and then SUBSTITUTE, you get the original
           ; string"). Every character that ISN'T '%' passes straight
           ; through, one-for-one. Confirmed via MAME: doubling a
           ; single '%' wasn't happening at all, and the returned
           ; count didn't grow to reflect the added characters -
           ; both are direct, expected consequences of this being the
           ; wrong algorithm entirely, not a smaller bug within it.
UELOOP:    LDD  UESRCLEN
           BEQ  UEDONE
           LDA  ,X+
           CMPA #'%'
           BNE  UENOTPCT
           LDB  #'%'      ; write the extra '%' first - the character
           STB  ,Y+       ; itself still gets written once more below,
                          ; giving two '%' total for each one in the
                          ; source. Handles multiple '%' characters in
                          ; the same string correctly, since this runs
                          ; independently for each one the loop visits.
UENOTPCT:  STA  ,Y+       ; write the actual character - always, for
                          ; every character, '%' or not
           LDD  UESRCLEN
           SUBD #1
           STD  UESRCLEN
           BRA  UELOOP
UEDONE:    TFR  Y,D       ; BUG FIX: was "LDD UEOUTLEN / STD ,U" -
           SUBD UEDST     ; overwriting whatever was left on top of
           STD  UEOUTLEN  ; the stack rather than pushing both
                          ; required return values, and separately,
                          ; UEOUTLEN itself was never correctly
                          ; tracked by the old backslash-decoding
                          ; loop's own per-character bookkeeping in a
                          ; way that accounted for doubled '%'
                          ; characters. Now computed directly as the
                          ; final write pointer (Y) minus the
                          ; original destination address (UEDST) -
                          ; correct regardless of how many characters
                          ; were doubled, since it's derived from
                          ; where writing actually stopped rather than
                          ; incremented alongside it.
           LDD  UEDST
           PSHU D         ; push c-addr2 (destination address)
           LDD  UEOUTLEN
           PSHU D         ; push u2 (actual unescaped length)
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

SUBSTITUTEW: ; REWRITE: was a plain substring search-and-replace on
             ; the bare registered name (via SEARCHW), which found
             ; "girl" and replaced only that span, leaving surrounding
             ; "%...%" delimiters untouched in the output - and never
             ; returned the substitution count ANS requires as a
             ; third stack item. Per the ANS spec (forth-standard.org/
             ; standard/string/SUBSTITUTE), SUBSTITUTE must scan for
             ; text between '%' (ASCII $25) delimiter pairs
             ; specifically: "%%" collapses to a single '%' (count
             ; unchanged); a name matching the REPLACES registration
             ; has the ENTIRE "%name%" span - delimiters included -
             ; replaced by the substitution text (count incremented);
             ; a non-matching name is passed through unchanged,
             ; delimiters and all (count unchanged); an unpaired
             ; trailing '%' with no closing delimiter passes the
             ; residue through unchanged. Confirmed via MAME testing
             ; against a real template. GLOBALS is fully packed
             ; (256/256), so this reuses MSCR/MSCR2/MSCR3/MSCR4
             ; (confirmed untouched by SUBCOPY) rather than adding
             ; dedicated cells: MSCR = current read position, MSCR2 =
             ; running substitution count, MSCR3/MSCR4 = local scratch
             ; per %-pair found. Reuses the existing COMPAREW for name
             ; matching rather than a new comparison loop.
             PULU D
             STD  SUBDESTCAP
             PULU D
             STD  SUBDESTADR
             PULU D
             STD  SUBSRCLEN
             PULU D
             STD  SUBSRCADR

             LDY  SUBDESTADR
             STY  SUBWPTR
             LDD  #0
             STD  SUBOUTLEN
             STD  MSCR        ; read position, starts at 0
             STD  MSCR2       ; substitution count, starts at 0

SUBSCAN:     LDD  MSCR
             CMPD SUBSRCLEN
             LBHS SUBSDONE
             LDX  SUBSRCADR
             LEAX D,X
             LDA  ,X
             CMPA #$25         ; '%' delimiter
             BEQ  SUBPCT
             LDD  #1
             JSR  SUBCOPY
             LDD  MSCR
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBPCT:      LDD  MSCR
             ADDD #1
             STD  MSCR3        ; scan for the closing '%'
SUBFINDCL:   LDD  MSCR3
             CMPD SUBSRCLEN
             BLO  SUBFC2
             ; no closing delimiter found - residue passed unchanged
             LDD  MSCR
             LDX  SUBSRCADR
             LEAX D,X
             LDD  SUBSRCLEN
             SUBD MSCR
             JSR  SUBCOPY
             LDD  SUBSRCLEN
             STD  MSCR
             LBRA SUBSCAN
SUBFC2:      LDD  MSCR3
             LDX  SUBSRCADR
             LEAX D,X
             LDA  ,X
             CMPA #$25
             BEQ  SUBFOUNDCL
             LDD  MSCR3
             ADDD #1
             STD  MSCR3
             LBRA SUBFINDCL

SUBFOUNDCL:  LDD  MSCR3
             SUBD MSCR
             SUBD #1
             STD  MSCR4         ; enclosed name length
             LBNE SUBHASNAME
             ; namelen 0: "%%" -> single '%' to output, count unchanged
             LDD  MSCR
             LDX  SUBSRCADR
             LEAX D,X
             LDD  #1
             JSR  SUBCOPY
             LDD  MSCR3
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBHASNAME:  LDD  MSCR
             ADDD #1
             LDX  SUBSRCADR
             LEAX D,X
             PSHU X
             LDD  MSCR4
             PSHU D
             LDD  REPLNAME
             PSHU D
             LDD  REPLNLEN
             PSHU D
             JSR  COMPAREW
             PULU D
             CMPD #0
             BNE  SUBNOMATCH
             ; valid name - replace the whole %name% span
             LDX  REPLVAL
             LDD  REPLVLEN
             JSR  SUBCOPY
             LDD  MSCR2
             ADDD #1
             STD  MSCR2
             LDD  MSCR3
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBNOMATCH:  ; not a registered name - pass %name% through unchanged
             LDD  MSCR
             LDX  SUBSRCADR
             LEAX D,X
             LDD  MSCR3
             SUBD MSCR
             ADDD #1
             JSR  SUBCOPY
             LDD  MSCR3
             ADDD #1
             STD  MSCR
             LBRA SUBSCAN

SUBSDONE:    LDX  SUBDESTADR
             PSHU X
             LDD  SUBOUTLEN
             PSHU D
             LDD  MSCR2
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
         PULU  D      ; BUG FIX: WORD always pushes a c-addr at the
                       ; end (the parsed text's address), which this
                       ; word never consumed - "(" only needs WORD's
                       ; side effect of advancing >IN past the closing
                       ; delimiter, not the address itself, but that
                       ; address was left stranded on the stack every
                       ; time. Explains both reported symptoms: a
                       ; stray value visible after a comment in
                       ; interpret mode, and a CSP mismatch (-22) for
                       ; any colon definition containing one, since
                       ; the leftover throws off the compile-time
                       ; stack-depth check between ":" and ";".
                       ; Confirmed via MAME debugger.
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

; ENVIRONMENT? - dispatcher complete; table has entries derived
; without fabricating unfixed capacities. /HOLD and /PAD were both
; added this session, answering HOLDMINSIZE and PADMINSIZE
; respectively (see each entry itself, below, for why each uses its
; own, conceptually correct constant rather than the numerically-
; equal PADOFFSET).
;
; WORDLISTS (16.3.2, Search-Order word set) is deliberately absent
; from ENVTABLE, not an oversight - this system doesn't implement
; the Search-Order word set, so WORDLISTS is genuinely an unknown
; attribute here. Per ENVIRONMENT?'s own spec (6.1.1345): "If the
; system treats the attribute as unknown, the returned flag is
; false" - falling through to ENVNOTFOUND already produces exactly
; that, correctly and completely, with no dispatcher work needed.
; Confirmed via MAME testing.
;
; MAX-D/MAX-UD were resolved this session via a genuine dispatcher
; extension, not just a table entry - both are double-cell values
; per their own ANS data type, which the original single-cell
; ENVFOUND (pushing exactly one value before TRUE) couldn't
; represent. Added a second table (ENVTABLE2) and matching loop
; (ENV2START/ENV2LOOP/ENV2FOUND, below) specifically for double-cell
; entries, rather than reworking the single-cell path to handle both
; shapes - see those labels for the full design.
;
; FLOORED was the third, separate open item flagged previously -
; investigated this session by tracing DIVCOMMON (shared by /, MOD,
; /MOD) against this system's own SM/REM and FM/MOD. Confirmed
; DIVCOMMON matches SM/REM's convention exactly (remainder sign
; restored from the dividend's own original sign, not the quotient's)
; - this system's primary division words use symmetric division, not
; floored. FLOORED now answers 0 (false) - see the entry itself,
; below, for the full trace.
ENVQUERY: PULU D
          STD  ENVLEN
          PULU D
          STD  ENVADDR
          LDX  #ENVTABLE
ENVLOOP:  LDD  ,X
          CMPD #0
          BEQ  ENV2START  ; CHANGED: was BEQ ENVNOTFOUND - now tries
                            ; the double-cell table (below) before
                            ; giving up entirely. See ENV2START/
                            ; ENV2LOOP for MAX-D/MAX-UD, added this
                            ; turn - both are double-cell values per
                            ; their own ANS data type, which this
                            ; single-cell table's ENVFOUND (pushing
                            ; exactly one value before TRUE) can't
                            ; represent correctly.
          PSHS X          ; BUG FIX: COMPAREW uses X as its own
                            ; internal scratch (LDX CMPA1, then LDA
                            ; ,X+ advancing through the comparison),
                            ; clobbering whatever the caller had there.
                            ; ENVQUERY needs X to still point at the
                            ; current table entry after COMPAREW
                            ; returns, both for ENVFOUND's own LDD 4,X
                            ; and for advancing to the next entry -
                            ; without saving it first, a successful
                            ; match left X sitting just past the
                            ; matched string's own text (for
                            ; "/COUNTED-STRING", 15 characters, that
                            ; lands exactly at the start of the next
                            ; entry's string, "MAX-N") - so ENVFOUND
                            ; read the "value" field from inside the
                            ; NEXT entry's own string text instead of
                            ; the real value. Confirmed via MAME: this
                            ; exact mechanism produces $4E4D precisely
                            ; - the bytes 'N' ($4E) and 'M' ($4D, the
                            ; start of "MAX-U") sitting 4 bytes into
                            ; "MAX-N", read as one cell.
          PSHU D
          LDD  2,X
          PSHU D
          LDD  ENVADDR
          PSHU D
          LDD  ENVLEN
          PSHU D
          JSR  COMPAREW
          PULS X          ; restore X before using it again
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

ENV2START: LDX  #ENVTABLE2  ; NEW: double-cell query table - kept
                            ; entirely separate from ENVTABLE above
                            ; rather than trying to unify both cases
                            ; into one mechanism, since the two
                            ; genuinely differ in entry size (8 bytes
                            ; here, vs 6 for single-cell) and in how
                            ; many cells a match pushes (two, not
                            ; one) - lower risk than reworking the
                            ; already-tested single-cell path to
                            ; handle both shapes at once.
ENV2LOOP: LDD  ,X
          CMPD #0
          BEQ  ENVNOTFOUND
          PSHS X          ; same COMPAREW X-clobber concern as above
          PSHU D
          LDD  2,X
          PSHU D
          LDD  ENVADDR
          PSHU D
          LDD  ENVLEN
          PSHU D
          JSR  COMPAREW
          PULS X
          PULU D
          CMPD #0
          BEQ  ENV2FOUND
          LEAX 8,X        ; entries are 8 bytes here (ADDR,LEN,LOW,
                            ; HIGH), not 6 (ADDR,LEN,VALUE)
          BRA  ENV2LOOP
ENV2FOUND: LDD  4,X       ; low cell - pushed first/deep, matching
           PSHU D          ; standard double-cell stack order (3.1.4.1:
                            ; the cell containing the most significant
                            ; part shall be above the cell containing
                            ; the least significant part)
           LDD  6,X        ; high cell - pushed second/top
           PSHU D
           LDD  #TRUEV
           PSHU D
           RTS

ENVNOTFOUND: LDD #FALSEV
             PSHU D
             RTS

ENVTABLE2:
         FDB   EN11,EN11L,$FFFF,$7FFF  ; MAX-D: maximum signed
                             ; double-cell value, $7FFFFFFF - low
                             ; cell $FFFF, high cell $7FFF (the
                             ; maximum positive 16-bit signed value in
                             ; the high cell, matching how a 32-bit
                             ; two's-complement maximum is laid out:
                             ; all bits set except the sign bit of the
                             ; most significant cell).
         FDB   EN12,EN12L,$FFFF,$FFFF  ; MAX-UD: maximum unsigned
                             ; double-cell value, $FFFFFFFF - both
                             ; cells all bits set.
         FDB   0
EN11:    FCC   "MAX-D"
EN11L    EQU   *-EN11
EN12:    FCC   "MAX-UD"
EN12L    EQU   *-EN12

ENVTABLE:
         FDB   EN1,EN1L,255  ; BUG FIX: was 31 - the maximum size of a
                             ; counted string is bounded by its 1-byte
                             ; count field (0-255), not 31, which
                             ; looks like it was mistakenly copied from
                             ; an unrelated constraint (WORD's own,
                             ; separate scan cap in an earlier version
                             ; of this file). /COUNTED-STRING's own
                             ; meaning (forth-standard.org/standard/
                             ; usage#usage:env) is specifically the
                             ; count byte's own maximum value.
         FDB   EN2,EN2L,32767
         FDB   EN3,EN3L,65535
         FDB   EN6,EN6L,8
         FDB   EN7,EN7L,HOLDMINSIZE  ; NEW: /HOLD was previously absent
                             ; entirely (the top-of-file note calling
                             ; out "/HOLD and /PAD... remain explicitly
                             ; incomplete/absent" was accurate at the
                             ; time). Answers HOLDMINSIZE (34), not the
                             ; larger PADOFFSET (84) - HOLDMINSIZE is
                             ; specifically the portion of the
                             ; CODEHERE-to-PAD gap reserved for the
                             ; pictured numeric output buffer, the same
                             ; amount WORDMAXCHARS deliberately holds
                             ; back from WORD's own use at the other
                             ; end of that same shared gap. PADOFFSET
                             ; is the total gap width, most of which is
                             ; actually earmarked for WORD's own
                             ; parsing - reporting it here would
                             ; overstate what HOLD can safely use
                             ; without risking collision with whatever
                             ; WORD is doing in the same space.
         FDB   EN8,EN8L,PADMINSIZE  ; NEW: /PAD, the last of the two
                             ; entries the top-of-file note originally
                             ; flagged as absent - now both present.
                             ; Answers PADMINSIZE (84) directly, per
                             ; ANS's own /PAD meaning (3.3.3.6, "the
                             ; size of the scratch area whose address
                             ; is returned by PAD") - PAD's own region,
                             ; growing upward from PAD itself, distinct
                             ; from HOLDMINSIZE above (which answers
                             ; for a different region entirely, the
                             ; downward-growing pictured-numeric buffer
                             ; in the CODEHERE-to-PAD gap). PADOFFSET
                             ; happens to equal PADMINSIZE numerically
                             ; in this implementation (PADOFFSET EQU
                             ; PADMINSIZE), but /PAD is answered with
                             ; the conceptually correct constant, not
                             ; the coincidentally-equal one.
         FDB   EN9,EN9L,0    ; NEW: FLOORED - previously the one item
                             ; in this area explicitly left open
                             ; pending its own investigation (unlike
                             ; WORDLISTS, this is a CORE query, not
                             ; tied to an unimplemented optional word
                             ; set, so "false by omission" wasn't the
                             ; right default). Investigated by tracing
                             ; DIVCOMMON (shared by /, MOD, /MOD)
                             ; against this system's own SM/REM and
                             ; FM/MOD: DIVCOMMON restores the
                             ; remainder's sign from DNSIGN (the
                             ; dividend's own original sign) after
                             ; dividing absolute values - exactly
                             ; SM/REM's own logic, confirmed identical
                             ; by direct comparison. FM/MOD, by
                             ; contrast, has an explicit flooring
                             ; adjustment step (correcting the
                             ; quotient and remainder when the
                             ; quotient would be negative with a
                             ; nonzero remainder) that DIVCOMMON does
                             ; not have. This system's primary
                             ; division words (/, MOD, /MOD) use
                             ; symmetric division, not floored -
                             ; FLOORED is 0 (false), a real, meaningful
                             ; answer (recognized query, value false),
                             ; not the "unrecognized" fallthrough
                             ; WORDLISTS correctly uses.
         FDB   EN10,EN10L,255  ; NEW: MAX-CHAR - maximum value of any
                             ; character in this implementation's
                             ; character set (3.2.6). This system uses
                             ; 8-bit characters throughout (matching
                             ; ADDRESS-UNIT-BITS=8, already in this
                             ; table) - a single byte's maximum value
                             ; is 255.
         FDB   EN13,EN13L,(RSTACK-DSTACK)/2  ; NEW: RETURN-STACK-
                             ; CELLS - computed from this system's own
                             ; stack region boundaries rather than
                             ; hardcoded, so this stays correct if the
                             ; memory map shifts again (it has
                             ; repeatedly this session). RSTACK's own
                             ; comment confirms the occupied range is
                             ; $BD00-RSTACK (768 bytes currently) -
                             ; DSTACK+1 is $BD00 exactly (the two
                             ; regions are contiguous, per RSTACK's
                             ; and DSTACK's own comments). Since
                             ; RSTACK-(DSTACK+1)+1 simplifies to
                             ; RSTACK-DSTACK (the +1/-1 cancel), the
                             ; simpler form is used directly: 384
                             ; currently.
         FDB   EN14,EN14L,(DSTACK-CODETOP+1)/2  ; NEW: STACK-CELLS -
                             ; same reasoning, for the data stack's own
                             ; region (CODETOP to DSTACK, 1024 bytes
                             ; currently, matching CODETOP's own
                             ; comment "code space ceiling (data stack
                             ; begins here)"): 512 currently.
         FDB   0
EN1:     FCC   "/COUNTED-STRING"
EN1L     EQU   *-EN1
EN2:     FCC   "MAX-N"
EN2L     EQU   *-EN2
EN3:     FCC   "MAX-U"
EN3L     EQU   *-EN3
EN6:     FCC   "ADDRESS-UNIT-BITS"
EN6L     EQU   *-EN6
EN7:     FCC   "/HOLD"
EN7L     EQU   *-EN7
EN8:     FCC   "/PAD"
EN8L     EQU   *-EN8
EN9:     FCC   "FLOORED"
EN9L     EQU   *-EN9
EN10:    FCC   "MAX-CHAR"
EN10L    EQU   *-EN10
EN13:    FCC   "RETURN-STACK-CELLS"
EN13L    EQU   *-EN13
EN14:    FCC   "STACK-CELLS"
EN14L    EQU   *-EN14

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
         STB   MSCR      ; BUG FIX: STB writes ONE byte, at MSCR
         LDB   MSCR      ; itself - both reads below used to read
         LSRB             ; MSCR+1 instead, a byte this routine never
         LSRB             ; writes at all, so both the high and low
         LSRB             ; nibble extraction ran on whatever stale
         LSRB             ; value happened to be sitting there, not
         CLRA             ; the byte actually passed in. Now reads
         PSHU  D           ; from MSCR, where STB actually put it.
         JSR   HEXDIGIT    ; Confirmed via MAME debugger: DUMP showed
         LDB   MSCR        ; $03 instead of $7B for a memory fill
         ANDB  #$0F        ; character, with the ASCII column (a
         CLRA              ; separate code path) correctly showing
         PSHU  D           ; "}".
         JSR   HEXDIGIT
         RTS

; DUMP - includes the partial-final-line ASCII fix
DUMPW:   PULU  D
         STD   DUMPCNT
         PULU  D
         STD   DUMPADDR
         JSR   CRW        ; FORMATTING: leading CR, so the first line
                          ; starts on its own fresh line - matches
                          ; DULEND's existing trailing CR after every
                          ; line (including the last), giving
                          ; consistent vertical alignment from the
                          ; first line to the last regardless of
                          ; where the cursor was when DUMP was called.
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
; SECTION 26: TRUE / FALSE. This section used to also hold
; ABORT/QUIT's hand-built dictionary headers (ABORTHDR/QUITHDR) -
; moved into BASEDICT and renamed to H_ABORT/H_QUIT (see the end
; of SECTION 27) so every header in this ROM lives in one
; contiguous block, rather than header data sitting apart from
; the rest of the dictionary inside BASECODE.
; ============================================================
; ------------------------------------------------------------
; TRUE / FALSE - simple subroutines, not the CONSTANT/DODOES
; pattern these used before (JSR DODOES + FDB ATSIGN + a value
; cell, matching what interactive CONSTANT compiles). Each is now
; a direct LDD/PSHU/RTS, like every other ordinary ROM word's CFA
; - no indirection, no value cell.
;
; RESOLVED: the previous version of this code deliberately inverted
; TRUE/FALSE's values from the system's own convention, per an
; earlier explicit request - FALSE pushed $FFFF and TRUE pushed
; $0000, disagreeing with TRUEV/FALSEV ($FFFF/$0000) and every
; comparison operator (=, <, >, and the rest), which all still
; returned TRUEV for a true result and FALSEV for false. Restored
; to the standard convention now: TRUE pushes $FFFF, FALSE pushes
; $0000, matching TRUEV/FALSEV and every comparison operator again.
; Each is a direct LDD/PSHU/RTS, like every other ordinary ROM
; word's CFA - no indirection, no value cell, no DODOES trampoline.
; ------------------------------------------------------------
TRUEBODY:  LDD   #$FFFF
           PSHU  D
           RTS

FALSEBODY: LDD   #$0000
           PSHU  D
           RTS

; ------------------------------------------------------------
; 1 / -1 / 2 / -2 - simple immediate-value words, same pattern as
; TRUE/FALSE above: direct LDD/PSHU/RTS, no indirection, no value
; cell. Headers are H_1/H_M1/H_2/H_M2 (SECTION 27, chained after
; H_FIND) - "1"/"-1"/"2"/"-2" aren't valid 6809 assembler labels.
; ------------------------------------------------------------
ONEBODY:   LDD   #1
           PSHU  D
           RTS

MONEBODY:  LDD   #-1
           PSHU  D
           RTS

TWOBODY:   LDD   #2
           PSHU  D
           RTS

MTWOBODY:  LDD   #-2
           PSHU  D
           RTS

; Verify no collision with init code,
; value should match ORG INITCODE.
BASECODEEND  EQU   *
BASECODESIZE EQU   BASECODEEND-BASECODE

; Prevent the assembler from extinguishing the gap between the
; BASECODE block and the INITCODE block when it generates the
; .bin file.
BASEND:
         FILL $FF,INITCODE-BASEND

; ============================================================
; SECTION 2: INIT CODE (COLDSTRT / WARM)
; ============================================================
         ORG   INITCODE       ; INITCODE is $FFA9 (was $FFA2, before that $FFA0, before that literal $FFC0)
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

         JSR   INITSERIAL

         IFNE  UNITTESTS  ; >>>>>>>>>>
         JSR   TSTRUNNER
         ELSE  ; <<<<<>>>>>
         NOP             ; BUG FIX (see the historical note above this
         NOP             ; call site's own comment, describing the
         NOP             ; original bug): this call site used to emit
                         ; 0 bytes when UNITTESTS' flag meaning
                         ; excluded the test framework, meaning
                         ; COLDSTRT's own size varied by 3 bytes
                         ; depending on UNITTESTS - with INITCODE's
                         ; own position fixed regardless, that risked
                         ; the code overflowing into VECTORS whenever
                         ; UNITTESTS was toggled on. Three NOPs here
                         ; are byte-for-byte the same size as the
                         ; JSR TSTRUNNER they replace, so this block
                         ; now always contributes exactly 3 bytes to
                         ; COLDSTRT either way - COLDSTRT's total size
                         ; no longer depends on UNITTESTS at all.
         ENDC  ; <<<<<<<<<<

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
; END OF CONSOLIDATED SOURCE
; ============================================================
