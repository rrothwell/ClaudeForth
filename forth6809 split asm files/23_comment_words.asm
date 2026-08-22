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

