; ============================================================
; 6809 FORTH - 07_header
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 7: HEADER (factored from :/CREATE/VARIABLE)
; ============================================================
HEADER:  LDD   #32
         PSHU  D
         JSR   WORD
         PULU  X
         LDA   ,X
         STA   NAMELEN
         LEAX  1,X
         STX   NAMEP

         PULU  D
         STB   HDRSMUDGE

         LDD   DPHERE
         STD   NEWHDR
         LDX   DPHERE
         LDA   NAMELEN
         TST   HDRSMUDGE
         BEQ   HDNOSM
         ORA   #$40
HDNOSM:  STA   ,X+
         LDY   NAMEP
         LDB   NAMELEN
         BEQ   HDNONM
HDCPY:   LDA   ,Y+
         STA   ,X+
         DECB
         BNE   HDCPY
HDNONM:  LDD   LATEST
         STD   ,X++
         LDD   CODEHERE
         STD   ,X++
         STX   DPHERE
         LDD   NEWHDR
         STD   LATEST
         RTS

; ============================================================
