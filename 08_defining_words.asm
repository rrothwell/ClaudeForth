; ============================================================
; 6809 FORTH - 08_defining_words
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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
         LDD   CODEHERE
         PSHU  D
         JSR   CODECOMMA
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
          LDD  CODEHERE
          PSHU D
          JSR  CODECOMMA
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
             LDD CODEHERE
             PSHU D
             JSR CODECOMMA
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
         LDD   CODEHERE
         PSHU  D
         JSR   CODECOMMA
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
         LDD   CODEHERE
         PSHU  D
         JSR   CODECOMMA
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
