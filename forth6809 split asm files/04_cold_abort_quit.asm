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

