\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 9 (09_outer_interpreter)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M09 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M09 at the end (below)
\ erases everything this file defined - including M09 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M09

\ F.6.1.1550  FIND
\ GT1/GT2 are normally defined by the '/['] tests in
\ 13_compiling_words.tests.fs (section 13), which forth6809.asm's
\ own section numbering places after this one. Defined locally
\ here (copied verbatim from that file) so this file has no
\ cross-section load-order dependency and can run standalone.
T{ : GT1 123 ; -> }T   T{ ' GT1 EXECUTE -> 123 }T
T{ : GT2 ['] GT1 ; IMMEDIATE -> }T   T{ GT2 EXECUTE -> 123 }T

HERE 3 C, CHAR G C, CHAR T C, CHAR 1 C, CONSTANT GT1STRING
HERE 3 C, CHAR G C, CHAR T C, CHAR 2 C, CONSTANT GT2STRING   T{ GT1STRING FIND -> ' GT1 -1 }T   T{ GT2STRING FIND -> ' GT2 1 }T

\ ---- section-marker: undo everything above ----
M09
