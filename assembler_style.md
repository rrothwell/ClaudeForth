# Assembler Style

To achieve consistency as an aid to readability  
the following style rules were applied to forth680.asm and unit_tests.asm.

1. Indent to opcode position is 12 characters to allow for label length.
1. Indent to in-line comment position is 36 characters to allow for branch labels.
1. All forth words should have an inline comment against the opcode 
   that matches the stack parameter name.
1. General assembly routines should have an introductory block comment
   with a description of the 
   subroutine name, its inputs and outputs with the register effects.
1. Forth words should have an introductory block comment 
   describing the word name & stack effect. 
1. The following should be echoed to a shadow file:
    1. Large explanatory comments at the start of subroutines, etc. 
       Replace the original with a short summary describing what the routine does.
       Refer to the original comment in the shadow file using a reference code.  
    1. Inline comments explaining bug fixes. 
       These should have a reference number or code.
       Original large inline comment should be replace by a comment referring to 
       the reference number or code. Like: ; See bugfix: XYZ.12.
       XYZ should correspond to the subroutine name.
1. Block comments at beginning of subroutines should refer to current functionality.
   not historical functionality. 
1. Dictionary entries should have a label of form H_XXX... 
   This regularises a mixture like: H_HEXW, H_DECIMAL, 
1. Dictionary entries should regularise the XT label to XXX...W.

A shadow file should have a name corresponding to its associated 
.asm file, but with a .shd extension.

A typical block comment for a subroutine, not a forth word,
would look like:

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

A typical block comment for a subroutine, not a forth word,
would look like:

```
; ------------------------------------------------------------
; EMIT  ( char -- )
; ------------------------------------------------------------
```