# Optional word sets (6j, 6k) and the disassembler (6l)

## 1. What stage 6j adds

Two assembly-time switches, set like `SERIALPOLL` (default 1, so the
default build is unchanged: same size, same words):

| Switch | Removes when 0 |
| --- | --- |
| `STRINGSET` | `/STRING`, `-TRAILING`, `SEARCH`, `BLANK`, `SLITERAL`, and the **headers** of `CMOVE`, `CMOVE>`, `COMPARE` |
| `STRINGEXT` | `UNESCAPE`, `REPLACES`, `CLR-REPLACES`, `SUBSTITUTE` (code and headers) |

Build with, for example, `--define=STRINGSET=0 --define=STRINGEXT=0`.

Layout: the headers are one contiguous run between `>NUMBER` and `S"`,
and the code is one contiguous run in section 19. Each switch wraps its
run in `IFNE`/`ENDC`. The link of the header after a removed run is set
by `H_STRLINK1` and `H_STRLINK2` (`EQU` chosen by the switch), so the
dictionary chain stays intact in all four combinations (checked by
walking the chain: 262 headers on, 250 with both off).

## 2. Dependencies found (the "assuming nothing depends on them" check)

Something did depend on three of them, so they are not fully removable:

- `CMOVE` and `CMOVE>` code is called by `MOVE` (a Core word). Code kept
  always; only the headers are optional.
- `COMPARE` code is called twice by `ENVIRONMENT?`. Code kept always; only
  the header is optional.
- `SNAME` (xt to name over all wordlists) sat in the string-extension run
  but is not a string word and nothing string-related uses it. It is now
  always assembled, ahead of the optional runs. The decompiler needs it.

`BLANK` and `SLITERAL` were in other sections (Memory, Compiling). Their
code and headers moved into the string runs. Nothing else calls them.
Side effect: `WORDS` lists those four words in the string group instead of
their old places. The shadow file needs no change (no comment moved or
renamed).

## 3. ROM recovered (measured, either serial build)

| Setting | Headers | Code | Total saved |
| --- | --- | --- | --- |
| `STRINGEXT=0` | 58 | 583 | **641** |
| `STRINGSET=0` | 93 | 169 | **262** |
| both 0 | 151 | 752 | **903** |

`BASEDICT` and `BASECODE` are still fixed `EQU`s, so the saved bytes show
up as a gap: below `BASECODE` (the dictionary ends early) and above
`BASECODEEND` (more padding before `INITCODE`). To use them for something
else, lower both constants by the saving.

The `SUBPOOL` RAM ($0200-$023F, 64 bytes) is only used by `REPLACES`.
It could also be reclaimed when `STRINGEXT=0` (not done; RAM is not tight).

## 4. Cautions

- `UNITTESTS=1` stops with an `ERROR` unless both string switches are 1.
  The check is an `ERROR` directive and an `IFEQ A*B`; I could only run the
  default path in my assembler, so please confirm lwasm accepts them.
- `ENVIRONMENT?` (stage 6k): `STRING` and `STRING-EXT` entries exist only
  when their switch is on, so a missing feature answers false. Cost 28
  bytes when both are on.
- ANS test file 27 is split (done): 27 is the String word set, 36 is the
  String extension. Each uses colon definitions for `S"`, because
  interpret-mode `S"` shares one buffer.

## 5. Verification of 6j and 6k

- All four switch combinations assemble in both serial builds; 262 headers
  with both on, 250 with both off.
- All 19 unit-test groups pass (group 0 `TSTKEYQ` fails exactly as on 6i
  in my emulator, which has no pending key).
- ANS 27: 50 run, 0 failed. ANS 36: 14 run, 0 failed (also with
  `STRINGSET=0`).

## 6. The disassembler (stage 6l)

### Words (switch `DISASM`, default 1; build with `--define=DISASM=0` to drop)

| Word | Stack | What it does |
| --- | --- | --- |
| `DASM` | `( addr -- addr' )` | Send one instruction as text; return the address of the next one. |
| `DIS` | `( addr u -- )` | List every instruction that starts in `addr` .. `addr+u-1`: address, bytes, text, one per line. |

Output is hexadecimal only, lwasm style:

    8000 86 A5           LDA #$A5
    8002 96 7B           LDA <$7B
    8004 B6 A5 A5        LDA $A5A5
    8007 A6 0A           LDA $0A,X
    8009 A6 F6           LDA [A,S]
    8013 A6 8C 1D        LDA $8033,PCR
    8024 8D 10           BSR $8036
    801E 34 76           PSHS A,B,X,Y,U
    8043 AD 9F 12 34     JSR [$1234]
    8070 A8              FCB $A8

- Immediate `#$xx`; direct `<$xx`; extended `$xxxx`, or `>$00xx` when the
  high byte is zero so that it stays extended.
- Indexed: `$0A,X`, `-$0A,X`, `,X`, `A,X`, `B,X`, `D,X`, `,X+`, `,X++`,
  `,-X`, `,--X`, `[...]` for indirect, `[$xxxx]` for extended indirect.
  An 8-bit offset that would fit in 5 bits is shown as `<$05,X`, and a
  16-bit offset that would fit in 8 bits as `>$0005,X`, so lwasm builds
  the same bytes.
- PC-relative operands and all branches show the absolute target:
  `$8033,PCR`, `BRA $8026`. A 16-bit PC-relative offset that would fit in
  8 bits is shown as `>$xxxx,PCR`.
- `PSHS`/`PULS`/`PSHU`/`PULU` lists in the order CC A B DP X Y U/S PC. Bit
  6 shows `U` for the S-stack ops and `S` for the U-stack ops. An empty list
  shows `#$00`.
- A byte that is not an instruction shows as `FCB $xx` and is one byte long.
  That covers unused opcodes, a prefix followed by something that has no
  prefixed form, a second prefix, undefined indexed postbytes (modes 7, A,
  E, indirect `,R+` and `,-R`, mode F without indirect) and `TFR`/`EXG`
  register codes 6, 7, C-F.
- `LSL`/`LSLA`/`LSLB` show as `ASL`/`ASLA`/`ASLB` (same opcode).

### Known limits

- Indexed postbyte bits that the CPU ignores (register bits for the
  PC-relative and extended-indirect forms) are not shown, so such a
  non-canonical encoding disassembles to the canonical text. 1,083 of the
  tested encodings are of this kind.
- A 5-bit offset of zero ($00, $20, $40, $60 as postbyte) shows as
  `$00,X`. lwasm builds `,X` from that text.
- `PSHS #$00` is lwasm syntax as far as I know. My own assembler does not
  take it.

### How it works (about 1.8 KB)

Table driven, not 256 handlers. Opcodes $00-$7F are decoded by high
nibble: read-modify-write columns ($0x, $4x-$7x share one 16-entry
table), the $1x and $3x tables (name and mode), and the branch names in
order for $2x. Opcodes $80-$FF are a 32-entry table (accumulator A side
and B side, 16 columns each); the mode comes from bits 4-5 and the
immediate width from the column. Prefix pages $10 and $11 only add an
8-entry override list and the long branches. Names live in one pool, the
last character of each with bit 7 set. Every character goes out through
one routine, `DCH`, which is silenced by a flag so `DIS` can run each
instruction once to find its length before it prints the bytes.
The tables are generated by `gen_dis_tables.py` (in the project) and
pasted into the source between `DNAMES:` and `DIXT:`.

### ROM cost, measured

| Part | Bytes |
| --- | --- |
| Code | 1,231 |
| Name pool and tables | 541 |
| Headers `DASM`, `DIS` | 17 |
| 19 bytes of direct-page globals | 0 ROM |
| **Total** | **1,789** |

`BASECODE` moved from $D936 to $D240 and `BASEDICT` from $CF87 to $C880
(`DISASM=1`). With `DISASM=0` the constants are the old ones and the
image is **byte for byte identical to 6k** (checked in both serial builds).
Spare ROM above the code: polled 333 bytes, interrupt 14 bytes.

### Unit-test regions

With `DISASM=1` the region below `BASEDICT` is $C880-$C100 = 1,920 bytes.
Groups that fit and pass with `DISASM=1`: 0, 2, 5, 13, 14, 15, 16, 17.
The other groups need `DISASM=0`. When `UNITTESTS` is defined and nonzero
and `DISASM` is not given, `DISASM` defaults to 0, so the usual
`--define=UNITTESTS=1 --define=TSTSELECTOR=n` command works unchanged.

### Verification

- Round trip: 20,432 byte sequences were disassembled by `DASM` in the
  emulator, the text reassembled with my assembler at the same address,
  and the bytes compared. Covered: every opcode on all three pages with
  three operand patterns, all 256 postbytes for every indexed opcode, all
  256 postbytes for `TFR`/`EXG`, extra offset sizes (+/-, 5, 8 and 16 bit)
  for the indexed forms, and double prefixes. Whether a byte is legal
  comes from my opcode tables, not from `DASM`. Result: 0 differences,
  except the known limits above (4 empty `PSHS` lists that my assembler
  rejects, and 1,083 non-canonical postbytes that cannot round trip).
- `37_disassembler.tests.fs`: 64 tests, 0 failed. Each checks the length
  `DASM` returns (instruction length, or 1 for a non-instruction) for an
  encoding. The text is printed to the terminal as the tests run. The text
  itself is checked by the round trip above, not by this file.
- All 19 unit-test groups pass with `DISASM=0`; 8 groups pass with
  `DISASM=1`. ANS files 27 (50/0), 33 (76/0), 34 (15/0), 36 (14/0) pass.
- Not run: lwasm, MAME, hardware.

## 7. Next: SEE (decompiler)

`SEE ( "name" -- )` for colon definitions, behind `DECOMP`: step through
the subroutine-threaded body, name each `JSR` target through `SNAME`, show
inline literals, branches and strings. This needs a read of how `IF`,
`DO`, literals and `S"` compile before it is written. Estimate 600-900
bytes; the spare ROM above `BASECODE` and the interrupt build's 14 bytes
mean `BASECODE`/`BASEDICT` move down again.
