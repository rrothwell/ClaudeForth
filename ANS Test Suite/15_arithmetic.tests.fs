\ ============================================================
\ ANS test suite - words implemented in forth6809.asm's
\ section 15 (15_arithmetic)
\ Requires ttester.fs then 00_test_prelude.fs to be loaded
\ first, in that order (the prelude itself uses T{/->/}T, so
\ ttester.fs must come first). Extracted from the ANS Forth
\ Standard, Annex F
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own copyright notice.
\ ============================================================

\ F.6.1.0090  *
T{ 0 0 * -> 0 }T   T{ 0 1 * -> 0 }T   T{ 1 0 * -> 0 }T   T{ 1 2 * -> 2 }T   T{ 2 1 * -> 2 }T   T{ 3 3 * -> 9 }T   T{ -3 3 * -> -9 }T   T{ 3 -3 * -> -9 }T   T{ -3 -3 * -> 9 }T
T{ MID-UINT+1 1 RSHIFT 2 * -> MID-UINT+1 }T   T{ MID-UINT+1 2 RSHIFT 4 * -> MID-UINT+1 }T   T{ MID-UINT+1 1 RSHIFT MID-UINT+1 OR 2 * -> MID-UINT+1 }T

\ F.6.1.0100  */
IFFLOORED : T*/ T*/MOD SWAP DROP ;
IFSYM : T*/ T*/MOD SWAP DROP ;
T{ 0 2 1 */ -> 0 2 1 T*/ }T   T{ 1 2 1 */ -> 1 2 1 T*/ }T   T{ 2 2 1 */ -> 2 2 1 T*/ }T   T{ -1 2 1 */ -> -1 2 1 T*/ }T   T{ -2 2 1 */ -> -2 2 1 T*/ }T   T{ 0 2 -1 */ -> 0 2 -1 T*/ }T   T{ 1 2 -1 */ -> 1 2 -1 T*/ }T   T{ 2 2 -1 */ -> 2 2 -1 T*/ }T   T{ -1 2 -1 */ -> -1 2 -1 T*/ }T   T{ -2 2 -1 */ -> -2 2 -1 T*/ }T   T{ 2 2 2 */ -> 2 2 2 T*/ }T   T{ -1 2 -1 */ -> -1 2 -1 T*/ }T   T{ -2 2 -2 */ -> -2 2 -2 T*/ }T   T{ 7 2 3 */ -> 7 2 3 T*/ }T   T{ 7 2 -3 */ -> 7 2 -3 T*/ }T   T{ -7 2 3 */ -> -7 2 3 T*/ }T   T{ -7 2 -3 */ -> -7 2 -3 T*/ }T   T{ MAX-INT 2 MAX-INT */ -> MAX-INT 2 MAX-INT T*/ }T   T{ MIN-INT 2 MIN-INT */ -> MIN-INT 2 MIN-INT T*/ }T

\ F.6.1.0110  */MOD
IFFLOORED : T*/MOD >R M* R> FM/MOD ;
IFSYM : T*/MOD >R M* R> SM/REM ;
T{ 0 2 1 */MOD -> 0 2 1 T*/MOD }T   T{ 1 2 1 */MOD -> 1 2 1 T*/MOD }T   T{ 2 2 1 */MOD -> 2 2 1 T*/MOD }T   T{ -1 2 1 */MOD -> -1 2 1 T*/MOD }T   T{ -2 2 1 */MOD -> -2 2 1 T*/MOD }T   T{ 0 2 -1 */MOD -> 0 2 -1 T*/MOD }T   T{ 1 2 -1 */MOD -> 1 2 -1 T*/MOD }T   T{ 2 2 -1 */MOD -> 2 2 -1 T*/MOD }T   T{ -1 2 -1 */MOD -> -1 2 -1 T*/MOD }T   T{ -2 2 -1 */MOD -> -2 2 -1 T*/MOD }T   T{ 2 2 2 */MOD -> 2 2 2 T*/MOD }T   T{ -1 2 -1 */MOD -> -1 2 -1 T*/MOD }T   T{ -2 2 -2 */MOD -> -2 2 -2 T*/MOD }T   T{ 7 2 3 */MOD -> 7 2 3 T*/MOD }T   T{ 7 2 -3 */MOD -> 7 2 -3 T*/MOD }T   T{ -7 2 3 */MOD -> -7 2 3 T*/MOD }T   T{ -7 2 -3 */MOD -> -7 2 -3 T*/MOD }T   T{ MAX-INT 2 MAX-INT */MOD -> MAX-INT 2 MAX-INT T*/MOD }T   T{ MIN-INT 2 MIN-INT */MOD -> MIN-INT 2 MIN-INT T*/MOD }T

\ F.6.1.0120  +
T{ 0 5 + -> 5 }T   T{ 5 0 + -> 5 }T   T{ 0 -5 + -> -5 }T   T{ -5 0 + -> -5 }T   T{ 1 2 + -> 3 }T   T{ 1 -2 + -> -1 }T   T{ -1 2 + -> 1 }T   T{ -1 -2 + -> -3 }T   T{ -1 1 + -> 0 }T   T{ MID-UINT 1 + -> MID-UINT+1 }T

\ F.6.1.0160  -
T{ 0 5 - -> -5 }T   T{ 5 0 - -> 5 }T   T{ 0 -5 - -> 5 }T   T{ -5 0 - -> -5 }T   T{ 1 2 - -> -1 }T   T{ 1 -2 - -> 3 }T   T{ -1 2 - -> -3 }T   T{ -1 -2 - -> 1 }T   T{ 0 1 - -> -1 }T   T{ MID-UINT+1 1 - -> MID-UINT }T

\ F.6.1.0230  /
IFFLOORED : T/ T/MOD SWAP DROP ;
IFSYM : T/ T/MOD SWAP DROP ;
T{ 0 1 / -> 0 1 T/ }T   T{ 1 1 / -> 1 1 T/ }T   T{ 2 1 / -> 2 1 T/ }T   T{ -1 1 / -> -1 1 T/ }T   T{ -2 1 / -> -2 1 T/ }T   T{ 0 -1 / -> 0 -1 T/ }T   T{ 1 -1 / -> 1 -1 T/ }T   T{ 2 -1 / -> 2 -1 T/ }T   T{ -1 -1 / -> -1 -1 T/ }T   T{ -2 -1 / -> -2 -1 T/ }T   T{ 2 2 / -> 2 2 T/ }T   T{ -1 -1 / -> -1 -1 T/ }T   T{ -2 -2 / -> -2 -2 T/ }T   T{ 7 3 / -> 7 3 T/ }T   T{ 7 -3 / -> 7 -3 T/ }T   T{ -7 3 / -> -7 3 T/ }T   T{ -7 -3 / -> -7 -3 T/ }T   T{ MAX-INT 1 / -> MAX-INT 1 T/ }T   T{ MIN-INT 1 / -> MIN-INT 1 T/ }T   T{ MAX-INT MAX-INT / -> MAX-INT MAX-INT T/ }T   T{ MIN-INT MIN-INT / -> MIN-INT MIN-INT T/ }T

\ F.6.1.0240  /MOD
IFFLOORED : T/MOD >R S>D R> FM/MOD ;
IFSYM : T/MOD >R S>D R> SM/REM ;
T{ 0 1 /MOD -> 0 1 T/MOD }T   T{ 1 1 /MOD -> 1 1 T/MOD }T   T{ 2 1 /MOD -> 2 1 T/MOD }T   T{ -1 1 /MOD -> -1 1 T/MOD }T   T{ -2 1 /MOD -> -2 1 T/MOD }T   T{ 0 -1 /MOD -> 0 -1 T/MOD }T   T{ 1 -1 /MOD -> 1 -1 T/MOD }T   T{ 2 -1 /MOD -> 2 -1 T/MOD }T   T{ -1 -1 /MOD -> -1 -1 T/MOD }T   T{ -2 -1 /MOD -> -2 -1 T/MOD }T   T{ 2 2 /MOD -> 2 2 T/MOD }T   T{ -1 -1 /MOD -> -1 -1 T/MOD }T   T{ -2 -2 /MOD -> -2 -2 T/MOD }T   T{ 7 3 /MOD -> 7 3 T/MOD }T   T{ 7 -3 /MOD -> 7 -3 T/MOD }T   T{ -7 3 /MOD -> -7 3 T/MOD }T   T{ -7 -3 /MOD -> -7 -3 T/MOD }T   T{ MAX-INT 1 /MOD -> MAX-INT 1 T/MOD }T   T{ MIN-INT 1 /MOD -> MIN-INT 1 T/MOD }T   T{ MAX-INT MAX-INT /MOD -> MAX-INT MAX-INT T/MOD }T   T{ MIN-INT MIN-INT /MOD -> MIN-INT MIN-INT T/MOD }T

\ F.6.1.0290  1+
T{ 0 1+ -> 1 }T   T{ -1 1+ -> 0 }T   T{ 1 1+ -> 2 }T   T{ MID-UINT 1+ -> MID-UINT+1 }T

\ F.6.1.0300  1-
T{ 2 1- -> 1 }T   T{ 1 1- -> 0 }T   T{ 0 1- -> -1 }T   T{ MID-UINT+1 1- -> MID-UINT }T

\ F.6.1.0320  2*
T{ 0S 2* -> 0S }T   T{ 1 2* -> 2 }T   T{ 4000 2* -> 8000 }T   T{ 1S 2* 1 XOR -> 1S }T   T{ MSB 2* -> 0S }T

\ F.6.1.0330  2/
T{ 0S 2/ -> 0S }T   T{ 1 2/ -> 0 }T   T{ 4000 2/ -> 2000 }T   T{ 1S 2/ -> 1S }T \ MSB PROPOGATED   T{ 1S 1 XOR 2/ -> 1S }T   T{ MSB 2/ MSB AND -> MSB }T

\ F.6.1.0690  ABS
T{ 0 ABS -> 0 }T   T{ 1 ABS -> 1 }T   T{ -1 ABS -> 1 }T   T{ MIN-INT ABS -> MID-UINT+1 }T

\ F.6.1.1561  FM/MOD
T{ 0 S>D 1 FM/MOD -> 0 0 }T   T{ 1 S>D 1 FM/MOD -> 0 1 }T   T{ 2 S>D 1 FM/MOD -> 0 2 }T   T{ -1 S>D 1 FM/MOD -> 0 -1 }T   T{ -2 S>D 1 FM/MOD -> 0 -2 }T   T{ 0 S>D -1 FM/MOD -> 0 0 }T   T{ 1 S>D -1 FM/MOD -> 0 -1 }T   T{ 2 S>D -1 FM/MOD -> 0 -2 }T   T{ -1 S>D -1 FM/MOD -> 0 1 }T   T{ -2 S>D -1 FM/MOD -> 0 2 }T   T{ 2 S>D 2 FM/MOD -> 0 1 }T   T{ -1 S>D -1 FM/MOD -> 0 1 }T   T{ -2 S>D -2 FM/MOD -> 0 1 }T   T{ 7 S>D 3 FM/MOD -> 1 2 }T   T{ 7 S>D -3 FM/MOD -> -2 -3 }T   T{ -7 S>D 3 FM/MOD -> 2 -3 }T   T{ -7 S>D -3 FM/MOD -> -1 2 }T   T{ MAX-INT S>D 1 FM/MOD -> 0 MAX-INT }T   T{ MIN-INT S>D 1 FM/MOD -> 0 MIN-INT }T   T{ MAX-INT S>D MAX-INT FM/MOD -> 0 1 }T   T{ MIN-INT S>D MIN-INT FM/MOD -> 0 1 }T   T{ 1S 1 4 FM/MOD -> 3 MAX-INT }T   T{ 1 MIN-INT M* 1 FM/MOD -> 0 MIN-INT }T   T{ 1 MIN-INT M* MIN-INT FM/MOD -> 0 1 }T   T{ 2 MIN-INT M* 2 FM/MOD -> 0 MIN-INT }T   T{ 2 MIN-INT M* MIN-INT FM/MOD -> 0 2 }T   T{ 1 MAX-INT M* 1 FM/MOD -> 0 MAX-INT }T   T{ 1 MAX-INT M* MAX-INT FM/MOD -> 0 1 }T   T{ 2 MAX-INT M* 2 FM/MOD -> 0 MAX-INT }T   T{ 2 MAX-INT M* MAX-INT FM/MOD -> 0 2 }T   T{ MIN-INT MIN-INT M* MIN-INT FM/MOD -> 0 MIN-INT }T   T{ MIN-INT MAX-INT M* MIN-INT FM/MOD -> 0 MAX-INT }T   T{ MIN-INT MAX-INT M* MAX-INT FM/MOD -> 0 MIN-INT }T   T{ MAX-INT MAX-INT M* MAX-INT FM/MOD -> 0 MAX-INT }T

\ F.6.1.1810  M*
T{ 0 0 M* -> 0 S>D }T   T{ 0 1 M* -> 0 S>D }T   T{ 1 0 M* -> 0 S>D }T   T{ 1 2 M* -> 2 S>D }T   T{ 2 1 M* -> 2 S>D }T   T{ 3 3 M* -> 9 S>D }T   T{ -3 3 M* -> -9 S>D }T   T{ 3 -3 M* -> -9 S>D }T   T{ -3 -3 M* -> 9 S>D }T   T{ 0 MIN-INT M* -> 0 S>D }T   T{ 1 MIN-INT M* -> MIN-INT S>D }T   T{ 2 MIN-INT M* -> 0 1S }T   T{ 0 MAX-INT M* -> 0 S>D }T   T{ 1 MAX-INT M* -> MAX-INT S>D }T   T{ 2 MAX-INT M* -> MAX-INT 1 LSHIFT 0 }T   T{ MIN-INT MIN-INT M* -> 0 MSB 1 RSHIFT }T   T{ MAX-INT MIN-INT M* -> MSB MSB 2/ }T   T{ MAX-INT MAX-INT M* -> 1 MSB 2/ INVERT }T

\ F.6.1.1870  MAX
T{ 0 1 MAX -> 1 }T   T{ 1 2 MAX -> 2 }T   T{ -1 0 MAX -> 0 }T   T{ -1 1 MAX -> 1 }T   T{ MIN-INT 0 MAX -> 0 }T   T{ MIN-INT MAX-INT MAX -> MAX-INT }T   T{ 0 MAX-INT MAX -> MAX-INT }T   T{ 0 0 MAX -> 0 }T   T{ 1 1 MAX -> 1 }T   T{ 1 0 MAX -> 1 }T   T{ 2 1 MAX -> 2 }T   T{ 0 -1 MAX -> 0 }T   T{ 1 -1 MAX -> 1 }T   T{ 0 MIN-INT MAX -> 0 }T   T{ MAX-INT MIN-INT MAX -> MAX-INT }T   T{ MAX-INT 0 MAX -> MAX-INT }T

\ F.6.1.1880  MIN
T{ 0 1 MIN -> 0 }T   T{ 1 2 MIN -> 1 }T   T{ -1 0 MIN -> -1 }T   T{ -1 1 MIN -> -1 }T   T{ MIN-INT 0 MIN -> MIN-INT }T   T{ MIN-INT MAX-INT MIN -> MIN-INT }T   T{ 0 MAX-INT MIN -> 0 }T   T{ 0 0 MIN -> 0 }T   T{ 1 1 MIN -> 1 }T   T{ 1 0 MIN -> 0 }T   T{ 2 1 MIN -> 1 }T   T{ 0 -1 MIN -> -1 }T   T{ 1 -1 MIN -> -1 }T   T{ 0 MIN-INT MIN -> MIN-INT }T   T{ MAX-INT MIN-INT MIN -> MIN-INT }T   T{ MAX-INT 0 MIN -> 0 }T

\ F.6.1.1890  MOD
IFFLOORED : TMOD T/MOD DROP ;
IFSYM : TMOD T/MOD DROP ;
T{ 0 1 MOD -> 0 1 TMOD }T   T{ 1 1 MOD -> 1 1 TMOD }T   T{ 2 1 MOD -> 2 1 TMOD }T   T{ -1 1 MOD -> -1 1 TMOD }T   T{ -2 1 MOD -> -2 1 TMOD }T   T{ 0 -1 MOD -> 0 -1 TMOD }T   T{ 1 -1 MOD -> 1 -1 TMOD }T   T{ 2 -1 MOD -> 2 -1 TMOD }T   T{ -1 -1 MOD -> -1 -1 TMOD }T   T{ -2 -1 MOD -> -2 -1 TMOD }T   T{ 2 2 MOD -> 2 2 TMOD }T   T{ -1 -1 MOD -> -1 -1 TMOD }T   T{ -2 -2 MOD -> -2 -2 TMOD }T   T{ 7 3 MOD -> 7 3 TMOD }T   T{ 7 -3 MOD -> 7 -3 TMOD }T   T{ -7 3 MOD -> -7 3 TMOD }T   T{ -7 -3 MOD -> -7 -3 TMOD }T   T{ MAX-INT 1 MOD -> MAX-INT 1 TMOD }T   T{ MIN-INT 1 MOD -> MIN-INT 1 TMOD }T   T{ MAX-INT MAX-INT MOD -> MAX-INT MAX-INT TMOD }T   T{ MIN-INT MIN-INT MOD -> MIN-INT MIN-INT TMOD }T

\ F.6.1.1910  NEGATE
T{ 0 NEGATE -> 0 }T   T{ 1 NEGATE -> -1 }T   T{ -1 NEGATE -> 1 }T   T{ 2 NEGATE -> -2 }T   T{ -2 NEGATE -> 2 }T

\ F.6.1.2170  S>D
T{ 0 S>D -> 0 0 }T   T{ 1 S>D -> 1 0 }T   T{ 2 S>D -> 2 0 }T   T{ -1 S>D -> -1 -1 }T   T{ -2 S>D -> -2 -1 }T   T{ MIN-INT S>D -> MIN-INT -1 }T   T{ MAX-INT S>D -> MAX-INT 0 }T

\ F.6.1.2214  SM/REM
T{ 0 S>D 1 SM/REM -> 0 0 }T   T{ 1 S>D 1 SM/REM -> 0 1 }T   T{ 2 S>D 1 SM/REM -> 0 2 }T   T{ -1 S>D 1 SM/REM -> 0 -1 }T   T{ -2 S>D 1 SM/REM -> 0 -2 }T   T{ 0 S>D -1 SM/REM -> 0 0 }T   T{ 1 S>D -1 SM/REM -> 0 -1 }T   T{ 2 S>D -1 SM/REM -> 0 -2 }T   T{ -1 S>D -1 SM/REM -> 0 1 }T   T{ -2 S>D -1 SM/REM -> 0 2 }T   T{ 2 S>D 2 SM/REM -> 0 1 }T   T{ -1 S>D -1 SM/REM -> 0 1 }T   T{ -2 S>D -2 SM/REM -> 0 1 }T   T{ 7 S>D 3 SM/REM -> 1 2 }T   T{ 7 S>D -3 SM/REM -> 1 -2 }T   T{ -7 S>D 3 SM/REM -> 1 -2 }T   T{ -7 S>D -3 SM/REM -> -1 2 }T   T{ MAX-INT S>D 1 SM/REM -> 0 MAX-INT }T   T{ MIN-INT S>D 1 SM/REM -> 0 MIN-INT }T   T{ MAX-INT S>D MAX-INT SM/REM -> 0 1 }T   T{ MIN-INT S>D MIN-INT SM/REM -> 0 1 }T   T{ 1S 1 4 SM/REM -> 3 MAX-INT }T   T{ 2 MIN-INT M* 2 SM/REM -> 0 MIN-INT }T   T{ 2 MIN-INT M* MIN-INT SM/REM -> 0 2 }T   T{ 2 MAX-INT M* 2 SM/REM -> 0 MAX-INT }T   T{ 2 MAX-INT M* MAX-INT SM/REM -> 0 2 }T   T{ MIN-INT MIN-INT M* MIN-INT SM/REM -> 0 MIN-INT }T   T{ MIN-INT MAX-INT M* MIN-INT SM/REM -> 0 MAX-INT }T   T{ MIN-INT MAX-INT M* MAX-INT SM/REM -> 0 MIN-INT }T   T{ MAX-INT MAX-INT M* MAX-INT SM/REM -> 0 MAX-INT }T

\ F.6.1.2360  UM*
T{ 0 0 UM* -> 0 0 }T   T{ 0 1 UM* -> 0 0 }T   T{ 1 0 UM* -> 0 0 }T   T{ 1 2 UM* -> 2 0 }T   T{ 2 1 UM* -> 2 0 }T   T{ 3 3 UM* -> 9 0 }T
T{ MID-UINT+1 1 RSHIFT 2 UM* -> MID-UINT+1 0 }T   T{ MID-UINT+1 2 UM* -> 0 1 }T   T{ MID-UINT+1 4 UM* -> 0 2 }T   T{ 1S 2 UM* -> 1S 1 LSHIFT 1 }T   T{ MAX-UINT MAX-UINT UM* -> 1 1 INVERT }T

\ F.6.1.2370  UM/MOD
T{ 0 0 1 UM/MOD -> 0 0 }T   T{ 1 0 1 UM/MOD -> 0 1 }T   T{ 1 0 2 UM/MOD -> 1 0 }T   T{ 3 0 2 UM/MOD -> 1 1 }T   T{ MAX-UINT 2 UM* 2 UM/MOD -> 0 MAX-UINT }T   T{ MAX-UINT 2 UM* MAX-UINT UM/MOD -> 0 2 }T   T{ MAX-UINT MAX-UINT UM* MAX-UINT UM/MOD -> 0 MAX-UINT }T

