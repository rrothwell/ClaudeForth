\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 23 (23_comment_words)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M23 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M23 at the end (below)
\ erases everything this file defined - including M23 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M23

\ F.6.1.0080  (
\ There is no space either side of the ).  T{ ( A comment)1234 -> }T   T{ : pc1 ( A comment)1234 ; pc1 -> 1234 }T

\ ---- section-marker: undo everything above ----
M23
