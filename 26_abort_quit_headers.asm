; ============================================================
; 6809 FORTH - 26_abort_quit_headers
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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
