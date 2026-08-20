; ============================================================
; SECTION 18: MEMORY (fetch/store, block ops)
; ============================================================
STOREW:  PULU  X
         PULU  D
         STD   ,X
         RTS

CFETCH:  PULU  X
         LDB   ,X
         CLRA
         PSHU  D
         RTS

CSTOREW: PULU  X
         PULU  D
         STB   ,X
         RTS

PLUSSTORE: PULU X
           PULU D
           ADDD ,X
           STD  ,X
           RTS

DFETCH:  PULU  X          ; BUG FIX: was reading high address first
         LDD   ,X         ; (pushed deep) then low address second
         PSHU  D          ; (pushed on top) - the reverse of what
         LDD   2,X        ; DSTORE actually writes (x1 low, x2 high),
         PSHU  D          ; so a 2! 2@ round trip swapped the two
         RTS              ; values. Now reads low first (x1, pushed
                          ; deep) then high second (x2, pushed on
                          ; top), matching DSTORE and correctly
                          ; round-tripping. Flagged by the parallel
                          ; 68000 port, confirmed by inspection.

DSTORE:  PULU  X
         PULU  D
         STD   2,X
         PULU  D
         STD   ,X
         RTS

CMOVEW:  PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDX   MVSRC
         LDY   MVDST
CMVLOOP: LDD   MVCNT
         BEQ   CMDONE
         SUBD  #1         ; BUG FIX: was after the byte copy below -
         STD   MVCNT      ; LDA ,X+ (needed for the byte itself)
                          ; clobbers A, D's high byte, corrupting the
                          ; count before SUBD used it. Unlike FILL,
                          ; there's no spare 16-bit register to keep
                          ; the count in instead - X and Y are both
                          ; already committed to the source and
                          ; destination addresses - so the fix here is
                          ; reordering: decrement and store while D
                          ; still holds the true count, before the
                          ; copy is free to clobber A. Confirmed via
                          ; MAME debugger: the loop never terminated.
         LDA   ,X+
         STA   ,Y+
         BRA   CMVLOOP
CMDONE:  RTS

CMOVEGT: PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDD   MVCNT
         BEQ   CGDONE
         LDX   MVSRC
         LEAX  D,X
         LEAX  -1,X
         LDY   MVDST
         LEAY  D,Y
         LEAY  -1,Y
CGLOOP:  LDA   ,X
         STA   ,Y
         LEAX  -1,X
         LEAY  -1,Y
         LDD   MVCNT
         SUBD  #1
         STD   MVCNT
         BNE   CGLOOP
CGDONE:  RTS

MOVEW:   PULU  D
         STD   MVCNT
         PULU  D
         STD   MVDST
         PULU  D
         STD   MVSRC
         LDD   MVDST
         CMPD  MVSRC
         BLS   MVLOW
         LDD   MVSRC
         PSHU  D
         LDD   MVDST
         PSHU  D
         LDD   MVCNT
         PSHU  D
         JMP   CMOVEGT
MVLOW:   LDD   MVSRC
         PSHU  D
         LDD   MVDST
         PSHU  D
         LDD   MVCNT
         PSHU  D
         JMP   CMOVEW

FILLW:   PULU  D
         STB   FILLCHR
         PULU  D
         TFR   D,Y        ; BUG FIX: was STD FILLCNT/LDD FILLCNT each
                          ; iteration - and inside the loop, LDA
                          ; FILLCHR (needed for the fill byte) clobbers
                          ; A, which is D's high byte, corrupting the
                          ; count that SUBD #1 then decremented from.
                          ; The high byte took on the fill character's
                          ; value instead of the count's real high
                          ; byte, so the count almost never reached
                          ; zero at the intended point - FILL ran far
                          ; past the requested length. Keeping the
                          ; count in Y instead removes the conflict
                          ; entirely (Y is untouched by loading the
                          ; fill character into A) and removes the
                          ; per-iteration memory round-trip - also
                          ; addresses the redundant scratch usage
                          ; flagged alongside this bug. Confirmed via
                          ; MAME debugger.
         PULU  D
         TFR   D,X        ; address, kept directly in X rather than
                          ; round-tripping through FILLADDR too
FILLOOP: CMPY  #0
         BEQ   FDONE
         LDA   FILLCHR
         STA   ,X+
         LEAY  -1,Y
         BRA   FILLOOP
FDONE:   RTS

ERASEW:  LDD   #0
         PSHU  D
         JMP   FILLW

