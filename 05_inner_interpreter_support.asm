; ============================================================
; 6809 FORTH - 05_inner_interpreter_support
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
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
