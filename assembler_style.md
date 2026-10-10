# Assembler Style

To achieve consistency as an aid to readability
the following style rules are applied to forth6809.asm and unit_tests.asm.

## Layout

1. The opcode starts in column 13 (12 characters of indent) to allow for label length.
1. In-line comments start in column 37 to allow for branch labels.
   If opcode plus operand runs past column 36, the comment is wrapped to
   the next line, starting at column 37. Moving large comments to the
   shadow file should keep this rare.
1. A label of 12 or more characters goes on a line by itself, with the
   opcode on the following line (the assembler accepts this).

## Comments

1. Forth words have an in-line comment naming the stack parameter, e.g.
   `PULU  X   ; addr`. The comment appears once only, next to the
   instruction that moves the value on or off the data stack.
1. General routines have an in-line comment naming the input or output,
   also once only, next to the instruction that moves it into or out of
   its register.
1. Forth words have an introductory block comment giving the word name
   and stack effect (example below).
1. General assembly routines have an introductory block comment giving
   the subroutine name, its inputs and outputs, and the register effects
   (example below).
1. Block comments at the start of a routine describe current functionality,
   not historical functionality.

## Shadow file

1. A shadow file has the same name as its .asm file with a .shd extension
   (forth6809.shd, unit_tests.shd).
1. The following are copied to the shadow file:
    1. Large explanatory comments at the start of subroutines, etc.
       Replace the original with a short summary of what the routine does,
       and refer to the original in the shadow file by reference code.
    1. In-line comments explaining bug fixes. Each has a unique reference
       code of the form XYZ.12, where XYZ is the subroutine name and the
       number is never reused, so a code identifies one entry only.
       Replace the original large in-line comment with a reference such as
       `; See bugfix: XYZ.12`. The shadow file holds the full text for
       each code.

## Dictionary labels

1. Each dictionary entry has a header label `H_<NAME>`, where NAME is the
   Forth word spelled out, **without** a trailing W: `H_DUP`, `H_HEX`,
   `H_EXPECT`.
1. The execution-token (XT) label is `<NAME>W`: `DUPW`, `HEXW`, `EXPECTW`.
   Header label and XT therefore pair as `H_HEX` / `HEXW`.
1. Words whose names contain punctuation keep their existing spelled-out
   labels (`H_TOR`, `H_KEYQ`, `H_ONEPLUS`, `H_DDUP`, and so on). Known
   inconsistencies in these spellings are left as they are for now;
   standardising them is a possible later change. Only the trailing-W
   rules above are applied to them (`H_TOR` / `TORW`).
1. The following XT labels are renamed to follow the `<NAME>W` rule.
   None of the new names is used anywhere in either source file.

   | Word | Old XT | New XT | Header label |
   |------|--------|--------|--------------|
   | `TRUE`  | `TRUEBODY`  | `TRUEW`    | `H_TRUE` (unchanged) |
   | `FALSE` | `FALSEBODY` | `FALSEW`   | `H_FALSE` (unchanged) |
   | `1`     | `ONEBODY`   | `POSONEW` | `H_1` -> `H_POSONE` |
   | `-1`    | `MONEBODY`  | `NEGONEW`  | `H_M1` -> `H_NEGONE` |
   | `2`     | `TWOBODY`   | `POSTWOW` | `H_2` -> `H_POSTWO` |
   | `-2`    | `MTWOBODY`  | `NEGTWOW`  | `H_M2` -> `H_NEGTWO` |

   `H_ABORT` / `ABORTW` already follow the rules and are unchanged.

## Verification

1. Style changes must not alter the object code. Assemble before and after
   each stage and require the two binaries to be byte-identical.
   Work in stages: whitespace, then label renames, then comments.
1. A label rename is applied to forth6809.asm and unit_tests.asm together.

## Block comment examples

General assembly routine:

```
; ------------------------------------------------------------
; Transmit a character by serial communications chip.
; PUTCHAR
;    Inputs:
;        RegA = character to insert into transmit buffer.
;    Outputs:
;        none
; ------------------------------------------------------------
```

Forth word:

```
; ------------------------------------------------------------
; EMIT  ( char -- )
; ------------------------------------------------------------
```
