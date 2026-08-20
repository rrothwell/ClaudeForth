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

