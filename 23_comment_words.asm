; ============================================================
; 6809 FORTH - 23_comment_words
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 23: COMMENT WORDS
; ============================================================
LPAREN:  LDD   #')'
         PSHU  D
         JSR   WORD
         RTS

BACKSLASH: LDD  SRCLEN
           STD  TOIN
           RTS

; ============================================================
