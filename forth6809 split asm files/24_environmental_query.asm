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

