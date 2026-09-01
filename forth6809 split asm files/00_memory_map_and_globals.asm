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
OPRTS    EQU  $39      ; used by section 3.8's control-flow test
                         ; harness to terminate each compiled test
                         ; snippet, compiled via CCOMMA
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

TSTCBUF  EQU   APPVARS+10    ; compile-time test harness (section 3.8,
                              ; control flow): scratch buffer real
                              ; compile-time words (IF/THEN/DO/LOOP/
                              ; etc) actually compile into - CODEHERE
                              ; is redirected here for the duration of
                              ; each compile, then restored, so the
                              ; real ROM/dictionary is never touched.
                              ; 80 bytes - generous headroom for the
                              ; small test snippets planned (the
                              ; largest, CASE with two OF clauses,
                              ; comes nowhere close)
TSTCSAV  EQU   APPVARS+90    ; saved CODEHERE, across a redirected
                              ; compile
TSTCSPS  EQU   APPVARS+92    ; saved CSP, across a redirected compile -
                              ; EXIT's own frame-counting scan depends
                              ; on CSP marking the right baseline
TSTLSAV  EQU   APPVARS+94    ; saved LATEST, across a RECURSE test
                              ; (which reads LATEST directly)
TSTFHDR  EQU   APPVARS+96    ; fake dictionary header, for RECURSE to
                              ; read via a redirected LATEST - 16
                              ; bytes (LEN/FL + name + LINK + CFA,
                              ; comfortably fits any short test name)

TSTDBUF  EQU   APPVARS+112   ; defining-words test harness (section
                              ; 3.9): scratch dictionary buffer -
                              ; DPHERE is redirected here for the
                              ; duration of each defining-word call,
                              ; so a real header never lands in the
                              ; real dictionary. 40 bytes.
TSTDSAV  EQU   APPVARS+152   ; saved DPHERE
TSTVBUF  EQU   APPVARS+154   ; scratch VARHERE buffer, for VARIABLE/
                              ; VALUE/2VARIABLE/BUFFER: to reserve
                              ; their own mutable space into. 20
                              ; bytes.
TSTVSAV  EQU   APPVARS+174   ; saved VARHERE
TSTNAMEB EQU   APPVARS+176   ; scratch fake source text, for HEADER's
                              ; own WORD-based name parsing (every
                              ; defining word reads a name from the
                              ; input source - unlike anything in
                              ; section 3.8) - 16 bytes
TSTSASAV EQU   APPVARS+192   ; saved SRCADDR
TSTSLSAV EQU   APPVARS+194   ; saved SRCLEN
TSTTISAV EQU   APPVARS+196   ; saved TOIN
TSTWCFA  EQU   APPVARS+198   ; the newly-defined test word's own CFA -
                              ; equal to CODEHERE (redirected) at the
                              ; moment the defining word is called,
                              ; saved so the compiled trampoline can
                              ; be executed afterward to verify its
                              ; runtime behavior
TSTSTSAV EQU   APPVARS+200   ; saved STATE, across a :/; test
TSTSMFLG EQU   APPVARS+202   ; scratch: header SMUDGE-bit check result
TSTDOESA EQU   APPVARS+204   ; address of a compiled "JSR SETDOES" -
                              ; JSR'd directly to simulate an outer
                              ; defining word reaching that point,
                              ; without needing to actually build one
TSTCSAV2 EQU   APPVARS+212   ; MARKER test: CODEHERE right after
                              ; executing the marker word (before it's
                              ; overwritten by this test's own restore)
TSTDSAV2 EQU   APPVARS+214   ; same, DPHERE
TSTVSAV2 EQU   APPVARS+216   ; same, VARHERE
TSTLSAV2 EQU   APPVARS+218   ; same, LATEST
TSTCBUF2 EQU   APPVARS+220   ; a SECOND, separate CODEHERE-redirect
                              ; target - real bug found via MAME: WORD
                              ; writes its parsed-token output directly
                              ; at CODEHERE (by its own documented
                              ; design, matching the ANS transient-
                              ; region contract - confirmed by reading
                              ; WORD's own code, not assumed). Any test
                              ; that parses a SECOND name later (TO,
                              ; IS, ACTION-OF) must NOT redirect
                              ; CODEHERE back to TSTCBUF for that
                              ; second parse, since TSTCBUF still holds
                              ; the FIRST word's already-compiled
                              ; trampoline at that point - WORD would
                              ; silently overwrite it, corrupting the
                              ; CFA that TSTWCFA still points to before
                              ; it gets a second chance to execute. 20
                              ; bytes - comfortably fits any short
                              ; parsed name plus its length byte.
TSTUMID  EQU   APPVARS+240   ; intermediate U capture (section 3.3,
                              ; return stack): >R/2>R tests capture U
                              ; right after moving a value to the
                              ; return stack, before moving it back -
                              ; a round-trip-only check could pass even
                              ; if both the move-out and move-back were
                              ; broken no-ops, since the value would
                              ; never have actually left; this catches
                              ; that specifically.

TSTOHSAV EQU   APPVARS+242   ; section 3.1 (System/Console I/O):
                              ; saves OUTHEAD (the output ring buffer's
                              ; write index) before an EMIT-family call,
                              ; so the test can confirm the character(s)
                              ; were genuinely queued into OUTBUF - not
                              ; just that the call returned without
                              ; crashing.

TSTBASAV EQU   APPVARS+243   ; section 3.13 (Numeric Output): saves the
                              ; real BASE across tests that do digit
                              ; conversion. Real bug found via MAME:
                              ; this whole test framework runs before
                              ; COLD (confirmed by tracing the boot
                              ; sequence directly - COLDSTRT clears all
                              ; of GLOBALS, including BASE, to zero,
                              ; then calls TSTRUNNER, with COLD's own
                              ; "BASE=10" initialization not running
                              ; until later) - so BASE reads as zero at
                              ; test time, not 10. With BASE=0,
                              ; UDDIGIT's own restoring-division
                              ; algorithm degrades into an unconditional
                              ; shift (the "subtract and check" step
                              ; never actually subtracts, since nothing
                              ; can compare below zero), so the value
                              ; being converted never genuinely
                              ; decreases - NUMSIGNS' own loop-until-
                              ; zero condition then never becomes true.
                              ; Every test in this section doing digit
                              ; conversion now explicitly saves BASE,
                              ; sets it to 10, and restores it
                              ; afterward - the same save/set/restore
                              ; pattern already established for
                              ; CODEHERE/STATE/SRCADDR etc throughout
                              ; this whole session, just not initially
                              ; applied to BASE since it was assumed
                              ; (incorrectly, for this specific,
                              ; pre-COLD execution context) to already
                              ; hold a valid value.

TSTHANDSAV EQU APPVARS+245   ; section 3.15 (Exception Handling): saves
                              ; the real HANDLER across a test verifying
                              ; CATCH correctly restores it afterward,
                              ; on both the success and throw paths -
                              ; confirmed via CATCH's own code that it
                              ; saves/restores HANDLER around every
                              ; call regardless of outcome, matching its
                              ; own documented "restores... HANDLER on
                              ; either path".

TSTSISAV EQU   APPVARS+247   ; section 3.17 (Environmental & System
                              ; Queries): saves the real SRCID across
                              ; TSTSOURCEID's and TSTREFILL's own tests,
                              ; both of which redirect SRCID directly.

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
TSTRUNNER: JSR   TSTSYSIO
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
; TSTSYSIO - System/Console I/O tests (glossary section 3.1, 12
; words, 7 tests). Six words are deliberately NOT tested here -
; KEY, ACCEPT, EXPECT, and QUERY all genuinely block on real
; input during automated, headless boot-time testing (confirmed
; by reading their own implementations: KEY spins on itself,
; ACCEPT calls KEY directly, EXPECT/QUERY both call ACCEPT); and
; ABORT/QUIT are both designed to never return (ABORT falls
; through into QUIT, which resets the return stack, discarding
; this entire call chain and hijacking the boot sequence into
; the interpreter's own top-level loop). See this group's own
; leading comment block, right before TSTKEYQ, for the full
; reasoning.
;
; EMIT/TYPE/CR/SPACE/SPACES are safe and already proven so - this
; whole test framework has used TYPE and CR (via TSTREPORT)
; thousands of times already across every prior test group.
; Each test here verifies the real queuing mechanism (OUTHEAD/
; OUTBUF), reading the actual character(s) back out of the
; output ring buffer to confirm they were genuinely queued, not
; just that the call returned without crashing.
; ------------------------------------------------------------
TSTSYSIO: JSR   CRW
           LDX   #TSTSYSIOMSG
           PSHU  X
           LDD   #5
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-0  ; >>>>

           JSR   TSTKEYQ
           JSR   TSTEMIT
           JSR   TSTCR
           JSR   TSTSPACE
           JSR   TSTSPACES
           JSR   TSTSPACESZ
           JSR   TSTTYPE

           ENDC ; <<<<

           RTS

TSTSYSIOMSG: FCC "SysIO"

           IFEQ TSTSELECTOR-0  ; >>>>

; ------------------------------------------------------------
; System/Console I/O test harness (glossary section 3.1). Half
; of this section's 12 words are deliberately NOT tested here,
; for reasons confirmed by reading their own implementations
; directly, not assumed from the glossary alone:
;
; KEY genuinely spins forever without real input (both its
; interrupt-driven and polled variants branch back to
; themselves - "BEQ KEY" - until a character arrives); ACCEPT
; calls KEY directly in its own main loop, and EXPECT/QUERY both
; call ACCEPT - all four inherit the same block. None of these
; can complete during automated, headless boot-time testing,
; where no real input will ever arrive.
;
; ABORT falls straight through into QUIT, which resets S to
; RP0 - discarding this entire call chain, including the path
; back to TSTRUNNER - and enters the interpreter's own top-level
; loop. Calling either directly would hijack the boot sequence
; entirely, not just fail one test.
;
; EMIT/TYPE/CR/SPACE/SPACES are safe and already proven so - this
; whole test framework has used TYPE and CR (via TSTREPORT)
; thousands of times already across every prior test group
; without incident. Each test here verifies the actual queuing
; mechanism (OUTHEAD/OUTBUF), not just "didn't crash" - reading
; the real character(s) back out of the output ring buffer to
; confirm they were genuinely queued, not just that the call
; returned.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTKEYQ - unit test for KEY?. With no real input pending
; during automated boot-time testing, expects FALSE - the
; normal, expected case for this kind of test run.
; ------------------------------------------------------------
TSTKEYQ: STU   TSTU0

         LDD   #TSTGUARD
         PSHU  D
         STU   TSTUB4

         JSR   KEYQ

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
KYFAIL: LDD   #FALSEV
KYDONE: LDX   #TSTKEYQNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTKEYQNAME: FCB  7
             FCC  "TSTKEYQ"

; ------------------------------------------------------------
; TSTEMIT - unit test for EMIT. Verifies the actual queuing
; mechanism: saves OUTHEAD before the call, then confirms it
; advanced by exactly one (wrapping correctly via OUTBUFSZ, a
; power of two) and that the queued byte at the old OUTHEAD
; position genuinely matches the character emitted - not just
; that the call returned.
; ------------------------------------------------------------
TSTEMIT: STU   TSTU0

         LDD   #TSTGUARD
         PSHU  D
         LDD   #65
         PSHU  D
         STU   TSTUB4

         JSR   EMIT

         STU   TSTUAF

         LDA   EMITCH  ; BUG FIX: was checking OUTHEAD/OUTBUF, assuming
                        ; the interrupt-driven EMIT (SERIALPOLL=0). Real
                        ; bug found via MAME: EMIT has two entirely
                        ; different implementations, gated the same way
                        ; as KEY's own two variants - the polling one
                        ; (SERIALPOLL=1, confirmed the currently active
                        ; build) writes directly to ACIADR and never
                        ; touches OUTHEAD/OUTBUF at all, so that check
                        ; always failed despite the character genuinely
                        ; being transmitted (confirmed in the terminal
                        ; output itself). EMITCH, by contrast, is set
                        ; unconditionally by both variants as their very
                        ; first step, before either mode-specific branch
                        ; - checking it verifies the argument was
                        ; correctly extracted from the stack regardless
                        ; of which EMIT variant is active, with no
                        ; conditional needed.
         CMPA  #65
         BNE   EMFAIL

         PULU  D
         CMPD  #TSTGUARD
         BNE   EMFAIL

         LDD   TSTUB4
         SUBD  TSTUAF
         CMPD  #-2
         BNE   EMFAIL

         LDD   #TRUEV
         BRA   EMDONE
EMFAIL:  LDD   #FALSEV
EMDONE:  LDX   #TSTEMITNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTEMITNAME: FCB  7
             FCC  "TSTEMIT"

; ------------------------------------------------------------
; TSTCR - unit test for CR. Verifies both queued bytes (13 then
; 10, CR then LF, matching the documented "CR then LF") land
; correctly in the output ring buffer, in order.
; ------------------------------------------------------------
TSTCR:   STU   TSTU0

         IFEQ SERIALPOLL  ; >>>>
         LDA   OUTHEAD
         STA   TSTOHSAV
         ENDC ; <<<<


         LDD   #TSTGUARD
         PSHU  D
         STU   TSTUB4

         JSR   CRW

         STU   TSTUAF

         IFEQ SERIALPOLL  ; >>>> full check: interrupt-driven EMIT
                          ; queues both bytes into OUTBUF, verifiable
                          ; in order
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
         ELSE  ; <<<<>>>> BUG FIX: was unconditionally checking OUTHEAD/
                          ; OUTBUF, assuming the interrupt-driven EMIT.
                          ; Real bug found via MAME: EMIT has two
                          ; entirely different implementations, gated
                          ; the same way as KEY's own two variants - the
                          ; polling one (SERIALPOLL=1, confirmed the
                          ; currently active build) writes directly to
                          ; ACIADR and never touches OUTHEAD/OUTBUF at
                          ; all, so this check always failed despite
                          ; both characters genuinely being transmitted
                          ; (confirmed in the terminal output itself).
                          ; EMITCH only reflects the LAST of the two
                          ; characters CRW emits (10, the LF) by the
                          ; time this runs, since each EMIT call
                          ; overwrites it - checking that plus the
                          ; depth check below is the most this variant
                          ; genuinely allows verifying; a direct
                          ; hardware write has no other inspectable,
                          ; persistent state.
         LDA   EMITCH
         CMPA  #10
         BNE   CRFAIL
         ENDC  ; <<<<<<<<<<

         PULU  D
         CMPD  #TSTGUARD
         BNE   CRFAIL

         LDD   TSTUB4
         SUBD  TSTUAF
         CMPD  #0
         BNE   CRFAIL

         LDD   #TRUEV
         BRA   CRDONE
CRFAIL: LDD   #FALSEV
CRDONE: LDX   #TSTCRNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTCRNAME: FCB  5
           FCC  "TSTCR"

; ------------------------------------------------------------
; TSTSPACE - unit test for SPACE. Verifies one space (32) is
; genuinely queued.
; ------------------------------------------------------------
TSTSPACE: STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          JSR  SPACEW

          STU  TSTUAF

          LDA  EMITCH  ; BUG FIX: was checking OUTHEAD/OUTBUF - same
                        ; fix and same reasoning as TSTEMIT's own fix
                        ; (see its comment). SPACEW calls EMIT
                        ; internally with a single character (32), so
                        ; EMITCH correctly reflects it regardless of
                        ; which EMIT variant is active.
          CMPA #32
          BNE  SCFAIL

          PULU D
          CMPD #TSTGUARD
          BNE  SCFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  SCFAIL

          LDD  #TRUEV
          BRA  SCDONE
SCFAIL:   LDD  #FALSEV
SCDONE:  LDX  #TSTSPACENAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTSPACENAME: FCB  8
              FCC  "TSTSPACE"

; ------------------------------------------------------------
; TSTSPACES - unit test for SPACES, normal (n=3) case. Verifies
; all three queued bytes are genuinely spaces (32), not just
; that OUTHEAD advanced by the right count.
; ------------------------------------------------------------
TSTSPACES: STU  TSTU0

           IFEQ SERIALPOLL  ; >>>>
           LDA  OUTHEAD
           STA  TSTOHSAV
           ENDC ; <<<<

           LDD  #TSTGUARD
           PSHU D
           LDD  #3
           PSHU D
           STU  TSTUB4

           JSR  SPACESW

           STU  TSTUAF

           IFEQ SERIALPOLL  ; >>>> full check: interrupt-driven EMIT
                            ; queues all three bytes into OUTBUF,
                            ; verifiable individually
           LDA  TSTOHSAV
           ADDA #3
           ANDA #OUTBUFSZ-1
           CMPA OUTHEAD
           BNE  SSFAIL

           LDX  #OUTBUF
           LDB  TSTOHSAV
           LDA  B,X
           CMPA #32
           BNE  SSFAIL
           INCB
           ANDB #OUTBUFSZ-1
           LDA  B,X
           CMPA #32
           BNE  SSFAIL
           INCB
           ANDB #OUTBUFSZ-1
           LDA  B,X
           CMPA #32
           BNE  SSFAIL
           ELSE  ; <<<<>>>> BUG FIX: was unconditionally checking
                            ; OUTHEAD/OUTBUF - same fix and reasoning as
                            ; TSTCR's own fix. In polling mode, EMITCH
                            ; only reflects the LAST of the three
                            ; identical spaces emitted, and there is no
                            ; persistent per-call count to verify
                            ; exactly three calls happened, not just
                            ; one or two - a genuine limitation of a
                            ; direct hardware write with no buffering,
                            ; not something this test can work around.
                            ; The depth check below still confirms n=3
                            ; was correctly consumed as an argument.
           LDA  EMITCH
           CMPA #32
           BNE  SSFAIL
           ENDC  ; <<<<<<<<<<

           PULU D
           CMPD #TSTGUARD
           BNE  SSFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #-2
           BNE  SSFAIL

           LDD  #TRUEV
           BRA  SSDONE
SSFAIL:    LDD  #FALSEV
SSDONE:    LDX  #TSTSPACESNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTSPACESNAME: FCB  9
               FCC  "TSTSPACES"

; ------------------------------------------------------------
; TSTSPACESZ - unit test for SPACES, n<=0 case. Documented
; behavior is "no output if n <= 0" - verifies OUTHEAD genuinely
; doesn't advance at all, not just that the call didn't crash.
; ------------------------------------------------------------
TSTSPACESZ: LDA  OUTHEAD
            STA  TSTOHSAV

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #0
            PSHU D
            STU  TSTUB4

            JSR  SPACESW

            STU  TSTUAF

            LDA  TSTOHSAV
            CMPA OUTHEAD
            BNE  S0FAIL

            PULU D
            CMPD #TSTGUARD
            BNE  S0FAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #-2
            BNE  S0FAIL

            LDD  #TRUEV
            BRA  S0DONE
S0FAIL:     LDD  #FALSEV
S0DONE:     LDX  #TSTSPACESZNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTSPACESZNAME: FCB  10
                FCC  "TSTSPACESZ"

; ------------------------------------------------------------
; TSTTYPE - unit test for TYPE. Writes a known 2-character
; string into scratch, calls TYPE on it, and verifies both
; queued bytes genuinely match the source string, in order -
; not just that OUTHEAD advanced by the right count.
; ------------------------------------------------------------
TSTTYPE: LDA   #'A'
         STA   TSTNAMEB
         LDA   #'B'
         STA   TSTNAMEB+1

         IFEQ SERIALPOLL  ; >>>>
         LDA   OUTHEAD
         STA   TSTOHSAV
         ENDC ; <<<<

         STU   TSTU0

         LDD   #TSTGUARD
         PSHU  D
         LDD   #TSTNAMEB
         PSHU  D
         LDD   #2
         PSHU  D
         STU   TSTUB4

         JSR   TYPE

         STU   TSTUAF

         IFEQ SERIALPOLL  ; >>>> full check: interrupt-driven EMIT
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
         ELSE  ; <<<<>>>> BUG FIX: was unconditionally checking OUTHEAD/
                          ; OUTBUF - same fix and reasoning as TSTCR's
                          ; own fix. EMITCH only reflects the LAST of
                          ; the two characters TYPE emits ('B') by the
                          ; time this runs; the depth check below still
                          ; confirms the addr/len arguments were
                          ; correctly consumed.
         LDA   EMITCH
         CMPA  #'B'
         BNE   TEFAIL
         ENDC  ; <<<<<<<<<<

         PULU  D
         CMPD  #TSTGUARD
         BNE   TEFAIL

         LDD   TSTUB4
         SUBD  TSTUAF
         CMPD  #-4
         BNE   TEFAIL

         LDD   #TRUEV
         BRA   TEDONE
TEFAIL:  LDD   #FALSEV
TEDONE:  LDX   #TSTTYPENAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTTYPENAME: FCB  7
             FCC  "TSTTYPE"

           ENDC ; <<<<

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

           IFEQ TSTSELECTOR-1  ; >>>>

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

           IFEQ TSTSELECTOR-1  ; >>>>

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
; TSTRETSTACK - return-stack tests (glossary section 3.3, 6
; words, 4 tests since >R/R> and 2>R/2R> are each combined into
; one round-trip test, matching how they can only be meaningfully
; tested together - the "must be balanced within the same
; definition" constraint each word's own glossary entry
; documents). Every >R/2>R in these tests is balanced by a
; matching R>/2R> before this group's own RTS - these words
; operate directly on the return stack, the same stack holding
; real subroutine return addresses, so leaving one unbalanced
; would corrupt the path back to whatever called this test.
;
; R@/2R@ tests specifically verify "non-destructive" for real:
; peek, then retrieve the original afterward and confirm it's
; still correct - not just that the peek itself returned the
; right value once.
; ------------------------------------------------------------
TSTRETSTACK: JSR CRW
           LDX   #TSTRETMSG
           PSHU  X
           LDD   #8
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-2  ; >>>>

           JSR   TSTTOR
           JSR   TSTRFETCH
           JSR   TSTTWOTOR
           JSR   TSTTWORFETCH

           ENDC ; <<<<

           RTS

TSTRETMSG: FCC "RetStack"

           IFEQ TSTSELECTOR-2  ; >>>>

; ------------------------------------------------------------
; Return-stack test harness (glossary section 3.3). Unlike
; every other test group in this file, these words operate
; directly on the return stack (S) - the same stack holding
; real subroutine return addresses, including this very test
; subroutine's own. Every >R/2>R is balanced by a matching
; R>/2R> within the same test body, before this test's own
; RTS - leaving one unbalanced would corrupt the return address
; needed to get back to TSTRUNNER (or whatever called it).
; Traced each word's own PULS/PSHS juggling by hand first to
; confirm this: >R/R>/2>R/2R> all temporarily lift the caller's
; own return address off S, do the actual move, then restore it
; on top - so the moved value ends up correctly nested one level
; inside the current subroutine's own return-stack frame,
; retrievable by a later R>/2R> in the same body, and cleanly
; gone by the time this test's own RTS runs.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTTOR - unit test for >R and R> together. Includes an
; intermediate check (right after >R, before R>) confirming the
; value genuinely left the data stack - a pure round-trip check
; could pass even if both words were broken no-ops, since the
; value would never actually have left.
; ------------------------------------------------------------
TSTTOR:  STU   TSTU0

         LDD   #TSTGUARD
         PSHU  D
         LDD   #TSTVAL1
         PSHU  D
         STU   TSTUB4

         JSR   TOR

         STU   TSTUMID

         LDD   TSTUB4
         SUBD  TSTUMID
         CMPD  #-2
         BNE   TRFAIL

         JSR   FROMR

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
TRFAIL:  LDD   #FALSEV
TRDONE:  LDX   #TSTTORNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTTORNAME: FCB  6
            FCC  "TSTTOR"

; ------------------------------------------------------------
; TSTRFETCH - unit test for R@. Moves a value to the return
; stack via >R, peeks it via R@ (verifying the copy matches),
; then retrieves the original via R> (verifying R@ genuinely
; left it there undisturbed, not just that R@ itself returned
; the right value once) - confirming "non-destructive" for real,
; not assumed from the name.
; ------------------------------------------------------------
TSTRFETCH: STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           LDD  #TSTVAL1
           PSHU D
           STU  TSTUB4

           JSR  TOR
           JSR  RFETCH
           JSR  FROMR

           STU  TSTUAF

           PULU D
           CMPD #TSTVAL1
           BNE  RFFAIL
           PULU D
           CMPD #TSTVAL1
           BNE  RFFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  RFFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #2
           BNE  RFFAIL

           LDD  #TRUEV
           BRA  RFDONE
RFFAIL:    LDD  #FALSEV
RFDONE:    LDX  #TSTRFETCHNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTRFETCHNAME: FCB  9
               FCC  "TSTRFETCH"

; ------------------------------------------------------------
; TSTTWOTOR - unit test for 2>R and 2R> together. Same
; intermediate-check reasoning as TSTTOR, applied to the pair -
; confirms both cells genuinely left the data stack before
; verifying the round trip.
; ------------------------------------------------------------
TSTTWOTOR: STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           LDD  #TSTVAL1
           PSHU D
           LDD  #TSTVAL2
           PSHU D
           STU  TSTUB4

           JSR  TWOTOR

           STU  TSTUMID

           LDD  TSTUB4
           SUBD TSTUMID
           CMPD #-4
           BNE  T2RFAIL

           JSR  TWOFROMR

           STU  TSTUAF

           PULU D
           CMPD #TSTVAL2
           BNE  T2RFAIL
           PULU D
           CMPD #TSTVAL1
           BNE  T2RFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  T2RFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  T2RFAIL

           LDD  #TRUEV
           BRA  T2RDONE
T2RFAIL:   LDD  #FALSEV
T2RDONE:   LDX  #TSTTWOTORNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTTWOTORNAME: FCB  9
               FCC  "TSTTWOTOR"

; ------------------------------------------------------------
; TSTTWORFETCH - unit test for 2R@. Same reasoning as
; TSTRFETCH, applied to the pair: moves x1,x2 to the return
; stack via 2>R, peeks via 2R@ (verifying both cells, correctly
; ordered), then retrieves the originals via 2R> (verifying 2R@
; genuinely left them there undisturbed).
; ------------------------------------------------------------
TSTTWORFETCH: STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              LDD  #TSTVAL1
              PSHU D
              LDD  #TSTVAL2
              PSHU D
              STU  TSTUB4

              JSR  TWOTOR
              JSR  TWORFETCH
              JSR  TWOFROMR

              STU  TSTUAF

              PULU D
              CMPD #TSTVAL2
              BNE  T2FFAIL
              PULU D
              CMPD #TSTVAL1
              BNE  T2FFAIL
              PULU D
              CMPD #TSTVAL2
              BNE  T2FFAIL
              PULU D
              CMPD #TSTVAL1
              BNE  T2FFAIL
              PULU D
              CMPD #TSTGUARD
              BNE  T2FFAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #4
              BNE  T2FFAIL

              LDD  #TRUEV
              BRA  T2FDONE
T2FFAIL:       LDD  #FALSEV
T2FDONE:       LDX  #TSTTWORFETCHNAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTTWORFETCHNAME: FCB  12
                  FCC  "TSTTWORFETCH"

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

           IFEQ TSTSELECTOR-3  ; >>>>

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

           IFEQ TSTSELECTOR-3  ; >>>>

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

           IFEQ TSTSELECTOR-4  ; >>>>

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

           IFEQ TSTSELECTOR-4  ; >>>>

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

           IFEQ TSTSELECTOR-5  ; >>>>

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

           IFEQ TSTSELECTOR-5  ; >>>>

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

; ------------------------------------------------------------
; TSTCOMPARE - comparison tests (glossary section 3.7). Covers
; every word in that section. Like several words in the previous
; group, most of these modify the top of stack in place rather
; than PULU/PSHU - the tests verify what's observable via the
; stack either way. Signed vs unsigned comparisons (</U<, >/U>)
; each tested with a case that would give the opposite answer
; under the other convention, confirming genuine sign-awareness
; rather than an accidentally-shared implementation. WITHIN
; tested against a wraparound range specifically (n2 near $FFFF,
; n3 wrapped past $0000), both inside and outside cases - the
; documented special case its own unsigned-offset implementation
; exists to handle, not just an ordinary non-wrapping range. D</
; DU< both tested with equal high cells and different low cells -
; the documented tie-break case a naive high-cell-only comparison
; would get wrong.
; ------------------------------------------------------------
TSTCOMPARE: JSR   CRW
           LDX   #TSTCOMPMSG
           PSHU  X
           LDD   #7
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-6  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTCOMPMSG: FCC "Compare"

           IFEQ TSTSELECTOR-6  ; >>>>

; ------------------------------------------------------------
; TSTEQ - unit test for EQUALW. true if equal - tested with matching values, the case that actually exercises the true branch.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

TSTEQNAME: FCB  5
             FCC  "TSTEQ"

; ------------------------------------------------------------
; TSTLT - unit test for LESSW. true if n1 signed less than n2 - tested with a negative n1 and positive n2, the case that distinguishes signed from unsigned comparison.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

TSTLTNAME: FCB  5
             FCC  "TSTLT"

; ------------------------------------------------------------
; TSTGT - unit test for GREATERW. true if n1 signed greater than n2 - same reasoning as < , reversed operands.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

TSTGTNAME: FCB  5
             FCC  "TSTGT"

; ------------------------------------------------------------
; TSTZEQ - unit test for ZEROEQ. true if n is zero - tested with a nonzero value, confirming false is genuinely reachable, not just the trivial zero case.
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTZEQ:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   ZEROEQ

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

TSTZEQNAME: FCB  6
              FCC  "TSTZEQ"

; ------------------------------------------------------------
; TSTZLT - unit test for ZEROLT. true if n is negative.
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTZLT:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           STU   TSTUB4

           JSR   ZEROLT

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

TSTZLTNAME: FCB  6
              FCC  "TSTZLT"

; ------------------------------------------------------------
; TSTULT - unit test for ULESSW. true if u1 unsigned less than u2 - tested with TSTVAL1 vs TSTNEG1's raw bit pattern (a large unsigned magnitude), the case that would invert under signed comparison, confirming this is genuinely unsigned.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
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

TSTULTNAME: FCB  6
              FCC  "TSTULT"

; ------------------------------------------------------------
; TSTNE - unit test for NOTEQUAL. true if not equal.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
; ------------------------------------------------------------
TSTNE:      STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           LDD   #TSTVAL2
           PSHU  D
           STU   TSTUB4

           JSR   NOTEQUAL

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

TSTNENAME: FCB  5
             FCC  "TSTNE"

; ------------------------------------------------------------
; TSTZNE - unit test for ZERONE. true if n is not zero.
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTZNE:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   ZERONE

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

TSTZNENAME: FCB  6
              FCC  "TSTZNE"

; ------------------------------------------------------------
; TSTZGT - unit test for ZEROGT. true if n is greater than zero - tested with a negative value, confirming the comparison correctly excludes negatives (not just zero).
; Arity: 1 cell(s) in, 1 cell(s) out -> depth check
; 0 (derived, not hand-typed).
; ------------------------------------------------------------
TSTZGT:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           STU   TSTUB4

           JSR   ZEROGT

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

TSTZGTNAME: FCB  6
              FCC  "TSTZGT"

; ------------------------------------------------------------
; TSTUGT - unit test for UGREATER. true if u1 unsigned greater than u2 - same reasoning as U< : TSTNEG1's raw bit pattern is a large unsigned magnitude, genuinely greater than TSTVAL1's here.
; Arity: 2 cell(s) in, 1 cell(s) out -> depth check
; -2 (derived, not hand-typed).
; ------------------------------------------------------------
TSTUGT:     STU   TSTU0

           LDD   #TSTGUARD
           PSHU  D
           LDD   #TSTNEG1
           PSHU  D
           LDD   #TSTVAL1
           PSHU  D
           STU   TSTUB4

           JSR   UGREATER

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

TSTUGTNAME: FCB  6
              FCC  "TSTUGT"

; ------------------------------------------------------------
; TSTWI1 - unit test for WITHINW. true if n2<=n1<n3 - tested with a wraparound range (n2 near $FFFF, n3 wrapped past $0000), the documented special case this word's own unsigned-offset implementation exists to handle correctly, with n1 inside the wrapped range.
; Arity: 3 cell(s) in, 1 cell(s) out -> depth check
; -4 (derived, not hand-typed).
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

TSTWI1NAME: FCB  6
              FCC  "TSTWI1"

; ------------------------------------------------------------
; TSTWI2 - unit test for WITHINW. same wraparound range as TSTWI1, with n1 genuinely outside it - confirms the wraparound handling correctly excludes as well as includes.
; Arity: 3 cell(s) in, 1 cell(s) out -> depth check
; -4 (derived, not hand-typed).
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

TSTWI2NAME: FCB  6
              FCC  "TSTWI2"

; ------------------------------------------------------------
; TSTDEQ - unit test for DEQUAL. double-cell equal - tested with matching double values.
; Arity: 4 cell(s) in, 1 cell(s) out -> depth check
; -6 (derived, not hand-typed).
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

           JSR   DEQUAL

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

TSTDEQNAME: FCB  6
              FCC  "TSTDEQ"

; ------------------------------------------------------------
; TSTDLT - unit test for DLESSW. double-cell signed less than - tested with equal high cells and different low cells, the tie-break case this word's own documented behavior specifically calls out (compares low cells unsigned only when the high cells are equal).
; Arity: 4 cell(s) in, 1 cell(s) out -> depth check
; -6 (derived, not hand-typed).
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

TSTDLTNAME: FCB  6
              FCC  "TSTDLT"

; ------------------------------------------------------------
; TSTDULT - unit test for DULESSW. double-cell unsigned less than - same tie-break reasoning as D<, both tiers compared unsigned.
; Arity: 4 cell(s) in, 1 cell(s) out -> depth check
; -6 (derived, not hand-typed).
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

TSTDULTNAME: FCB  7
               FCC  "TSTDULT"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTCTRLFLOW - control-flow tests (glossary section 3.8, 22
; words - all except UNLOOP, which is a genuine runtime no-op
; and tested directly like ALIGN's own test, needing none of
; this section's compile-time harness). Every other test
; redirects CODEHERE to a scratch buffer (TSTCBUF), calls the
; real compile-time words directly (JSR IF, JSR THEN, JSR DO,
; etc - the actual routines the compiler itself calls, not a
; hand-simulated imitation), restores CODEHERE, then executes
; the compiled snippet directly. Tests the real interaction
; between compile-time correctness (right bytes, right patched
; offsets) and runtime correctness (right control flow) in one
; coherent check, without needing the outer interpreter, FIND,
; or a real dictionary entry.
;
; Given the planned future application of the ANS test suite for
; broader standards-compliance coverage, these tests focus on
; this system's own compile/patch mechanism working correctly -
; not full end-to-end parsing, which the ANS suite will cover.
;
; One case is deliberately NOT tested: DO with limit=index.
; Traced precisely (simulated the real DOTEST increment-and-
; compare-equal logic) and confirmed it takes a full 65536-
; iteration wraparound to naturally reconverge on equality, not
; one - true to the letter of "runs at least once" but
; impractical for a boot-time self-check. ?DO's own equivalent
; case IS tested (TSTQDOLPEQ) - its own skip check happens
; before the loop is entered at all, confirmed fast and safe by
; the same kind of trace.
; ------------------------------------------------------------
TSTCTRLFLOW: JSR CRW
           LDX   #TSTCTRLMSG
           PSHU  X
           LDD   #8
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-7  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTCTRLMSG: FCC "CtrlFlow"

           IFEQ TSTSELECTOR-7  ; >>>>

; ------------------------------------------------------------
; Control-flow test harness (glossary section 3.8). Each test
; redirects CODEHERE to a scratch buffer (TSTCBUF), calls the
; real compile-time control-flow words directly (JSR IF, JSR
; THEN, etc - the same routines the compiler itself calls when
; parsing IF/THEN/DO/LOOP/etc, not a hand-simulated imitation),
; then restores CODEHERE and executes the compiled snippet
; directly. This tests the actual interaction between compile-
; time correctness (right bytes, right patched offsets) and
; runtime correctness (right control flow) in one coherent
; test, without needing the outer interpreter, FIND, or a
; dictionary entry - matching the ANS test suite's own planned
; role for broader standards-compliance coverage; these tests
; specifically verify this system's own compile/patch mechanism
; works correctly, not full end-to-end parsing.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTIFT1 - unit test for IF/THEN, true case. Compiles
; "IF <lit 111> THEN" into scratch, then runs it with a true
; flag - the branch is NOT taken, so 111 should be pushed.
; Verified by hand-trace before writing: ZBRANCH's patched
; offset comes out to 7 (from the placeholder field to just
; past the compiled LIT+111), correctly skipping nothing when
; the flag is true and falling through into the literal.
; ------------------------------------------------------------
TSTIFT1: LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   IF

         LDD   #111
         PSHU  D
         JSR   LITERALW

         JSR   THEN

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
T1FAIL:  LDD   #FALSEV
T1DONE:  LDX   #TSTIFT1NAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTIFT1NAME: FCB  7
             FCC  "TSTIFT1"

; ------------------------------------------------------------
; TSTIFT2 - unit test for IF/THEN, false case. Same compiled
; snippet as TSTIFT1, run with a false flag instead - the
; branch IS taken, jumping straight past the LIT+111, so 111
; should NOT appear; only the guard remains.
; ------------------------------------------------------------
TSTIFT2: LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   IF

         LDD   #111
         PSHU  D
         JSR   LITERALW

         JSR   THEN

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
T2FAIL:  LDD   #FALSEV
T2DONE:  LDX   #TSTIFT2NAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTIFT2NAME: FCB  7
             FCC  "TSTIFT2"

; ------------------------------------------------------------
; TSTIET1 - unit test for IF/ELSE/THEN, true case. Compiles
; "IF <lit 111> ELSE <lit 222> THEN" into scratch. True flag
; should take the IF-body (111) and skip the ELSE-body (222)
; via ELSE's own unconditional branch. Verified by hand-trace:
; IF's patched offset (12) lands exactly at the ELSE-body's
; start; ELSE's own patched offset (7) lands exactly past it.
; ------------------------------------------------------------
TSTIET1: LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   IF

         LDD   #111
         PSHU  D
         JSR   LITERALW

         JSR   ELSE

         LDD   #222
         PSHU  D
         JSR   LITERALW

         JSR   THEN

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
E1FAIL:  LDD   #FALSEV
E1DONE:  LDX   #TSTIET1NAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTIET1NAME: FCB  7
             FCC  "TSTIET1"

; ------------------------------------------------------------
; TSTIET2 - unit test for IF/ELSE/THEN, false case. Same
; compiled snippet as TSTIET1, run with a false flag - should
; take the ELSE-body (222) instead, IF-body (111) skipped.
; ------------------------------------------------------------
TSTIET2: LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   IF

         LDD   #111
         PSHU  D
         JSR   LITERALW

         JSR   ELSE

         LDD   #222
         PSHU  D
         JSR   LITERALW

         JSR   THEN

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
E2FAIL:  LDD   #FALSEV
E2DONE:  LDX   #TSTIET2NAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTIET2NAME: FCB  7
             FCC  "TSTIET2"

; ------------------------------------------------------------
; TSTBGU - unit test for BEGIN/UNTIL. Compiles
; "BEGIN 1+ DUP <lit 5> = UNTIL" into scratch - increments,
; duplicates, compares to 5, loops back while not equal. Run
; starting from 0; verified by hand-trace across all 5
; iterations (0->1->2->3->4->5, exiting exactly on reaching 5,
; not one iteration early or late) before writing. The patched
; back-edge offset is negative (-17), the same PATCH routine
; used for forward references handling both directions
; correctly based on relative position.
; ------------------------------------------------------------
TSTBGU:  LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   BEGIN

         LDD   #ONEPLUS
         PSHU  D
         JSR   CCALL

         LDD   #DUP
         PSHU  D
         JSR   CCALL

         LDD   #5
         PSHU  D
         JSR   LITERALW

         LDD   #EQUALW
         PSHU  D
         JSR   CCALL

         JSR   UNTIL

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
BUFAIL:  LDD   #FALSEV
BUDONE:  LDX   #TSTBGUNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTBGUNAME: FCB  6
            FCC  "TSTBGU"

; ------------------------------------------------------------
; TSTBWR - unit test for BEGIN/WHILE/REPEAT. Compiles
; "BEGIN DUP <lit 5> < WHILE 1+ REPEAT" - opposite polarity
; from TSTBGU's UNTIL (continues on true, exits on false,
; rather than the reverse) - starting from 0, increments while
; less than 5. Naturally exercises both of WHILE's outcomes in
; one test: the continue path 5 times, the exit path once.
; Verified by hand-trace: WHILE's patched forward offset (10)
; lands exactly at the final RTS; REPEAT's patched back-edge
; (-22) lands exactly at BEGIN.
; ------------------------------------------------------------
TSTBWR:  LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   BEGIN

         LDD   #DUP
         PSHU  D
         JSR   CCALL

         LDD   #5
         PSHU  D
         JSR   LITERALW

         LDD   #LESSW
         PSHU  D
         JSR   CCALL

         JSR   WHILE

         LDD   #ONEPLUS
         PSHU  D
         JSR   CCALL

         JSR   REPEAT

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
BWFAIL:  LDD   #FALSEV
BWDONE:  LDX   #TSTBWRNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTBWRNAME: FCB  6
            FCC  "TSTBWR"

; ------------------------------------------------------------
; TSTRECUR - unit test for RECURSE. Builds a fake dictionary
; header in scratch (TSTFHDR: LEN/FL=3, name "FOO", a
; don't-care LINK, and DUP's real address as the CFA), points
; LATEST at it, then calls RECURSE directly. Verifies RECURSE
; correctly parses an arbitrary header (LEN/FL's 5-bit length
; field, skipping name+LINK to reach the CFA) and compiles a
; correct call to it - tests the actual mechanism (header
; parsing, CFA extraction, CCALL), not genuine self-recursion,
; which would need a real in-progress compilation to set up
; meaningfully. Confirmed by hand-trace: RECURSE's own address
; arithmetic (+1 past LEN/FL, +namelen past the name, +2 past
; LINK) lands exactly on TSTFHDR+6, where the CFA is placed.
; ------------------------------------------------------------
TSTRECUR: LDD  LATEST
          STD  TSTLSAV
          LDD  CODEHERE
          STD  TSTCSAV

          LDA  #3
          STA  TSTFHDR
          LDA  #'F'
          STA  TSTFHDR+1
          LDA  #'O'
          STA  TSTFHDR+2
          LDA  #'O'
          STA  TSTFHDR+3
          LDD  #0
          STD  TSTFHDR+4
          LDD  #DUP
          STD  TSTFHDR+6

          LDD  #TSTFHDR
          STD  LATEST

          LDD  #TSTCBUF
          STD  CODEHERE

          JSR  RECURSE

          LDD  #OPRTS
          PSHU D
          JSR  CCOMMA

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTLSAV
          STD  LATEST

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTVAL1
          PSHU D
          STU  TSTUB4

          JSR  TSTCBUF

          STU  TSTUAF

          PULU D
          CMPD #TSTVAL1
          BNE  RCFAIL
          PULU D
          CMPD #TSTVAL1
          BNE  RCFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  RCFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  RCFAIL

          LDD  #TRUEV
          BRA  RCDONE
RCFAIL:   LDD  #FALSEV
RCDONE:   LDX  #TSTRECURNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTRECURNAME: FCB  8
              FCC  "TSTRECUR"

; ------------------------------------------------------------
; TSTDOLP - unit test for DO/LOOP. Compiles "DO I + LOOP",
; run with limit=5, start-index=0, and a seed accumulator of 0
; already on the stack. Verifies the full I sequence (0,1,2,3,4)
; by summing it via + each iteration - a wrong index sequence
; (off-by-one, wrong direction, wrong starting value) would
; produce a different sum than the correct 0+1+2+3+4=10, not
; just "some number of iterations happened."
;
; The documented limit=index edge case (runs at least once) is
; deliberately NOT tested here: traced precisely (simulated the
; real DOTEST increment-and-compare-equal logic) and confirmed
; it takes a full 65536 iterations to naturally reconverge on
; equality, not one - true to the letter of "at least once" but
; impractical for a boot-time self-check. Left untested, not
; guessed at; noted in the open-items checklist.
; ------------------------------------------------------------
TSTDOLP: LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   DO

         LDD   #IWORD
         PSHU  D
         JSR   CCALL

         LDD   #PLUS
         PSHU  D
         JSR   CCALL

         JSR   LOOP

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
DWFAIL:  LDD   #FALSEV
DWDONE:  LDX   #TSTDOLPNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTDOLPNAME: FCB  7
             FCC  "TSTDOLP"

; ------------------------------------------------------------
; TSTQDOLP - unit test for ?DO/LOOP, normal (non-skip) case.
; Same "?DO I + LOOP" structure and I-sum verification as
; TSTDOLP, confirming ?DO behaves like DO when index != limit.
; ------------------------------------------------------------
TSTQDOLP: LDD  CODEHERE
          STD  TSTCSAV
          LDD  #TSTCBUF
          STD  CODEHERE

          JSR  QDO

          LDD  #IWORD
          PSHU D
          JSR  CCALL

          LDD  #PLUS
          PSHU D
          JSR  CCALL

          JSR  LOOP

          LDD  #OPRTS
          PSHU D
          JSR  CCOMMA

          LDD  TSTCSAV
          STD  CODEHERE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #0
          PSHU D
          LDD  #5
          PSHU D
          LDD  #0
          PSHU D
          STU  TSTUB4

          JSR  TSTCBUF

          STU  TSTUAF

          PULU D
          CMPD #10
          BNE  QLFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  QLFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-4
          BNE  QLFAIL

          LDD  #TRUEV
          BRA  QLDONE
QLFAIL:   LDD  #FALSEV
QLDONE:   LDX  #TSTQDOLPNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTQDOLPNAME: FCB  8
              FCC  "TSTQDOLP"

; ------------------------------------------------------------
; TSTQDOLPEQ - unit test for ?DO/LOOP, limit=index case - the
; documented case that DISTINGUISHES ?DO from plain DO: skips
; the loop entirely, unlike DO's own limit=index behavior
; (confirmed separately to take a full 65536-iteration
; wraparound, not tested here - see TSTDOLP's own notes). This
; case IS fast and safe to test directly: QDOSETUP's own skip
; check happens before the loop is entered at all, confirmed by
; hand-trace of its code. Same "?DO I + LOOP" body, but since
; the body never runs, the seed should come back completely
; unchanged (0, not 10).
; ------------------------------------------------------------
TSTQDOLPEQ: LDD  CODEHERE
            STD  TSTCSAV
            LDD  #TSTCBUF
            STD  CODEHERE

            JSR  QDO

            LDD  #IWORD
            PSHU D
            JSR  CCALL

            LDD  #PLUS
            PSHU D
            JSR  CCALL

            JSR  LOOP

            LDD  #OPRTS
            PSHU D
            JSR  CCOMMA

            LDD  TSTCSAV
            STD  CODEHERE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #0
            PSHU D
            LDD  #5
            PSHU D
            LDD  #5
            PSHU D
            STU  TSTUB4

            JSR  TSTCBUF

            STU  TSTUAF

            PULU D
            CMPD #0
            BNE  QEFAIL
            PULU D
            CMPD #TSTGUARD
            BNE  QEFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #-4
            BNE  QEFAIL

            LDD  #TRUEV
            BRA  QEDONE
QEFAIL:     LDD  #FALSEV
QEDONE:     LDX  #TSTQDOLPEQNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTQDOLPEQNAME: FCB  10
                FCC  "TSTQDOLPEQ"

; ------------------------------------------------------------
; TSTPLOOP - unit test for DO/+LOOP. Compiles
; "DO I + 3 LITERAL +LOOP", run with limit=10, start=0 - a step
; (3) that doesn't land exactly on the limit, deliberately
; exercising the crossing-boundary exit condition rather than
; landing-exactly-on-it, since those are handled by genuinely
; different checks in DOPLUSTEST (confirmed by reading its own
; code - crosses-sign OR lands-exactly, checked separately).
; Visits I=0,3,6,9, exits when 9+3=12 crosses past 10. Sum=18.
; ------------------------------------------------------------
TSTPLOOP: LDD  CODEHERE
          STD  TSTCSAV
          LDD  #TSTCBUF
          STD  CODEHERE

          JSR  DO

          LDD  #IWORD
          PSHU D
          JSR  CCALL

          LDD  #PLUS
          PSHU D
          JSR  CCALL

          LDD  #3
          PSHU D
          JSR  LITERALW

          JSR  PLUSLOOP

          LDD  #OPRTS
          PSHU D
          JSR  CCOMMA

          LDD  TSTCSAV
          STD  CODEHERE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #0
          PSHU D
          LDD  #10
          PSHU D
          LDD  #0
          PSHU D
          STU  TSTUB4

          JSR  TSTCBUF

          STU  TSTUAF

          PULU D
          CMPD #18
          BNE  POFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  POFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-4
          BNE  POFAIL

          LDD  #TRUEV
          BRA  PODONE
POFAIL:   LDD  #FALSEV
PODONE:   LDX  #TSTPLOOPNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTPLOOPNAME: FCB  8
              FCC  "TSTPLOOP"

; ------------------------------------------------------------
; TSTJIDX - unit test for J. Compiles a doubly-nested DO loop:
; "DO 2 0 DO J 10 * I + + LOOP LOOP" - outer index 0..2, inner
; 0..1, accumulating (outer*10+inner) each pass. Verifies BOTH
; I and J are read correctly, and specifically at the right
; return-stack offset once genuinely nested (J's own "8,S" -
; not the "10,S" an earlier, already-documented bug used, per
; this word's own extensive bug-fix history in the source
; itself, retraced by hand here rather than assumed still
; correct). Six (outer,inner) pairs, expected sum 63 - a wrong
; nesting depth or wrong index read would produce a different
; sum, not just "some accumulation happened."
; ------------------------------------------------------------
TSTJIDX: LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         JSR   DO

         LDD   #2
         PSHU  D
         JSR   LITERALW
         LDD   #0
         PSHU  D
         JSR   LITERALW

         JSR   DO

         LDD   #JWORD
         PSHU  D
         JSR   CCALL

         LDD   #10
         PSHU  D
         JSR   LITERALW

         LDD   #STAR
         PSHU  D
         JSR   CCALL

         LDD   #IWORD
         PSHU  D
         JSR   CCALL

         LDD   #PLUS
         PSHU  D
         JSR   CCALL

         LDD   #PLUS
         PSHU  D
         JSR   CCALL

         JSR   LOOP

         JSR   LOOP

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
JIFAIL:  LDD   #FALSEV
JIDONE:  LDX   #TSTJIDXNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTJIDXNAME: FCB  7
             FCC  "TSTJIDX"

; ------------------------------------------------------------
; TSTLEAVE - unit test for LEAVE. Compiles
; "DO I DUP 3 LITERAL = IF LEAVE THEN + LOOP", limit=10,
; start=0 - would normally visit I=0..9, but LEAVE forces exit
; once I=3 is reached. LEAVE only sets a flag; the actual exit
; happens at the NEXT LOOP check (per its own documented
; behavior, "exit at its next LOOP") - confirmed by hand-trace
; of DOTEST's own logic (checks the flag first, before its
; normal increment/compare). Since + runs before LOOP's check,
; I=3 IS accumulated before the loop exits - sum=0+1+2+3=6, not
; 0+1+2=3 (which would indicate LEAVE incorrectly took effect
; immediately) and not the full 0..9 (which would indicate
; LEAVE didn't work at all).
; ------------------------------------------------------------
TSTLEAVE: LDD  CODEHERE
          STD  TSTCSAV
          LDD  #TSTCBUF
          STD  CODEHERE

          JSR  DO

          LDD  #IWORD
          PSHU D
          JSR  CCALL

          LDD  #DUP
          PSHU D
          JSR  CCALL

          LDD  #3
          PSHU D
          JSR  LITERALW

          LDD  #EQUALW
          PSHU D
          JSR  CCALL

          JSR  IF

          LDD  #LEAVE
          PSHU D
          JSR  CCALL

          JSR  THEN

          LDD  #PLUS
          PSHU D
          JSR  CCALL

          JSR  LOOP

          LDD  #OPRTS
          PSHU D
          JSR  CCOMMA

          LDD  TSTCSAV
          STD  CODEHERE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #0
          PSHU D
          LDD  #10
          PSHU D
          LDD  #0
          PSHU D
          STU  TSTUB4

          JSR  TSTCBUF

          STU  TSTUAF

          PULU D
          CMPD #6
          BNE  LVFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  LVFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-4
          BNE  LVFAIL

          LDD  #TRUEV
          BRA  LVDONE
LVFAIL:   LDD  #FALSEV
LVDONE:   LDX  #TSTLEAVENAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTLEAVENAME: FCB  8
              FCC  "TSTLEAVE"

; ------------------------------------------------------------
; TSTEXIT - unit test for EXIT. Compiles
; "DO I DUP 3 LITERAL = IF EXIT THEN I + LOOP", limit=10,
; start=0 - EXIT fires when I=3, discarding the one open DO
; frame and returning immediately. Sets the real CSP to U's
; value right before the first control-flow marker is pushed
; (matching what ":" does at the start of a real definition),
; since EXIT's own compile-time frame count depends on it -
; confirmed by hand-trace: at the point EXIT is compiled, U
; holds IF's own pending (addr,TAGFWD) on top of DO's
; (addr,TAGDO), and EXIT's scan correctly counts exactly one
; TAGDO between U and CSP. Unlike TSTLEAVE, EXIT fires
; immediately when reached - the following + never runs for
; I=3, so sum=0+1+2=3, not 6.
; ------------------------------------------------------------
TSTEXIT: LDD   CSP
         STD   TSTCSPS
         LDD   CODEHERE
         STD   TSTCSAV
         LDD   #TSTCBUF
         STD   CODEHERE

         TFR   U,D
         STD   CSP

         JSR   DO

         LDD   #IWORD
         PSHU  D
         JSR   CCALL

         LDD   #DUP
         PSHU  D
         JSR   CCALL

         LDD   #3
         PSHU  D
         JSR   LITERALW

         LDD   #EQUALW
         PSHU  D
         JSR   CCALL

         JSR   IF

         JSR   EXIT

         JSR   THEN

         LDD   #PLUS
         PSHU  D
         JSR   CCALL

         JSR   LOOP

         LDD   #OPRTS
         PSHU  D
         JSR   CCOMMA

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
EXFAIL:  LDD   #FALSEV
EXDONE:  LDX   #TSTEXITNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTEXITNAME: FCB  7
             FCC  "TSTEXIT"

; ------------------------------------------------------------
; TSTUNLOOP - unit test for UNLOOP. A true no-op (bare RTS) per
; its own extensively-documented design history in the source -
; superseded by EXIT's own automatic frame-discarding, kept
; only for source compatibility. Not compile-time/immediate
; like the rest of this section - a plain runtime word, tested
; directly without the compile harness, same pattern as ALIGN's
; own test in section 3.6: pushes decoy values, calls UNLOOP,
; confirms the whole stack is genuinely undisturbed.
; ------------------------------------------------------------
TSTUNLOOP: STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           LDD  #TSTVAL1
           PSHU D
           LDD  #TSTVAL2
           PSHU D
           STU  TSTUB4

           JSR  UNLOOP

           STU  TSTUAF

           PULU D
           CMPD #TSTVAL2
           BNE  UOFAIL
           PULU D
           CMPD #TSTVAL1
           BNE  UOFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  UOFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  UOFAIL

           LDD  #TRUEV
           BRA  UODONE
UOFAIL:    LDD  #FALSEV
UODONE:    LDX  #TSTUNLOOPNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTUNLOOPNAME: FCB  9
               FCC  "TSTUNLOOP"

; ------------------------------------------------------------
; TSTCASE1 - unit test for CASE/OF/ENDOF/ENDCASE, matching
; clause. Compiles
; "CASE 1 LITERAL OF 111 LITERAL ENDOF
;       2 LITERAL OF 222 LITERAL ENDOF ENDCASE"
; with selector=2, matching the second clause. Traced by hand:
; OF compiles OVER/=/ZBRANCH<placeholder>/DROP - the DROP only
; runs on a match, consuming the selector; ENDOF compiles an
; unconditional branch past the remaining clauses AND patches
; its own OF's placeholder to the next clause's OF; ENDCASE
; patches every pending ENDOF branch to the true end and
; compiles a final fallback DROP for the no-match case.
; ------------------------------------------------------------
TSTCASE1: LDD  CODEHERE
          STD  TSTCSAV
          LDD  #TSTCBUF
          STD  CODEHERE

          JSR  CASEW

          LDD  #1
          PSHU D
          JSR  LITERALW
          JSR  OF
          LDD  #111
          PSHU D
          JSR  LITERALW
          JSR  ENDOF

          LDD  #2
          PSHU D
          JSR  LITERALW
          JSR  OF
          LDD  #222
          PSHU D
          JSR  LITERALW
          JSR  ENDOF

          JSR  ENDCASE

          LDD  #OPRTS
          PSHU D
          JSR  CCOMMA

          LDD  TSTCSAV
          STD  CODEHERE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #2
          PSHU D
          STU  TSTUB4

          JSR  TSTCBUF

          STU  TSTUAF

          PULU D
          CMPD #222
          BNE  C1FAIL
          PULU D
          CMPD #TSTGUARD
          BNE  C1FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  C1FAIL

          LDD  #TRUEV
          BRA  C1DONE
C1FAIL:   LDD  #FALSEV
C1DONE:   LDX  #TSTCASE1NAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTCASE1NAME: FCB  9
              FCC  "TSTCASE1"

; ------------------------------------------------------------
; TSTCASE2 - unit test for CASE/OF/ENDOF/ENDCASE, no-match
; case. Same compiled snippet as TSTCASE1, run with a selector
; (99) matching neither clause - should fall through both OF
; checks (selector preserved across each non-match, per the
; documented "( x n -- | x )" effect) and reach ENDCASE's own
; fallback DROP, consuming the selector with nothing pushed in
; its place.
; ------------------------------------------------------------
TSTCASE2: LDD  CODEHERE
          STD  TSTCSAV
          LDD  #TSTCBUF
          STD  CODEHERE

          JSR  CASEW

          LDD  #1
          PSHU D
          JSR  LITERALW
          JSR  OF
          LDD  #111
          PSHU D
          JSR  LITERALW
          JSR  ENDOF

          LDD  #2
          PSHU D
          JSR  LITERALW
          JSR  OF
          LDD  #222
          PSHU D
          JSR  LITERALW
          JSR  ENDOF

          JSR  ENDCASE

          LDD  #OPRTS
          PSHU D
          JSR  CCOMMA

          LDD  TSTCSAV
          STD  CODEHERE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #99
          PSHU D
          STU  TSTUB4

          JSR  TSTCBUF

          STU  TSTUAF

          PULU D
          CMPD #TSTGUARD
          BNE  C2FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-2
          BNE  C2FAIL

          LDD  #TRUEV
          BRA  C2DONE
C2FAIL:   LDD  #FALSEV
C2DONE:   LDX  #TSTCASE2NAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTCASE2NAME: FCB  9
              FCC  "TSTCASE2"

; ------------------------------------------------------------
; TSTTHENZ - unit test for THEN, tag-mismatch case. Pushes a
; wrong value (0, matching none of TAGFWD/TAGBACK/TAGDO/TAGOF)
; in place of the expected TAGFWD, then calls THEN via CATCH.
; CFERR (confirmed by reading it directly) throws -22
; immediately without ever touching CODEHERE - the error path
; never reaches any compiling code - so this needs no CODEHERE
; redirect, unlike every other test in this section. Same
; CATCH-based pattern as the divide-by-zero tests in earlier
; sections: verify the thrown code and CATCH's own depth-
; restoration contract, not the unspecified i*x values.
; ------------------------------------------------------------
TSTTHENZ: STU  TSTU0

          LDD  #0
          PSHU D
          LDD  #0
          PSHU D
          LDX  #THEN
          PSHU X
          STU  TSTUB4

          JSR  CATCH

          STU  TSTUAF

          PULU D
          CMPD #-22
          BNE  T3FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  T3FAIL

          LDD  #TRUEV
          BRA  T3DONE
T3FAIL:   LDD  #FALSEV
T3DONE:   LDX  #TSTTHENZNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTTHENZNAME: FCB  8
              FCC  "TSTTHENZ"

; ------------------------------------------------------------
; TSTUNTILZ - unit test for UNTIL, tag-mismatch case. Same
; pattern as TSTTHENZ - wrong value in place of TAGBACK.
; ------------------------------------------------------------
TSTUNTILZ: STU  TSTU0

           LDD  #0
           PSHU D
           LDD  #0
           PSHU D
           LDX  #UNTIL
           PSHU X
           STU  TSTUB4

           JSR  CATCH

           STU  TSTUAF

           PULU D
           CMPD #-22
           BNE  U3FAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  U3FAIL

           LDD  #TRUEV
           BRA  U3DONE
U3FAIL:    LDD  #FALSEV
U3DONE:    LDX  #TSTUNTLZNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTUNTLZNAME: FCB  9
              FCC  "TSTUNTILZ"

; ------------------------------------------------------------
; TSTENDOFZ - unit test for ENDOF, tag-mismatch case. Same
; pattern - wrong value in place of TAGOF.
; ------------------------------------------------------------
TSTENDOFZ: STU  TSTU0

           LDD  #0
           PSHU D
           LDD  #0
           PSHU D
           LDX  #ENDOF
           PSHU X
           STU  TSTUB4

           JSR  CATCH

           STU  TSTUAF

           PULU D
           CMPD #-22
           BNE  EOFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  EOFAIL

           LDD  #TRUEV
           BRA  EODONE
EOFAIL:    LDD  #FALSEV
EODONE:    LDX  #TSTENDFZNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTENDFZNAME: FCB  9
              FCC  "TSTENDOFZ"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTDEFWORDS - defining-words tests (glossary section 3.9, 17
; words, 12 tests since VALUE/TO and IS/ACTION-OF are each
; combined into one test). Every defining word parses a name
; from the input source via WORD (HEADER's own mechanism,
; shared by :/CREATE) - a complexity nothing in section 3.8 had.
; Each test redirects CODEHERE, DPHERE, VARHERE, and
; SRCADDR/SRCLEN/TOIN together (a fake name, "TESTWD", reused
; safely across every test here since each redirect/restore
; cycle is fully isolated), calls the real defining word
; directly, saves the newly-defined word's own CFA (= CODEHERE
; at the moment the defining word was called), restores
; everything, then executes that CFA directly to verify runtime
; behavior.
;
; A real, structurally important finding from this section:
; HEADER writes to the real LATEST variable unconditionally, not
; a redirectable copy like CODEHERE/DPHERE/VARHERE - every test
; here explicitly saves and restores it, confirmed necessary by
; reading HEADER's own code directly, not assumed safe by analogy
; with the other three pointers.
;
; MARKER's own test is the one exception to the general
; redirect-then-restore-then-execute order: DOMARKER (confirmed
; by reading it directly) writes to the real DPHERE/CODEHERE/
; VARHERE/LATEST unconditionally too, so that test executes the
; marker word while still redirected, only restoring the real
; environment afterward - getting this order backwards would
; have corrupted the real dictionary pointers with scratch
; addresses.
;
; Bare CREATE (never followed by DOES>) is deliberately not
; tested on its own - traced its placeholder "behavior field"
; (a genuine compiled JSR DOESRT0 instruction) and confirmed
; DODOES reads that field as raw data, not as code to execute -
; which only produces a valid jump target for the raw-address
; form every other defining word uses (VARIABLE, CONSTANT, etc,
; via CODECOMMA), not CREATE's own placeholder JSR instruction.
; Bare CREATE's own direct-execution behavior isn't meant to be
; relied upon before a DOES> patches it.
; ------------------------------------------------------------
TSTDEFWORDS: JSR CRW
           LDX   #TSTDEFMSG
           PSHU  X
           LDD   #8
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-8  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTDEFMSG: FCC "DefWords"

           IFEQ TSTSELECTOR-8  ; >>>>

; ------------------------------------------------------------
; Defining-words test harness (glossary section 3.9). Every
; defining word parses a name from the input source via WORD -
; unlike anything in section 3.8's control-flow tests - so each
; test redirects CODEHERE, DPHERE, VARHERE, and SRCADDR/SRCLEN/
; TOIN together (a fake name text, "TESTWD", reused safely
; across every test here since each redirect/restore cycle is
; fully isolated), calls the real defining word directly, saves
; the newly-defined word's own CFA (= CODEHERE at the moment the
; defining word was called), restores everything, then executes
; that CFA directly to verify runtime behavior. Traced by hand:
; CREATE/VARIABLE/CONSTANT/etc all use HEADER (shared header-
; building) then compile a fixed 5-byte trampoline (3-byte
; "JSR DODOES" + a 2-byte "behavior field") before their own
; PFA - confirmed the behavior field holds a genuine compiled
; JSR instruction only for CREATE's own bare placeholder
; (DOESRT0, later patched by DOES>); every other defining word
; (VARIABLE, CONSTANT, DEFER, MARKER, VALUE) instead compiles a
; raw 2-byte address there directly (via CODECOMMA, not CCALL) -
; DODOES reads this field as data either way, which only works
; correctly for the raw-address form. This is why bare CREATE,
; executed before any DOES>, isn't tested here - its own
; placeholder behavior field isn't meant to be read as data,
; only ever overwritten by DOES> before first use.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTVAR - unit test for VARIABLE. Compiles "VARIABLE TESTWD"
; into scratch, then executes the result. Verifies it pushes
; its own PFA address (TSTVBUF, since VARHERE was redirected
; there) and that the cell there was correctly initialized to
; zero - VARIABLE's own documented behavior, not assumed.
; ------------------------------------------------------------
TSTVAR:  LDD   CODEHERE
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

         JSR   VARIABLE

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
VRFAIL:  LDD   #FALSEV
VRDONE:  LDX   #TSTVARNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTVARNAME: FCB  6
            FCC  "TSTVAR"

; ------------------------------------------------------------
; TSTCONST - unit test for CONSTANT. Compiles "5 CONSTANT
; TESTWD" (5 already pushed before CONSTANT runs, matching its
; own "x name --" signature) into scratch, then executes the
; result. Verifies it pushes the stored value (5), not its own
; address - confirmed by tracing CONSTANT's own behavior field:
; it compiles a raw address to ATSIGN (@) there directly via
; CODECOMMA, not CREATE's own placeholder mechanism.
; ------------------------------------------------------------
TSTCONST: LDD  CODEHERE
          STD  TSTCSAV
          LDD  DPHERE
          STD  TSTDSAV
          LDD  VARHERE
          STD  TSTVSAV
          LDD  SRCADDR
          STD  TSTSASAV
          LDD  SRCLEN
          STD  TSTSLSAV
          LDD  TOIN
          STD  TSTTISAV
          LDD  LATEST
          STD  TSTLSAV

          LDA  #'T'
          STA  TSTNAMEB
          LDA  #'E'
          STA  TSTNAMEB+1
          LDA  #'S'
          STA  TSTNAMEB+2
          LDA  #'T'
          STA  TSTNAMEB+3
          LDA  #'W'
          STA  TSTNAMEB+4
          LDA  #'D'
          STA  TSTNAMEB+5

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #TSTDBUF
          STD  DPHERE
          LDD  #TSTVBUF
          STD  VARHERE
          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #6
          STD  SRCLEN
          LDD  #0
          STD  TOIN

          LDD  CODEHERE
          STD  TSTWCFA

          LDD  #5
          PSHU D
          JSR  CONSTANT

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTDSAV
          STD  DPHERE
          LDD  TSTVSAV
          STD  VARHERE
          LDD  TSTSASAV
          STD  SRCADDR
          LDD  TSTSLSAV
          STD  SRCLEN
          LDD  TSTTISAV
          STD  TOIN
          LDD  TSTLSAV
          STD  LATEST

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          LDX  TSTWCFA
          JSR  ,X

          STU  TSTUAF

          PULU D
          CMPD #5
          BNE  CNFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  CNFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  CNFAIL

          LDD  #TRUEV
          BRA  CNDONE
CNFAIL:   LDD  #FALSEV
CNDONE:   LDX  #TSTCONSTNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTCONSTNAME: FCB  8
              FCC  "TSTCONST"

; ------------------------------------------------------------
; TSTCOLON - unit test for : and ; together. Compiles
; ": TESTWD 111 ;" into scratch (COLON parses the name, builds
; a smudged header, sets CSP to the current U as the control-
; flow balance baseline, sets STATE compiling; a literal 111 is
; compiled; SEMI compiles the closing RTS, checks the CSP
; balance, un-smudges the header, restores STATE) - then
; executes the result and verifies it pushes 111. Also verifies
; the header's own SMUDGE bit is correctly clear after SEMI -
; not just that execution happened to work.
; ------------------------------------------------------------
TSTCOLON: LDD  CODEHERE
          STD  TSTCSAV
          LDD  DPHERE
          STD  TSTDSAV
          LDD  VARHERE
          STD  TSTVSAV
          LDD  SRCADDR
          STD  TSTSASAV
          LDD  SRCLEN
          STD  TSTSLSAV
          LDD  TOIN
          STD  TSTTISAV
          LDD  LATEST
          STD  TSTLSAV
          LDD  CSP
          STD  TSTCSPS
          LDD  STATE
          STD  TSTSTSAV

          LDA  #'T'
          STA  TSTNAMEB
          LDA  #'E'
          STA  TSTNAMEB+1
          LDA  #'S'
          STA  TSTNAMEB+2
          LDA  #'T'
          STA  TSTNAMEB+3
          LDA  #'W'
          STA  TSTNAMEB+4
          LDA  #'D'
          STA  TSTNAMEB+5

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #TSTDBUF
          STD  DPHERE
          LDD  #TSTVBUF
          STD  VARHERE
          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #6
          STD  SRCLEN
          LDD  #0
          STD  TOIN

          LDD  CODEHERE
          STD  TSTWCFA

          JSR  COLON

          LDD  #111
          PSHU D
          JSR  LITERALW

          JSR  SEMI

          LDA  TSTDBUF
          ANDA #$40
          STA  TSTSMFLG

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTDSAV
          STD  DPHERE
          LDD  TSTVSAV
          STD  VARHERE
          LDD  TSTSASAV
          STD  SRCADDR
          LDD  TSTSLSAV
          STD  SRCLEN
          LDD  TSTTISAV
          STD  TOIN
          LDD  TSTLSAV
          STD  LATEST
          LDD  TSTCSPS
          STD  CSP
          LDD  TSTSTSAV
          STD  STATE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          LDX  TSTWCFA
          JSR  ,X

          STU  TSTUAF

          PULU D
          CMPD #111
          BNE  CLFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  CLFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  CLFAIL

          TST  TSTSMFLG
          BNE  CLFAIL

          LDD  #TRUEV
          BRA  CLDONE
CLFAIL:   LDD  #FALSEV
CLDONE:   LDX  #TSTCOLONNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTCOLONNAME: FCB  8
              FCC  "TSTCOLON"

; ------------------------------------------------------------
; TSTCRDOES - unit test for CREATE/DOES> together. Compiles the
; equivalent of "CREATE TESTWD 5 , DOES> @ 1+" directly (CREATE,
; store 5 at the PFA, DOES>'s own compile action, then @ and 1+
; compiled as the new behavior, terminated with RTS) - executing
; TESTWD should push 6 (5 fetched, then incremented).
;
; DOES>'s own runtime action (SETDOES) does a documented "double
; return": it patches LATEST's behavior field using the return
; address ITS OWN "JSR SETDOES" call provides, then pops a
; SECOND return address and jumps there - designed for the
; normal case where DOES> is reached from inside an enclosing
; defining word (like a real ": MAKETEST CREATE ... DOES> ... ;"
; would compile), which itself has its own caller. Traced by
; hand: calling directly into the compiled "JSR SETDOES"
; instruction itself (not through an intermediate wrapper)
; naturally supplies exactly the two stack levels SETDOES
; expects - its own JSR provides the first (becoming the new
; behavior field value), and this test's own call provides the
; second (correctly resuming here afterward) - no extra
; scaffolding needed, confirmed correct rather than assumed.
; ------------------------------------------------------------
TSTCRDOES: LDD  CODEHERE
           STD  TSTCSAV
           LDD  DPHERE
           STD  TSTDSAV
           LDD  VARHERE
           STD  TSTVSAV
           LDD  SRCADDR
           STD  TSTSASAV
           LDD  SRCLEN
           STD  TSTSLSAV
           LDD  TOIN
           STD  TSTTISAV
           LDD  LATEST
           STD  TSTLSAV

           LDA  #'T'
           STA  TSTNAMEB
           LDA  #'E'
           STA  TSTNAMEB+1
           LDA  #'S'
           STA  TSTNAMEB+2
           LDA  #'T'
           STA  TSTNAMEB+3
           LDA  #'W'
           STA  TSTNAMEB+4
           LDA  #'D'
           STA  TSTNAMEB+5

           LDD  #TSTCBUF
           STD  CODEHERE
           LDD  #TSTDBUF
           STD  DPHERE
           LDD  #TSTVBUF
           STD  VARHERE
           LDD  #TSTNAMEB
           STD  SRCADDR
           LDD  #6
           STD  SRCLEN
           LDD  #0
           STD  TOIN

           LDD  CODEHERE
           STD  TSTWCFA

           JSR  CREATE

           LDD  #5
           PSHU D
           JSR  COMMA

           LDD  CODEHERE
           STD  TSTDOESA

           JSR  DOESGT

           LDD  #ATSIGN
           PSHU D
           JSR  CCALL

           LDD  #ONEPLUS
           PSHU D
           JSR  CCALL

           LDD  #OPRTS
           PSHU D
           JSR  CCOMMA

           LDD  TSTCSAV
           STD  CODEHERE
           LDD  TSTDSAV
           STD  DPHERE
           LDD  TSTVSAV
           STD  VARHERE
           LDD  TSTSASAV
           STD  SRCADDR
           LDD  TSTSLSAV
           STD  SRCLEN
           LDD  TSTTISAV
           STD  TOIN

           LDX  TSTDOESA  ; BUG FIX: was preceded by restoring LATEST
                          ; to its real value here - but SETDOES
                          ; (confirmed by reading its own code) reads
                          ; LATEST directly to find which header to
                          ; patch, so restoring it first meant SETDOES
                          ; patched the real, wrong word instead of
                          ; TESTWD, leaving TESTWD stuck on its
                          ; original DOESRT0 placeholder. LATEST now
                          ; stays pointed at TESTWD (this test's own
                          ; fake header) until right after this call.
           JSR  ,X

           LDD  TSTLSAV
           STD  LATEST

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           STU  TSTUB4

           LDX  TSTWCFA
           JSR  ,X

           STU  TSTUAF

           PULU D
           CMPD #6
           BNE  CDFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  CDFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #2
           BNE  CDFAIL

           LDD  #TRUEV
           BRA  CDDONE
CDFAIL:    LDD  #FALSEV
CDDONE:    LDX  #TSTCRDOESNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTCRDOESNAME: FCB  9
               FCC  "TSTCRDOES"

; ------------------------------------------------------------
; TST2VAR - unit test for 2VARIABLE. Compiles "2VARIABLE
; TESTWD" into scratch, then executes the result. Verifies it
; pushes its own PFA address (TSTVBUF) and that BOTH cells there
; were correctly initialized to zero.
; ------------------------------------------------------------
TST2VAR: LDD   CODEHERE
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

         JSR   TWOVARIABLE

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
T2VFAIL:  LDD   #FALSEV
T2VDONE:  LDX   #TST2VARNAME
          PSHU  X
          PSHU  D
          JSR   TSTREPORT

          LDU   TSTU0
          RTS

TST2VARNAME: FCB  7
             FCC  "TST2VAR"

; ------------------------------------------------------------
; TST2CONST - unit test for 2CONSTANT. Compiles
; "100 200 2CONSTANT TESTWD" into scratch (x1=100 stored at the
; lower address, x2=200 at the higher, matching 2@/2!'s own
; convention), then executes the result. Verifies it pushes both
; cells correctly ordered (200 on top/popped first, 100 deeper -
; matching 2@'s own documented behavior), not their own address.
; ------------------------------------------------------------
TST2CONST: LDD  CODEHERE
           STD  TSTCSAV
           LDD  DPHERE
           STD  TSTDSAV
           LDD  VARHERE
           STD  TSTVSAV
           LDD  SRCADDR
           STD  TSTSASAV
           LDD  SRCLEN
           STD  TSTSLSAV
           LDD  TOIN
           STD  TSTTISAV
           LDD  LATEST
           STD  TSTLSAV

           LDA  #'T'
           STA  TSTNAMEB
           LDA  #'E'
           STA  TSTNAMEB+1
           LDA  #'S'
           STA  TSTNAMEB+2
           LDA  #'T'
           STA  TSTNAMEB+3
           LDA  #'W'
           STA  TSTNAMEB+4
           LDA  #'D'
           STA  TSTNAMEB+5

           LDD  #TSTCBUF
           STD  CODEHERE
           LDD  #TSTDBUF
           STD  DPHERE
           LDD  #TSTVBUF
           STD  VARHERE
           LDD  #TSTNAMEB
           STD  SRCADDR
           LDD  #6
           STD  SRCLEN
           LDD  #0
           STD  TOIN

           LDD  CODEHERE
           STD  TSTWCFA

           LDD  #100
           PSHU D
           LDD  #200
           PSHU D
           JSR  TWOCONSTANT

           LDD  TSTCSAV
           STD  CODEHERE
           LDD  TSTDSAV
           STD  DPHERE
           LDD  TSTVSAV
           STD  VARHERE
           LDD  TSTSASAV
           STD  SRCADDR
           LDD  TSTSLSAV
           STD  SRCLEN
           LDD  TSTTISAV
           STD  TOIN
           LDD  TSTLSAV
           STD  LATEST

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           STU  TSTUB4

           LDX  TSTWCFA
           JSR  ,X

           STU  TSTUAF

           PULU D
           CMPD #200
           BNE  T2CFAIL
           PULU D
           CMPD #100
           BNE  T2CFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  T2CFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #4
           BNE  T2CFAIL

           LDD  #TRUEV
           BRA  T2CDONE
T2CFAIL:   LDD  #FALSEV
T2CDONE:   LDX  #TST2CONSTNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TST2CONSTNAME: FCB  9
               FCC  "TST2CONST"

; ------------------------------------------------------------
; TSTBUFC - unit test for BUFFER:. Compiles "10 BUFFER: TESTWD"
; into scratch (u=10, the requested size, popped before the name
; is even parsed - confirmed by reading BUFFERCOLON's own code,
; which pops u as its very first action, before calling HEADER),
; then executes the result. Verifies it pushes its own PFA
; address (matching VARIABLE's own DOESRT0 behavior - BUFFER:
; shares it) and that VARHERE genuinely advanced by exactly the
; requested 10 bytes - not just that some space was reserved.
; Contents are documented uninitialized, so not checked.
; ------------------------------------------------------------
TSTBUFC: LDD   CODEHERE
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
         JSR   BUFFERCOLON

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
BFFAIL:  LDD   #FALSEV
BFDONE:  LDX   #TSTBUFCNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTBUFCNAME: FCB  7
             FCC  "TSTBUFC"

; ------------------------------------------------------------
; TSTVALTO - unit test for VALUE and TO together. Compiles
; "42 VALUE TESTWD", executes it (expect 42), then interprets
; "99 TO TESTWD" directly (TO parses "TESTWD" via WORD+FIND,
; needing LATEST still pointed at it - not restored until this
; whole test finishes, unlike every earlier test in this
; section), executes TESTWD again (expect 99). Explicitly forces
; STATE=0 (interpreting) before calling TO, since its own
; behavior genuinely differs by STATE (confirmed by reading its
; code: TOIMMED's direct store path only runs when STATE=0) -
; not left to chance.
; ------------------------------------------------------------
TSTVALTO: LDD  CODEHERE
          STD  TSTCSAV
          LDD  DPHERE
          STD  TSTDSAV
          LDD  VARHERE
          STD  TSTVSAV
          LDD  SRCADDR
          STD  TSTSASAV
          LDD  SRCLEN
          STD  TSTSLSAV
          LDD  TOIN
          STD  TSTTISAV
          LDD  STATE
          STD  TSTSTSAV
          LDD  LATEST
          STD  TSTLSAV

          LDA  #'T'
          STA  TSTNAMEB
          LDA  #'E'
          STA  TSTNAMEB+1
          LDA  #'S'
          STA  TSTNAMEB+2
          LDA  #'T'
          STA  TSTNAMEB+3
          LDA  #'W'
          STA  TSTNAMEB+4
          LDA  #'D'
          STA  TSTNAMEB+5

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #TSTDBUF
          STD  DPHERE
          LDD  #TSTVBUF
          STD  VARHERE
          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #6
          STD  SRCLEN
          LDD  #0
          STD  TOIN

          LDD  CODEHERE
          STD  TSTWCFA

          LDD  #42
          PSHU D
          JSR  VALUEW

          LDD  TSTCSAV
          STD  CODEHERE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          LDX  TSTWCFA
          JSR  ,X

          STU  TSTUAF

          PULU D
          CMPD #42
          LBNE  VTFAIL  ; was BNE - out of short-branch range, since
                        ; VTFAIL sits past this test's entire second
                        ; round (the TO reassignment and re-check)
          PULU D
          CMPD #TSTGUARD
          LBNE  VTFAIL  ; was BNE - same reason

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          LBNE  VTFAIL  ; was BNE - same reason

          LDD  #TSTCBUF2  ; BUG FIX: was TSTCBUF - WORD writes its
                           ; parsed-token output directly at CODEHERE
                           ; (see TSTCBUF2's own comment), which would
                           ; silently overwrite TESTWD's own already-
                           ; compiled trampoline still sitting at
                           ; TSTCBUF, corrupting the CFA TSTWCFA points
                           ; to before this test's second execution.
                           ; Confirmed via MAME: a crash jumping into
                           ; invalid memory at TSTCBUF's own address,
                           ; landing on WORD's own leftover length byte
                           ; instead of the trampoline's real opcode.
          STD  CODEHERE
          LDA  #'T'
          STA  TSTNAMEB
          LDA  #'E'
          STA  TSTNAMEB+1
          LDA  #'S'
          STA  TSTNAMEB+2
          LDA  #'T'
          STA  TSTNAMEB+3
          LDA  #'W'
          STA  TSTNAMEB+4
          LDA  #'D'
          STA  TSTNAMEB+5
          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #6
          STD  SRCLEN
          LDD  #0
          STD  TOIN
          LDD  #0
          STD  STATE

          LDD  #99
          PSHU D
          JSR  TOW

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTDSAV
          STD  DPHERE
          LDD  TSTVSAV
          STD  VARHERE
          LDD  TSTSASAV
          STD  SRCADDR
          LDD  TSTSLSAV
          STD  SRCLEN
          LDD  TSTTISAV
          STD  TOIN
          LDD  TSTSTSAV
          STD  STATE
          LDD  TSTLSAV
          STD  LATEST

          LDD  #TSTGUARD
          PSHU D
          STU   TSTUB4

          LDX  TSTWCFA
          JSR  ,X

          STU  TSTUAF

          PULU D
          CMPD #99
          BNE  VTFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  VTFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  VTFAIL

          LDD  #TRUEV
          BRA  VTDONE
VTFAIL:   LDD  #FALSEV
VTDONE:   LDX  #TSTVALTONAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTVALTONAME: FCB  8
              FCC  "TSTVALTO"

; ------------------------------------------------------------
; TSTDEFER1 - unit test for DEFER, default-action case. Compiles
; "DEFER TESTWD" into scratch, then executes it via CATCH.
; Verifies the default action throws -21 (per DEFER's own
; documented behavior before IS/DEFER! sets a real target) and
; that CATCH's own depth-restoration contract holds - same
; pattern as the divide-by-zero tests in earlier sections.
; ------------------------------------------------------------
TSTDEFER1: LDD  CODEHERE
           STD  TSTCSAV
           LDD  DPHERE
           STD  TSTDSAV
           LDD  VARHERE
           STD  TSTVSAV
           LDD  SRCADDR
           STD  TSTSASAV
           LDD  SRCLEN
           STD  TSTSLSAV
           LDD  TOIN
           STD  TSTTISAV
           LDD  LATEST
           STD  TSTLSAV

           LDA  #'T'
           STA  TSTNAMEB
           LDA  #'E'
           STA  TSTNAMEB+1
           LDA  #'S'
           STA  TSTNAMEB+2
           LDA  #'T'
           STA  TSTNAMEB+3
           LDA  #'W'
           STA  TSTNAMEB+4
           LDA  #'D'
           STA  TSTNAMEB+5

           LDD  #TSTCBUF
           STD  CODEHERE
           LDD  #TSTDBUF
           STD  DPHERE
           LDD  #TSTVBUF
           STD  VARHERE
           LDD  #TSTNAMEB
           STD  SRCADDR
           LDD  #6
           STD  SRCLEN
           LDD  #0
           STD  TOIN

           LDD  CODEHERE
           STD  TSTWCFA

           JSR  DEFERW

           LDD  TSTCSAV
           STD  CODEHERE
           LDD  TSTDSAV
           STD  DPHERE
           LDD  TSTVSAV
           STD  VARHERE
           LDD  TSTSASAV
           STD  SRCADDR
           LDD  TSTSLSAV
           STD  SRCLEN
           LDD  TSTTISAV
           STD  TOIN
           LDD  TSTLSAV
           STD  LATEST

           STU  TSTU0

           LDX  TSTWCFA
           PSHU X
           STU  TSTUB4

           JSR  CATCH

           STU  TSTUAF

           PULU D
           CMPD #-21
           BNE  DF1FAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  DF1FAIL

           LDD  #TRUEV
           BRA  DF1DONE
DF1FAIL:   LDD  #FALSEV
DF1DONE:   LDX  #TSTDEF1NAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTDEF1NAME: FCB  9
             FCC  "TSTDEFER1"

; ------------------------------------------------------------
; TSTDEFER2 - unit test for DEFER together with DEFER!/DEFER@.
; Compiles "DEFER TESTWD", sets its target to DUP's own xt via
; DEFER! (an ordinary runtime word - unlike DEFER's own name-
; parsing, DEFER!/DEFER@ take an xt-defer directly, no WORD/FIND
; needed), executes TESTWD (should now behave like DUP), then
; reads the target back via DEFER@ to confirm it matches.
; ------------------------------------------------------------
TSTDEFER2: LDD  CODEHERE
           STD  TSTCSAV
           LDD  DPHERE
           STD  TSTDSAV
           LDD  VARHERE
           STD  TSTVSAV
           LDD  SRCADDR
           STD  TSTSASAV
           LDD  SRCLEN
           STD  TSTSLSAV
           LDD  TOIN
           STD  TSTTISAV
           LDD  LATEST
           STD  TSTLSAV

           LDA  #'T'
           STA  TSTNAMEB
           LDA  #'E'
           STA  TSTNAMEB+1
           LDA  #'S'
           STA  TSTNAMEB+2
           LDA  #'T'
           STA  TSTNAMEB+3
           LDA  #'W'
           STA  TSTNAMEB+4
           LDA  #'D'
           STA  TSTNAMEB+5

           LDD  #TSTCBUF
           STD  CODEHERE
           LDD  #TSTDBUF
           STD  DPHERE
           LDD  #TSTVBUF
           STD  VARHERE
           LDD  #TSTNAMEB
           STD  SRCADDR
           LDD  #6
           STD  SRCLEN
           LDD  #0
           STD  TOIN

           LDD  CODEHERE
           STD  TSTWCFA

           JSR  DEFERW

           LDD  TSTCSAV
           STD  CODEHERE
           LDD  TSTDSAV
           STD  DPHERE
           LDD  TSTVSAV
           STD  VARHERE
           LDD  TSTSASAV
           STD  SRCADDR
           LDD  TSTSLSAV
           STD  SRCLEN
           LDD  TSTTISAV
           STD  TOIN
           LDD  TSTLSAV
           STD  LATEST

           LDD  #DUP
           PSHU D
           LDX  TSTWCFA
           PSHU X
           JSR  DEFERSTORE

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           LDD  #TSTVAL1
           PSHU D
           STU  TSTUB4

           LDX  TSTWCFA
           JSR  ,X

           STU  TSTUAF

           PULU D
           CMPD #TSTVAL1
           BNE  DF2FAIL
           PULU D
           CMPD #TSTVAL1
           BNE  DF2FAIL
           PULU D
           CMPD #TSTGUARD
           BNE  DF2FAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #2
           BNE  DF2FAIL

           LDX  TSTWCFA
           PSHU X
           JSR  DEFERFETCH

           PULU D
           CMPD #DUP
           BNE  DF2FAIL

           LDD  #TRUEV
           BRA  DF2DONE
DF2FAIL:   LDD  #FALSEV
DF2DONE:   LDX  #TSTDEF2NAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTDEF2NAME: FCB  9
             FCC  "TSTDEFER2"

; ------------------------------------------------------------
; TSTISOF - unit test for IS and ACTION-OF together. Compiles
; "DEFER TESTWD", interprets "DUP IS TESTWD" directly (IS parses
; "TESTWD" via WORD+FIND, needing LATEST still pointed at it -
; not restored until this whole test finishes), executes TESTWD
; (should now behave like DUP), then interprets "ACTION-OF
; TESTWD" to fetch the current target by name and confirms it
; matches DUP's own xt. Explicitly forces STATE=0 before both IS
; and ACTION-OF, since both are documented to behave differently
; by STATE, same reasoning as TSTVALTO's own TO test.
; ------------------------------------------------------------
TSTISOF: LDD   CODEHERE
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

         LDD   #TSTCBUF2  ; BUG FIX: this redirect was missing entirely
                          ; - WORD writes its parsed-token output
                          ; directly at CODEHERE regardless of STATE
                          ; (see TSTCBUF2's own comment), so without
                          ; this, ISW's own internal name-parse would
                          ; write into the real, unredirected CODEHERE -
                          ; unsafe during boot-time testing, before
                          ; COLD has set it to anything meaningful. Not
                          ; TSTCBUF specifically here (unlike TSTVALTO's
                          ; TO-phase fix), since nothing in this phase
                          ; needs TSTCBUF's own contents preserved yet -
                          ; but using the same dedicated buffer
                          ; throughout keeps every phase's redirect
                          ; consistent and safe regardless of order.
         STD   CODEHERE

         LDD   #DUP
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
         LBNE   ISFAIL  ; was BNE - out of short-branch range, since
                        ; ISFAIL sits past this test's entire second
                        ; phase (the ACTION-OF lookup and re-check)
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

         LDD   #TSTCBUF2  ; BUG FIX: same missing redirect as before
                          ; ISW above - ACTIONOF's own internal WORD
                          ; call needs somewhere safe to write its
                          ; parsed-token output too.
         STD   CODEHERE

         JSR   ACTIONOF

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
         CMPD  #DUP
         BNE   ISFAIL

         LDD   #TRUEV
         BRA   ISDONE
ISFAIL:  LDD   #FALSEV
ISDONE:  LDX   #TSTISOFNAME
         PSHU  X
         PSHU  D
         JSR   TSTREPORT

         LDU   TSTU0
         RTS

TSTISOFNAME: FCB  7
             FCC  "TSTISOF"

; ------------------------------------------------------------
; TSTMARKER - unit test for MARKER. Compiles "MARKER TESTWD"
; (CODEHERE/DPHERE/VARHERE redirected to scratch, as with every
; other test in this section), then simulates "something was
; defined after the marker" by manually advancing the redirected
; pointers further and pointing the real LATEST elsewhere,
; executes the marker word, and verifies everything was restored
; to TSTCBUF/TSTDBUF/TSTVBUF directly - the state BEFORE the
; marker word itself was created, not the state right after.
; MARKER's own documented behavior is "forgets itself too" -
; traced MARKERW's own code and confirmed its internal snapshot
; is taken at its very start, before HEADER or any compiling
; runs at all, so that's genuinely the correct restore target,
; not assumed.
;
; DOMARKER (confirmed by reading it directly) writes to the
; real DPHERE/CODEHERE/VARHERE/LATEST unconditionally, not to
; any redirected copy - so this test must execute the marker
; word while CODEHERE/DPHERE/VARHERE are still redirected (their
; real values are restored only afterward), unlike every other
; test in this section, which restores first and executes
; second. Getting this order backwards would have corrupted the
; real dictionary pointers with scratch addresses.
; ------------------------------------------------------------
TSTMARKER: LDD  CODEHERE
           STD  TSTCSAV
           LDD  DPHERE
           STD  TSTDSAV
           LDD  VARHERE
           STD  TSTVSAV
           LDD  SRCADDR
           STD  TSTSASAV
           LDD  SRCLEN
           STD  TSTSLSAV
           LDD  TOIN
           STD  TSTTISAV
           LDD  LATEST
           STD  TSTLSAV

           LDA  #'T'
           STA  TSTNAMEB
           LDA  #'E'
           STA  TSTNAMEB+1
           LDA  #'S'
           STA  TSTNAMEB+2
           LDA  #'T'
           STA  TSTNAMEB+3
           LDA  #'W'
           STA  TSTNAMEB+4
           LDA  #'D'
           STA  TSTNAMEB+5

           LDD  #TSTCBUF
           STD  CODEHERE
           LDD  #TSTDBUF
           STD  DPHERE
           LDD  #TSTVBUF
           STD  VARHERE
           LDD  #TSTNAMEB
           STD  SRCADDR
           LDD  #6
           STD  SRCLEN
           LDD  #0
           STD  TOIN

           LDD  CODEHERE
           STD  TSTWCFA

           JSR  MARKERW

           LDD  SRCLEN
           STD  TSTSLSAV
           LDD  TOIN
           STD  TSTTISAV

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           STU  TSTUB4

           LDD  CODEHERE
           ADDD #30
           STD  CODEHERE
           LDD  DPHERE
           ADDD #30
           STD  DPHERE
           LDD  VARHERE
           ADDD #30
           STD  VARHERE
           LDD  #TSTFHDR
           STD  LATEST

           LDX  TSTWCFA
           JSR  ,X

           STU  TSTUAF

           LDD  CODEHERE
           STD  TSTCSAV2
           LDD  DPHERE
           STD  TSTDSAV2
           LDD  VARHERE
           STD  TSTVSAV2
           LDD  LATEST
           STD  TSTLSAV2

           LDD  TSTCSAV
           STD  CODEHERE
           LDD  TSTDSAV
           STD  DPHERE
           LDD  TSTVSAV
           STD  VARHERE
           LDD  TSTSASAV
           STD  SRCADDR
           LDD  TSTSLSAV
           STD  SRCLEN
           LDD  TSTTISAV
           STD  TOIN

           PULU D
           CMPD #TSTGUARD
           BNE  MKFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  MKFAIL

           LDD  TSTCSAV2  ; BUG FIX: was compared against TSTMKCOD, a
           CMPD #TSTCBUF  ; captured snapshot of CODEHERE right AFTER
                          ; MARKERW finished building its own header -
                          ; wrong target. MARKER's own documented
                          ; behavior is "forgets itself too" - traced
                          ; MARKERW's own code and confirmed its
                          ; snapshot (MKDP/MKCODE/MKVAR/MKLATEST) is
                          ; taken at its very start, before HEADER or
                          ; any compiling runs at all - so DOMARKER
                          ; correctly restores to the state BEFORE the
                          ; marker word itself was created (TSTCBUF
                          ; directly), not the state right after. The
                          ; real dictionary/compile mechanism was
                          ; already working correctly; only this
                          ; test's own comparison target was wrong.
           BNE  MKFAIL
           LDD  TSTDSAV2
           CMPD #TSTDBUF
           BNE  MKFAIL
           LDD  TSTVSAV2
           CMPD #TSTVBUF
           BNE  MKFAIL
           LDD  TSTLSAV2
           CMPD TSTLSAV
           BNE  MKFAIL

           LDD  TSTLSAV
           STD  LATEST

           LDD  #TRUEV
           BRA  MKDONE
MKFAIL:    LDD  TSTLSAV
           STD  LATEST
           LDD  #FALSEV
MKDONE:    LDX  #TSTMARKERNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTMARKERNAME: FCB  9
               FCC  "TSTMARKER"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTCOMPWORDS - compiling-words tests (glossary section 3.10,
; 13 words, 17 tests since several get separate cases: TICK
; found/not-found, ['] compiling/interpreting state, POSTPONE
; normal/immediate word, SLITERAL compiling/interpreting state,
; ABORT" false/true flag). Reuses the scratch infrastructure
; established for sections 3.8/3.9 throughout.
;
; POSTPONE is this section's hardest case: a genuine two-level
; compile-time mechanism. Traced its own code first - for a
; normal word, it compiles code that ITSELF compiles a call to
; that word later, when the current definition eventually runs,
; not immediately (standard ANS semantics: POSTPONE appends a
; word's own compilation semantics to the current definition,
; and for an ordinary word that semantics IS "compile a call to
; it", so appending it only makes sense if the current
; definition later performs that compiling action itself,
; against whatever's being compiled at that later point).
; Verified via the compiled byte sequence directly rather than
; fully executing a triple-nested compile chain.
;
; ABORT" is safely testable for both its flag cases - confirmed
; by reading its own runtime code that it uses THROW -2
; internally, not the raw, never-returns ABORT mechanism plain
; ABORT itself uses (still deliberately untested, per section
; 3.1's own reasoning).
; ------------------------------------------------------------
TSTCOMPWORDS: JSR CRW
           LDX   #TSTCWMSG
           PSHU  X
           LDD   #9
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-9  ; >>>>

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
           JSR   TSTTOBODY
           JSR   TSTEXECUTE
           JSR   TSTSLITERAL1
           JSR   TSTSLITERAL2
           JSR   TSTABORTQ1
           JSR   TSTABORTQ2

           ENDC ; <<<<

           RTS

TSTCWMSG: FCC "CompWords"

           IFEQ TSTSELECTOR-9  ; >>>>

; ------------------------------------------------------------
; Compiling-words test harness (glossary section 3.10). Reuses
; the scratch infrastructure established for sections 3.8/3.9
; (TSTCBUF/TSTCBUF2 for CODEHERE redirects, TSTFHDR for a fake
; dictionary header, TSTNAMEB for a fake source name). POSTPONE
; is this section's own hardest case: a genuine two-level
; compile-time mechanism (compiling code that, for a normal
; word, itself compiles a call to that word later, when the
; current definition eventually runs - not immediately, unlike
; every other compile-time word tested so far). ABORT" is safely
; testable for both its true and false flag cases - traced its
; own runtime behavior directly and confirmed it uses THROW -2
; internally, not the raw, never-returns ABORT mechanism plain
; ABORT itself uses (which remains untested, per section 3.1's
; own reasoning).
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTIMMED - unit test for IMMEDIATE. Builds a fake header (LEN/
; FL=3, no flags), points LATEST at it, calls IMMEDIATE, and
; verifies the header's own LEN/FL byte now has bit 7 set -
; confirmed a memory-only operation with no data-stack effect,
; so the guard check is the whole verification beyond that.
; ------------------------------------------------------------
TSTIMMED: LDD  LATEST
          STD  TSTLSAV

          LDA  #3
          STA  TSTFHDR
          LDA  #'F'
          STA  TSTFHDR+1
          LDA  #'O'
          STA  TSTFHDR+2
          LDA  #'O'
          STA  TSTFHDR+3
          LDD  #0
          STD  TSTFHDR+4
          LDD  #DUP
          STD  TSTFHDR+6

          LDD  #TSTFHDR
          STD  LATEST

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          JSR  IMMEDIATE

          STU  TSTUAF

          LDA  TSTFHDR
          CMPA #$83
          BNE  IMFAIL

          PULU D
          CMPD #TSTGUARD
          BNE  IMFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  IMFAIL

          LDD  #TRUEV
          BRA  IMDONE
IMFAIL:   LDD  #FALSEV
IMDONE:   LDX  #TSTIMMEDNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDD  TSTLSAV
          STD  LATEST

          LDU  TSTU0
          RTS

TSTIMMEDNAME: FCB  8
              FCC  "TSTIMMED"

; ------------------------------------------------------------
; TSTSTATE - unit test for STATE. Verifies it pushes the address
; of the real STATE variable (a plain variable, per its own
; documented "( -- addr )" effect - not its current value).
; ------------------------------------------------------------
TSTSTATE: STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          JSR  STATEW

          STU  TSTUAF

          PULU D
          CMPD #STATE
          BNE  STFAIL2
          PULU D
          CMPD #TSTGUARD
          BNE  STFAIL2

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  STFAIL2

          LDD  #TRUEV
          BRA  STDONE2
STFAIL2:  LDD  #FALSEV
STDONE2:  LDX  #TSTSTATENAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTSTATENAME: FCB  8
              FCC  "TSTSTATE"

; ------------------------------------------------------------
; TSTBRACKETS - unit test for [ and ] together. Verifies ]
; sets STATE to -1 (compiling) and [ sets it back to 0
; (interpreting) - both memory-only operations, no data-stack
; effect.
; ------------------------------------------------------------
TSTBRACKETS: LDD  STATE
             STD  TSTSTSAV

             STU  TSTU0

             LDD  #TSTGUARD
             PSHU D
             STU  TSTUB4

             JSR  RBRACKET

             LDD  STATE
             CMPD #-1
             BNE  BKFAIL

             JSR  LBRACKET

             STU  TSTUAF

             LDD  STATE
             CMPD #0
             BNE  BKFAIL

             PULU D
             CMPD #TSTGUARD
             BNE  BKFAIL

             LDD  TSTUB4
             SUBD TSTUAF
             CMPD #0
             BNE  BKFAIL

             LDD  #TRUEV
             BRA  BKDONE
BKFAIL:      LDD  #FALSEV
BKDONE:      LDX  #TSTBRACKETSNAME
             PSHU X
             PSHU D
             JSR  TSTREPORT

             LDD  TSTSTSAV
             STD  STATE

             LDU  TSTU0
             RTS

TSTBRACKETSNAME: FCB  11
                 FCC  "TSTBRACKETS"

; ------------------------------------------------------------
; TSTTICK1 - unit test for ' (tick), found case. Builds a fake
; header pointing at DUP's own CFA, redirects LATEST to it and
; SRCADDR to a matching fake name, and verifies TICK returns the
; correct xt. Redirects CODEHERE too, even though TICK doesn't
; itself compile anything - WORD's own internal parse still
; writes through it regardless (the same real bug found via MAME
; earlier applies to any word that calls WORD, not just the
; defining words that originally surfaced it).
; ------------------------------------------------------------
TSTTICK1: LDD  CODEHERE
          STD  TSTCSAV
          LDD  LATEST
          STD  TSTLSAV
          LDD  SRCADDR
          STD  TSTSASAV
          LDD  SRCLEN
          STD  TSTSLSAV
          LDD  TOIN
          STD  TSTTISAV

          LDA  #3
          STA  TSTFHDR
          LDA  #'F'
          STA  TSTFHDR+1
          LDA  #'O'
          STA  TSTFHDR+2
          LDA  #'O'
          STA  TSTFHDR+3
          LDD  #0
          STD  TSTFHDR+4
          LDD  #DUP
          STD  TSTFHDR+6

          LDA  #'F'
          STA  TSTNAMEB
          LDA  #'O'
          STA  TSTNAMEB+1
          LDA  #'O'
          STA  TSTNAMEB+2

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #TSTFHDR
          STD  LATEST
          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #3
          STD  SRCLEN
          LDD  #0
          STD  TOIN

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          JSR  TICK

          STU  TSTUAF

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTLSAV
          STD  LATEST
          LDD  TSTSASAV
          STD  SRCADDR
          LDD  TSTSLSAV
          STD  SRCLEN
          LDD  TSTTISAV
          STD  TOIN

          PULU D
          CMPD #DUP
          BNE  TK1FAIL
          PULU D
          CMPD #TSTGUARD
          BNE  TK1FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  TK1FAIL

          LDD  #TRUEV
          BRA  TK1DONE
TK1FAIL:  LDD  #FALSEV
TK1DONE:  LDX  #TSTTICK1NAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTTICK1NAME: FCB  8
              FCC  "TSTTICK1"

; ------------------------------------------------------------
; TSTTICK2 - unit test for ' (tick), not-found case. Redirects
; LATEST to an empty chain (0, the standard chain-terminator
; sentinel used throughout this ROM), so FIND has nothing to
; match. Verifies -13 via CATCH.
; ------------------------------------------------------------
TSTTICK2: LDD  CODEHERE
          STD  TSTCSAV
          LDD  LATEST
          STD  TSTLSAV
          LDD  SRCADDR
          STD  TSTSASAV
          LDD  SRCLEN
          STD  TSTSLSAV
          LDD  TOIN
          STD  TSTTISAV

          LDA  #'F'
          STA  TSTNAMEB
          LDA  #'O'
          STA  TSTNAMEB+1
          LDA  #'O'
          STA  TSTNAMEB+2

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #0
          STD  LATEST
          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #3
          STD  SRCLEN
          LDD  #0
          STD  TOIN

          STU  TSTU0

          LDX  #TICK
          PSHU X
          STU  TSTUB4

          JSR  CATCH

          STU  TSTUAF

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTLSAV
          STD  LATEST
          LDD  TSTSASAV
          STD  SRCADDR
          LDD  TSTSLSAV
          STD  SRCLEN
          LDD  TSTTISAV
          STD  TOIN

          PULU D
          CMPD #-13
          BNE  TK2FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  TK2FAIL

          LDD  #TRUEV
          BRA  TK2DONE
TK2FAIL:  LDD  #FALSEV
TK2DONE:  LDX  #TSTTICK2NAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTTICK2NAME: FCB  8
              FCC  "TSTTICK2"

; ------------------------------------------------------------
; TSTCOMPCOMMA - unit test for COMPILE,. Compiles a call to
; DUP's own xt into scratch, then executes the result with a
; known value to confirm it genuinely behaves like DUP - not
; just that some bytes were written.
; ------------------------------------------------------------
TSTCOMPCOMMA: LDD  CODEHERE
              STD  TSTCSAV

              LDD  #TSTCBUF
              STD  CODEHERE

              LDD  #DUP
              PSHU D
              JSR  COMPILECOMMA

              LDD  #OPRTS
              PSHU D
              JSR  CCOMMA

              LDD  TSTCSAV
              STD  CODEHERE

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              LDD  #TSTVAL1
              PSHU D
              STU  TSTUB4

              LDX  #TSTCBUF
              JSR  ,X

              STU  TSTUAF

              PULU D
              CMPD #TSTVAL1
              BNE  CCFAIL
              PULU D
              CMPD #TSTVAL1
              BNE  CCFAIL
              PULU D
              CMPD #TSTGUARD
              BNE  CCFAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #2
              BNE  CCFAIL

              LDD  #TRUEV
              BRA  CCDONE
CCFAIL:       LDD  #FALSEV
CCDONE:       LDX  #TSTCCNAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTCCNAME: FCB  12
           FCC  "TSTCOMPCOMMA"

; ------------------------------------------------------------
; TSTLITERAL - unit test for LITERAL. Already used extensively
; as an internal helper throughout sections 3.8/3.9's own tests,
; but gets its own dedicated, direct test here too, per this
; section's own coverage. Compiles a known value as a literal,
; then executes the result to confirm it genuinely pushes it.
; ------------------------------------------------------------
TSTLITERAL: LDD  CODEHERE
            STD  TSTCSAV

            LDD  #TSTCBUF
            STD  CODEHERE

            LDD  #TSTVAL1
            PSHU D
            JSR  LITERALW

            LDD  #OPRTS
            PSHU D
            JSR  CCOMMA

            LDD  TSTCSAV
            STD  CODEHERE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            LDX  #TSTCBUF
            JSR  ,X

            STU  TSTUAF

            PULU D
            CMPD #TSTVAL1
            BNE  LIFAIL
            PULU D
            CMPD #TSTGUARD
            BNE  LIFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #2
            BNE  LIFAIL

            LDD  #TRUEV
            BRA  LIDONE
LIFAIL:     LDD  #FALSEV
LIDONE:     LDX  #TSTLITNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTLITNAME: FCB  10
            FCC  "TSTLITERAL"

; ------------------------------------------------------------
; TSTBRACKTICK1 - unit test for ['], compiling-state case.
; Compile-only, so STATE must be -1 for this to work at all
; (confirmed by reading its own code: throws -14 otherwise).
; Builds a fake header pointing at DUP, compiles a literal of
; its xt via ['], then executes the result to confirm it
; genuinely pushes DUP's own xt.
; ------------------------------------------------------------
TSTBRACKTICK1: LDD  CODEHERE
               STD  TSTCSAV
               LDD  LATEST
               STD  TSTLSAV
               LDD  SRCADDR
               STD  TSTSASAV
               LDD  SRCLEN
               STD  TSTSLSAV
               LDD  TOIN
               STD  TSTTISAV
               LDD  STATE
               STD  TSTSTSAV

               LDA  #3
               STA  TSTFHDR
               LDA  #'F'
               STA  TSTFHDR+1
               LDA  #'O'
               STA  TSTFHDR+2
               LDA  #'O'
               STA  TSTFHDR+3
               LDD  #0
               STD  TSTFHDR+4
               LDD  #DUP
               STD  TSTFHDR+6

               LDA  #'F'
               STA  TSTNAMEB
               LDA  #'O'
               STA  TSTNAMEB+1
               LDA  #'O'
               STA  TSTNAMEB+2

               LDD  #TSTCBUF
               STD  CODEHERE
               LDD  #TSTFHDR
               STD  LATEST
               LDD  #TSTNAMEB
               STD  SRCADDR
               LDD  #3
               STD  SRCLEN
               LDD  #0
               STD  TOIN
               LDD  #-1
               STD  STATE

               JSR  BRACKTICK

               LDD  #OPRTS
               PSHU D
               JSR  CCOMMA

               LDD  TSTCSAV
               STD  CODEHERE
               LDD  TSTLSAV
               STD  LATEST
               LDD  TSTSASAV
               STD  SRCADDR
               LDD  TSTSLSAV
               STD  SRCLEN
               LDD  TSTTISAV
               STD  TOIN
               LDD  TSTSTSAV
               STD  STATE

               STU  TSTU0

               LDD  #TSTGUARD
               PSHU D
               STU  TSTUB4

               LDX  #TSTCBUF
               JSR  ,X

               STU  TSTUAF

               PULU D
               CMPD #DUP
               BNE  BT1FAIL
               PULU D
               CMPD #TSTGUARD
               BNE  BT1FAIL

               LDD  TSTUB4
               SUBD TSTUAF
               CMPD #2
               BNE  BT1FAIL

               LDD  #TRUEV
               BRA  BT1DONE
BT1FAIL:       LDD  #FALSEV
BT1DONE:       LDX  #TSTBT1NAME
               PSHU X
               PSHU D
               JSR  TSTREPORT

               LDU  TSTU0
               RTS

TSTBT1NAME: FCB  13
            FCC  "TSTBRACKTICK1"

; ------------------------------------------------------------
; TSTBRACKTICK2 - unit test for ['], interpreting-state case.
; STATE=0, verifies -14 via CATCH.
; ------------------------------------------------------------
TSTBRACKTICK2: LDD  CODEHERE
               STD  TSTCSAV
               LDD  LATEST
               STD  TSTLSAV
               LDD  SRCADDR
               STD  TSTSASAV
               LDD  SRCLEN
               STD  TSTSLSAV
               LDD  TOIN
               STD  TSTTISAV
               LDD  STATE
               STD  TSTSTSAV

               LDA  #'F'
               STA  TSTNAMEB
               LDA  #'O'
               STA  TSTNAMEB+1
               LDA  #'O'
               STA  TSTNAMEB+2

               LDD  #TSTCBUF
               STD  CODEHERE
               LDD  #TSTFHDR
               STD  LATEST
               LDD  #TSTNAMEB
               STD  SRCADDR
               LDD  #3
               STD  SRCLEN
               LDD  #0
               STD  TOIN
               LDD  #0
               STD  STATE

               STU  TSTU0

               LDX  #BRACKTICK
               PSHU X
               STU  TSTUB4

               JSR  CATCH

               STU  TSTUAF

               LDD  TSTCSAV
               STD  CODEHERE
               LDD  TSTLSAV
               STD  LATEST
               LDD  TSTSASAV
               STD  SRCADDR
               LDD  TSTSLSAV
               STD  SRCLEN
               LDD  TSTTISAV
               STD  TOIN
               LDD  TSTSTSAV
               STD  STATE

               PULU D
               CMPD #-14
               BNE  BT2FAIL

               LDD  TSTUB4
               SUBD TSTUAF
               CMPD #0
               BNE  BT2FAIL

               LDD  #TRUEV
               BRA  BT2DONE
BT2FAIL:       LDD  #FALSEV
BT2DONE:       LDX  #TSTBT2NAME
               PSHU X
               PSHU D
               JSR  TSTREPORT

               LDU  TSTU0
               RTS

TSTBT2NAME: FCB  13
            FCC  "TSTBRACKTICK2"

; ------------------------------------------------------------
; TSTPOSTPONE1 - unit test for POSTPONE, normal (non-immediate)
; word case. Traced its own code first: for a normal word,
; POSTPONE compiles "[LIT xt][JSR COMPILE,]" into the current
; definition - NOT a direct call to the word itself. This is
; standard ANS semantics (POSTPONE appends a word's own
; compilation semantics to the current definition; for an
; ordinary word, that semantics IS "compile a call to it", so
; the current definition, when it later runs, must itself
; perform that compiling action against whatever definition is
; being compiled at that later point - not immediately). Given
; the genuine complexity of fully executing that second level
; (which would need a further redirected CODEHERE and a further
; round of execute-and-verify), this test instead verifies the
; compiled byte sequence directly - still a meaningful,
; unambiguous check of POSTPONE's own documented mechanism.
; ------------------------------------------------------------
TSTPOSTPONE1: LDD  CODEHERE
              STD  TSTCSAV
              LDD  LATEST
              STD  TSTLSAV
              LDD  SRCADDR
              STD  TSTSASAV
              LDD  SRCLEN
              STD  TSTSLSAV
              LDD  TOIN
              STD  TSTTISAV
              LDD  STATE
              STD  TSTSTSAV

              LDA  #3
              STA  TSTFHDR
              LDA  #'F'
              STA  TSTFHDR+1
              LDA  #'O'
              STA  TSTFHDR+2
              LDA  #'O'
              STA  TSTFHDR+3
              LDD  #0
              STD  TSTFHDR+4
              LDD  #DUP
              STD  TSTFHDR+6

              LDA  #'F'
              STA  TSTNAMEB
              LDA  #'O'
              STA  TSTNAMEB+1
              LDA  #'O'
              STA  TSTNAMEB+2

              LDD  #TSTCBUF
              STD  CODEHERE
              LDD  #TSTFHDR
              STD  LATEST
              LDD  #TSTNAMEB
              STD  SRCADDR
              LDD  #3
              STD  SRCLEN
              LDD  #0
              STD  TOIN
              LDD  #-1
              STD  STATE

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              JSR  POSTPONEW

              STU  TSTUAF

              LDD  TSTCSAV
              STD  CODEHERE
              LDD  TSTLSAV
              STD  LATEST
              LDD  TSTSASAV
              STD  SRCADDR
              LDD  TSTSLSAV
              STD  SRCLEN
              LDD  TSTTISAV
              STD  TOIN
              LDD  TSTSTSAV
              STD  STATE

              PULU D
              CMPD #TSTGUARD
              BNE  PP1FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #0
              BNE  PP1FAIL

              LDX  #TSTCBUF

              LDA  ,X
              CMPA #OPJSR
              BNE  PP1FAIL
              LDD  1,X
              CMPD #LIT
              BNE  PP1FAIL
              LDD  3,X
              CMPD #DUP
              BNE  PP1FAIL
              LDA  5,X
              CMPA #OPJSR
              BNE  PP1FAIL
              LDD  6,X
              CMPD #COMPILECOMMA
              BNE  PP1FAIL

              LDD  #TRUEV
              BRA  PP1DONE
PP1FAIL:      LDD  #FALSEV
PP1DONE:      LDX  #TSTPP1NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTPP1NAME: FCB  12
            FCC  "TSTPOSTPONE1"

; ------------------------------------------------------------
; TSTPOSTPONE2 - unit test for POSTPONE, immediate word case.
; Confirmed via FIND's own code that it pushes 1 for immediate
; words, -1 otherwise - POSTPONEW branches on exactly that. For
; an immediate word, its own "compilation semantics" IS
; "execute it now" (that's what immediate means), so POSTPONE
; compiles a direct call to it - simpler to verify than the
; normal-word case, no second level involved.
; ------------------------------------------------------------
TSTPOSTPONE2: LDD  CODEHERE
              STD  TSTCSAV
              LDD  LATEST
              STD  TSTLSAV
              LDD  SRCADDR
              STD  TSTSASAV
              LDD  SRCLEN
              STD  TSTSLSAV
              LDD  TOIN
              STD  TSTTISAV
              LDD  STATE
              STD  TSTSTSAV

              LDA  #$83
              STA  TSTFHDR
              LDA  #'F'
              STA  TSTFHDR+1
              LDA  #'O'
              STA  TSTFHDR+2
              LDA  #'O'
              STA  TSTFHDR+3
              LDD  #0
              STD  TSTFHDR+4
              LDD  #SPACEW
              STD  TSTFHDR+6

              LDA  #'F'
              STA  TSTNAMEB
              LDA  #'O'
              STA  TSTNAMEB+1
              LDA  #'O'
              STA  TSTNAMEB+2

              LDD  #TSTCBUF
              STD  CODEHERE
              LDD  #TSTFHDR
              STD  LATEST
              LDD  #TSTNAMEB
              STD  SRCADDR
              LDD  #3
              STD  SRCLEN
              LDD  #0
              STD  TOIN
              LDD  #-1
              STD  STATE

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              JSR  POSTPONEW

              STU  TSTUAF

              LDD  TSTCSAV
              STD  CODEHERE
              LDD  TSTLSAV
              STD  LATEST
              LDD  TSTSASAV
              STD  SRCADDR
              LDD  TSTSLSAV
              STD  SRCLEN
              LDD  TSTTISAV
              STD  TOIN
              LDD  TSTSTSAV
              STD  STATE

              PULU D
              CMPD #TSTGUARD
              BNE  PP2FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #0
              BNE  PP2FAIL

              LDX  #TSTCBUF

              LDA  ,X
              CMPA #OPJSR
              BNE  PP2FAIL
              LDD  1,X
              CMPD #SPACEW
              BNE  PP2FAIL

              LDD  #TRUEV
              BRA  PP2DONE
PP2FAIL:      LDD  #FALSEV
PP2DONE:      LDX  #TSTPP2NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTPP2NAME: FCB  12
            FCC  "TSTPOSTPONE2"

; ------------------------------------------------------------
; TSTTOBODY - unit test for >BODY. Already used extensively as
; an internal helper throughout section 3.9's DEFER@/DEFER!/TO/
; IS tests, but gets its own dedicated test here too.
;
; BUG FIX: this test originally assumed TOBODY returns xt+5
; itself (a pure address computation) - wrong, confirmed via
; MAME: TOBODY computes xt+5, then DEREFERENCES it ("LDD ,X"),
; returning the VALUE stored there, not the address itself. This
; is genuinely correct behavior for this system's own trampoline
; design, not a bug in TOBODY - reconciled directly against why
; section 3.9's DEFER@/DEFER!/TO/IS tests, which relied on this
; same TOBODY and passed on real hardware, never surfaced this:
; those tests set up real trampolines (via VALUEW/DEFERW) whose
; own compile-time code stores a genuinely meaningful value at
; xt+5 (for DEFER, the current target xt; for VALUE, the stored
; value) - "the body" for this system's own design IS the value
; at xt+5, not xt+5's own address. This test never initialized
; TSTCBUF+5 to anything at all, so it was comparing against
; whatever garbage happened to already be there - now sets a
; known value there first and verifies TOBODY returns exactly
; that.
; ------------------------------------------------------------
TSTTOBODY: LDD  #TSTVAL1
           STD  TSTCBUF+5

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           LDD  #TSTCBUF
           PSHU D
           STU  TSTUB4

           JSR  TOBODY

           STU  TSTUAF

           PULU D
           CMPD #TSTVAL1
           BNE  TBFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  TBFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  TBFAIL

           LDD  #TRUEV
           BRA  TBDONE
TBFAIL:    LDD  #FALSEV
TBDONE:    LDX  #TSTTBNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTTBNAME: FCB  9
           FCC  "TSTTOBODY"

; ------------------------------------------------------------
; TSTEXECUTE - unit test for EXECUTE. Executes DUP via its own
; xt with a known value, confirming it genuinely behaves like
; DUP - not just that the call returned.
; ------------------------------------------------------------
TSTEXECUTE: STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #TSTVAL1
            PSHU D
            LDD  #DUP
            PSHU D
            STU  TSTUB4

            JSR  EXECUTE

            STU  TSTUAF

            PULU D
            CMPD #TSTVAL1
            BNE  XQFAIL
            PULU D
            CMPD #TSTVAL1
            BNE  XQFAIL
            PULU D
            CMPD #TSTGUARD
            BNE  XQFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #0
            BNE  XQFAIL

            LDD  #TRUEV
            BRA  XQDONE
XQFAIL:     LDD  #FALSEV
XQDONE:    LDX  #TSTEXECNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTEXECNAME: FCB  10
             FCC  "TSTEXECUTE"

; ------------------------------------------------------------
; TSTSLITERAL1 - unit test for SLITERAL, compiling-state case.
; Compile-only (throws -14 otherwise, per its own code). Pushes
; a known 2-character string, compiles it as a runtime literal,
; then executes the result to confirm it genuinely pushes the
; correct (addr len) pair - checking the actual content at the
; returned address, not just that some address and a length of
; 2 came back.
; ------------------------------------------------------------
TSTSLITERAL1: LDD  CODEHERE
              STD  TSTCSAV
              LDD  STATE
              STD  TSTSTSAV

              LDA  #'A'
              STA  TSTNAMEB
              LDA  #'B'
              STA  TSTNAMEB+1

              LDD  #TSTCBUF
              STD  CODEHERE
              LDD  #-1
              STD  STATE

              LDD  #TSTNAMEB
              PSHU D
              LDD  #2
              PSHU D
              JSR  SLITERALW

              LDD  #OPRTS
              PSHU D
              JSR  CCOMMA

              LDD  TSTCSAV
              STD  CODEHERE
              LDD  TSTSTSAV
              STD  STATE

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              LDX  #TSTCBUF
              JSR  ,X

              STU  TSTUAF

              PULU D
              CMPD #2
              BNE  SL1FAIL

              PULU D
              TFR  D,X
              LDA  ,X
              CMPA #'A'
              BNE  SL1FAIL
              LDA  1,X
              CMPA #'B'
              BNE  SL1FAIL

              PULU D
              CMPD #TSTGUARD
              BNE  SL1FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #4
              BNE  SL1FAIL

              LDD  #TRUEV
              BRA  SL1DONE
SL1FAIL:      LDD  #FALSEV
SL1DONE:      LDX  #TSTSL1NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTSL1NAME: FCB  12
            FCC  "TSTSLITERAL1"

; ------------------------------------------------------------
; TSTSLITERAL2 - unit test for SLITERAL, interpreting-state
; case. STATE=0, verifies -14 via CATCH.
; ------------------------------------------------------------
TSTSLITERAL2: LDD  CODEHERE
              STD  TSTCSAV
              LDD  STATE
              STD  TSTSTSAV

              LDD  #TSTCBUF
              STD  CODEHERE
              LDD  #0
              STD  STATE

              STU  TSTU0

              LDD  #TSTNAMEB
              PSHU D
              LDD  #2
              PSHU D
              LDX  #SLITERALW
              PSHU X
              STU  TSTUB4

              JSR  CATCH

              STU  TSTUAF

              LDD  TSTCSAV
              STD  CODEHERE
              LDD  TSTSTSAV
              STD  STATE

              PULU D
              CMPD #-14
              BNE  SL2FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #0
              BNE  SL2FAIL

              LDD  #TRUEV
              BRA  SL2DONE
SL2FAIL:      LDD  #FALSEV
SL2DONE:      LDX  #TSTSL2NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTSL2NAME: FCB  12
            FCC  "TSTSLITERAL2"

; ------------------------------------------------------------
; TSTABORTQ1 - unit test for ABORT", false-flag case. Compile-
; only (throws -14 otherwise). Compiles ABORT" with a known
; message ("HI"), executes with a false flag, and verifies
; execution genuinely resumes right after the embedded message
; text - confirmed by hand-tracing DOABORTQUOTE's own code: on
; false, it skips past the inline message and returns normally,
; matching its own documented "on false flag: does nothing
; further".
; ------------------------------------------------------------
TSTABORTQ1: LDD  CODEHERE
            STD  TSTCSAV
            LDD  SRCADDR
            STD  TSTSASAV
            LDD  SRCLEN
            STD  TSTSLSAV
            LDD  TOIN
            STD  TSTTISAV
            LDD  STATE
            STD  TSTSTSAV

            LDA  #'H'
            STA  TSTNAMEB
            LDA  #'I'
            STA  TSTNAMEB+1
            LDA  #34
            STA  TSTNAMEB+2

            LDD  #TSTCBUF
            STD  CODEHERE
            LDD  #TSTNAMEB
            STD  SRCADDR
            LDD  #3
            STD  SRCLEN
            LDD  #0
            STD  TOIN
            LDD  #-1
            STD  STATE

            JSR  ABORTQUOTE

            LDD  #OPRTS
            PSHU D
            JSR  CCOMMA

            LDD  TSTCSAV
            STD  CODEHERE
            LDD  TSTSASAV
            STD  SRCADDR
            LDD  TSTSLSAV
            STD  SRCLEN
            LDD  TSTTISAV
            STD  TOIN
            LDD  TSTSTSAV
            STD  STATE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #FALSEV
            PSHU D
            STU  TSTUB4

            LDX  #TSTCBUF
            JSR  ,X

            STU  TSTUAF

            PULU D
            CMPD #TSTGUARD
            BNE  AQ1FAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #-2
            BNE  AQ1FAIL

            LDD  #TRUEV
            BRA  AQ1DONE
AQ1FAIL:    LDD  #FALSEV
AQ1DONE:    LDX  #TSTAQ1NAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTAQ1NAME: FCB  10
            FCC  "TSTABORTQ1"

; ------------------------------------------------------------
; TSTABORTQ2 - unit test for ABORT", true-flag case. Same
; compiled snippet as TSTABORTQ1, executed via CATCH with a true
; flag instead. Confirmed by reading DOABORTQUOTE's own code
; that it uses THROW -2 internally, not the raw, never-returns
; ABORT mechanism plain ABORT itself uses (which remains
; deliberately untested, per section 3.1's own reasoning) - so
; this case is safe to test directly, unlike plain ABORT would
; be.
; ------------------------------------------------------------
TSTABORTQ2: LDD  CODEHERE
            STD  TSTCSAV
            LDD  SRCADDR
            STD  TSTSASAV
            LDD  SRCLEN
            STD  TSTSLSAV
            LDD  TOIN
            STD  TSTTISAV
            LDD  STATE
            STD  TSTSTSAV

            LDA  #'H'
            STA  TSTNAMEB
            LDA  #'I'
            STA  TSTNAMEB+1
            LDA  #34
            STA  TSTNAMEB+2

            LDD  #TSTCBUF
            STD  CODEHERE
            LDD  #TSTNAMEB
            STD  SRCADDR
            LDD  #3
            STD  SRCLEN
            LDD  #0
            STD  TOIN
            LDD  #-1
            STD  STATE

            JSR  ABORTQUOTE

            LDD  #OPRTS
            PSHU D
            JSR  CCOMMA

            LDD  TSTCSAV
            STD  CODEHERE
            LDD  TSTSASAV
            STD  SRCADDR
            LDD  TSTSLSAV
            STD  SRCLEN
            LDD  TSTTISAV
            STD  TOIN
            LDD  TSTSTSAV
            STD  STATE

            STU  TSTU0

            LDD  #TRUEV
            PSHU D
            LDX  #TSTCBUF
            PSHU X
            STU  TSTUB4

            JSR  CATCH

            STU  TSTUAF

            PULU D
            CMPD #-2
            BNE  AQ2FAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #0
            BNE  AQ2FAIL

            LDD  #TRUEV
            BRA  AQ2DONE
AQ2FAIL:    LDD  #FALSEV
AQ2DONE:    LDX  #TSTAQ2NAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTAQ2NAME: FCB  10
            FCC  "TSTABORTQ2"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTMEMORY - memory tests (glossary section 3.11, 22 words, 16
; tests since several are combined into round-trip tests that
; can only be meaningfully verified together: @/!, C@/C!, 2@/2!,
; and the CODEHERE-region words (,/C,/ALLOT/HERE) and VARHERE-
; region words (V,/VC,/VALLOT/VHERE) each combined into one
; sequential walk-through per region.
;
; MOVE is traced from its own code to genuinely choose its copy
; direction by comparing src and dst addresses, delegating to
; CMOVE or CMOVE> to stay overlap-safe - so its own tests
; specifically include both overlap directions (TSTMOVE2/
; TSTMOVE3), each with its expected result hand-derived and
; independently simulated in Python before writing the test, not
; a trivial non-overlapping case alone (TSTMOVE1).
; ------------------------------------------------------------
TSTMEMORY: JSR CRW
           LDX   #TSTMEMMSG
           PSHU  X
           LDD   #6
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-10  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTMEMMSG: FCC "Memory"

           IFEQ TSTSELECTOR-10  ; >>>>

; ------------------------------------------------------------
; Memory test harness (glossary section 3.11). Mostly simpler,
; direct memory-access words (no compile-time behavior, no
; name-parsing) - but , C, ALLOT HERE PAD touch CODEHERE, and
; V, VC, VALLOT VHERE touch VARHERE, so those still need the
; same redirect-based safety established for sections 3.8/3.9.
; TSTCBUF is reused here as general scratch memory for the
; simpler fetch/store tests, safe since each TSTSELECTOR group
; runs exclusively of every other.
;
; MOVE is traced to genuinely choose its copy direction based on
; comparing src and dst addresses (delegating to CMOVE or
; CMOVE> as appropriate) - so its own tests specifically include
; overlapping regions in both directions, not just a trivial
; non-overlapping case, to verify that claim for real.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTFETCHSTORE - unit test for @ and ! together (can only be
; meaningfully tested as a round trip). Stores a known value at
; scratch, fetches it back, verifies the match.
; ------------------------------------------------------------
TSTFETCHSTORE: STU  TSTU0

               LDD  #TSTGUARD
               PSHU D
               LDD  #TSTVAL1
               PSHU D
               LDD  #TSTCBUF
               PSHU D
               STU  TSTUB4

               JSR  STOREW

               LDD  #TSTCBUF
               PSHU D

               JSR  ATSIGN

               STU  TSTUAF

               PULU D
               CMPD #TSTVAL1
               BNE  FSFAIL
               PULU D
               CMPD #TSTGUARD
               BNE  FSFAIL

               LDD  TSTUB4
               SUBD TSTUAF
               CMPD #-2
               BNE  FSFAIL

               LDD  #TRUEV
               BRA  FSDONE
FSFAIL:        LDD  #FALSEV
FSDONE:        LDX  #TSTFSNAME
               PSHU X
               PSHU D
               JSR  TSTREPORT

               LDU  TSTU0
               RTS

TSTFSNAME: FCB  13
           FCC  "TSTFETCHSTORE"

; ------------------------------------------------------------
; TSTCFETCHSTORE - unit test for C@ and C! together. Pre-fills
; the cell with a distinctive nonzero pattern ($FFFF) via a
; direct write (not through C!/C@ themselves), then confirms C!
; genuinely only touches the single byte at the exact address
; given - not the "other half" of a 2-byte cell in some assumed
; sense - and that C@ genuinely zero-extends (not just returns
; whatever was there).
;
; BUG FIX: this test's own expected value after C! was wrong,
; not CSTOREW - confirmed via MAME: expected $FF34 (assuming
; the untouched byte, from the $FFFF pre-fill, would end up as
; the high byte of the word), but CSTOREW writes directly at
; the given address (TSTCBUF itself, the LOWER address), leaving
; TSTCBUF+1 (the higher address) untouched at $FF - and since
; LDD on this big-endian 6809 reads the high byte of the word
; from the lower address first, that's $34FF, not $FF34. The
; single-byte write and the zero-extending fetch were both
; already correct; only this test's own arithmetic about which
; byte ends up where was wrong.
; ------------------------------------------------------------
TSTCFETCHSTORE: LDD  #$FFFF
                STD  TSTCBUF

                STU  TSTU0

                LDD  #TSTGUARD
                PSHU D
                LDD  #$34
                PSHU D
                LDD  #TSTCBUF
                PSHU D
                STU  TSTUB4

                JSR  CSTOREW

                LDD  TSTCBUF
                CMPD #$34FF
                BNE  CFFAIL

                LDD  #TSTCBUF
                PSHU D

                JSR  CFETCH

                STU  TSTUAF

                PULU D
                CMPD #$0034
                BNE  CFFAIL
                PULU D
                CMPD #TSTGUARD
                BNE  CFFAIL

                LDD  TSTUB4
                SUBD TSTUAF
                CMPD #-2
                BNE  CFFAIL

                LDD  #TRUEV
                BRA  CFDONE
CFFAIL:         LDD  #FALSEV
CFDONE:         LDX  #TSTCFNAME
                PSHU X
                PSHU D
                JSR  TSTREPORT

                LDU  TSTU0
                RTS

TSTCFNAME: FCB  14
           FCC  "TSTCFETCHSTORE"

; ------------------------------------------------------------
; TSTPLUSSTORE - unit test for +!. Pre-initializes the cell to a
; known value, adds a known delta, and verifies the sum landed
; correctly.
; ------------------------------------------------------------
TSTPLUSSTORE: LDD  #TSTVAL1
              STD  TSTCBUF

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              LDD  #100
              PSHU D
              LDD  #TSTCBUF
              PSHU D
              STU  TSTUB4

              JSR  PLUSSTORE

              STU  TSTUAF

              LDD  TSTCBUF
              CMPD #TSTVAL1+100
              BNE  PSFAIL

              PULU D
              CMPD #TSTGUARD
              BNE  PSFAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #-4
              BNE  PSFAIL

              LDD  #TRUEV
              BRA  PSDONE
PSFAIL:       LDD  #FALSEV
PSDONE:       LDX  #TSTPSNAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTPSNAME: FCB  12
           FCC  "TSTPLUSSTORE"

; ------------------------------------------------------------
; TST2FETCHSTORE - unit test for 2@ and 2! together. Stores a
; known pair, fetches it back, and verifies the correct
; ordering (x1 at the lower address, x2 at the higher, matching
; the documented convention on both ends).
; ------------------------------------------------------------
TST2FETCHSTORE: STU  TSTU0

                LDD  #TSTGUARD
                PSHU D
                LDD  #TSTVAL1
                PSHU D
                LDD  #TSTVAL2
                PSHU D
                LDD  #TSTCBUF
                PSHU D
                STU  TSTUB4

                JSR  DSTORE

                LDD  #TSTCBUF
                PSHU D

                JSR  DFETCH

                STU  TSTUAF

                PULU D
                CMPD #TSTVAL2
                BNE  DFFAIL
                PULU D
                CMPD #TSTVAL1
                BNE  DFFAIL
                PULU D
                CMPD #TSTGUARD
                BNE  DFFAIL

                LDD  TSTUB4
                SUBD TSTUAF
                CMPD #-2
                BNE  DFFAIL

                LDD  TSTCBUF
                CMPD #TSTVAL1
                BNE  DFFAIL
                LDD  TSTCBUF+2
                CMPD #TSTVAL2
                BNE  DFFAIL

                LDD  #TRUEV
                BRA  DFDONE
DFFAIL:         LDD  #FALSEV
DFDONE:         LDX  #TSTDFNAME
                PSHU X
                PSHU D
                JSR  TSTREPORT

                LDU  TSTU0
                RTS

TSTDFNAME: FCB  14
           FCC  "TST2FETCHSTORE"

; ------------------------------------------------------------
; TSTCODEHERE - combined unit test for , C, ALLOT, and HERE
; together (glossary section 3.11's own CODEHERE-region words).
; Redirects CODEHERE to scratch and walks through a sequence:
; HERE reports the redirected value, COMMA appends a cell (and
; the written cell is verified directly, not just the advance),
; C, appends a byte (verified the same way), ALLOT reserves then
; releases bytes (confirming both directions work, matching
; "reserve (or release, if negative)"), and a final HERE
; confirms the cumulative result.
; ------------------------------------------------------------
TSTCODEHERE: LDD  CODEHERE
             STD  TSTCSAV

             LDD  #TSTCBUF
             STD  CODEHERE

             STU  TSTU0

             LDD  #TSTGUARD
             PSHU D
             STU  TSTUB4

             JSR  HEREW
             PULU D
             CMPD #TSTCBUF
             BNE  CHFAIL

             LDD  #TSTVAL1
             PSHU D
             JSR  COMMA
             LDD  TSTCBUF
             CMPD #TSTVAL1
             BNE  CHFAIL
             LDD  CODEHERE
             CMPD #TSTCBUF+2
             BNE  CHFAIL

             LDD  #$56
             PSHU D
             JSR  CCOMMA
             LDA  TSTCBUF+2
             CMPA #$56
             BNE  CHFAIL
             LDD  CODEHERE
             CMPD #TSTCBUF+3
             BNE  CHFAIL

             LDD  #10
             PSHU D
             JSR  ALLOT
             LDD  CODEHERE
             CMPD #TSTCBUF+13
             BNE  CHFAIL

             LDD  #-4
             PSHU D
             JSR  ALLOT
             LDD  CODEHERE
             CMPD #TSTCBUF+9
             BNE  CHFAIL

             JSR  HEREW
             PULU D
             CMPD #TSTCBUF+9
             BNE  CHFAIL

             STU  TSTUAF

             PULU D
             CMPD #TSTGUARD
             BNE  CHFAIL

             LDD  TSTUB4
             SUBD TSTUAF
             CMPD #0
             BNE  CHFAIL

             LDD  #TRUEV
             BRA  CHDONE
CHFAIL:      LDD  #FALSEV
CHDONE:      LDX  #TSTCHNAME
             PSHU X
             PSHU D
             JSR  TSTREPORT

             LDD  TSTCSAV
             STD  CODEHERE

             LDU  TSTU0
             RTS

TSTCHNAME: FCB  11
           FCC  "TSTCODEHERE"

; ------------------------------------------------------------
; TSTVARHERE - combined unit test for V, VC, VALLOT, and VHERE
; together - same structure as TSTCODEHERE, but for the
; mutable/variable region (VARHERE) instead.
; ------------------------------------------------------------
TSTVARHERE: LDD  VARHERE
            STD  TSTVSAV

            LDD  #TSTVBUF
            STD  VARHERE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            JSR  VHEREW
            PULU D
            CMPD #TSTVBUF
            BNE  VHFAIL

            LDD  #TSTVAL1
            PSHU D
            JSR  VCOMMA
            LDD  TSTVBUF
            CMPD #TSTVAL1
            BNE  VHFAIL
            LDD  VARHERE
            CMPD #TSTVBUF+2
            BNE  VHFAIL

            LDD  #$56
            PSHU D
            JSR  VCCOMMA
            LDA  TSTVBUF+2
            CMPA #$56
            BNE  VHFAIL
            LDD  VARHERE
            CMPD #TSTVBUF+3
            BNE  VHFAIL

            LDD  #10
            PSHU D
            JSR  VALLOT
            LDD  VARHERE
            CMPD #TSTVBUF+13
            BNE  VHFAIL

            LDD  #-4
            PSHU D
            JSR  VALLOT
            LDD  VARHERE
            CMPD #TSTVBUF+9
            BNE  VHFAIL

            JSR  VHEREW
            PULU D
            CMPD #TSTVBUF+9
            BNE  VHFAIL

            STU  TSTUAF

            PULU D
            CMPD #TSTGUARD
            BNE  VHFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #0
            BNE  VHFAIL

            LDD  #TRUEV
            BRA  VHDONE
VHFAIL:     LDD  #FALSEV
VHDONE:     LDX  #TSTVHNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDD  TSTVSAV
            STD  VARHERE

            LDU  TSTU0
            RTS

TSTVHNAME: FCB  10
           FCC  "TSTVARHERE"

; ------------------------------------------------------------
; TSTPAD - unit test for PAD. Redirects CODEHERE, verifies PAD
; reports CODEHERE+PADOFFSET, using the same symbolic constant
; PADW's own code uses rather than a hardcoded number.
; ------------------------------------------------------------
TSTPAD: LDD  CODEHERE
        STD  TSTCSAV

        LDD  #TSTCBUF
        STD  CODEHERE

        STU  TSTU0

        LDD  #TSTGUARD
        PSHU D
        STU  TSTUB4

        JSR  PADW

        STU  TSTUAF

        PULU D
        CMPD #TSTCBUF+PADOFFSET
        BNE  PAFAIL
        PULU D
        CMPD #TSTGUARD
        BNE  PAFAIL

        LDD  TSTUB4
        SUBD TSTUAF
        CMPD #2
        BNE  PAFAIL

        LDD  #TRUEV
        BRA  PADONE
PAFAIL: LDD  #FALSEV
PADONE: LDX  #TSTPADNAME
        PSHU X
        PSHU D
        JSR  TSTREPORT

        LDD  TSTCSAV
        STD  CODEHERE

        LDU  TSTU0
        RTS

TSTPADNAME: FCB  6
            FCC  "TSTPAD"

; ------------------------------------------------------------
; TSTUNUSED - unit test for UNUSED. Redirects CODEHERE, verifies
; UNUSED reports CODETOP-CODEHERE, using the same symbolic
; constant UNUSEDW's own code uses.
; ------------------------------------------------------------
TSTUNUSED: LDD  CODEHERE
           STD  TSTCSAV

           LDD  #TSTCBUF
           STD  CODEHERE

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           STU  TSTUB4

           JSR  UNUSEDW

           STU  TSTUAF

           PULU D
           CMPD #CODETOP-TSTCBUF
           BNE  UNFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  UNFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #2
           BNE  UNFAIL

           LDD  #TRUEV
           BRA  UNDONE
UNFAIL:    LDD  #FALSEV
UNDONE:    LDX  #TSTUNNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDD  TSTCSAV
           STD  CODEHERE

           LDU  TSTU0
           RTS

TSTUNNAME: FCB  9
           FCC  "TSTUNUSED"

; ------------------------------------------------------------
; TSTVUNUSED - unit test for VUNUSED. Redirects VARHERE, verifies
; VUNUSED reports APPVARSEND-VARHERE, using the same symbolic
; constant VUNUSEDW's own code uses (per its own bug-fix comment,
; confirmed already correct - this was the real bug found and
; fixed earlier in a prior session, not something to re-litigate
; here, just confirm holds).
; ------------------------------------------------------------
TSTVUNUSED: LDD  VARHERE
            STD  TSTVSAV

            LDD  #TSTVBUF
            STD  VARHERE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            JSR  VUNUSEDW

            STU  TSTUAF

            PULU D
            CMPD #APPVARSEND-TSTVBUF
            BNE  VUFAIL
            PULU D
            CMPD #TSTGUARD
            BNE  VUFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #2
            BNE  VUFAIL

            LDD  #TRUEV
            BRA  VUDONE
VUFAIL:     LDD  #FALSEV
VUDONE:     LDX  #TSTVUNNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDD  TSTVSAV
            STD  VARHERE

            LDU  TSTU0
            RTS

TSTVUNNAME: FCB  10
            FCC  "TSTVUNUSED"

; ------------------------------------------------------------
; TSTFILL - unit test for FILL. Fills 5 scratch bytes with a
; known character, then verifies every one of the 5 bytes
; individually - not just spot-checking the first and last.
; ------------------------------------------------------------
TSTFILL: STU  TSTU0

         LDD  #TSTGUARD
         PSHU D
         LDD  #TSTCBUF
         PSHU D
         LDD  #5
         PSHU D
         LDD  #$41
         PSHU D
         STU  TSTUB4

         JSR  FILLW

         STU  TSTUAF

         LDX  #TSTCBUF
         LDB  #5
FILVLP:  LDA  ,X+
         CMPA #$41
         BNE  FLFAIL
         DECB
         BNE  FILVLP

         PULU D
         CMPD #TSTGUARD
         BNE  FLFAIL

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #-6
         BNE  FLFAIL

         LDD  #TRUEV
         BRA  FLDONE
FLFAIL:  LDD  #FALSEV
FLDONE:  LDX  #TSTFLNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDU  TSTU0
         RTS

TSTFLNAME: FCB  7
           FCC  "TSTFILL"

; ------------------------------------------------------------
; TSTERASE - unit test for ERASE. Pre-fills scratch with a
; nonzero pattern first (so a no-op couldn't accidentally pass),
; erases it, and verifies every byte is genuinely zero.
; ------------------------------------------------------------
TSTERASE: LDX  #TSTCBUF
          LDB  #5
ERSETLP:  LDA  #$FF
          STA  ,X+
          DECB
          BNE  ERSETLP

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTCBUF
          PSHU D
          LDD  #5
          PSHU D
          STU  TSTUB4

          JSR  ERASEW

          STU  TSTUAF

          LDX  #TSTCBUF
          LDB  #5
ERSVLP:   LDA  ,X+
          CMPA #0
          BNE  ERFAIL
          DECB
          BNE  ERSVLP

          PULU D
          CMPD #TSTGUARD
          BNE  ERFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-4
          BNE  ERFAIL

          LDD  #TRUEV
          BRA  ERDONE
ERFAIL:   LDD  #FALSEV
ERDONE:   LDX  #TSTERNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTERNAME: FCB  8
           FCC  "TSTERASE"

; ------------------------------------------------------------
; TSTCMOVE - unit test for CMOVE. Non-overlapping regions (well
; separated within TSTCBUF's own 80 bytes) - CMOVE's own
; overlap-unsafe behavior in the high-over-low direction is
; exactly what MOVE exists to route around, so CMOVE's own
; tests stick to the simple, well-defined case; see TSTMOVE2/
; TSTMOVE3 below for the overlap-specific verification.
; ------------------------------------------------------------
TSTCMOVE: LDA  #'A'
          STA  TSTCBUF
          LDA  #'B'
          STA  TSTCBUF+1
          LDA  #'C'
          STA  TSTCBUF+2
          LDA  #'D'
          STA  TSTCBUF+3
          LDA  #'E'
          STA  TSTCBUF+4

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTCBUF
          PSHU D
          LDD  #TSTCBUF+10
          PSHU D
          LDD  #5
          PSHU D
          STU  TSTUB4

          JSR  CMOVEW

          STU  TSTUAF

          LDA  TSTCBUF+10
          CMPA #'A'
          BNE  CVFAIL
          LDA  TSTCBUF+11
          CMPA #'B'
          BNE  CVFAIL
          LDA  TSTCBUF+12
          CMPA #'C'
          BNE  CVFAIL
          LDA  TSTCBUF+13
          CMPA #'D'
          BNE  CVFAIL
          LDA  TSTCBUF+14
          CMPA #'E'
          BNE  CVFAIL

          PULU D
          CMPD #TSTGUARD
          BNE  CVFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-6
          BNE  CVFAIL

          LDD  #TRUEV
          BRA  CVDONE
CVFAIL:   LDD  #FALSEV
CVDONE:   LDX  #TSTCMNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTCMNAME: FCB  8
           FCC  "TSTCMOVE"

; ------------------------------------------------------------
; TSTCMOVEGT - unit test for CMOVE>. Non-overlapping regions,
; same reasoning as TSTCMOVE.
; ------------------------------------------------------------
TSTCMOVEGT: LDA  #'A'
            STA  TSTCBUF
            LDA  #'B'
            STA  TSTCBUF+1
            LDA  #'C'
            STA  TSTCBUF+2
            LDA  #'D'
            STA  TSTCBUF+3
            LDA  #'E'
            STA  TSTCBUF+4

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #TSTCBUF
            PSHU D
            LDD  #TSTCBUF+10
            PSHU D
            LDD  #5
            PSHU D
            STU  TSTUB4

            JSR  CMOVEGT

            STU  TSTUAF

            LDA  TSTCBUF+10
            CMPA #'A'
            BNE  CXFAIL
            LDA  TSTCBUF+11
            CMPA #'B'
            BNE  CXFAIL
            LDA  TSTCBUF+12
            CMPA #'C'
            BNE  CXFAIL
            LDA  TSTCBUF+13
            CMPA #'D'
            BNE  CXFAIL
            LDA  TSTCBUF+14
            CMPA #'E'
            BNE  CXFAIL

            PULU D
            CMPD #TSTGUARD
            BNE  CXFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #-6
            BNE  CXFAIL

            LDD  #TRUEV
            BRA  CXDONE
CXFAIL:     LDD  #FALSEV
CXDONE:     LDX  #TSTCGNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTCGNAME: FCB  10
           FCC  "TSTCMOVEGT"

; ------------------------------------------------------------
; TSTMOVE1 - unit test for MOVE, non-overlapping sanity case.
; ------------------------------------------------------------
TSTMOVE1: LDA  #'A'
          STA  TSTCBUF
          LDA  #'B'
          STA  TSTCBUF+1
          LDA  #'C'
          STA  TSTCBUF+2
          LDA  #'D'
          STA  TSTCBUF+3
          LDA  #'E'
          STA  TSTCBUF+4

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTCBUF
          PSHU D
          LDD  #TSTCBUF+20
          PSHU D
          LDD  #5
          PSHU D
          STU  TSTUB4

          JSR  MOVEW

          STU  TSTUAF

          LDA  TSTCBUF+20
          CMPA #'A'
          BNE  MV1FAIL
          LDA  TSTCBUF+21
          CMPA #'B'
          BNE  MV1FAIL
          LDA  TSTCBUF+22
          CMPA #'C'
          BNE  MV1FAIL
          LDA  TSTCBUF+23
          CMPA #'D'
          BNE  MV1FAIL
          LDA  TSTCBUF+24
          CMPA #'E'
          BNE  MV1FAIL

          PULU D
          CMPD #TSTGUARD
          BNE  MV1FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-6
          BNE  MV1FAIL

          LDD  #TRUEV
          BRA  MV1DONE
MV1FAIL:  LDD  #FALSEV
MV1DONE:  LDX  #TSTMV1NAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTMV1NAME: FCB  8
            FCC  "TSTMOVE1"

; ------------------------------------------------------------
; TSTMOVE2 - unit test for MOVE, overlapping case with dst >
; src (dst = TSTCBUF+2, src = TSTCBUF, 5 bytes - a 2-byte
; forward shift). MOVE's own code compares addresses and
; delegates to CMOVE> (high-to-low) whenever dst > src,
; specifically to avoid the corruption a naive low-to-high copy
; would cause here (byte 2 would get overwritten by the copy
; before ever being read as a source byte). Expected result
; hand-derived and independently simulated in Python before
; writing this test, not guessed: "ABABCDE" across bytes 0-6.
; ------------------------------------------------------------
TSTMOVE2: LDA  #'A'
          STA  TSTCBUF
          LDA  #'B'
          STA  TSTCBUF+1
          LDA  #'C'
          STA  TSTCBUF+2
          LDA  #'D'
          STA  TSTCBUF+3
          LDA  #'E'
          STA  TSTCBUF+4
          LDA  #'X'
          STA  TSTCBUF+5
          LDA  #'X'
          STA  TSTCBUF+6

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTCBUF
          PSHU D
          LDD  #TSTCBUF+2
          PSHU D
          LDD  #5
          PSHU D
          STU  TSTUB4

          JSR  MOVEW

          STU  TSTUAF

          LDA  TSTCBUF
          CMPA #'A'
          BNE  MV2FAIL
          LDA  TSTCBUF+1
          CMPA #'B'
          BNE  MV2FAIL
          LDA  TSTCBUF+2
          CMPA #'A'
          BNE  MV2FAIL
          LDA  TSTCBUF+3
          CMPA #'B'
          BNE  MV2FAIL
          LDA  TSTCBUF+4
          CMPA #'C'
          BNE  MV2FAIL
          LDA  TSTCBUF+5
          CMPA #'D'
          BNE  MV2FAIL
          LDA  TSTCBUF+6
          CMPA #'E'
          BNE  MV2FAIL

          PULU D
          CMPD #TSTGUARD
          BNE  MV2FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-6
          BNE  MV2FAIL

          LDD  #TRUEV
          BRA  MV2DONE
MV2FAIL:  LDD  #FALSEV
MV2DONE:  LDX  #TSTMV2NAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTMV2NAME: FCB  8
            FCC  "TSTMOVE2"

; ------------------------------------------------------------
; TSTMOVE3 - unit test for MOVE, overlapping case with dst <
; src (dst = TSTCBUF, src = TSTCBUF+2, 5 bytes - a 2-byte
; backward shift). MOVE delegates to plain CMOVE (low-to-high)
; whenever dst < src, avoiding the mirror-image corruption a
; naive high-to-low copy would cause here. Expected result
; hand-derived and independently simulated before writing:
; "ABCDEDE" across bytes 0-6 (bytes 5-6 untouched, outside the
; destination range).
; ------------------------------------------------------------
TSTMOVE3: LDA  #'X'
          STA  TSTCBUF
          LDA  #'X'
          STA  TSTCBUF+1
          LDA  #'A'
          STA  TSTCBUF+2
          LDA  #'B'
          STA  TSTCBUF+3
          LDA  #'C'
          STA  TSTCBUF+4
          LDA  #'D'
          STA  TSTCBUF+5
          LDA  #'E'
          STA  TSTCBUF+6

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTCBUF+2
          PSHU D
          LDD  #TSTCBUF
          PSHU D
          LDD  #5
          PSHU D
          STU  TSTUB4

          JSR  MOVEW

          STU  TSTUAF

          LDA  TSTCBUF
          CMPA #'A'
          BNE  MV3FAIL
          LDA  TSTCBUF+1
          CMPA #'B'
          BNE  MV3FAIL
          LDA  TSTCBUF+2
          CMPA #'C'
          BNE  MV3FAIL
          LDA  TSTCBUF+3
          CMPA #'D'
          BNE  MV3FAIL
          LDA  TSTCBUF+4
          CMPA #'E'
          BNE  MV3FAIL
          LDA  TSTCBUF+5
          CMPA #'D'
          BNE  MV3FAIL
          LDA  TSTCBUF+6
          CMPA #'E'
          BNE  MV3FAIL

          PULU D
          CMPD #TSTGUARD
          BNE  MV3FAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-6
          BNE  MV3FAIL

          LDD  #TRUEV
          BRA  MV3DONE
MV3FAIL:  LDD  #FALSEV
MV3DONE:  LDX  #TSTMV3NAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTMV3NAME: FCB  8
            FCC  "TSTMOVE3"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTSTRPARSE - strings & parsing tests (glossary section 3.12,
; 16 words, 19 tests since several get separate cases: [CHAR]
; compiling/interpreting state, S" compiling/interpreting state
; (this word genuinely has both), SEARCH found/not-found,
; REPLACES/SUBSTITUTE combined across two tests (covering all 4
; of SUBSTITUTE's own documented %-delimiter cases), SNAME
; found/not-found.
;
; . has no STATE check at all in its own code (confirmed by
; reading it directly - matches "no interpretation semantics,
; per ANS" without a specific -14 throw, unlike [CHAR]/S"), so
; only its compiling case is tested. Its own runtime calls TYPE
; internally, so its own test applies the SERIALPOLL-conditional
; lesson from section 3.1 from the start, rather than
; re-discovering it via a failed MAME run.
;
; SUBSTITUTE/REPLACES/UNESCAPE all carry extensive prior-session
; bug-fix history in their own comments - confirmed fresh against
; the actual current code (not re-derived from scratch), and
; SUBSTITUTE's own expected outputs independently simulated in
; Python against the traced algorithm before writing the tests,
; not hand-derived and assumed correct.
;
; Note: this section's own COMPARE (string comparison) word's
; test is named TSTSCOMPARE, not TSTCOMPARE - the latter was
; already taken by section 3.7's own comparison-operators group
; wrapper, caught by the standard collision check before
; insertion.
; ------------------------------------------------------------
TSTSTRPARSE: JSR CRW
           LDX   #TSTSTRPMSG
           PSHU  X
           LDD   #8
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-11  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTSTRPMSG: FCC "StrParse"

           IFEQ TSTSELECTOR-11  ; >>>>

; ------------------------------------------------------------
; Strings & Parsing test harness (glossary section 3.12). Reuses
; the redirect infrastructure from sections 3.8-3.10 for the
; name-parsing words (WORD/CHAR/[CHAR]/S"/."). DOTQUOTE's own
; runtime (DOTSTR) calls TYPE internally, which - per section
; 3.1's own already-debugged finding - has two entirely
; different implementations gated by SERIALPOLL; its own test
; below applies that same lesson from the start rather than
; re-discovering it.
;
; SUBSTITUTE/REPLACES/UNESCAPE all have extensive prior-session
; bug-fix history baked into their own comments (SUBSTITUTE's
; %-delimiter algorithm, UNESCAPE's doubling-not-escaping
; behavior) - trusted as ground truth here (each confirmed via a
; prior MAME-tested session), verified fresh against the actual
; code rather than re-derived from scratch, and tested against
; that confirmed, current behavior.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTCOUNT - unit test for COUNT. Builds a counted string at
; scratch, verifies the returned (addr len) correctly skips the
; count byte and reports its value.
; ------------------------------------------------------------
TSTCOUNT: LDA  #5
          STA  TSTCBUF
          LDA  #'H'
          STA  TSTCBUF+1
          LDA  #'E'
          STA  TSTCBUF+2
          LDA  #'L'
          STA  TSTCBUF+3
          LDA  #'L'
          STA  TSTCBUF+4
          LDA  #'O'
          STA  TSTCBUF+5

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTCBUF
          PSHU D
          STU  TSTUB4

          JSR  COUNT

          STU  TSTUAF

          PULU D
          CMPD #5
          BNE  CTFAIL
          PULU D
          CMPD #TSTCBUF+1
          BNE  CTFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  CTFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  CTFAIL

          LDD  #TRUEV
          BRA  CTDONE
CTFAIL:   LDD  #FALSEV
CTDONE:   LDX  #TSTCTNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTCTNAME: FCB  8
           FCC  "TSTCOUNT"

; ------------------------------------------------------------
; TSTCHARW - unit test for CHAR. Redirects CODEHERE (WORD's own
; parse output still lands there internally, even though CHAR
; itself doesn't compile anything) and the source, parses a
; space-delimited fake source ("AB CD"), and verifies it returns
; 'A' - the first character of the first word.
; ------------------------------------------------------------
TSTCHARW: LDD  CODEHERE
          STD  TSTCSAV
          LDD  SRCADDR
          STD  TSTSASAV
          LDD  SRCLEN
          STD  TSTSLSAV
          LDD  TOIN
          STD  TSTTISAV

          LDA  #'A'
          STA  TSTNAMEB
          LDA  #'B'
          STA  TSTNAMEB+1
          LDA  #32
          STA  TSTNAMEB+2
          LDA  #'C'
          STA  TSTNAMEB+3
          LDA  #'D'
          STA  TSTNAMEB+4

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #5
          STD  SRCLEN
          LDD  #0
          STD  TOIN

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          JSR  CHARW

          STU  TSTUAF

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTSASAV
          STD  SRCADDR
          LDD  TSTSLSAV
          STD  SRCLEN
          LDD  TSTTISAV
          STD  TOIN

          PULU D
          CMPD #'A'
          BNE  CWFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  CWFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  CWFAIL

          LDD  #TRUEV
          BRA  CWDONE
CWFAIL:   LDD  #FALSEV
CWDONE:   LDX  #TSTCWNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTCWNAME: FCB  8
           FCC  "TSTCHARW"

; ------------------------------------------------------------
; TSTBRACKCHAR1 - unit test for [CHAR], compiling-state case.
; Compile-only (throws -14 otherwise, per its own STATE check).
; Compiles the character as a literal, then executes the result
; to confirm it genuinely pushes 'A'.
; ------------------------------------------------------------
TSTBRACKCHAR1: LDD  CODEHERE
               STD  TSTCSAV
               LDD  SRCADDR
               STD  TSTSASAV
               LDD  SRCLEN
               STD  TSTSLSAV
               LDD  TOIN
               STD  TSTTISAV
               LDD  STATE
               STD  TSTSTSAV

               LDA  #'A'
               STA  TSTNAMEB
               LDA  #'B'
               STA  TSTNAMEB+1
               LDA  #32
               STA  TSTNAMEB+2

               LDD  #TSTCBUF
               STD  CODEHERE
               LDD  #TSTNAMEB
               STD  SRCADDR
               LDD  #3
               STD  SRCLEN
               LDD  #0
               STD  TOIN
               LDD  #-1
               STD  STATE

               JSR  BRACKCHAR

               LDD  #OPRTS
               PSHU D
               JSR  CCOMMA

               LDD  TSTCSAV
               STD  CODEHERE
               LDD  TSTSASAV
               STD  SRCADDR
               LDD  TSTSLSAV
               STD  SRCLEN
               LDD  TSTTISAV
               STD  TOIN
               LDD  TSTSTSAV
               STD  STATE

               STU  TSTU0

               LDD  #TSTGUARD
               PSHU D
               STU  TSTUB4

               LDX  #TSTCBUF
               JSR  ,X

               STU  TSTUAF

               PULU D
               CMPD #'A'
               BNE  BC1FAIL
               PULU D
               CMPD #TSTGUARD
               BNE  BC1FAIL

               LDD  TSTUB4
               SUBD TSTUAF
               CMPD #2
               BNE  BC1FAIL

               LDD  #TRUEV
               BRA  BC1DONE
BC1FAIL:       LDD  #FALSEV
BC1DONE:       LDX  #TSTBC1NAME
               PSHU X
               PSHU D
               JSR  TSTREPORT

               LDU  TSTU0
               RTS

TSTBC1NAME: FCB  13
            FCC  "TSTBRACKCHAR1"

; ------------------------------------------------------------
; TSTBRACKCHAR2 - unit test for [CHAR], interpreting-state case.
; STATE=0, verifies -14 via CATCH.
; ------------------------------------------------------------
TSTBRACKCHAR2: LDD  CODEHERE
               STD  TSTCSAV
               LDD  SRCADDR
               STD  TSTSASAV
               LDD  SRCLEN
               STD  TSTSLSAV
               LDD  TOIN
               STD  TSTTISAV
               LDD  STATE
               STD  TSTSTSAV

               LDA  #'A'
               STA  TSTNAMEB
               LDA  #'B'
               STA  TSTNAMEB+1
               LDA  #32
               STA  TSTNAMEB+2

               LDD  #TSTCBUF
               STD  CODEHERE
               LDD  #TSTNAMEB
               STD  SRCADDR
               LDD  #3
               STD  SRCLEN
               LDD  #0
               STD  TOIN
               LDD  #0
               STD  STATE

               STU  TSTU0

               LDX  #BRACKCHAR
               PSHU X
               STU  TSTUB4

               JSR  CATCH

               STU  TSTUAF

               LDD  TSTCSAV
               STD  CODEHERE
               LDD  TSTSASAV
               STD  SRCADDR
               LDD  TSTSLSAV
               STD  SRCLEN
               LDD  TSTTISAV
               STD  TOIN
               LDD  TSTSTSAV
               STD  STATE

               PULU D
               CMPD #-14
               BNE  BC2FAIL

               LDD  TSTUB4
               SUBD TSTUAF
               CMPD #0
               BNE  BC2FAIL

               LDD  #TRUEV
               BRA  BC2DONE
BC2FAIL:       LDD  #FALSEV
BC2DONE:       LDX  #TSTBC2NAME
               PSHU X
               PSHU D
               JSR  TSTREPORT

               LDU  TSTU0
               RTS

TSTBC2NAME: FCB  13
            FCC  "TSTBRACKCHAR2"

; ------------------------------------------------------------
; TSTPARSE - unit test for PARSE. Uses a fake source starting
; with the delimiter itself (",XY", delimiter ',') specifically
; to verify PARSE's own documented distinguishing behavior -
; "does not skip leading delimiters, unlike WORD" - the leading
; comma should be hit immediately, returning a zero-length token
; right where TOIN started, not skipped over to find "XY".
; ------------------------------------------------------------
TSTPARSE: LDD  SRCADDR
          STD  TSTSASAV
          LDD  SRCLEN
          STD  TSTSLSAV
          LDD  TOIN
          STD  TSTTISAV

          LDA  #','
          STA  TSTNAMEB
          LDA  #'X'
          STA  TSTNAMEB+1
          LDA  #'Y'
          STA  TSTNAMEB+2

          LDD  #TSTNAMEB
          STD  SRCADDR
          LDD  #3
          STD  SRCLEN
          LDD  #0
          STD  TOIN

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #','
          PSHU D
          STU  TSTUB4

          JSR  PARSEW

          STU  TSTUAF

          LDD  TSTSASAV
          STD  SRCADDR
          LDD  TSTSLSAV
          STD  SRCLEN
          LDD  TSTTISAV
          STD  TOIN

          PULU D
          CMPD #0
          BNE  PRFAIL
          PULU D
          CMPD #TSTNAMEB
          BNE  PRFAIL
          PULU D
          CMPD #TSTGUARD
          BNE  PRFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #2
          BNE  PRFAIL

          LDD  #TRUEV
          BRA  PRDONE
PRFAIL:   LDD  #FALSEV
PRDONE:   LDX  #TSTPRNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTPRNAME: FCB  8
           FCC  "TSTPARSE"

; ------------------------------------------------------------
; TSTPARSENAME - unit test for PARSE-NAME. Fake source with 2
; leading spaces before the token ("  AB CD"), verifying it
; genuinely skips them - the opposite of PARSE's own behavior,
; confirming the two aren't accidentally sharing one code path
; that only happens to work for one of them.
; ------------------------------------------------------------
TSTPARSENAME: LDD  SRCADDR
              STD  TSTSASAV
              LDD  SRCLEN
              STD  TSTSLSAV
              LDD  TOIN
              STD  TSTTISAV

              LDA  #32
              STA  TSTNAMEB
              LDA  #32
              STA  TSTNAMEB+1
              LDA  #'A'
              STA  TSTNAMEB+2
              LDA  #'B'
              STA  TSTNAMEB+3
              LDA  #32
              STA  TSTNAMEB+4
              LDA  #'C'
              STA  TSTNAMEB+5
              LDA  #'D'
              STA  TSTNAMEB+6

              LDD  #TSTNAMEB
              STD  SRCADDR
              LDD  #7
              STD  SRCLEN
              LDD  #0
              STD  TOIN

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              JSR  PARSENAME

              STU  TSTUAF

              LDD  TSTSASAV
              STD  SRCADDR
              LDD  TSTSLSAV
              STD  SRCLEN
              LDD  TSTTISAV
              STD  TOIN

              PULU D
              CMPD #2
              BNE  PZFAIL
              PULU D
              CMPD #TSTNAMEB+2
              BNE  PZFAIL
              PULU D
              CMPD #TSTGUARD
              BNE  PZFAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #4
              BNE  PZFAIL

              LDD  #TRUEV
              BRA  PZDONE
PZFAIL:       LDD  #FALSEV
PZDONE:       LDX  #TSTPNNAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTPNNAME: FCB  12
           FCC  "TSTPARSENAME"

; ------------------------------------------------------------
; TSTSQUOTE1 - unit test for S", compiling-state case. Compiles
; a known 2-character string, then executes the result to
; confirm it genuinely pushes (addr len) with the correct
; content at addr - not just that the call returned two numbers.
; ------------------------------------------------------------
TSTSQUOTE1: LDD  CODEHERE
            STD  TSTCSAV
            LDD  SRCADDR
            STD  TSTSASAV
            LDD  SRCLEN
            STD  TSTSLSAV
            LDD  TOIN
            STD  TSTTISAV
            LDD  STATE
            STD  TSTSTSAV

            LDA  #'H'
            STA  TSTNAMEB
            LDA  #'I'
            STA  TSTNAMEB+1
            LDA  #34
            STA  TSTNAMEB+2

            LDD  #TSTCBUF
            STD  CODEHERE
            LDD  #TSTNAMEB
            STD  SRCADDR
            LDD  #3
            STD  SRCLEN
            LDD  #0
            STD  TOIN
            LDD  #-1
            STD  STATE

            JSR  SQUOTE

            LDD  #OPRTS
            PSHU D
            JSR  CCOMMA

            LDD  TSTCSAV
            STD  CODEHERE
            LDD  TSTSASAV
            STD  SRCADDR
            LDD  TSTSLSAV
            STD  SRCLEN
            LDD  TSTTISAV
            STD  TOIN
            LDD  TSTSTSAV
            STD  STATE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            LDX  #TSTCBUF
            JSR  ,X

            STU  TSTUAF

            PULU D
            CMPD #2
            BNE  SQ1FAIL

            PULU D
            TFR  D,X
            LDA  ,X
            CMPA #'H'
            BNE  SQ1FAIL
            LDA  1,X
            CMPA #'I'
            BNE  SQ1FAIL

            PULU D
            CMPD #TSTGUARD
            BNE  SQ1FAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #4
            BNE  SQ1FAIL

            LDD  #TRUEV
            BRA  SQ1DONE
SQ1FAIL:    LDD  #FALSEV
SQ1DONE:    LDX  #TSTSQ1NAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTSQ1NAME: FCB  10
            FCC  "TSTSQUOTE1"

; ------------------------------------------------------------
; TSTSQUOTE2 - unit test for S", interpreting-state case.
; Redirects CODEHERE first so PAD's own computed address (which
; SQUOTE's own interpreting branch writes to) is predictable,
; then calls S" directly (no compile/execute step needed, since
; interpreting S" stages the string and returns immediately) and
; verifies the returned (addr len) content, plus that addr
; genuinely landed at PAD's current, redirected address.
; ------------------------------------------------------------
TSTSQUOTE2: LDD  CODEHERE
            STD  TSTCSAV
            LDD  SRCADDR
            STD  TSTSASAV
            LDD  SRCLEN
            STD  TSTSLSAV
            LDD  TOIN
            STD  TSTTISAV
            LDD  STATE
            STD  TSTSTSAV

            LDA  #'H'
            STA  TSTNAMEB
            LDA  #'I'
            STA  TSTNAMEB+1
            LDA  #34
            STA  TSTNAMEB+2

            LDD  #TSTCBUF
            STD  CODEHERE
            LDD  #TSTNAMEB
            STD  SRCADDR
            LDD  #3
            STD  SRCLEN
            LDD  #0
            STD  TOIN
            LDD  #0
            STD  STATE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            JSR  SQUOTE

            STU  TSTUAF

            LDD  TSTCSAV
            STD  CODEHERE
            LDD  TSTSASAV
            STD  SRCADDR
            LDD  TSTSLSAV
            STD  SRCLEN
            LDD  TSTTISAV
            STD  TOIN
            LDD  TSTSTSAV
            STD  STATE

            PULU D
            CMPD #2
            BNE  SQ2FAIL

            PULU D
            CMPD #TSTCBUF+PADOFFSET
            BNE  SQ2FAIL

            TFR  D,X
            LDA  ,X
            CMPA #'H'
            BNE  SQ2FAIL
            LDA  1,X
            CMPA #'I'
            BNE  SQ2FAIL

            PULU D
            CMPD #TSTGUARD
            BNE  SQ2FAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #4
            BNE  SQ2FAIL

            LDD  #TRUEV
            BRA  SQ2DONE
SQ2FAIL:    LDD  #FALSEV
SQ2DONE:    LDX  #TSTSQ2NAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTSQ2NAME: FCB  10
            FCC  "TSTSQUOTE2"

; ------------------------------------------------------------
; TSTDOTQUOTE - unit test for .". No STATE check at all in its
; own code (confirmed by reading it directly - matches "no
; interpretation semantics, per ANS" without a specific -14
; throw, unlike [CHAR]/S"), so only the compiling case is
; tested, matching how it's actually meant to be used. Its own
; runtime (DOTSTR) calls TYPE internally, which has two entirely
; different implementations gated by SERIALPOLL (the same real
; finding from section 3.1) - applying that lesson from the
; start here rather than re-discovering it: EMITCH works
; universally for a single-character check, but this outputs
; multiple characters, so - matching TSTCR's own established
; fix - the full OUTHEAD/OUTBUF check only applies under
; SERIALPOLL=0, with a narrower EMITCH-based check (last
; character only, plus the stack-depth check) for SERIALPOLL=1.
; ------------------------------------------------------------
TSTDOTQUOTE: LDD  CODEHERE
             STD  TSTCSAV
             LDD  SRCADDR
             STD  TSTSASAV
             LDD  SRCLEN
             STD  TSTSLSAV
             LDD  TOIN
             STD  TSTTISAV

             LDA  #'H'
             STA  TSTNAMEB
             LDA  #'I'
             STA  TSTNAMEB+1
             LDA  #34
             STA  TSTNAMEB+2

             LDD  #TSTCBUF
             STD  CODEHERE
             LDD  #TSTNAMEB
             STD  SRCADDR
             LDD  #3
             STD  SRCLEN
             LDD  #0
             STD  TOIN

             JSR  DOTQUOTE

             LDD  #OPRTS
             PSHU D
             JSR  CCOMMA

             LDD  TSTCSAV
             STD  CODEHERE
             LDD  TSTSASAV
             STD  SRCADDR
             LDD  TSTSLSAV
             STD  SRCLEN
             LDD  TSTTISAV
             STD  TOIN

             IFEQ SERIALPOLL  ; >>>>
             LDA  OUTHEAD
             STA  TSTOHSAV
             ENDC ; <<<<

             STU  TSTU0

             LDD  #TSTGUARD
             PSHU D
             STU  TSTUB4

             LDX  #TSTCBUF
             JSR  ,X

             STU  TSTUAF

             IFEQ SERIALPOLL  ; >>>>
             LDA  TSTOHSAV
             ADDA #2
             ANDA #OUTBUFSZ-1
             CMPA OUTHEAD
             BNE  DXFAIL

             LDX  #OUTBUF
             LDB  TSTOHSAV
             LDA  B,X
             CMPA #'H'
             BNE  DXFAIL
             INCB
             ANDB #OUTBUFSZ-1
             LDA  B,X
             CMPA #'I'
             BNE  DXFAIL
             ELSE  ; <<<<>>>>
             LDA  EMITCH
             CMPA #'I'
             BNE  DXFAIL
             ENDC  ; <<<<<<<<<<

             PULU D
             CMPD #TSTGUARD
             BNE  DXFAIL

             LDD  TSTUB4
             SUBD TSTUAF
             CMPD #0
             BNE  DXFAIL

             LDD  #TRUEV
             BRA  DXDONE
DXFAIL:      LDD  #FALSEV
DXDONE:      LDX  #TSTDQNAME
             PSHU X
             PSHU D
             JSR  TSTREPORT

             LDU  TSTU0
             RTS

TSTDQNAME: FCB  11
           FCC  "TSTDOTQUOTE"

; ------------------------------------------------------------
; TSTSCOMPARE - unit test for COMPARE. Four sequential sub-cases
; within one test body, each popping and verifying its own
; result immediately: less-than, equal, greater-than, and the
; prefix tie-break case specifically (a shorter string that's a
; true prefix of a longer one compares less, per the standard
; three-way convention) - not just LT/EQ/GT on same-length
; strings, which alone wouldn't exercise the tie-break path at
; all.
; ------------------------------------------------------------
TSTSCOMPARE: LDA  #'A'
            STA  TSTCBUF
            LDA  #'B'
            STA  TSTCBUF+1
            LDA  #'A'
            STA  TSTCBUF+2
            LDA  #'C'
            STA  TSTCBUF+3

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            LDD  #TSTCBUF
            PSHU D
            LDD  #2
            PSHU D
            LDD  #TSTCBUF+2
            PSHU D
            LDD  #2
            PSHU D
            JSR  COMPAREW
            PULU D
            CMPD #-1
            BNE  CQFAIL

            LDD  #TSTCBUF
            PSHU D
            LDD  #2
            PSHU D
            LDD  #TSTCBUF
            PSHU D
            LDD  #2
            PSHU D
            JSR  COMPAREW
            PULU D
            CMPD #0
            BNE  CQFAIL

            LDD  #TSTCBUF+2
            PSHU D
            LDD  #2
            PSHU D
            LDD  #TSTCBUF
            PSHU D
            LDD  #2
            PSHU D
            JSR  COMPAREW
            PULU D
            CMPD #1
            BNE  CQFAIL

            LDD  #TSTCBUF
            PSHU D
            LDD  #2
            PSHU D
            LDD  #TSTCBUF
            PSHU D
            LDD  #3
            PSHU D
            JSR  COMPAREW
            PULU D
            CMPD #-1
            BNE  CQFAIL

            STU  TSTUAF

            PULU D
            CMPD #TSTGUARD
            BNE  CQFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #0
            BNE  CQFAIL

            LDD  #TRUEV
            BRA  CQDONE
CQFAIL:     LDD  #FALSEV
CQDONE:     LDX  #TSTCQNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTCQNAME: FCB  11
           FCC  "TSTSCOMPARE"

; ------------------------------------------------------------
; TSTSEARCH1 - unit test for SEARCH, found case. Haystack
; "HELLOWORLD", needle "WOR" - verifies the returned addr3 lands
; exactly at the match position (not just that flag is true),
; len3 equals the needle's own length, and flag is true.
; ------------------------------------------------------------
TSTSEARCH1: LDA  #'H'
            STA  TSTCBUF
            LDA  #'E'
            STA  TSTCBUF+1
            LDA  #'L'
            STA  TSTCBUF+2
            LDA  #'L'
            STA  TSTCBUF+3
            LDA  #'O'
            STA  TSTCBUF+4
            LDA  #'W'
            STA  TSTCBUF+5
            LDA  #'O'
            STA  TSTCBUF+6
            LDA  #'R'
            STA  TSTCBUF+7
            LDA  #'L'
            STA  TSTCBUF+8
            LDA  #'D'
            STA  TSTCBUF+9

            LDA  #'W'
            STA  TSTCBUF+20
            LDA  #'O'
            STA  TSTCBUF+21
            LDA  #'R'
            STA  TSTCBUF+22

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #TSTCBUF
            PSHU D
            LDD  #10
            PSHU D
            LDD  #TSTCBUF+20
            PSHU D
            LDD  #3
            PSHU D
            STU  TSTUB4

            JSR  SEARCHW

            STU  TSTUAF

            PULU D
            CMPD #TRUEV
            BNE  SR1FAIL
            PULU D
            CMPD #3
            BNE  SR1FAIL
            PULU D
            CMPD #TSTCBUF+5
            BNE  SR1FAIL
            PULU D
            CMPD #TSTGUARD
            BNE  SR1FAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #-2
            BNE  SR1FAIL

            LDD  #TRUEV
            BRA  SR1DONE
SR1FAIL:    LDD  #FALSEV
SR1DONE:    LDX  #TSTSR1NAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTSR1NAME: FCB  10
            FCC  "TSTSEARCH1"

; ------------------------------------------------------------
; TSTSEARCH2 - unit test for SEARCH, not-found case. Verifies
; addr3/len3 fall back to the original haystack (addr1/len1)
; unchanged, and flag is false.
; ------------------------------------------------------------
TSTSEARCH2: LDA  #'H'
            STA  TSTCBUF
            LDA  #'E'
            STA  TSTCBUF+1
            LDA  #'L'
            STA  TSTCBUF+2
            LDA  #'L'
            STA  TSTCBUF+3
            LDA  #'O'
            STA  TSTCBUF+4

            LDA  #'X'
            STA  TSTCBUF+20
            LDA  #'Y'
            STA  TSTCBUF+21

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #TSTCBUF
            PSHU D
            LDD  #5
            PSHU D
            LDD  #TSTCBUF+20
            PSHU D
            LDD  #2
            PSHU D
            STU  TSTUB4

            JSR  SEARCHW

            STU  TSTUAF

            PULU D
            CMPD #FALSEV
            BNE  SR2FAIL
            PULU D
            CMPD #5
            BNE  SR2FAIL
            PULU D
            CMPD #TSTCBUF
            BNE  SR2FAIL
            PULU D
            CMPD #TSTGUARD
            BNE  SR2FAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #-2
            BNE  SR2FAIL

            LDD  #TRUEV
            BRA  SR2DONE
SR2FAIL:    LDD  #FALSEV
SR2DONE:    LDX  #TSTSR2NAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTSR2NAME: FCB  10
            FCC  "TSTSEARCH2"

; ------------------------------------------------------------
; TSTDASHTRAILING - unit test for -TRAILING. "AB   " (2 letters,
; 3 trailing spaces, len=5) trims to len=2, addr unchanged -
; confirmed via its own code that it's a peek-and-modify-top
; operation on the stack, not a pop-then-push of a new addr.
; ------------------------------------------------------------
TSTDASHTRAILING: LDA  #'A'
                 STA  TSTCBUF
                 LDA  #'B'
                 STA  TSTCBUF+1
                 LDA  #32
                 STA  TSTCBUF+2
                 LDA  #32
                 STA  TSTCBUF+3
                 LDA  #32
                 STA  TSTCBUF+4

                 STU  TSTU0

                 LDD  #TSTGUARD
                 PSHU D
                 LDD  #TSTCBUF
                 PSHU D
                 LDD  #5
                 PSHU D
                 STU  TSTUB4

                 JSR  DASHTRAILING

                 STU  TSTUAF

                 PULU D
                 CMPD #2
                 BNE  DTFAIL2
                 PULU D
                 CMPD #TSTCBUF
                 BNE  DTFAIL2
                 PULU D
                 CMPD #TSTGUARD
                 BNE  DTFAIL2

                 LDD  TSTUB4
                 SUBD TSTUAF
                 CMPD #0
                 BNE  DTFAIL2

                 LDD  #TRUEV
                 BRA  DTDONE2
DTFAIL2:         LDD  #FALSEV
DTDONE2:         LDX  #TSTDTNAME
                 PSHU X
                 PSHU D
                 JSR  TSTREPORT

                 LDU  TSTU0
                 RTS

TSTDTNAME: FCB  15
           FCC  "TSTDASHTRAILING"

; ------------------------------------------------------------
; TSTSLASHSTRING - unit test for /STRING. "HELLO" trimmed by 2
; from the front - verifies both the advanced address and the
; reduced length.
; ------------------------------------------------------------
TSTSLASHSTRING: LDA  #'H'
                STA  TSTCBUF
                LDA  #'E'
                STA  TSTCBUF+1
                LDA  #'L'
                STA  TSTCBUF+2
                LDA  #'L'
                STA  TSTCBUF+3
                LDA  #'O'
                STA  TSTCBUF+4

                STU  TSTU0

                LDD  #TSTGUARD
                PSHU D
                LDD  #TSTCBUF
                PSHU D
                LDD  #5
                PSHU D
                LDD  #2
                PSHU D
                STU  TSTUB4

                JSR  SLASHSTRING

                STU  TSTUAF

                PULU D
                CMPD #3
                BNE  SLSFAIL
                PULU D
                CMPD #TSTCBUF+2
                BNE  SLSFAIL
                PULU D
                CMPD #TSTGUARD
                BNE  SLSFAIL

                LDD  TSTUB4
                SUBD TSTUAF
                CMPD #-2
                BNE  SLSFAIL

                LDD  #TRUEV
                BRA  SLSDONE
SLSFAIL:        LDD  #FALSEV
SLSDONE:        LDX  #TSTSLSNAME
                PSHU X
                PSHU D
                JSR  TSTREPORT

                LDU  TSTU0
                RTS

TSTSLSNAME: FCB  14
            FCC  "TSTSLASHSTRING"

; ------------------------------------------------------------
; TSTREPLSUBS1 - unit test for REPLACES and SUBSTITUTE together
; (can only be meaningfully tested together - SUBSTITUTE depends
; on a prior REPLACES registration). Registers "X"->"Z", then
; runs the template "%%A%X%B%Y%" through SUBSTITUTE - covering
; three of the four documented cases in one pass: "%%" collapses
; to a single '%', "%X%" (a registered name) gets replaced
; (count incremented), and "%Y%" (not registered) passes through
; unchanged, delimiters included. Expected result ("%AZB%Y%",
; count=1) independently simulated in Python against the actual
; traced algorithm before writing this test, not hand-derived
; and hoped correct - see TSTREPLSUBS2 for the fourth case
; (unpaired trailing '%'), tested separately for clearer failure
; diagnosis.
; ------------------------------------------------------------
TSTREPLSUBS1: LDA  #'Z'
              STA  TSTCBUF

              LDA  #'X'
              STA  TSTCBUF+10

              LDA  #'%'
              STA  TSTCBUF+20
              LDA  #'%'
              STA  TSTCBUF+21
              LDA  #'A'
              STA  TSTCBUF+22
              LDA  #'%'
              STA  TSTCBUF+23
              LDA  #'X'
              STA  TSTCBUF+24
              LDA  #'%'
              STA  TSTCBUF+25
              LDA  #'B'
              STA  TSTCBUF+26
              LDA  #'%'
              STA  TSTCBUF+27
              LDA  #'Y'
              STA  TSTCBUF+28
              LDA  #'%'
              STA  TSTCBUF+29

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              LDD  #TSTCBUF
              PSHU D
              LDD  #1
              PSHU D
              LDD  #TSTCBUF+10
              PSHU D
              LDD  #1
              PSHU D
              JSR  REPLACESW

              LDD  #TSTCBUF+20
              PSHU D
              LDD  #10
              PSHU D
              LDD  #TSTCBUF+40
              PSHU D
              LDD  #20
              PSHU D
              JSR  SUBSTITUTEW

              STU  TSTUAF

              PULU D
              CMPD #1
              BNE  RS1FAIL
              PULU D
              CMPD #7
              BNE  RS1FAIL
              PULU D
              CMPD #TSTCBUF+40
              BNE  RS1FAIL

              LDX  #TSTCBUF+40
              LDA  ,X
              CMPA #'%'
              BNE  RS1FAIL
              LDA  1,X
              CMPA #'A'
              BNE  RS1FAIL
              LDA  2,X
              CMPA #'Z'
              BNE  RS1FAIL
              LDA  3,X
              CMPA #'B'
              BNE  RS1FAIL
              LDA  4,X
              CMPA #'%'
              BNE  RS1FAIL
              LDA  5,X
              CMPA #'Y'
              BNE  RS1FAIL
              LDA  6,X
              CMPA #'%'
              BNE  RS1FAIL

              PULU D
              CMPD #TSTGUARD
              BNE  RS1FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #6
              BNE  RS1FAIL

              LDD  #TRUEV
              BRA  RS1DONE
RS1FAIL:      LDD  #FALSEV
RS1DONE:      LDX  #TSTRS1NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTRS1NAME: FCB  12
            FCC  "TSTREPLSUBS1"

; ------------------------------------------------------------
; TSTREPLSUBS2 - unit test for SUBSTITUTE's fourth documented
; case: an unpaired trailing '%' with no closing delimiter
; anywhere in the remainder passes the residue through
; unchanged. Template "AB%CD" (the '%' never finds a partner)
; -> "AB%CD", count=0. Same REPLACES registration reused from
; TSTREPLSUBS1's own reasoning - a second REPLACES call
; overwrites the first (documented as single-slot only), so this
; test registers its own pair fresh rather than relying on any
; prior test's own registration still being active.
; ------------------------------------------------------------
TSTREPLSUBS2: LDA  #'Z'
              STA  TSTCBUF

              LDA  #'X'
              STA  TSTCBUF+10

              LDA  #'A'
              STA  TSTCBUF+20
              LDA  #'B'
              STA  TSTCBUF+21
              LDA  #'%'
              STA  TSTCBUF+22
              LDA  #'C'
              STA  TSTCBUF+23
              LDA  #'D'
              STA  TSTCBUF+24

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              LDD  #TSTCBUF
              PSHU D
              LDD  #1
              PSHU D
              LDD  #TSTCBUF+10
              PSHU D
              LDD  #1
              PSHU D
              JSR  REPLACESW

              LDD  #TSTCBUF+20
              PSHU D
              LDD  #5
              PSHU D
              LDD  #TSTCBUF+40
              PSHU D
              LDD  #20
              PSHU D
              JSR  SUBSTITUTEW

              STU  TSTUAF

              PULU D
              CMPD #0
              BNE  RS2FAIL
              PULU D
              CMPD #5
              BNE  RS2FAIL
              PULU D
              CMPD #TSTCBUF+40
              BNE  RS2FAIL

              LDX  #TSTCBUF+40
              LDA  ,X
              CMPA #'A'
              BNE  RS2FAIL
              LDA  1,X
              CMPA #'B'
              BNE  RS2FAIL
              LDA  2,X
              CMPA #'%'
              BNE  RS2FAIL
              LDA  3,X
              CMPA #'C'
              BNE  RS2FAIL
              LDA  4,X
              CMPA #'D'
              BNE  RS2FAIL

              PULU D
              CMPD #TSTGUARD
              BNE  RS2FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #6
              BNE  RS2FAIL

              LDD  #TRUEV
              BRA  RS2DONE
RS2FAIL:      LDD  #FALSEV
RS2DONE:      LDX  #TSTRS2NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTRS2NAME: FCB  12
            FCC  "TSTREPLSUBS2"

; ------------------------------------------------------------
; TSTSNAME1 - unit test for SNAME, found case. Searches the
; real, live dictionary (confirmed via its own code that it
; walks from the real LATEST, not a redirectable copy - no
; redirect needed or possible here) for DUP's own xt, verifying
; the returned name content matches "DUP" exactly, not just a
; nonzero length.
; ------------------------------------------------------------
TSTSNAME1: STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           LDD  #DUP
           PSHU D
           STU  TSTUB4

           JSR  SNAMEW

           STU  TSTUAF

           PULU D
           CMPD #3
           BNE  SN1FAIL

           PULU D
           TFR  D,X
           LDA  ,X
           CMPA #'D'
           BNE  SN1FAIL
           LDA  1,X
           CMPA #'U'
           BNE  SN1FAIL
           LDA  2,X
           CMPA #'P'
           BNE  SN1FAIL

           PULU D
           CMPD #TSTGUARD
           BNE  SN1FAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #2
           BNE  SN1FAIL

           LDD  #TRUEV
           BRA  SN1DONE
SN1FAIL:   LDD  #FALSEV
SN1DONE:   LDX  #TSTSN1NAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTSN1NAME: FCB  9
            FCC  "TSTSNAME1"

; ------------------------------------------------------------
; TSTSNAME2 - unit test for SNAME, not-found case. TSTCBUF (a
; scratch APPVARS address, nowhere near the real code/dictionary
; region) doesn't match any real word's own CFA - verifies
; SNAME correctly reports (0 0) rather than a false match or a
; crash walking off the end of the chain.
; ------------------------------------------------------------
TSTSNAME2: STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           LDD  #TSTCBUF
           PSHU D
           STU  TSTUB4

           JSR  SNAMEW

           STU  TSTUAF

           PULU D
           CMPD #0
           BNE  SN2FAIL
           PULU D
           CMPD #0
           BNE  SN2FAIL
           PULU D
           CMPD #TSTGUARD
           BNE  SN2FAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #2
           BNE  SN2FAIL

           LDD  #TRUEV
           BRA  SN2DONE
SN2FAIL:   LDD  #FALSEV
SN2DONE:   LDX  #TSTSN2NAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTSN2NAME: FCB  9
            FCC  "TSTSNAME2"

; ------------------------------------------------------------
; TSTUNESCAPE - unit test for UNESCAPE. Source "A%B" (3 chars,
; one '%' in the middle) doubles the '%' to produce "A%%B" (4
; chars) - confirmed via its own code and a prior session's
; already-corrected design comment that this is genuinely a
; doubling operation, not backslash-sequence decoding. Verifies
; every output character individually and the grown length,
; not just that some output was produced.
; ------------------------------------------------------------
TSTUNESCAPE: LDA  #'A'
             STA  TSTCBUF
             LDA  #'%'
             STA  TSTCBUF+1
             LDA  #'B'
             STA  TSTCBUF+2

             STU  TSTU0

             LDD  #TSTGUARD
             PSHU D
             LDD  #TSTCBUF
             PSHU D
             LDD  #3
             PSHU D
             LDD  #TSTCBUF+10
             PSHU D
             STU  TSTUB4

             JSR  UNESCAPEW

             STU  TSTUAF

             PULU D
             CMPD #4
             BNE  UXFAIL
             PULU D
             CMPD #TSTCBUF+10
             BNE  UXFAIL

             TFR  D,X
             LDA  ,X
             CMPA #'A'
             BNE  UXFAIL
             LDA  1,X
             CMPA #'%'
             BNE  UXFAIL
             LDA  2,X
             CMPA #'%'
             BNE  UXFAIL
             LDA  3,X
             CMPA #'B'
             BNE  UXFAIL

             PULU D
             CMPD #TSTGUARD
             BNE  UXFAIL

             LDD  TSTUB4
             SUBD TSTUAF
             CMPD #-2
             BNE  UXFAIL

             LDD  #TRUEV
             BRA  UXDONE
UXFAIL:      LDD  #FALSEV
UXDONE:      LDX  #TSTUENAME
             PSHU X
             PSHU D
             JSR  TSTREPORT

             LDU  TSTU0
             RTS

TSTUENAME: FCB  11
           FCC  "TSTUNESCAPE"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTNUMOUT - numeric output tests (glossary section 3.13, 14
; words, 13 tests since #S and #> are combined into one test,
; matching how they're naturally used together as the tail of
; the standard pictured-output idiom "<# ... #S #>").
;
; The pictured-numeric-output core (<# # #S #> HOLD HOLDS) is
; pure string-building with no I/O, tested directly. SIGN
; carries real bug-fix history - a prior bare BPL right after
; PULU didn't affect condition codes on real 6809 hardware, and
; the bug was masked for every internal caller by caller-side
; luck (each ran a flag-setting LDD right before calling SIGN).
; This section's own SIGN test deliberately poisons the flags
; with an unrelated CMPX immediately before each direct call,
; so it exercises the exact previously-broken scenario rather
; than repeating the same kind of luck that hid the bug.
;
; The high-level printing words (./U./.R/U.R/?/D./D.R) all
; produce real output via TYPE/EMIT internally, so each applies
; the SERIALPOLL-conditional split established in section 3.1 -
; full OUTHEAD/OUTBUF verification under SERIALPOLL=0, an
; EMITCH-based last-character check under SERIALPOLL=1. .R/U.R/
; D.R specifically test the padding path (a width wider than the
; actual digits), not just a no-padding sanity case. D./D.R use
; a genuine double-cell value (-100000, computed and verified
; independently in Python before writing the tests) to exercise
; the 32-bit negation path, not a value that happens to fit in
; one cell.
;
; Note: this section's own COMPARE-adjacent naming risk doesn't
; apply here, but every group wrapper name (TSTNUMOUT) and every
; internal FAIL/DONE prefix was still checked against the whole
; file before insertion, per the standard practice that caught
; the TSTCOMPARE collision in the prior section.
; ------------------------------------------------------------
TSTNUMOUT: JSR CRW
           LDX   #TSTNUMOUTMSG
           PSHU  X
           LDD   #6
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-12  ; >>>>

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

           ENDC ; <<<<

           RTS

TSTNUMOUTMSG: FCC "NumOut"

           IFEQ TSTSELECTOR-12  ; >>>>

; ------------------------------------------------------------
; Numeric Output test harness (glossary section 3.13). The
; pictured-numeric-output core (<# # #S #> HOLD HOLDS SIGN) is
; pure string-building with no I/O, tested directly. The
; high-level printing words (./U./.R/U.R/?/D./D.R) all produce
; real output via TYPE and/or EMIT internally, so per section
; 3.1's own already-debugged finding, each applies the
; SERIALPOLL-conditional split established there: full OUTHEAD/
; OUTBUF verification under SERIALPOLL=0, an EMITCH-based check
; of the last character under SERIALPOLL=1 - accepted as a
; known, honest limitation for words ending in a trailing space
; (./U./D. all print a fixed final space character, so the
; polling-mode check there confirms less than for the
; no-trailing-space words, but is still correct and consistent
; with the same trade-off already established for TSTCR/
; TSTSPACES/TSTTYPE/TSTDOTQUOTE in earlier sections).
;
; SIGN itself carries real bug-fix history: a prior version used
; a bare BPL immediately after PULU, which doesn't affect
; condition codes on real 6809 hardware - the bug was masked for
; every internal caller by "caller-side luck" (each happened to
; run a flag-setting LDD right before calling SIGN). This
; section's own SIGN test deliberately poisons the flags with an
; unrelated, known-positive value immediately before the actual
; PSHU/JSR SIGN sequence specifically so a standalone call - the
; exact scenario the bug-fix comment says was previously broken
; - is what gets tested, not a scenario that happens to work via
; the same kind of caller-side luck that hid the original bug.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTLTNUM - unit test for <#. No stack effect of its own -
; verifies it sets HLD to PAD's current (redirected) address.
; ------------------------------------------------------------
TSTLTNUM: LDD  CODEHERE
          STD  TSTCSAV

          LDD  #TSTCBUF
          STD  CODEHERE

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          JSR  LTNUM

          STU  TSTUAF

          LDD  HLD
          CMPD #TSTCBUF+PADOFFSET
          BNE  LNFAIL

          PULU D
          CMPD #TSTGUARD
          BNE  LNFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  LNFAIL

          LDD  #TRUEV
          BRA  LNDONE
LNFAIL:   LDD  #FALSEV
LNDONE:   LDX  #TSTLNNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDD  TSTCSAV
          STD  CODEHERE

          LDU  TSTU0
          RTS

TSTLNNAME: FCB  8
           FCC  "TSTLTNUM"

; ------------------------------------------------------------
; TSTHOLD - unit test for HOLD. Holds 'A' then 'B' - since HOLD
; grows the buffer downward and prepends (decrements HLD first,
; then writes at the new, lower position), the second-held
; character ends up at the lower address, so reading forward
; from the final HLD should give "BA", not "AB".
; ------------------------------------------------------------
TSTHOLD: LDD  CODEHERE
         STD  TSTCSAV

         LDD  #TSTCBUF
         STD  CODEHERE

         STU  TSTU0

         LDD  #TSTGUARD
         PSHU D
         STU  TSTUB4

         JSR  LTNUM

         LDD  #'A'
         PSHU D
         JSR  HOLD

         LDD  #'B'
         PSHU D
         JSR  HOLD

         STU  TSTUAF

         LDX  HLD
         LDA  ,X
         CMPA #'B'
         BNE  HDFAIL
         LDA  1,X
         CMPA #'A'
         BNE  HDFAIL

         PULU D
         CMPD #TSTGUARD
         BNE  HDFAIL

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #0
         BNE  HDFAIL

         LDD  #TRUEV
         BRA  HDDONE
HDFAIL:  LDD  #FALSEV
HDDONE:  LDX  #TSTHDNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDD  TSTCSAV
         STD  CODEHERE

         LDU  TSTU0
         RTS

TSTHDNAME: FCB  7
           FCC  "TSTHOLD"

; ------------------------------------------------------------
; TSTHOLDS - unit test for HOLDS. Holds the string "XY" - since
; HOLDS iterates its source backward (last character first) and
; HOLD itself prepends, the two behaviors combine to preserve
; the original forward order in the pictured buffer, matching
; its own documented "depends on HOLD's exact decrement-by-one
; behavior".
; ------------------------------------------------------------
TSTHOLDS: LDD  CODEHERE
          STD  TSTCSAV

          LDD  #TSTCBUF
          STD  CODEHERE

          LDA  #'X'
          STA  TSTNAMEB
          LDA  #'Y'
          STA  TSTNAMEB+1

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          STU  TSTUB4

          JSR  LTNUM

          LDD  #TSTNAMEB
          PSHU D
          LDD  #2
          PSHU D
          JSR  HOLDS

          STU  TSTUAF

          LDX  HLD
          LDA  ,X
          CMPA #'X'
          BNE  HOFAIL
          LDA  1,X
          CMPA #'Y'
          BNE  HOFAIL

          PULU D
          CMPD #TSTGUARD
          BNE  HOFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  HOFAIL

          LDD  #TRUEV
          BRA  HODONE
HOFAIL:   LDD  #FALSEV
HODONE:   LDX  #TSTHSNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDD  TSTCSAV
          STD  CODEHERE

          LDU  TSTU0
          RTS

TSTHSNAME: FCB  8
           FCC  "TSTHOLDS"

; ------------------------------------------------------------
; TSTSIGN - unit test for SIGN. Deliberately poisons the CPU
; flags with an unrelated CMPX (setting them to reflect a
; positive comparison result, without touching D or the value
; about to be pushed) immediately before each PSHU/JSR SIGN
; call - specifically so this test exercises the exact scenario
; the word's own bug-fix comment says was previously broken (a
; direct, standalone call not preceded by a flag-setting LDD of
; the true value), rather than relying on the same kind of
; caller-side luck that hid the original bug. Two sub-cases:
; negative (with flags poisoned toward positive, confirming the
; minus sign still gets added - would fail if SIGN reverted to
; testing stale flags instead of the value it just popped) and
; positive (with flags poisoned toward negative, confirming no
; minus sign gets added incorrectly).
; ------------------------------------------------------------
TSTSIGN: LDD  CODEHERE
         STD  TSTCSAV

         LDD  #TSTCBUF
         STD  CODEHERE

         STU  TSTU0

         LDD  #TSTGUARD
         PSHU D
         STU  TSTUB4

         JSR  LTNUM

         LDD  #-5
         LDX  #1
         CMPX #0
         PSHU D
         JSR  SIGN

         LDX  HLD
         LDA  ,X
         CMPA #'-'
         BNE  SGFAIL

         JSR  LTNUM

         LDD  #5
         LDX  #-1
         CMPX #0
         PSHU D
         JSR  SIGN

         STU  TSTUAF

         LDD  HLD
         CMPD #TSTCBUF+PADOFFSET
         BNE  SGFAIL

         PULU D
         CMPD #TSTGUARD
         BNE  SGFAIL

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #0
         BNE  SGFAIL

         LDD  #TRUEV
         BRA  SGDONE
SGFAIL:  LDD  #FALSEV
SGDONE:  LDX  #TSTSGNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDD  TSTCSAV
         STD  CODEHERE

         LDU  TSTU0
         RTS

TSTSGNAME: FCB  7
           FCC  "TSTSIGN"

; ------------------------------------------------------------
; TSTNUMSIGN - unit test for #. Converts one digit of 25 (base
; 10, ud1 = (25, 0)) - verifies the held character is '5' (the
; least-significant digit, processed first per the standard
; pictured-output convention) and the returned ud2 is the
; quotient (2, 0).
; ------------------------------------------------------------
TSTNUMSIGN: LDD  CODEHERE
            STD  TSTCSAV
            LDD  BASE
            STD  TSTBASAV

            LDD  #TSTCBUF
            STD  CODEHERE
            LDD  #10
            STD  BASE

            STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            JSR  LTNUM

            LDD  #25
            PSHU D
            LDD  #0
            PSHU D
            JSR  NUMSIGN

            STU  TSTUAF

            LDD  TSTBASAV
            STD  BASE

            PULU D
            CMPD #0
            BNE  NZFAIL
            PULU D
            CMPD #2
            BNE  NZFAIL

            LDX  HLD
            LDA  ,X
            CMPA #'5'
            BNE  NZFAIL

            PULU D
            CMPD #TSTGUARD
            BNE  NZFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #4  ; BUG FIX: was 0 - mistakenly copied the net-
                     ; zero reasoning from TSTNUMSIGNSGT (which calls
                     ; #> to consume ud2 before capturing TSTUAF).
                     ; This test captures TSTUAF right after NUMSIGN
                     ; returns, with ud2 (the quotient) still sitting
                     ; on the stack - confirmed via MAME: the user's
                     ; own register dump showed D=$0004 at this exact
                     ; comparison, precisely matching the 2 extra
                     ; cells (quotient low+high) genuinely present at
                     ; TSTUAF's own capture point that aren't present
                     ; at TSTUB4's (captured before NUMSIGN even ran).
                     ; NUMSIGN itself was never broken; only this
                     ; test's own expected depth value was wrong.
            BNE  NZFAIL

            LDD  #TRUEV
            BRA  NZDONE
NZFAIL:     LDD  #FALSEV
NZDONE:     LDX  #TSTNSNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDD  TSTCSAV
            STD  CODEHERE

            LDU  TSTU0
            RTS

TSTNSNAME: FCB  10
           FCC  "TSTNUMSIGN"

; ------------------------------------------------------------
; TSTNUMSIGNSGT - combined unit test for #S and #> (naturally
; used together as the tail of the standard pictured-output
; idiom "<# ... #S #>"). Converts ud1=(12345,0) fully via #S,
; then #> to get (addr len) - verifies both the string content
; ("12345", all 5 digits in correct order) and the length.
; ------------------------------------------------------------
TSTNUMSIGNSGT: LDD  CODEHERE
               STD  TSTCSAV
               LDD  BASE
               STD  TSTBASAV

               LDD  #TSTCBUF
               STD  CODEHERE
               LDD  #10
               STD  BASE

               STU  TSTU0

               LDD  #TSTGUARD
               PSHU D
               STU  TSTUB4

               JSR  LTNUM

               LDD  #12345
               PSHU D
               LDD  #0
               PSHU D
               JSR  NUMSIGNS
               JSR  NUMGT

               STU  TSTUAF

               LDD  TSTBASAV
               STD  BASE

               PULU D
               CMPD #5
               BNE  NXFAIL

               PULU D
               TFR  D,X
               LDA  ,X
               CMPA #'1'
               BNE  NXFAIL
               LDA  1,X
               CMPA #'2'
               BNE  NXFAIL
               LDA  2,X
               CMPA #'3'
               BNE  NXFAIL
               LDA  3,X
               CMPA #'4'
               BNE  NXFAIL
               LDA  4,X
               CMPA #'5'
               BNE  NXFAIL

               PULU D
               CMPD #TSTGUARD
               BNE  NXFAIL

               LDD  TSTUB4
               SUBD TSTUAF
               CMPD #4
               BNE  NXFAIL

               LDD  #TRUEV
               BRA  NXDONE
NXFAIL:        LDD  #FALSEV
NXDONE:        LDX  #TSTNGNAME
               PSHU X
               PSHU D
               JSR  TSTREPORT

               LDD  TSTCSAV
               STD  CODEHERE

               LDU  TSTU0
               RTS

TSTNGNAME: FCB  13
           FCC  "TSTNUMSIGNSGT"

; ------------------------------------------------------------
; TSTDOT - unit test for . (DOT). Prints -42, expecting "-42 "
; (4 chars: minus, two digits, trailing space). Under SERIALPOLL=0
; verifies all 4 queued bytes directly; under SERIALPOLL=1 (the
; polling variant, confirmed the active build), verifies only the
; last-emitted character via EMITCH - a fixed trailing space in
; this word's case, a known, accepted, less-discriminating check
; consistent with the same trade-off already established for
; TSTCR/TSTSPACES/TSTTYPE/TSTDOTQUOTE.
; ------------------------------------------------------------
TSTDOT: LDD  CODEHERE
        STD  TSTCSAV
        LDD  BASE
        STD  TSTBASAV

        LDD  #TSTCBUF
        STD  CODEHERE
        LDD  #10
        STD  BASE

        IFEQ SERIALPOLL  ; >>>>
        LDA  OUTHEAD
        STA  TSTOHSAV
        ENDC ; <<<<

        STU  TSTU0

        LDD  #TSTGUARD
        PSHU D
        LDD  #-42
        PSHU D
        STU  TSTUB4

        JSR  DOT

        STU  TSTUAF

        LDD  TSTCSAV
        STD  CODEHERE
        LDD  TSTBASAV
        STD  BASE

        IFEQ SERIALPOLL  ; >>>>
        LDA  TSTOHSAV
        ADDA #4
        ANDA #OUTBUFSZ-1
        CMPA OUTHEAD
        BNE  DTFAIL3

        LDX  #OUTBUF
        LDB  TSTOHSAV
        LDA  B,X
        CMPA #'-'
        BNE  DTFAIL3
        INCB
        ANDB #OUTBUFSZ-1
        LDA  B,X
        CMPA #'4'
        BNE  DTFAIL3
        INCB
        ANDB #OUTBUFSZ-1
        LDA  B,X
        CMPA #'2'
        BNE  DTFAIL3
        INCB
        ANDB #OUTBUFSZ-1
        LDA  B,X
        CMPA #32
        BNE  DTFAIL3
        ELSE  ; <<<<>>>>
        LDA  EMITCH
        CMPA #32
        BNE  DTFAIL3
        ENDC  ; <<<<<<<<<<

        PULU D
        CMPD #TSTGUARD
        BNE  DTFAIL3

        LDD  TSTUB4
        SUBD TSTUAF
        CMPD #-2
        BNE  DTFAIL3

        LDD  #TRUEV
        BRA  DTDONE3
DTFAIL3: LDD  #FALSEV
DTDONE3: LDX  #TSTDTNAME2
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDU  TSTU0
         RTS

TSTDTNAME2: FCB  6
            FCC  "TSTDOT"

; ------------------------------------------------------------
; TSTUDOT - unit test for U. Prints 42, expecting "42 " (3
; chars: two digits, trailing space).
; ------------------------------------------------------------
TSTUDOT: LDD  CODEHERE
         STD  TSTCSAV
         LDD  BASE
         STD  TSTBASAV

         LDD  #TSTCBUF
         STD  CODEHERE
         LDD  #10
         STD  BASE

         IFEQ SERIALPOLL  ; >>>>
         LDA  OUTHEAD
         STA  TSTOHSAV
         ENDC ; <<<<

         STU  TSTU0

         LDD  #TSTGUARD
         PSHU D
         LDD  #42
         PSHU D
         STU  TSTUB4

         JSR  UDOT

         STU  TSTUAF

         LDD  TSTCSAV
         STD  CODEHERE
         LDD  TSTBASAV
         STD  BASE

         IFEQ SERIALPOLL  ; >>>>
         LDA  TSTOHSAV
         ADDA #3
         ANDA #OUTBUFSZ-1
         CMPA OUTHEAD
         BNE  UFFAIL

         LDX  #OUTBUF
         LDB  TSTOHSAV
         LDA  B,X
         CMPA #'4'
         BNE  UFFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'2'
         BNE  UFFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #32
         BNE  UFFAIL
         ELSE  ; <<<<>>>>
         LDA  EMITCH
         CMPA #32
         BNE  UFFAIL
         ENDC  ; <<<<<<<<<<

         PULU D
         CMPD #TSTGUARD
         BNE  UFFAIL

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #-2
         BNE  UFFAIL

         LDD  #TRUEV
         BRA  UFDONE
UFFAIL:  LDD  #FALSEV
UFDONE:  LDX  #TSTUDNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDU  TSTU0
         RTS

TSTUDNAME: FCB  7
           FCC  "TSTUDOT"

; ------------------------------------------------------------
; TSTDOTR - unit test for .R. Prints 42 with width 5, expecting
; "   42" (3 leading spaces + 2 digits = 5 chars total, no
; trailing space) - specifically exercising the padding path,
; not just a no-padding sanity case.
; ------------------------------------------------------------
TSTDOTR: LDD  CODEHERE
         STD  TSTCSAV
         LDD  BASE
         STD  TSTBASAV

         LDD  #TSTCBUF
         STD  CODEHERE
         LDD  #10
         STD  BASE

         IFEQ SERIALPOLL  ; >>>>
         LDA  OUTHEAD
         STA  TSTOHSAV
         ENDC ; <<<<

         STU  TSTU0

         LDD  #TSTGUARD
         PSHU D
         LDD  #42
         PSHU D
         LDD  #5
         PSHU D
         STU  TSTUB4

         JSR  DOTR

         STU  TSTUAF

         LDD  TSTCSAV
         STD  CODEHERE
         LDD  TSTBASAV
         STD  BASE

         IFEQ SERIALPOLL  ; >>>>
         LDA  TSTOHSAV
         ADDA #5
         ANDA #OUTBUFSZ-1
         CMPA OUTHEAD
         BNE  DRFAIL

         LDX  #OUTBUF
         LDB  TSTOHSAV
         LDA  B,X
         CMPA #32
         BNE  DRFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #32
         BNE  DRFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #32
         BNE  DRFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'4'
         BNE  DRFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'2'
         BNE  DRFAIL
         ELSE  ; <<<<>>>>
         LDA  EMITCH
         CMPA #'2'
         BNE  DRFAIL
         ENDC  ; <<<<<<<<<<

         PULU D
         CMPD #TSTGUARD
         BNE  DRFAIL

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #-4
         BNE  DRFAIL

         LDD  #TRUEV
         BRA  DRDONE
DRFAIL:  LDD  #FALSEV
DRDONE:  LDX  #TSTDRNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDU  TSTU0
         RTS

TSTDRNAME: FCB  7
           FCC  "TSTDOTR"

; ------------------------------------------------------------
; TSTUDOTR - unit test for U.R. Prints 42 with width 5,
; expecting "   42" - same padding-path reasoning as TSTDOTR.
; ------------------------------------------------------------
TSTUDOTR: LDD  CODEHERE
          STD  TSTCSAV
          LDD  BASE
          STD  TSTBASAV

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #10
          STD  BASE

          IFEQ SERIALPOLL  ; >>>>
          LDA  OUTHEAD
          STA  TSTOHSAV
          ENDC ; <<<<

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #42
          PSHU D
          LDD  #5
          PSHU D
          STU  TSTUB4

          JSR  UDOTR

          STU  TSTUAF

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTBASAV
          STD  BASE

          IFEQ SERIALPOLL  ; >>>>
          LDA  TSTOHSAV
          ADDA #5
          ANDA #OUTBUFSZ-1
          CMPA OUTHEAD
          BNE  URFAIL

          LDX  #OUTBUF
          LDB  TSTOHSAV
          LDA  B,X
          CMPA #32
          BNE  URFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #32
          BNE  URFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #32
          BNE  URFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'4'
          BNE  URFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'2'
          BNE  URFAIL
          ELSE  ; <<<<>>>>
          LDA  EMITCH
          CMPA #'2'
          BNE  URFAIL
          ENDC  ; <<<<<<<<<<

          PULU D
          CMPD #TSTGUARD
          BNE  URFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-4
          BNE  URFAIL

          LDD  #TRUEV
          BRA  URDONE
URFAIL:   LDD  #FALSEV
URDONE:   LDX  #TSTURNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTURNAME: FCB  8
           FCC  "TSTUDOTR"

; ------------------------------------------------------------
; TSTQMARK - unit test for ?. Stores -7 at a scratch cell
; (separate from the CODEHERE-redirected pictured-output
; region, to avoid conflict), calls ? with its address, expects
; "-7 " (fetches and prints signed, via DOT internally).
; ------------------------------------------------------------
TSTQMARK: LDD  CODEHERE
          STD  TSTCSAV
          LDD  BASE
          STD  TSTBASAV

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #10
          STD  BASE

          LDD  #-7
          STD  TSTCBUF+50

          IFEQ SERIALPOLL  ; >>>>
          LDA  OUTHEAD
          STA  TSTOHSAV
          ENDC ; <<<<

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #TSTCBUF+50
          PSHU D
          STU  TSTUB4

          JSR  QMARK

          STU  TSTUAF

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTBASAV
          STD  BASE

          IFEQ SERIALPOLL  ; >>>>
          LDA  TSTOHSAV
          ADDA #3
          ANDA #OUTBUFSZ-1
          CMPA OUTHEAD
          BNE  QMFAIL

          LDX  #OUTBUF
          LDB  TSTOHSAV
          LDA  B,X
          CMPA #'-'
          BNE  QMFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'7'
          BNE  QMFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #32
          BNE  QMFAIL
          ELSE  ; <<<<>>>>
          LDA  EMITCH
          CMPA #32
          BNE  QMFAIL
          ENDC  ; <<<<<<<<<<

          PULU D
          CMPD #TSTGUARD
          BNE  QMFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-2
          BNE  QMFAIL

          LDD  #TRUEV
          BRA  QMDONE
QMFAIL:   LDD  #FALSEV
QMDONE:   LDX  #TSTQMNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTQMNAME: FCB  8
           FCC  "TSTQMARK"

; ------------------------------------------------------------
; TSTDDOT - unit test for D. Prints d = -100000 (a genuine
; double-cell value: high cell $FFFE, low cell $7960, computed
; and verified independently in Python before writing this
; test - specifically exercising the 32-bit negation path
; (MNEG32), not just a value that happens to fit in one cell).
; Expects "-100000 " (8 chars).
; ------------------------------------------------------------
TSTDDOT: LDD  CODEHERE
         STD  TSTCSAV
         LDD  BASE
         STD  TSTBASAV

         LDD  #TSTCBUF
         STD  CODEHERE
         LDD  #10
         STD  BASE

         IFEQ SERIALPOLL  ; >>>>
         LDA  OUTHEAD
         STA  TSTOHSAV
         ENDC ; <<<<

         STU  TSTU0

         LDD  #TSTGUARD
         PSHU D
         LDD  #$7960
         PSHU D
         LDD  #$FFFE
         PSHU D
         STU  TSTUB4

         JSR  DDOT

         STU  TSTUAF

         LDD  TSTCSAV
         STD  CODEHERE
         LDD  TSTBASAV
         STD  BASE

         IFEQ SERIALPOLL  ; >>>>
         LDA  TSTOHSAV
         ADDA #8
         ANDA #OUTBUFSZ-1
         CMPA OUTHEAD
         BNE  DDFAIL

         LDX  #OUTBUF
         LDB  TSTOHSAV
         LDA  B,X
         CMPA #'-'
         BNE  DDFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'1'
         BNE  DDFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'0'
         BNE  DDFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'0'
         BNE  DDFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'0'
         BNE  DDFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'0'
         BNE  DDFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'0'
         BNE  DDFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #32
         BNE  DDFAIL
         ELSE  ; <<<<>>>>
         LDA  EMITCH
         CMPA #32
         BNE  DDFAIL
         ENDC  ; <<<<<<<<<<

         PULU D
         CMPD #TSTGUARD
         BNE  DDFAIL

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #-4
         BNE  DDFAIL

         LDD  #TRUEV
         BRA  DDDONE
DDFAIL:  LDD  #FALSEV
DDDONE:  LDX  #TSTDDNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDU  TSTU0
         RTS

TSTDDNAME: FCB  7
           FCC  "TSTDDOT"

; ------------------------------------------------------------
; TSTDDOTR - unit test for D.R. Same d = -100000 as TSTDDOT,
; width 10 - "-100000" is 7 chars, so padding = 3 spaces,
; expecting "   -100000" (10 chars total, no trailing space).
; ------------------------------------------------------------
TSTDDOTR: LDD  CODEHERE
          STD  TSTCSAV
          LDD  BASE
          STD  TSTBASAV

          LDD  #TSTCBUF
          STD  CODEHERE
          LDD  #10
          STD  BASE

          IFEQ SERIALPOLL  ; >>>>
          LDA  OUTHEAD
          STA  TSTOHSAV
          ENDC ; <<<<

          STU  TSTU0

          LDD  #TSTGUARD
          PSHU D
          LDD  #$7960
          PSHU D
          LDD  #$FFFE
          PSHU D
          LDD  #10
          PSHU D
          STU  TSTUB4

          JSR  DDOTR

          STU  TSTUAF

          LDD  TSTCSAV
          STD  CODEHERE
          LDD  TSTBASAV
          STD  BASE

          IFEQ SERIALPOLL  ; >>>>
          LDA  TSTOHSAV
          ADDA #10
          ANDA #OUTBUFSZ-1
          CMPA OUTHEAD
          BNE  DRRFAIL

          LDX  #OUTBUF
          LDB  TSTOHSAV
          LDA  B,X
          CMPA #32
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #32
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #32
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'-'
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'1'
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'0'
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'0'
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'0'
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'0'
          BNE  DRRFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'0'
          BNE  DRRFAIL
          ELSE  ; <<<<>>>>
          LDA  EMITCH
          CMPA #'0'
          BNE  DRRFAIL
          ENDC  ; <<<<<<<<<<

          PULU D
          CMPD #TSTGUARD
          BNE  DRRFAIL

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #-6
          BNE  DRRFAIL

          LDD  #TRUEV
          BRA  DRRDONE
DRRFAIL:  LDD  #FALSEV
DRRDONE:  LDX  #TSTDRRNAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTDRRNAME: FCB  8
            FCC  "TSTDDOTR"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTBASERADIX - base/radix control tests (glossary section
; 3.14, 4 words, 1 combined test - each word's own effect is a
; single BASE read/write, trivially covered together rather than
; separately). No I/O involved, so no SERIALPOLL-conditional
; complexity needed here, unlike the printing-heavy sections.
; ------------------------------------------------------------
TSTBASERADIX: JSR CRW
           LDX   #TSTBRMSG
           PSHU  X
           LDD   #9
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-13  ; >>>>

           JSR   TSTBASE

           ENDC ; <<<<

           RTS

TSTBRMSG: FCC "BaseRadix"

           IFEQ TSTSELECTOR-13  ; >>>>

; ------------------------------------------------------------
; Base/Radix Control test harness (glossary section 3.14). All
; four words are pure state-setting/reading with no I/O
; involved, so none of this section's tests need the
; SERIALPOLL-conditional complexity used throughout the printing
; sections. Combined into one test, given each word's own
; effect is trivially verified by reading BASE directly - four
; separate tests would just repeat the same save/set/verify/
; restore shape four times over. TSTBASAV (added in section
; 3.13, when the real, pre-COLD BASE=0 bug was found and fixed)
; is reused here to save/restore the real BASE across this test
; too, per the same established reasoning.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTBASE - combined unit test for BASE, DECIMAL, HEX, and
; BINARY. Sets BASE via each of HEX/BINARY/DECIMAL in turn,
; verifying the correct value lands each time, then calls BASE
; itself and verifies both that it returns the variable's own
; address (not its value, per "( -- addr )") and that reading
; through that address reflects DECIMAL's own, most recent
; setting (10).
; ------------------------------------------------------------
TSTBASE: LDD  BASE
         STD  TSTBASAV

         STU  TSTU0

         JSR  HEXW
         LDD  BASE
         CMPD #16
         BNE  BSFAIL

         JSR  BINARYW
         LDD  BASE
         CMPD #2
         BNE  BSFAIL

         JSR  DECIMAL
         LDD  BASE
         CMPD #10
         BNE  BSFAIL

         LDD  #TSTGUARD
         PSHU D
         STU  TSTUB4

         JSR  BASEW

         STU  TSTUAF

         PULU D
         CMPD #BASE
         BNE  BSFAIL

         TFR  D,X
         LDD  ,X
         CMPD #10
         BNE  BSFAIL

         PULU D
         CMPD #TSTGUARD
         BNE  BSFAIL

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #2
         BNE  BSFAIL

         LDD  #TRUEV
         BRA  BSDONE
BSFAIL:  LDD  #FALSEV
BSDONE:  LDX  #TSTBSNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDD  TSTBASAV
         STD  BASE

         LDU  TSTU0
         RTS

TSTBSNAME: FCB  7
           FCC  "TSTBASE"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTEXCEPTION - exception handling tests (glossary section
; 3.15, 2 words, 4 tests since CATCH/THROW can only be
; meaningfully tested together - THROW's own effect is only
; observable through a CATCH that traps it). Already used
; extensively as this whole session's own error-testing
; mechanism throughout sections 3.8-3.14, so their correctness
; has substantial indirect evidence already; this section still
; gets its own, direct, dedicated tests.
;
; Critical safety constraint, confirmed by reading THROW's own
; code directly: with no active CATCH, THROW jumps straight to
; ABORT (unsafe to trigger directly - it resets the return
; stack, destroying this whole test framework's own call chain,
; per section 3.1's own established reasoning). Every THROW in
; this section's own tests is either wrapped in a genuine,
; active CATCH (via a dedicated internal helper, TSTTHROWHLP,
; that only ever gets invoked that way), or is a THROW(0) call -
; confirmed via THROW's own code to be a pure, unconditional
; no-op that never touches HANDLER or ABORT at all, so that one
; specific case is safe to call directly.
;
; TSTCATCHTHROW specifically verifies the two dummy values
; TSTTHROWHLP pushes before throwing are genuinely gone
; afterward, confirming CATCH's own documented "restores data
; stack depth... on either path" for real. TSTHANDLERSAVE
; verifies the HANDLER half of that same documented guarantee
; directly, by reading HANDLER itself before and after CATCH
; calls on both the success and throw paths, rather than only
; inferring it from stack-level behavior.
; ------------------------------------------------------------
TSTEXCEPTION: JSR CRW
           LDX   #TSTEXCMSG
           PSHU  X
           LDD   #6
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-14  ; >>>>

           JSR   TSTCATCHOK
           JSR   TSTCATCHTHROW
           JSR   TSTTHROWZERO
           JSR   TSTHANDLERSAVE

           ENDC ; <<<<

           RTS

TSTEXCMSG: FCC "Except"

           IFEQ TSTSELECTOR-14  ; >>>>

; ------------------------------------------------------------
; Exception Handling test harness (glossary section 3.15).
; CATCH/THROW have already been used extensively as this whole
; session's own error-testing mechanism throughout sections
; 3.8-3.14, so their correctness has substantial indirect
; evidence already - this section still gets its own, direct
; tests, matching the established practice of every section
; getting dedicated coverage rather than relying on incidental
; use elsewhere.
;
; Critical safety constraint, confirmed by reading THROW's own
; code directly: with no active CATCH, THROW jumps straight to
; ABORT (already established elsewhere in this session as unsafe
; to trigger directly - it resets the return stack, destroying
; this whole test framework's own call chain). Every THROW in
; this section's own tests is either wrapped in a genuine,
; active CATCH, or is a THROW(0) call - confirmed via CATCH's own
; code to be a pure no-op that never touches HANDLER or ABORT at
; all, so that specific case is safe to call directly.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTCATCHOK - unit test for CATCH, success path. Wraps DUP (a
; genuine, real dictionary word, not a synthetic stand-in) and
; verifies both that DUP's own effect genuinely happened (the
; value really was duplicated) and that CATCH itself returns 0.
; ------------------------------------------------------------
TSTCATCHOK: STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            LDD  #TSTVAL1
            PSHU D
            LDX  #DUP
            PSHU X
            STU  TSTUB4

            JSR  CATCH

            STU  TSTUAF

            PULU D
            CMPD #0
            BNE  COFAIL
            PULU D
            CMPD #TSTVAL1
            BNE  COFAIL
            PULU D
            CMPD #TSTVAL1
            BNE  COFAIL
            PULU D
            CMPD #TSTGUARD
            BNE  COFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #2
            BNE  COFAIL

            LDD  #TRUEV
            BRA  CODONE
COFAIL:     LDD  #FALSEV
CODONE:     LDX  #TSTCONAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTCONAME: FCB  10
           FCC  "TSTCATCHOK"

; ------------------------------------------------------------
; TSTTHROWHLP - internal helper, not a dictionary word or a
; test of its own. Pushes two dummy values (to verify CATCH's
; own stack-depth restoration genuinely discards them, not just
; that a thrown code arrives correctly) then throws a known,
; distinctive, non-trivial code. Only ever invoked via CATCH
; (below), never called directly - calling it any other way
; would hit THROW's own uncaught path (JMP ABORT), which this
; whole test framework cannot survive.
; ------------------------------------------------------------
TSTTHROWHLP: LDD  #TSTVAL1
             PSHU D
             LDD  #TSTVAL2
             PSHU D
             LDD  #TSTNEG1
             PSHU D
             JSR  THROW
             RTS

; ------------------------------------------------------------
; TSTCATCHTHROW - unit test for CATCH, exception path, and for
; THROW's own non-local exit together (the two can only be
; meaningfully tested as a pair - THROW's own effect is only
; observable through a CATCH that traps it). Verifies CATCH
; returns the exact thrown code, and specifically verifies the
; two dummy values TSTTHROWHLP pushes before throwing are
; genuinely gone afterward - confirming the documented "restores
; data stack depth... on either path" for real, not just that
; the final result happens to look right.
; ------------------------------------------------------------
TSTCATCHTHROW: STU  TSTU0

               LDD  #TSTGUARD
               PSHU D
               LDX  #TSTTHROWHLP
               PSHU X
               STU  TSTUB4

               JSR  CATCH

               STU  TSTUAF

               PULU D
               CMPD #TSTNEG1
               BNE  CTFAIL2
               PULU D
               CMPD #TSTGUARD
               BNE  CTFAIL2

               LDD  TSTUB4
               SUBD TSTUAF
               CMPD #0
               BNE  CTFAIL2

               LDD  #TRUEV
               BRA  CTDONE2
CTFAIL2:       LDD  #FALSEV
CTDONE2:       LDX  #TSTCTNAME2
               PSHU X
               PSHU D
               JSR  TSTREPORT

               LDU  TSTU0
               RTS

TSTCTNAME2: FCB  13
            FCC  "TSTCATCHTHROW"

; ------------------------------------------------------------
; TSTTHROWZERO - unit test for THROW(0). Confirmed via its own
; code that N=0 is a genuine, unconditional no-op (BEQ THDONE
; skips everything, never touching HANDLER or ABORT), so this
; is the one THROW call in this section safe to make directly,
; without any CATCH wrapping it. Verifies it consumes its
; argument and does nothing else - no non-local exit, no stack
; disturbance beyond popping the 0 itself.
; ------------------------------------------------------------
TSTTHROWZERO: STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              LDD  #0
              PSHU D
              STU  TSTUB4

              JSR  THROW

              STU  TSTUAF

              PULU D
              CMPD #TSTGUARD
              BNE  TVFAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #-2
              BNE  TVFAIL

              LDD  #TRUEV
              BRA  TVDONE
TVFAIL:       LDD  #FALSEV
TVDONE:       LDX  #TSTTZNAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTTZNAME: FCB  12
           FCC  "TSTTHROWZERO"

; ------------------------------------------------------------
; TSTHANDLERSAVE - unit test verifying CATCH correctly restores
; HANDLER afterward, on both paths - the success path (wrapping
; DUP) and the throw path (wrapping TSTTHROWHLP again). Confirms
; the documented "restores... HANDLER on either path" directly,
; by reading HANDLER itself before and after each call, rather
; than only inferring it from the stack-level behavior CATCH's
; other tests already cover.
; ------------------------------------------------------------
TSTHANDLERSAVE: LDD  HANDLER
                STD  TSTHANDSAV

                STU  TSTU0

                LDD  #TSTGUARD
                PSHU D
                STU  TSTUB4

                LDD  #TSTVAL1
                PSHU D
                LDX  #DUP
                PSHU X

                JSR  CATCH

                LDD  HANDLER
                CMPD TSTHANDSAV
                BNE  HNFAIL

                PULU D
                CMPD #0
                BNE  HNFAIL
                PULU D
                CMPD #TSTVAL1
                BNE  HNFAIL
                PULU D
                CMPD #TSTVAL1
                BNE  HNFAIL

                LDX  #TSTTHROWHLP
                PSHU X

                JSR  CATCH

                STU  TSTUAF

                LDD  HANDLER
                CMPD TSTHANDSAV
                BNE  HNFAIL

                PULU D
                CMPD #TSTNEG1
                BNE  HNFAIL

                PULU D
                CMPD #TSTGUARD
                BNE  HNFAIL

                LDD  TSTUB4
                SUBD TSTUAF
                CMPD #2
                BNE  HNFAIL

                LDD  #TRUEV
                BRA  HNDONE
HNFAIL:         LDD  #FALSEV
HNDONE:         LDX  #TSTHNNAME
                PSHU X
                PSHU D
                JSR  TSTREPORT

                LDU  TSTU0
                RTS

TSTHNNAME: FCB  14
           FCC  "TSTHANDLERSAVE"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTCOMMENTS - comments tests (glossary section 3.16, 2 words).
; Both immediate and parse from source, so both redirect
; SRCADDR/SRCLEN/TOIN, matching the established pattern from
; sections 3.8-3.12. ( specifically carries real bug-fix history
; (a stray value left on the data stack, confirmed and fixed via
; MAME in a prior session) that this section's own test verifies
; directly - the data stack is genuinely unchanged after a
; comment, not just that parsing advanced correctly.
; ------------------------------------------------------------
TSTCOMMENTS: JSR CRW
           LDX   #TSTCOMMSG
           PSHU  X
           LDD   #8
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-15  ; >>>>

           JSR   TSTLPAREN
           JSR   TSTBACKSLASH

           ENDC ; <<<<

           RTS

TSTCOMMSG: FCC "Comments"

           IFEQ TSTSELECTOR-15  ; >>>>

; ------------------------------------------------------------
; Comments test harness (glossary section 3.16). Both words
; parse from source, so both redirect SRCADDR/SRCLEN/TOIN,
; matching the established pattern from sections 3.8-3.12.
;
; ( specifically carries real bug-fix history worth verifying
; directly, not just noting: a prior version omitted consuming
; WORD's own returned c-addr, leaving a stray value on the data
; stack after every "(...)" comment - confirmed via MAME at the
; time, symptomatic both as a visible stray value in interpret
; mode and as a -22 CSP mismatch for any colon definition
; containing one. This section's own test specifically confirms
; the data stack is genuinely unchanged (net 0), not just that
; parsing advanced correctly.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTLPAREN - unit test for (. Fake source "hi)m" with TOIN
; starting at 0 - verifies TOIN lands exactly past the closing
; paren (at 3, immediately before "m", not consuming it), and
; that the data stack is genuinely unchanged - the specific
; behavior the bug-fix comment describes as previously broken.
; Since ( only ever advances TOIN, never SRCADDR itself, the
; fake source's own known address (TSTNAMEB) is used directly to
; verify the character just past the paren, with no need to
; re-read SRCADDR after the call.
; ------------------------------------------------------------
TSTLPAREN: LDD  SRCADDR
           STD  TSTSASAV
           LDD  SRCLEN
           STD  TSTSLSAV
           LDD  TOIN
           STD  TSTTISAV

           LDA  #'h'
           STA  TSTNAMEB
           LDA  #'i'
           STA  TSTNAMEB+1
           LDA  #')'
           STA  TSTNAMEB+2
           LDA  #'m'
           STA  TSTNAMEB+3

           LDD  #TSTNAMEB
           STD  SRCADDR
           LDD  #4
           STD  SRCLEN
           LDD  #0
           STD  TOIN

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           STU  TSTUB4

           JSR  LPAREN

           STU  TSTUAF

           LDD  TOIN
           CMPD #3
           BNE  LPFAIL

           LDA  TSTNAMEB+3
           CMPA #'m'
           BNE  LPFAIL

           LDD  TSTSASAV
           STD  SRCADDR
           LDD  TSTSLSAV
           STD  SRCLEN
           LDD  TSTTISAV
           STD  TOIN

           PULU D
           CMPD #TSTGUARD
           BNE  LPFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #0
           BNE  LPFAIL

           LDD  #TRUEV
           BRA  LPDONE
LPFAIL:    LDD  #FALSEV
LPDONE:    LDX  #TSTLPNAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTLPNAME: FCB  9
           FCC  "TSTLPAREN"

; ------------------------------------------------------------
; TSTBACKSLASH - unit test for \. Fake source with SRCLEN=10,
; TOIN starting partway through at 3 (simulating being midway
; through a line) - verifies TOIN lands exactly at SRCLEN,
; consuming the rest of the line. Confirmed via its own code
; that it reads SRCLEN directly (not a fixed buffer length),
; matching its own documented "follows SOURCE... operates
; correctly inside EVALUATE" - this test's own redirect of
; SRCLEN specifically, rather than relying on the real terminal
; input buffer's own length, is what actually exercises that.
; ------------------------------------------------------------
TSTBACKSLASH: LDD  SRCLEN
              STD  TSTSLSAV
              LDD  TOIN
              STD  TSTTISAV

              LDD  #10
              STD  SRCLEN
              LDD  #3
              STD  TOIN

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              JSR  BACKSLASH

              STU  TSTUAF

              LDD  TOIN
              CMPD #10
              BNE  BLFAIL

              LDD  TSTSLSAV
              STD  SRCLEN
              LDD  TSTTISAV
              STD  TOIN

              PULU D
              CMPD #TSTGUARD
              BNE  BLFAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #0
              BNE  BLFAIL

              LDD  #TRUEV
              BRA  BLDONE
BLFAIL:       LDD  #FALSEV
BLDONE:       LDX  #TSTBLNAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTBLNAME: FCB  12
           FCC  "TSTBACKSLASH"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTENVSYS - environmental & system queries tests (glossary
; section 3.17, 10 words, 8 tests since TIB/#TIB/>IN/SPAN/BL are
; combined into one test, and ENVIRONMENT? gets three separate
; tests of its own - single-cell, double-cell, and unsupported-
; string cases).
;
; REFILL genuinely blocks on real input when the source is the
; terminal (confirmed by reading its own code: the terminal
; branch calls QUERY, which per section 3.1's own already-
; established finding calls ACCEPT, which calls KEY, which spins
; forever without real input) - only its safely-testable path
; (source is a string) is tested here, matching the same
; reasoning already applied to KEY/ACCEPT/EXPECT/QUERY
; themselves. EVALUATE genuinely executes its given string as
; real Forth source via JSR INTERPRET - confirmed safe via
; INTERPRET's own code (it simply stops when input is exhausted,
; no automatic REFILL, so no blocking risk), making a short,
; deliberately harmless string ("1 2 +") safe to evaluate
; directly.
;
; ENVIRONMENT? carries substantial, already-documented bug-fix
; history (a COMPAREW-clobbers-X bug, confirmed via MAME with the
; exact $4E4D symptom). This section's own tests specifically
; query "/COUNTED-STRING" immediately followed by "MAX-N" - the
; exact adjacent pair the bug-fix comment describes - so a
; regression of that specific mechanism would be caught again,
; not just assumed fixed from the comment alone.
; ------------------------------------------------------------
TSTENVSYS: JSR CRW
           LDX   #TSTENVSYSMSG
           PSHU  X
           LDD   #6
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-16  ; >>>>

           JSR   TSTENVVARS
           JSR   TSTSOURCE
           JSR   TSTSOURCEID
           JSR   TSTREFILL
           JSR   TSTEVALUATE
           JSR   TSTENVQUERY1
           JSR   TSTENVQUERY2
           JSR   TSTENVQUERY3

           ENDC ; <<<<

           RTS

TSTENVSYSMSG: FCC "EnvSys"

           IFEQ TSTSELECTOR-16  ; >>>>

; ------------------------------------------------------------
; Environmental & System Queries test harness (glossary section
; 3.17). Five words (TIB/#TIB/>IN/SPAN/BL) are simple constant/
; variable readers, combined into one test rather than five
; separate ones, matching the established approach from section
; 3.14's own TSTBASE.
;
; REFILL genuinely blocks on real input when the source is the
; terminal (confirmed by reading its own code directly: the
; terminal branch calls QUERY, which - per section 3.1's own
; already-established finding - calls ACCEPT, which calls KEY,
; which spins forever without real input). Only its safely-
; testable path (source is a string, SRCID<>0) is tested here,
; matching the same reasoning already applied to KEY/ACCEPT/
; EXPECT/QUERY themselves in section 3.1.
;
; EVALUATE genuinely executes its given string as real Forth
; source via JSR INTERPRET - confirmed via INTERPRET's own code
; that it simply stops and returns when input is exhausted (no
; automatic REFILL, so no blocking risk), making a short,
; deliberately harmless string ("1 2 +") safe to evaluate
; directly.
;
; ENVIRONMENT? carries substantial, already-documented bug-fix
; history (a COMPAREW-clobbers-X bug, confirmed via MAME with the
; exact $4E4D symptom - reading two bytes of the NEXT table
; entry's own name text as if they were the current entry's
; value). This section's own tests specifically query
; "/COUNTED-STRING" immediately followed by "MAX-N" - the exact
; adjacent pair the bug-fix comment describes - so a regression
; of that specific mechanism would be caught again, not just
; assumed fixed from the comment alone.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTENVVARS - combined unit test for TIB, #TIB, >IN, SPAN, and
; BL. The first four are variables (return their own address);
; BL is a constant (returns 32 directly).
; ------------------------------------------------------------
TSTENVVARS: STU  TSTU0

            LDD  #TSTGUARD
            PSHU D
            STU  TSTUB4

            JSR  TIBW
            PULU D
            CMPD #TIBBUF
            BNE  EVFAIL

            JSR  NTIBW
            PULU D
            CMPD #NTIB
            BNE  EVFAIL

            JSR  TOINW
            PULU D
            CMPD #TOIN
            BNE  EVFAIL

            JSR  SPANW
            PULU D
            CMPD #SPAN
            BNE  EVFAIL

            JSR  BLW
            PULU D
            CMPD #32
            BNE  EVFAIL

            STU  TSTUAF

            PULU D
            CMPD #TSTGUARD
            BNE  EVFAIL

            LDD  TSTUB4
            SUBD TSTUAF
            CMPD #0
            BNE  EVFAIL

            LDD  #TRUEV
            BRA  EVDONE
EVFAIL:     LDD  #FALSEV
EVDONE:     LDX  #TSTEVNAME
            PSHU X
            PSHU D
            JSR  TSTREPORT

            LDU  TSTU0
            RTS

TSTEVNAME: FCB  10
           FCC  "TSTENVVARS"

; ------------------------------------------------------------
; TSTSOURCE - unit test for SOURCE. Redirects SRCADDR/SRCLEN to
; known, distinctive values, verifies SOURCE returns exactly
; those.
; ------------------------------------------------------------
TSTSOURCE: LDD  SRCADDR
           STD  TSTSASAV
           LDD  SRCLEN
           STD  TSTSLSAV

           LDD  #TSTCBUF
           STD  SRCADDR
           LDD  #7
           STD  SRCLEN

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           STU  TSTUB4

           JSR  SOURCEW

           STU  TSTUAF

           LDD  TSTSASAV
           STD  SRCADDR
           LDD  TSTSLSAV
           STD  SRCLEN

           PULU D
           CMPD #7
           BNE  SOFAIL
           PULU D
           CMPD #TSTCBUF
           BNE  SOFAIL
           PULU D
           CMPD #TSTGUARD
           BNE  SOFAIL

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #4
           BNE  SOFAIL

           LDD  #TRUEV
           BRA  SODONE
SOFAIL:    LDD  #FALSEV
SODONE:    LDX  #TSTSONAME
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTSONAME: FCB  9
           FCC  "TSTSOURCE"

; ------------------------------------------------------------
; TSTSOURCEID - unit test for SOURCE-ID. Redirects SRCID to a
; known, distinctive value, verifies SOURCE-ID returns exactly
; that.
; ------------------------------------------------------------
TSTSOURCEID: LDD  SRCID
             STD  TSTSISAV

             LDD  #-1
             STD  SRCID

             STU  TSTU0

             LDD  #TSTGUARD
             PSHU D
             STU  TSTUB4

             JSR  SOURCEID

             STU  TSTUAF

             LDD  TSTSISAV
             STD  SRCID

             PULU D
             CMPD #-1
             BNE  SIFAIL
             PULU D
             CMPD #TSTGUARD
             BNE  SIFAIL

             LDD  TSTUB4
             SUBD TSTUAF
             CMPD #2
             BNE  SIFAIL

             LDD  #TRUEV
             BRA  SIDONE
SIFAIL:      LDD  #FALSEV
SIDONE:      LDX  #TSTSINAME
             PSHU X
             PSHU D
             JSR  TSTREPORT

             LDU  TSTU0
             RTS

TSTSINAME: FCB  11
           FCC  "TSTSOURCEID"

; ------------------------------------------------------------
; TSTREFILL - unit test for REFILL, string-source path only.
; Confirmed via its own code that the terminal-source path
; (SRCID=0) genuinely blocks on real input (calls QUERY, which
; per section 3.1's own established finding calls ACCEPT, which
; calls KEY, which spins forever without it) - deliberately not
; tested, matching the same reasoning already applied to KEY/
; ACCEPT/EXPECT/QUERY themselves. Only the safely-testable path
; (source is a string, SRCID<>0) is exercised: redirects SRCID
; to a nonzero value and verifies REFILL correctly reports
; false, matching its own documented "fails (false) if the
; current source is a string, per ANS".
; ------------------------------------------------------------
TSTREFILL: LDD  SRCID
           STD  TSTSISAV

           LDD  #-1
           STD  SRCID

           STU  TSTU0

           LDD  #TSTGUARD
           PSHU D
           STU  TSTUB4

           JSR  REFILLW

           STU  TSTUAF

           LDD  TSTSISAV
           STD  SRCID

           PULU D
           CMPD #FALSEV
           BNE  RFFAIL2
           PULU D
           CMPD #TSTGUARD
           BNE  RFFAIL2

           LDD  TSTUB4
           SUBD TSTUAF
           CMPD #2
           BNE  RFFAIL2

           LDD  #TRUEV
           BRA  RFDONE2
RFFAIL2:   LDD  #FALSEV
RFDONE2:   LDX  #TSTRFNAME2
           PSHU X
           PSHU D
           JSR  TSTREPORT

           LDU  TSTU0
           RTS

TSTRFNAME2: FCB  9
            FCC  "TSTREFILL"

; ------------------------------------------------------------
; TSTEVALUATE - unit test for EVALUATE. Evaluates the string
; "1 2 +" (confirmed safe via INTERPRET's own code: it simply
; stops and returns when input is exhausted, no automatic
; REFILL, so no blocking risk) - verifies the result (3) lands
; on the data stack, and that the whole input-source state
; (SRCADDR/SRCLEN/SRCID/TOIN) is genuinely restored to what it
; was before the call, not left pointing at the evaluated
; string. BASE is explicitly saved/set/restored too, per section
; 3.13's own established lesson, so "1"/"2" parse as decimal
; regardless of what BASE happened to hold at test time.
; ------------------------------------------------------------
TSTEVALUATE: LDD  SRCADDR
             STD  TSTSASAV
             LDD  SRCLEN
             STD  TSTSLSAV
             LDD  SRCID
             STD  TSTSISAV
             LDD  TOIN
             STD  TSTTISAV
             LDD  BASE
             STD  TSTBASAV
             LDD  LATEST
             STD  TSTLSAV
             LDD  CODEHERE
             STD  TSTCSAV

             LDD  #10
             STD  BASE
             LDD  #BASELATEST  ; BUG FIX: confirmed via MAME - LATEST,
             STD  LATEST       ; like BASE, is only set by COLD (right
                                ; alongside "BASE=10", in the very same
                                ; init block), which hasn't run yet at
                                ; this whole test framework's own,
                                ; pre-COLD execution point. With
                                ; LATEST=0, FIND reports every word,
                                ; including the real "+" this test
                                ; evaluates, as not found - INTERPRET
                                ; then falls through trying to parse
                                ; "+" as a number, fails that too, and
                                ; throws an error this test never
                                ; catches, landing at THUNCAU's own
                                ; JMP ABORT - which resets the return
                                ; stack, explaining exactly why the
                                ; user's own test run terminated
                                ; without ever reaching TSTENVQUERY1/2/
                                ; 3. The same class of gap as section
                                ; 3.13's own BASE=0 finding, just for a
                                ; different variable this section's
                                ; own EVALUATE test was the first to
                                ; genuinely depend on.

             LDD  #TSTCBUF2  ; SECOND BUG FIX: the LATEST fix above
             STD  CODEHERE   ; alone didn't resolve this - confirmed
                                ; via a second MAME run (the failure
                                ; persisted, with the terminal output
                                ; varying between runs, a strong sign
                                ; of memory corruption rather than a
                                ; single deterministic missing-value
                                ; problem). Root cause: CODEHERE, like
                                ; BASE and LATEST, is only set by COLD
                                ; and was never redirected by this
                                ; test at all - unlike every other
                                ; test in this whole session involving
                                ; WORD (which EVALUATE's own internal
                                ; JSR INTERPRET calls repeatedly, once
                                ; per token). With CODEHERE=0
                                ; (unredirected), WORD's own write of
                                ; each parsed token's [len][text]
                                ; landed straight at address $0000 -
                                ; which is STATE's own address (offset
                                ; $00, the very first bytes of
                                ; GLOBALS, confirmed by re-reading its
                                ; own RMB declaration directly). Even
                                ; a single-character token like "1"
                                ; overwrites STATE with a nonzero
                                ; value, flipping INTERPRET into
                                ; thinking it's compiling rather than
                                ; interpreting mid-parse - explaining
                                ; both the sequence's own termination
                                ; and why the visible output varied
                                ; between runs (the exact corruption
                                ; pattern depends on residual memory
                                ; state from whatever ran immediately
                                ; before). Redirected to TSTCBUF2, not
                                ; TSTCBUF, specifically because TSTCBUF
                                ; already holds this test's own source
                                ; string ("1 2 +") - redirecting to the
                                ; same buffer would let WORD overwrite
                                ; the very source text still being
                                ; parsed.

             LDA  #'1'
             STA  TSTCBUF
             LDA  #32
             STA  TSTCBUF+1
             LDA  #'2'
             STA  TSTCBUF+2
             LDA  #32
             STA  TSTCBUF+3
             LDA  #'+'
             STA  TSTCBUF+4

             STU  TSTU0

             LDD  #TSTGUARD
             PSHU D
             LDD  #TSTCBUF
             PSHU D
             LDD  #5
             PSHU D
             STU  TSTUB4

             JSR  EVALUATEW

             STU  TSTUAF

             LDD  SRCADDR
             CMPD TSTSASAV
             BNE  ELFAIL
             LDD  SRCLEN
             CMPD TSTSLSAV
             BNE  ELFAIL
             LDD  SRCID
             CMPD TSTSISAV
             BNE  ELFAIL
             LDD  TOIN
             CMPD TSTTISAV
             BNE  ELFAIL

             LDD  TSTBASAV
             STD  BASE
             LDD  TSTLSAV
             STD  LATEST
             LDD  TSTCSAV
             STD  CODEHERE

             PULU D
             CMPD #3
             BNE  ELFAIL
             PULU D
             CMPD #TSTGUARD
             BNE  ELFAIL

             LDD  TSTUB4
             SUBD TSTUAF
             CMPD #-2
             BNE  ELFAIL

             LDD  #TRUEV
             BRA  ELDONE
ELFAIL:      LDD  #FALSEV
ELDONE:      LDX  #TSTELNAME
             PSHU X
             PSHU D
             JSR  TSTREPORT

             LDU  TSTU0
             RTS

TSTELNAME: FCB  11
           FCC  "TSTEVALUATE"

; ------------------------------------------------------------
; TSTENVQUERY1 - unit test for ENVIRONMENT?, verifying the exact
; adjacent-entry pair its own bug-fix comment describes:
; "/COUNTED-STRING" (255) immediately followed by "MAX-N"
; (32767) - the specific mechanism that once let COMPAREW's own
; X-clobbering read bytes from the wrong table entry, confirmed
; via MAME with the exact $4E4D symptom (per the code's own
; comment). Querying this exact pair again here means a
; regression of that specific mechanism would be caught, not
; just assumed still fixed from the comment alone.
; ------------------------------------------------------------
TSTENVQUERY1: LDA  #'/'
              STA  TSTCBUF
              LDA  #'C'
              STA  TSTCBUF+1
              LDA  #'O'
              STA  TSTCBUF+2
              LDA  #'U'
              STA  TSTCBUF+3
              LDA  #'N'
              STA  TSTCBUF+4
              LDA  #'T'
              STA  TSTCBUF+5
              LDA  #'E'
              STA  TSTCBUF+6
              LDA  #'D'
              STA  TSTCBUF+7
              LDA  #'-'
              STA  TSTCBUF+8
              LDA  #'S'
              STA  TSTCBUF+9
              LDA  #'T'
              STA  TSTCBUF+10
              LDA  #'R'
              STA  TSTCBUF+11
              LDA  #'I'
              STA  TSTCBUF+12
              LDA  #'N'
              STA  TSTCBUF+13
              LDA  #'G'
              STA  TSTCBUF+14

              LDA  #'M'
              STA  TSTCBUF+20
              LDA  #'A'
              STA  TSTCBUF+21
              LDA  #'X'
              STA  TSTCBUF+22
              LDA  #'-'
              STA  TSTCBUF+23
              LDA  #'N'
              STA  TSTCBUF+24

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              LDD  #TSTCBUF
              PSHU D
              LDD  #15
              PSHU D
              JSR  ENVQUERY

              PULU D
              CMPD #TRUEV
              BNE  EN1FAIL
              PULU D
              CMPD #255
              BNE  EN1FAIL

              LDD  #TSTCBUF+20
              PSHU D
              LDD  #5
              PSHU D
              JSR  ENVQUERY

              STU  TSTUAF

              PULU D
              CMPD #TRUEV
              BNE  EN1FAIL
              PULU D
              CMPD #32767
              BNE  EN1FAIL

              PULU D
              CMPD #TSTGUARD
              BNE  EN1FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #4
              BNE  EN1FAIL

              LDD  #TRUEV
              BRA  EN1DONE
EN1FAIL:       LDD  #FALSEV
EN1DONE:       LDX  #TSTEN1NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTEN1NAME: FCB  12
           FCC  "TSTENVQUERY1"

; ------------------------------------------------------------
; TSTENVQUERY2 - unit test for ENVIRONMENT?, double-cell case.
; Queries "MAX-D" - confirmed via its own table entry to be
; $7FFFFFFF (low cell $FFFF, high cell $7FFF) - exercising the
; separate double-cell table path (ENVTABLE2/ENV2START), not
; just the single-cell one TSTENVQUERY1 already covers.
; ------------------------------------------------------------
TSTENVQUERY2: LDA  #'M'
              STA  TSTCBUF
              LDA  #'A'
              STA  TSTCBUF+1
              LDA  #'X'
              STA  TSTCBUF+2
              LDA  #'-'
              STA  TSTCBUF+3
              LDA  #'D'
              STA  TSTCBUF+4

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              LDD  #TSTCBUF
              PSHU D
              LDD  #5
              PSHU D
              JSR  ENVQUERY

              STU  TSTUAF

              PULU D
              CMPD #TRUEV
              BNE  EW2FAIL
              PULU D
              CMPD #$7FFF
              BNE  EW2FAIL
              PULU D
              CMPD #$FFFF
              BNE  EW2FAIL

              PULU D
              CMPD #TSTGUARD
              BNE  EW2FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #6
              BNE  EW2FAIL

              LDD  #TRUEV
              BRA  EW2DONE
EW2FAIL:      LDD  #FALSEV
EW2DONE:      LDX  #TSTEW2NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTEW2NAME: FCB  12
            FCC  "TSTENVQUERY2"

; ------------------------------------------------------------
; TSTENVQUERY3 - unit test for ENVIRONMENT?, unsupported string
; case. Queries "ZZZZZ" - genuinely absent from both tables -
; verifies false is reported, matching the documented "-- false"
; result for an unrecognized string.
; ------------------------------------------------------------
TSTENVQUERY3: LDA  #'Z'
              STA  TSTCBUF
              STA  TSTCBUF+1
              STA  TSTCBUF+2
              STA  TSTCBUF+3
              STA  TSTCBUF+4

              STU  TSTU0

              LDD  #TSTGUARD
              PSHU D
              STU  TSTUB4

              LDD  #TSTCBUF
              PSHU D
              LDD  #5
              PSHU D
              JSR  ENVQUERY

              STU  TSTUAF

              PULU D
              CMPD #FALSEV
              BNE  EW3FAIL
              PULU D
              CMPD #TSTGUARD
              BNE  EW3FAIL

              LDD  TSTUB4
              SUBD TSTUAF
              CMPD #2
              BNE  EW3FAIL

              LDD  #TRUEV
              BRA  EW3DONE
EW3FAIL:      LDD  #FALSEV
EW3DONE:      LDX  #TSTEW3NAME
              PSHU X
              PSHU D
              JSR  TSTREPORT

              LDU  TSTU0
              RTS

TSTEW3NAME: FCB  12
            FCC  "TSTENVQUERY3"

           ENDC ; <<<<

; ------------------------------------------------------------
; TSTTOOLS - tools word set tests (glossary section 3.18, 3
; words). WORDS depends directly on LATEST (confirmed via its
; own code) - redirected for this test, applying the same
; lesson section 3.17's own TSTEVALUATE surfaced. DUMP dumps a
; deliberately non-multiple-of-16 byte count (5), the exact
; scenario its own already-documented DUVALID bug fix addresses,
; and this section's own test specifically verifies the ASCII
; column's blanking for the unused portion, not just the real
; data. .S prints the entire real data stack, including whatever
; the calling chain already left there - unlike every other test
; in this session, the full output can't be predicted in
; advance, so this section's own test verifies the core,
; documented "non-destructive" guarantee directly instead.
; ------------------------------------------------------------
TSTTOOLS: JSR CRW
           LDX   #TSTTOOLSMSG
           PSHU  X
           LDD   #5
           PSHU  D
           JSR   TYPE
           JSR   CRW

           IFEQ TSTSELECTOR-17  ; >>>>

           JSR   TSTDOTS
           JSR   TSTWORDS
           JSR   TSTDUMP

           ENDC ; <<<<

           RTS

TSTTOOLSMSG: FCC "Tools"

           IFEQ TSTSELECTOR-17  ; >>>>

; ------------------------------------------------------------
; Tools test harness (glossary section 3.18). WORDS depends
; directly on LATEST (confirmed via its own code: it walks from
; LATEST until the chain terminates at 0) - the same real, pre-
; COLD dependency section 3.17's own TSTEVALUATE was found to
; need, so this section's own WORDS test redirects LATEST too,
; applying that lesson from the start rather than rediscovering
; it. All three words produce visible output, so all apply the
; SERIALPOLL-conditional split established in section 3.1.
;
; .S prints the ENTIRE real data stack, including whatever this
; whole calling chain (TSTRUNNER and everything above it) already
; left there before this test even started - unlike every other
; test in this session, there's no way to know the full, exact
; output in advance. This test's own verification is deliberately
; narrower as a result: confirms the core, documented guarantee
; directly (the stack is genuinely unchanged afterward, non-
; destructive for real) plus, in interrupt mode only (where the
; first characters queued are unambiguously this test's own top
; value, since .S starts from the current top of stack), that the
; very first characters match - rather than attempting to predict
; or verify the complete printed output.
;
; DUMP carries real, already-documented bug-fix history: a prior
; version's ASCII column read past the actual byte count on a
; partial final line, showing garbage characters for the unused
; portion - fixed via DUVALID tracking. This section's own test
; specifically dumps a non-multiple-of-16 byte count (5), the
; exact scenario that bug affected, verifying the ASCII column's
; own blanking for the remaining, invalid columns.
; ------------------------------------------------------------

; ------------------------------------------------------------
; TSTDOTS - unit test for .S. Pushes two known values (no guard
; sentinel below them, since .S would print that too), calls .S,
; and verifies the stack is genuinely unchanged afterward - the
; core, documented "non-destructive" guarantee, confirmed
; directly rather than inferred. In interrupt mode specifically,
; also confirms the very first characters queued match the top
; value's own printed form (unambiguous, since .S starts from
; the current top of stack); polling mode only confirms some
; output occurred, given EMITCH alone can't distinguish this
; test's own output from whatever the rest of the real stack
; contributes afterward.
; ------------------------------------------------------------
TSTDOTS: LDD  BASE
         STD  TSTBASAV

         LDD  #10
         STD  BASE      ; BUG FIX: confirmed via MAME - the same
                          ; BASE=0 infinite loop already found and
                          ; fixed in section 3.13. .S internally calls
                          ; DOT for each stack item, which calls
                          ; NUMSIGN/UDDIGIT - the same restoring-
                          ; division mechanism that degrades into an
                          ; unconditional shift when BASE=0 (only set
                          ; by COLD, which hasn't run yet at this
                          ; whole test framework's own pre-COLD
                          ; execution point), so the value being
                          ; converted never genuinely decreases.
                          ; Forgot to apply this section 3.13 lesson
                          ; to this specific test when first writing
                          ; it. WORDS and DUMP were checked and
                          ; confirmed NOT to need this same fix: WORDS
                          ; does no numeric conversion at all (just
                          ; TYPEs name text), and DUMP's own hex
                          ; conversion (HEXDIGIT/HEXBYTE) is a fixed,
                          ; hardcoded base-16 converter, confirmed via
                          ; its own code to never reference BASE at
                          ; all - genuinely independent of it, not
                          ; just assumed safe.

         STU  TSTU0

         IFEQ SERIALPOLL  ; >>>>
         LDA  OUTHEAD
         STA  TSTOHSAV
         ENDC ; <<<<

         LDD  #TSTVAL1
         PSHU D
         LDD  #7
         PSHU D
         STU  TSTUB4

         JSR  DOTS

         STU  TSTUAF

         IFEQ SERIALPOLL  ; >>>>
         LDA  TSTOHSAV
         ADDA #2
         ANDA #OUTBUFSZ-1
         CMPA OUTHEAD
         BNE  DYFAIL

         LDX  #OUTBUF
         LDB  TSTOHSAV
         LDA  B,X
         CMPA #'7'
         BNE  DYFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #32
         BNE  DYFAIL
         ELSE  ; <<<<>>>>
         LDA  EMITCH
         CMPA #0
         BEQ  DYFAIL
         ENDC  ; <<<<<<<<<<

         LDD  TSTBASAV
         STD  BASE

         LDD  TSTUAF
         SUBD TSTUB4
         CMPD #0
         BNE  DYFAIL

         PULU D
         CMPD #7
         BNE  DYFAIL
         PULU D
         CMPD #TSTVAL1
         BNE  DYFAIL

         LDD  #TRUEV
         BRA  DYDONE
DYFAIL:  LDD  #FALSEV
DYDONE:  LDX  #TSTDSNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDU  TSTU0
         RTS

TSTDSNAME: FCB  7
           FCC  "TSTDOTS"

; ------------------------------------------------------------
; TSTWORDS - unit test for WORDS. Builds two small, linked fake
; headers ("CD" pointing back to "AB", terminated with 0) and
; redirects LATEST to the more recent one - confirmed via its
; own code that WORDS walks directly from LATEST until the chain
; terminates, so this is the one dependency it genuinely has.
; Verifies the full expected output ("CD AB " followed by CR/LF,
; 8 bytes total) under SERIALPOLL=0; under SERIALPOLL=1, only the
; last character (LF, from the trailing CR) is checkable via
; EMITCH.
; ------------------------------------------------------------
TSTWORDS: LDD  LATEST
          STD  TSTLSAV

          LDA  #2
          STA  TSTCBUF
          LDA  #'A'
          STA  TSTCBUF+1
          LDA  #'B'
          STA  TSTCBUF+2
          LDD  #0
          STD  TSTCBUF+3
          LDD  #DUP
          STD  TSTCBUF+5

          LDA  #2
          STA  TSTCBUF+10
          LDA  #'C'
          STA  TSTCBUF+11
          LDA  #'D'
          STA  TSTCBUF+12
          LDD  #TSTCBUF
          STD  TSTCBUF+13
          LDD  #DUP
          STD  TSTCBUF+15

          LDD  #TSTCBUF+10
          STD  LATEST

          IFEQ SERIALPOLL  ; >>>>
          LDA  OUTHEAD
          STA  TSTOHSAV
          ENDC ; <<<<

          STU  TSTU0
          STU  TSTUB4

          JSR  WORDSW

          STU  TSTUAF

          LDD  TSTLSAV
          STD  LATEST

          IFEQ SERIALPOLL  ; >>>>
          LDA  TSTOHSAV
          ADDA #8
          ANDA #OUTBUFSZ-1
          CMPA OUTHEAD
          BNE  WOFAIL

          LDX  #OUTBUF
          LDB  TSTOHSAV
          LDA  B,X
          CMPA #'C'
          BNE  WOFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'D'
          BNE  WOFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #32
          BNE  WOFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'A'
          BNE  WOFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #'B'
          BNE  WOFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #32
          BNE  WOFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #13
          BNE  WOFAIL
          INCB
          ANDB #OUTBUFSZ-1
          LDA  B,X
          CMPA #10
          BNE  WOFAIL
          ELSE  ; <<<<>>>>
          LDA  EMITCH
          CMPA #10
          BNE  WOFAIL
          ENDC  ; <<<<<<<<<<

          LDD  TSTUB4
          SUBD TSTUAF
          CMPD #0
          BNE  WOFAIL

          LDD  #TRUEV
          BRA  WODONE
WOFAIL:   LDD  #FALSEV
WODONE:   LDX  #TSTWONAME
          PSHU X
          PSHU D
          JSR  TSTREPORT

          LDU  TSTU0
          RTS

TSTWONAME: FCB  8
           FCC  "TSTWORDS"

; ------------------------------------------------------------
; TSTDUMP - unit test for DUMP. Dumps 5 bytes ("ABCDE") -
; deliberately less than 16, the exact scenario the word's own
; already-documented bug fix (DUVALID tracking) addresses:
; without it, the ASCII column read past the actual byte count
; on a partial final line, showing garbage for the unused
; portion instead of blanks. Under SERIALPOLL=0, verifies the
; total byte count (69: leading CR/LF, 5 real hex byte pairs, 11
; padded hex slots, 1 separator, the 16-character ASCII column,
; trailing CR/LF), the 5 real hex digit pairs at their known
; offsets, and - the specific, bug-relevant check - the full
; 16-character ASCII column itself: the first 5 characters match
; "ABCDE" and the remaining 11 are genuinely blank (32), verified
; via a loop rather than 11 unrolled checks. Under SERIALPOLL=1,
; only the last character (LF, from the trailing CR) is
; checkable via EMITCH.
; ------------------------------------------------------------
TSTDUMP: LDA  #'A'
         STA  TSTCBUF
         LDA  #'B'
         STA  TSTCBUF+1
         LDA  #'C'
         STA  TSTCBUF+2
         LDA  #'D'
         STA  TSTCBUF+3
         LDA  #'E'
         STA  TSTCBUF+4

         IFEQ SERIALPOLL  ; >>>>
         LDA  OUTHEAD
         STA  TSTOHSAV
         ENDC ; <<<<

         STU  TSTU0
         STU  TSTUB4

         LDD  #TSTCBUF
         PSHU D
         LDD  #5
         PSHU D
         JSR  DUMPW

         STU  TSTUAF

         IFEQ SERIALPOLL  ; >>>>
         LDA  TSTOHSAV
         ADDA #69
         ANDA #OUTBUFSZ-1
         CMPA OUTHEAD
         BNE  DUFAIL

         LDX  #OUTBUF
         LDB  TSTOHSAV
         ADDB #2
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'4'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'1'
         BNE  DUFAIL

         LDB  TSTOHSAV
         ADDB #5
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'4'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'2'
         BNE  DUFAIL

         LDB  TSTOHSAV
         ADDB #14
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'4'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'5'
         BNE  DUFAIL

         LDB  TSTOHSAV
         ADDB #51
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'A'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'B'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'C'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'D'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LDA  B,X
         CMPA #'E'
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1

         LDY  #11
DUBLNKLP: LDA  B,X
         CMPA #32
         BNE  DUFAIL
         INCB
         ANDB #OUTBUFSZ-1
         LEAY -1,Y
         BNE  DUBLNKLP
         ELSE  ; <<<<>>>>
         LDA  EMITCH
         CMPA #10
         BNE  DUFAIL
         ENDC  ; <<<<<<<<<<

         LDD  TSTUB4
         SUBD TSTUAF
         CMPD #0
         BNE  DUFAIL

         LDD  #TRUEV
         BRA  DUDONE2
DUFAIL:  LDD  #FALSEV
DUDONE2: LDX  #TSTDUNAME
         PSHU X
         PSHU D
         JSR  TSTREPORT

         LDU  TSTU0
         RTS

TSTDUNAME: FCB  7
           FCC  "TSTDUMP"

           ENDC ; <<<<

         ENDC  ; <<<<<<<<<<

ROM:
         FILL $FF,BASEDICT-ROM

