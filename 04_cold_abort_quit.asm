; ============================================================
; 6809 FORTH - 04_cold_abort_quit
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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
