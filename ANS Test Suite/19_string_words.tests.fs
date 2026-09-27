\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 19 (19_string_words)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0895  CHAR
T{ CHAR X -> 58 }T   T{ CHAR HELLO -> 48 }T

\ F.6.1.0980  COUNT
T{ GT1STRING COUNT -> GT1STRING CHAR+ 3 }T

\ F.6.1.2310  TYPE
See F.6.1.1320 EMIT.

\ F.6.1.2450  WORD
: GS3 WORD COUNT SWAP C@ ;   T{ BL GS3 HELLO -> 5 CHAR H }T   T{ CHAR " GS3 GOODBYE" -> 7 CHAR G }T   T{ BL GS3
DROP -> 0 }T

\ F.6.1.2520  [CHAR]
T{ : GC1 [CHAR] X ; -> }T   T{ : GC2 [CHAR] HELLO ; -> }T   T{ GC1 -> 58 }T   T{ GC2 -> 48 }T

\ F.6.2.2020  PARSE-NAME
T{ PARSE-NAME abcd S" abcd" S= -> <TRUE> }T   T{ PARSE-NAME abcde S" abcde" S= -> <TRUE> }T
\ test empty parse area   T{ PARSE-NAME
NIP -> 0 }T   T{ PARSE-NAME
NIP -> 0 }T
T{ : parse-name-test ( "name1" "name2" -- n )
PARSE-NAME PARSE-NAME S= ; -> }T
T{ parse-name-test abcd abcd -> <TRUE> }T   T{ parse-name-test abcde abcdf -> <FALSE> }T   T{ parse-name-test abcdf abcde -> <FALSE> }T   T{ parse-name-test abcde abcde
-> <TRUE> }T

