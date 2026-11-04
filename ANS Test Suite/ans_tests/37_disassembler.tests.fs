\ ============================================================
\ ANS-style test suite - disassembler words DASM and DIS
\ (DISASM=1 builds only). DASM sends the text of one instruction
\ and returns the next address, so these tests check the length the
\ decoder gives each encoding, including prefix pages, indexed modes
\ and bytes that are not instructions (length 1). The text itself is
\ sent to the terminal while the tests run; the displayed lines are
\ the disassembly of each test sequence.
\ Requires ttester.fs then 00_test_prelude.fs to be loaded first,
\ in that order.
\ ============================================================
MARKER M37
TEST-BEGIN
HEX

CREATE BUF 8 ALLOT
\ SEQ ( c1 .. cn n -- )  store the bytes at BUF, c1 first.
: SEQ BEGIN DUP WHILE 1- TUCK BUF + C! REPEAT DROP ;
\ LEN ( -- n )  disassemble BUF and return its length.
: LEN BUF DUP DASM SWAP - ;

T{ 12 1 SEQ LEN -> 1 }T
T{ 4F 1 SEQ LEN -> 1 }T
T{ 86 A5 2 SEQ LEN -> 2 }T
T{ C3 12 34 3 SEQ LEN -> 3 }T
T{ 10 83 12 34 4 SEQ LEN -> 4 }T
T{ 11 8C 12 34 4 SEQ LEN -> 4 }T
T{ 8E 12 34 3 SEQ LEN -> 3 }T
T{ CE 12 34 3 SEQ LEN -> 3 }T
T{ 10 CE 12 34 4 SEQ LEN -> 4 }T
T{ 96 12 2 SEQ LEN -> 2 }T
T{ B6 12 34 3 SEQ LEN -> 3 }T
T{ 7E 12 34 3 SEQ LEN -> 3 }T
T{ 7F 12 34 3 SEQ LEN -> 3 }T
T{ 0F 12 2 SEQ LEN -> 2 }T
T{ 20 05 2 SEQ LEN -> 2 }T
T{ 10 27 01 00 4 SEQ LEN -> 4 }T
T{ 16 01 00 3 SEQ LEN -> 3 }T
T{ 17 01 00 3 SEQ LEN -> 3 }T
T{ 8D 05 2 SEQ LEN -> 2 }T
T{ 1F 01 2 SEQ LEN -> 2 }T
T{ 1E 89 2 SEQ LEN -> 2 }T
T{ 34 FF 2 SEQ LEN -> 2 }T
T{ 36 01 2 SEQ LEN -> 2 }T
T{ 3C 01 2 SEQ LEN -> 2 }T
T{ 1A 01 2 SEQ LEN -> 2 }T
T{ 1C EF 2 SEQ LEN -> 2 }T
T{ A6 84 2 SEQ LEN -> 2 }T
T{ A6 0A 2 SEQ LEN -> 2 }T
T{ A6 88 10 3 SEQ LEN -> 3 }T
T{ A6 89 12 34 4 SEQ LEN -> 4 }T
T{ A6 8C 10 3 SEQ LEN -> 3 }T
T{ A6 8D 12 34 4 SEQ LEN -> 4 }T
T{ A6 9F 12 34 4 SEQ LEN -> 4 }T
T{ A6 9D 12 34 4 SEQ LEN -> 4 }T
T{ 10 AE 89 12 34 5 SEQ LEN -> 5 }T
T{ 30 8B 2 SEQ LEN -> 2 }T
T{ A6 85 2 SEQ LEN -> 2 }T
T{ A6 80 2 SEQ LEN -> 2 }T
T{ A6 81 2 SEQ LEN -> 2 }T
T{ A6 82 2 SEQ LEN -> 2 }T
T{ A6 83 2 SEQ LEN -> 2 }T
T{ 3F 1 SEQ LEN -> 1 }T
T{ 10 3F 2 SEQ LEN -> 2 }T
T{ 11 3F 2 SEQ LEN -> 2 }T
T{ 39 1 SEQ LEN -> 1 }T
T{ 3B 1 SEQ LEN -> 1 }T
T{ 3D 1 SEQ LEN -> 1 }T
T{ 01 1 SEQ LEN -> 1 }T
T{ 02 1 SEQ LEN -> 1 }T
T{ 10 10 2 SEQ LEN -> 1 }T
T{ 10 12 2 SEQ LEN -> 1 }T
T{ 11 21 2 SEQ LEN -> 1 }T
T{ 87 12 2 SEQ LEN -> 1 }T
T{ 8F 12 34 3 SEQ LEN -> 1 }T
T{ CD 12 34 3 SEQ LEN -> 1 }T
T{ 3E 1 SEQ LEN -> 1 }T
T{ 38 1 SEQ LEN -> 1 }T
T{ 1B 1 SEQ LEN -> 1 }T
T{ A6 87 2 SEQ LEN -> 1 }T
T{ A6 90 2 SEQ LEN -> 1 }T
T{ 1E 6F 2 SEQ LEN -> 1 }T
T{ 4E 1 SEQ LEN -> 1 }T
T{ 5E 1 SEQ LEN -> 1 }T
T{ 0B 1 SEQ LEN -> 1 }T

\ DIS lists whole instructions in a range.
: DEMO BUF 3 DIS ;
86 A5 2 SEQ 12 BUF 2 + C! DEMO

TEST-END
M37
