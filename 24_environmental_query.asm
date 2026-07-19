; ============================================================
; 6809 FORTH - 24_environmental_query
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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
