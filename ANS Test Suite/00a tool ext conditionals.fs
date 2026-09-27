\ ============================================================
\ 00a_tool_ext_conditionals.fs
\ [IF] [ELSE] [THEN] - Programming-Tools word set (conditional
\ compilation), not implemented natively by forth6809.asm.
\
\ These are needed before ttester.fs itself will load: ttester.fs
\ uses [IF]/[ELSE]/[THEN] in its own HAS-FLOATING and
\ HAS-FLOATING-STACK ENVIRONMENT? checks. So this file must be
\ sent first, ahead of ttester.fs, 00_test_prelude.fs, and every
\ section file.
\
\ This is the reference implementation given informatively by the
\ standard itself (forth-standard.org/standard/tools/BracketELSE),
\ built only from words already resident in forth6809.asm: BL,
\ WORD, COUNT, S", COMPARE, REFILL, IF/ELSE/THEN, BEGIN/WHILE/
\ REPEAT/UNTIL, ?DUP, EXIT, IMMEDIATE. [IF] with a false flag and
\ [ELSE] both need to do exactly the same thing - skip forward,
\ tracking nesting depth, until the matching [ELSE] or [THEN] at
\ the current level - so [IF] just falls through into [ELSE]'s
\ code via POSTPONE when its flag is false. [THEN] is a no-op
\ marker; it only has to exist as a word so the interpreter/
\ compiler doesn't choke when it's reached normally.
\ ============================================================

: [ELSE] ( -- )
   1 BEGIN
      BEGIN  BL WORD COUNT DUP  WHILE          \ level adr len
         2DUP S" [IF]" COMPARE 0= IF
            2DROP 1+                            \ level'
         ELSE
            2DUP S" [ELSE]" COMPARE 0= IF
               2DROP 1- DUP IF 1+ THEN          \ level'
            ELSE
               S" [THEN]" COMPARE 0= IF
                  1-                             \ level'
               THEN
            THEN
         THEN
         ?DUP 0= IF EXIT THEN                    \ level'
      REPEAT 2DROP
      REFILL 0=
   UNTIL
   DROP
; IMMEDIATE

: [IF] ( flag -- )
   0= IF POSTPONE [ELSE] THEN
; IMMEDIATE

: [THEN] ( -- )
; IMMEDIATE
