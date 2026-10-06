\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 24 (24_environmental_query)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ ---- section-marker: makes this file independently runnable ----
\ M24 snapshots the dictionary/HERE state right before this
\ file's own definitions begin. Invoking M24 at the end (below)
\ erases everything this file defined - including M24 itself -
\ restoring the system to the state it was in just after
\ ttester.fs + 00_test_prelude.fs were loaded. This lets the
\ automation load/run/reset one section file at a time, in any
\ order, without cross-file dictionary pollution.
MARKER M24
\ Reset the pass/fail counters, record the stack depth.
TEST-BEGIN

\ F.6.1.0560  >IN

VARIABLE SCANS

\ This test must retain the multiline split 
\ to proceed to completion by scanning multiple lines.
\ It infinite loops in INTERPRET otherwise.
: RESCAN? -1 SCANS +! SCANS @ IF 0 >IN ! THEN ;
T{ 2 SCANS !
 345 RESCAN?
 -> 345 345 }T

: GS2 5 SCANS ! S" 123 RESCAN?" EVALUATE ;
T{ GS2 -> 123 123 123 123 123 }T

\ These tests must start on a new line
\ This block's literals (123456, 14145, 8115...) need DECIMAL, but
\ the >NUMBER section right below needs ambient HEX back - its own
\ expected results include bare hex digits ("F", and BL's "20")
\ that aren't valid decimal numbers at all. Previously this file
\ called DECIMAL here and never switched back, which broke its own
\ later >NUMBER tests (not just the next file in load order, as
\ with 08/11/12 - this one broke itself). Save/restore locally.
\ BUG FIX (round 1): was "BASE @ >R DECIMAL ... R> BASE !" - unsafe
\ spanning separate top-level lines (see 08_defining_words.tests.fs's
\ matching comment for the full >R/R> mechanism). (GN1 and
\ >NUMBER-BASED below use >R/R> too, but entirely inside their own
\ single colon-definition, executed as one unbroken call - that's
\ the safe, standard use and is left alone.)
\ BUG FIX (round 2): plain "BASE @ DECIMAL ... BASE !" is also
\ fragile - an uncaught error anywhere in between wipes a parked
\ stack value via QLOOP's top-level recovery. Unconditional restore
\ instead - see 08_defining_words.tests.fs for the full reasoning.

\ BUG FIX (cell size): the original Annex F text used 123456 here,
\ which needs a 32-bit cell - in a 16-bit cell it wraps to $E240
\ (negative as signed), so "9 <" is wrongly true on the very first
\ pass, >IN lands on the "IN" of ">IN" and BADWORD throws -13. The
\ standard itself later changed this test to 12345 for 16-bit
\ systems (forth-standard.org >IN page). Expected results below
\ follow from the same digit-stripping: 12345 2345 345 45 5.
\ BUG FIX (missing text): the second test originally ended
\ "14 >IN ! GCD calculation" - those two words are deliberately
\ skipped over by the ">IN +!" 34-character jump; without them the
\ jump overshoots the end of the line instead of landing on "->".
\ Both tests rely on >IN pointing at or beyond the end of the line
\ being treated as end-of-input (WORD/PARSE/PARSE-NAME fix).
\ Kept in the standard's own two-line layout, which deliberately
\ exercises >IN landing just past the end of the first line.
DECIMAL
T{ 12345 DEPTH OVER 9 < 35 AND + 3 + >IN !
-> 12345 2345 345 45 5 }T
T{ 14145 8115 ?DUP 0= 34 AND >IN +! TUCK MOD 14 >IN ! GCD calculation
-> 15 }T

HEX

\ F.6.1.0570  >NUMBER

CREATE GN-BUF 0 C,
: GN-STRING GN-BUF 1 ;
: GN-CONSUMED GN-BUF CHAR+ 0 ;
: GN' [CHAR] ' WORD CHAR+ C@ GN-BUF C! GN-STRING ;
T{ 0 0 GN' 0' >NUMBER -> 0 0 GN-CONSUMED }T
T{ 0 0 GN' 1' >NUMBER -> 1 0 GN-CONSUMED }T
T{ 1 0 GN' 1' >NUMBER -> BASE @ 1+ 0 GN-CONSUMED }T

\ FOLLOWING SHOULD FAIL TO CONVERT

\ BUG FIX: these three tests used to be glued onto the end of this
\ comment's own line - the same "comment swallows the rest of the
\ line" hazard found and fixed in 12_control_flow.tests.fs,
\ 23_comment_words.tests.fs, 08_defining_words.tests.fs, and
\ 19_string_words.tests.fs - so none of them ever ran. Split onto
\ their own line below.

T{ 0 0 GN' -' >NUMBER -> 0 0 GN-STRING }T
T{ 0 0 GN' +' >NUMBER -> 0 0 GN-STRING }T
T{ 0 0 GN' .' >NUMBER -> 0 0 GN-STRING }T

: >NUMBER-BASED BASE @ >R BASE ! >NUMBER R> BASE ! ;
T{ 0 0 GN' 2' 10 >NUMBER-BASED -> 2 0 GN-CONSUMED }T
T{ 0 0 GN' 2' 2 >NUMBER-BASED -> 0 0 GN-STRING }T
T{ 0 0 GN' F' 10 >NUMBER-BASED -> F 0 GN-CONSUMED }T
T{ 0 0 GN' G' 10 >NUMBER-BASED -> 0 0 GN-STRING }T
T{ 0 0 GN' G' MAX-BASE >NUMBER-BASED -> 10 0 GN-CONSUMED }T
T{ 0 0 GN' Z' MAX-BASE >NUMBER-BASED -> 23 0 GN-CONSUMED }T

: GN1 ( UD BASE -- UD' LEN )
BASE @ >R BASE !
<# #S #> 0 0 2SWAP >NUMBER SWAP DROP
R> BASE ! ;
T{ 0 0 2 GN1 -> 0 0 0 }T
T{ MAX-UINT 0 2 GN1 -> MAX-UINT 0 0 }T
T{ MAX-UINT DUP 2 GN1 -> MAX-UINT DUP 0 }T
T{ 0 0 MAX-BASE GN1 -> 0 0 0 }T
T{ MAX-UINT 0 MAX-BASE GN1 -> MAX-UINT 0 0 }T
T{ MAX-UINT DUP MAX-BASE GN1 -> MAX-UINT DUP 0 }T

\ F.6.1.0770  BL

T{ BL -> 20 }T

\ F.6.1.1345  ENVIRONMENT?

\ ERRATUM IN THE STANDARD'S OWN TEST: "DUP 0= XOR INVERT" turns ANY
\ single flag into 0 (flag XOR (flag=0) is always -1, and INVERT
\ makes that 0), so the published X:deferred test "-> <TRUE>" can
\ never pass on any system. A contributor note on forth-standard.org's
\ ENVIRONMENT? page says the same, and also that a conforming system
\ may answer false to every query. Replaced it with a valid check:
\ whatever ENVIRONMENT? answers for X:deferred, the result must be
\ exactly one well-formed flag (0 or -1, no extra cells, which the
\ harness depth check enforces). X:notfound below is unchanged.
T{ S" X:deferred" ENVIRONMENT? DUP 0= OVER TRUE = OR NIP -> <TRUE> }T
T{ S" X:notfound" ENVIRONMENT? DUP 0= XOR INVERT -> <FALSE> }T

\ F.6.1.1360  EVALUATE

: GE1 S" 123" ; IMMEDIATE
: GE2 S" 123 1+" ; IMMEDIATE
: GE3 S" : GE4 345 ;" ;
: GE5 EVALUATE ; IMMEDIATE
T{ GE1 EVALUATE -> 123 }T
T{ GE2 EVALUATE -> 124 }T
T{ GE3 EVALUATE -> }T
T{ GE4 -> 345 }T
T{ : GE6 GE1 GE5 ; -> }T
T{ GE6 -> 123 }T
T{ : GE7 GE2 GE5 ; -> }T
T{ GE7 -> 124 }T

\ F.6.1.2216  SOURCE

: GS1 S" SOURCE" 2DUP EVALUATE >R SWAP >R = R> R> = ;
T{ GS1 -> <TRUE> <TRUE> }T

: GS4 SOURCE >IN ! DROP ;   
T{ GS4 123 456 -> }T

\ Print this file's TEST SUMMARY and trim any stray stack cells.
TEST-END
\ ---- section-marker: undo everything above ----
M24
