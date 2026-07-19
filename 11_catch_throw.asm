; ============================================================
; 6809 FORTH - 11_catch_throw
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 11: COLON / SEMICOLON support already in section 8
; (COLON/SEMI) - CATCH/THROW, CFERR
; ============================================================
CFERR:   LDD   #-22
         PSHU  D
         JSR   THROW
         RTS

CATCH:   PULU  X
         LDD   HANDLER
         PSHS  D
         PSHS  U
         TFR   S,D
         STD   HANDLER

         JSR   ,X

         LEAS  2,S
         PULS  D
         STD   HANDLER
         LDD   #0
         PSHU  D
         RTS

THROW:   PULU  D
         CMPD  #0
         BEQ   THDONE

         STD   THROWN
         LDX   HANDLER
         BEQ   THUNCAU

         TFR   X,S
         PULS  D
         TFR   D,U
         PULS  D
         STD   HANDLER

         LDD   THROWN
         PSHU  D
         RTS
THDONE:  RTS

THUNCAU: LDD   THROWN
         PSHU  D
         JMP   ABORT

; ============================================================
