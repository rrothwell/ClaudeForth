\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 10 (10_query_accept_key_emit)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0695  ACCEPT
CREATE ABUF 80 CHARS ALLOT
: ACCEPT-TEST
CR ." PLEASE TYPE UP TO 80 CHARACTERS:" CR
ABUF 80 ACCEPT
CR ." RECEIVED: " [CHAR] " EMIT
ABUF SWAP TYPE [CHAR] " EMIT CR
;
T{ ACCEPT-TEST -> }T

\ F.6.1.0990  CR
See F.6.1.1320 EMIT.

\ F.6.1.1320  EMIT
: OUTPUT-TEST
." YOU SHOULD SEE THE STANDARD GRAPHIC CHARACTERS:" CR
41 BL DO I EMIT LOOP CR
61 41 DO I EMIT LOOP CR
7F 61 DO I EMIT LOOP CR
." YOU SHOULD SEE 0-9 SEPARATED BY A SPACE:" CR
9 1+ 0 DO I . LOOP CR
." YOU SHOULD SEE 0-9 (WITH NO SPACES):" CR
[CHAR] 9 1+ [CHAR] 0 DO I 0 SPACES EMIT LOOP CR
." YOU SHOULD SEE A-G SEPARATED BY A SPACE:" CR
[CHAR] G 1+ [CHAR] A DO I EMIT SPACE LOOP CR
." YOU SHOULD SEE 0-5 SEPARATED BY TWO SPACES:" CR
5 1+ 0 DO I [CHAR] 0 + EMIT 2 SPACES LOOP CR
." YOU SHOULD SEE TWO SEPARATE LINES:" CR
S" LINE 1" TYPE CR S" LINE 2" TYPE CR
." YOU SHOULD SEE THE NUMBER RANGES OF SIGNED AND UNSIGNED NUMBERS:" CR
." SIGNED: " MIN-INT . MAX-INT . CR
." UNSIGNED: " 0 U. MAX-UINT U. CR
;
T{ OUTPUT-TEST -> }T

\ F.6.1.2220  SPACE
See F.6.1.1320 EMIT.

\ F.6.1.2230  SPACES
See F.6.1.1320 EMIT.

