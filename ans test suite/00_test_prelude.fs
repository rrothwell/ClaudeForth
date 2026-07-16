\ ============================================================
\ 00_test_prelude.fs
\ Shared prerequisites for every section's ANS test file below.
\ Load ttester.fs FIRST (this file uses T{/->/}T itself, in the
\ BITSSET? and MSB checks below, so it cannot load before the
\ harness does), then this file, then any section file, in the
\ order given by each section file's own header comment.
\ Extracted from the ANS Forth Standard, Annex F: Test Suite
\ (https://forth-standard.org/standard/testsuite), which is
\ explicitly redistributable per its own header:
\   "(C) 1995 JOHNS HOPKINS UNIVERSITY / APPLIED PHYSICS LABORATORY
\    MAY BE DISTRIBUTED FREELY AS LONG AS THIS COPYRIGHT NOTICE
\    REMAINS."
\ ============================================================

HEX

\ ---- F.3.1 Basic Assumptions ----
T{ -> }T                        \ Start with a clean slate
T{ : BITSSET? IF 0 0 ELSE 0 THEN ; -> }T
T{ 0 BITSSET? -> 0 }T
T{ 1 BITSSET? -> 0 0 }T
T{ -1 BITSSET? -> 0 0 }T

\ ---- F.3.2 Booleans (needs AND, INVERT tested first - section 16) ----
\ 0S and 1S are actually defined via CONSTANT in F.3.5 below, but the
\ narrative places their first use here; both groups are included in
\ this shared prelude since nearly every later section depends on them.

\ ---- F.3.3 Shifts ----
1S 1 RSHIFT INVERT CONSTANT MSB
T{ MSB BITSSET? -> 0 0 }T

\ ---- F.3.5 Comparisons - upper/lower bound constants ----
0 INVERT CONSTANT MAX-UINT
0 INVERT 1 RSHIFT CONSTANT MAX-INT
0 INVERT 1 RSHIFT INVERT CONSTANT MIN-INT
0 INVERT 1 RSHIFT CONSTANT MID-UINT
0 INVERT 1 RSHIFT INVERT CONSTANT MID-UINT+1

0S CONSTANT <FALSE>
1S CONSTANT <TRUE>

\ ---- F.3.10 Division - floored vs symmetric conditional compilation ----
: IFFLOORED [ -3 2 / -2 = INVERT ] LITERAL IF POSTPONE \ THEN ;
: IFSYM [ -3 2 / -1 = INVERT ] LITERAL IF POSTPONE \ THEN ;

\ ---- F.3.19 Number Patterns - string compare (String word set assumed absent) ----
: S= ( ADDR1 C1 ADDR2 C2 -- T/F ) \ Compare two strings.
>R SWAP R@ = IF \ Make sure strings have same length
R> ?DUP IF \ If non-empty strings
0 DO
OVER C@ OVER C@ - IF 2DROP <FALSE> UNLOOP EXIT THEN
SWAP CHAR+ SWAP CHAR+
LOOP
THEN
2DROP <TRUE> \ If we get here, strings match
ELSE
R> DROP 2DROP <FALSE> \ Lengths mismatch
THEN ;

24 CONSTANT MAX-BASE \ BASE 2 ... 36
: COUNT-BITS
0 0 INVERT BEGIN DUP WHILE >R 1+ R> 2* REPEAT DROP ;
COUNT-BITS 2* CONSTANT #BITS-UD \ NUMBER OF BITS IN UD

\ ---- F.3.20 Memory Movement - shared buffers (FILL must run before MOVE) ----
CREATE FBUF 00 C, 00 C, 00 C,
CREATE SBUF 12 C, 34 C, 56 C,
: SEEBUF FBUF C@ FBUF CHAR+ C@ FBUF CHAR+ CHAR+ C@ ;

DECIMAL
