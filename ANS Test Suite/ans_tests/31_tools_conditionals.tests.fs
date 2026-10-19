\ ============================================================
\ ANS test suite - Programming-Tools words [IF] [ELSE] [THEN]
\ (native since stage 6d; before that they were loaded from
\ 00a_tool_ext_conditionals.fs).
\ Requires ttester.fs then 00_test_prelude.fs first, in that order.
\ The first block follows F.15.6.2.2531 / 2532 / 2533 of the
\ standard's test suite; the rest cover compile-time use, nesting,
\ flag handling, case, and look-alike names.
\ ============================================================
MARKER M31
TEST-BEGIN

HEX

\ ---- [IF] [ELSE] [THEN], from the standard ----
T{ TRUE  [IF] 111 [ELSE] 222 [THEN] -> 111 }T
T{ FALSE [IF] 111 [ELSE] 222 [THEN] -> 222 }T
T{ TRUE  [IF] 1 2 [ELSE] 3 4 [THEN] -> 1 2 }T
T{ FALSE [IF] 1 2 [ELSE] 3 4 [THEN] -> 3 4 }T
T{ TRUE  [IF] 1 TRUE  [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 1 2 }T
T{ FALSE [IF] 1 TRUE  [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 4 }T
T{ FALSE [IF] 1 FALSE [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 4 }T
T{ TRUE  [IF] 1 FALSE [IF] 2 [ELSE] 3 [THEN] [ELSE] 4 [THEN] -> 1 3 }T

\ ---- without an [ELSE] ----
T{ TRUE  [IF] 5 [THEN] -> 5 }T
T{ FALSE [IF] 5 [THEN] -> }T
T{ FALSE [IF] 1 TRUE [IF] 2 [THEN] [ELSE] 3 [THEN] -> 3 }T
T{ FALSE [IF] 1 FALSE [IF] 2 [THEN] [THEN] 6 -> 6 }T

\ ---- the flag is consumed, anything under it is untouched ----
T{ 7 TRUE  [IF] [THEN] -> 7 }T
T{ 7 FALSE [IF] [THEN] -> 7 }T
T{ 5 [IF] 1 [ELSE] 2 [THEN] -> 1 }T
T{ -1 [IF] 1 [ELSE] 2 [THEN] -> 1 }T
T{ MIN-INT [IF] 1 [ELSE] 2 [THEN] -> 1 }T
T{ 0 [IF] 1 [ELSE] 2 [THEN] -> 2 }T

\ ---- [ELSE] and [THEN] on their own ----
\ [ELSE] reached in the true branch skips to its [THEN].
T{ 1 [ELSE] 2 [THEN] 3 -> 1 3 }T
T{ 1 [THEN] 2 -> 1 2 }T
T{ 1 [ELSE] 2 [IF] 3 [ELSE] 4 [THEN] [THEN] 5 -> 1 5 }T

\ ---- the skipped text is never executed or looked up ----
T{ FALSE [IF] no-such-word-1 [ELSE] 8 [THEN] -> 8 }T
T{ TRUE [IF] 9 [ELSE] no-such-word-2 [THEN] -> 9 }T
T{ FALSE [IF] 1 2 3 4 5 DROP DROP DROP [ELSE] 0 [THEN] -> 0 }T

\ ---- while compiling: the flag is computed with [ ... ] ----
T{ : cc1 [ TRUE  ] [IF] 111 [ELSE] 222 [THEN] ; cc1 -> 111 }T
T{ : cc2 [ FALSE ] [IF] 111 [ELSE] 222 [THEN] ; cc2 -> 222 }T
T{ : cc3 1 [ FALSE ] [IF] 2 [THEN] 3 ; cc3 -> 1 3 }T
\ A definition inside the skipped part is not compiled.
T{ FALSE [IF] : cc4 4 ; [ELSE] : cc4 44 ; [THEN] cc4 -> 44 }T
T{ TRUE  [IF] : cc5 5 ; [ELSE] : cc5 55 ; [THEN] cc5 -> 5 }T

\ ---- case matters, as it does for every name in the system ----
\ Lower and mixed case spellings inside skipped text are ordinary
\ words, not markers: only the exact upper-case names count.
T{ FALSE [IF] [else] [then] [If] [ELSE] 3 [THEN] -> 3 }T
T{ TRUE  [IF] 1 [ELSE] [then] [if] 2 [THEN] -> 1 }T
T{ FALSE [IF] 1 [Else] 2 [ELSE] 4 [THEN] -> 4 }T

\ ---- names that only look like the markers are skipped over ----
T{ FALSE [IF] [IFX] [ELS] [THE] [ELSEY] [THENS] [ELSE] 1 [THEN] -> 1 }T
T{ FALSE [IF] [IX] [ELSX] [THEX] [ELSE] 7 [THEN] -> 7 }T
T{ FALSE [IF] [] [IF [IF]] [ELSE] 2 [THEN] -> 2 }T

\ ---- at the end of the input (EVALUATE): the skip just ends ----
: ev1 S" FALSE [IF] 1 2" EVALUATE ;
T{ ev1 -> }T
: ev2 S" 3 FALSE [IF] 1 [ELSE] 4" EVALUATE ;
T{ ev2 -> 3 4 }T
: ev3 S" 5 FALSE [IF] 1 [ELSE] 4 [THEN] 6" EVALUATE ;
T{ ev3 -> 5 4 6 }T
: ev4 S" TRUE [IF] 7 [ELSE] 8 [THEN]" EVALUATE ;
T{ ev4 -> 7 }T

\ ---- spread over more than one line (the skip refills the input) ----
T{ TRUE  [IF] 1
             2
          [ELSE]
             3
             4
          [THEN] -> 1 2 }T
T{ FALSE [IF] 1
             2
          [ELSE]
             3
             4
          [THEN] -> 3 4 }T

\ Print this file's TEST SUMMARY and trim any stray stack cells.
TEST-END
\ ---- section-marker: undo everything above ----
M31
