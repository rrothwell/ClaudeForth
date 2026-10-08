# forth6809.asm Defects Found by the ANS Test Suite

A historical record, kept for interest. Each entry is a defect in
`forth6809.asm` that the ANS tests (or the way they were run) exposed.
All are fixed, and all 17 section files now pass with a clean data stack
on MAME and via minicom.

## `2@` and `2!`: reversed cell order

`2@` and `2!` had the two cells in the wrong order. The standard puts x2 at
`addr` and x1 at `addr+cell`. `2CONSTANT` now stores x2 (low) then x1 (high)
to match. Found by section 18 (memory).

## `CATCH` / `THROW`: input source not preserved

`CATCH` did not save and restore the input source (`SRCADDR`, `SRCLEN`,
`SRCID`, `>IN`). A throw out of a nested `EVALUATE` lost the rest of the
calling line, which left stray cells on the data stack (four after section 11).
The `CATCH` frame now carries all four values and `THROW` restores them.

## `EVALUATE`: input source kept in fixed cells

`EVALUATE` saved the input source in fixed cells, so a nested or aborted
`EVALUATE` could overwrite it. It now saves and restores it on the return stack.

## `ABORT`: did not throw

`ABORT` reset the system instead of throwing, so a `CATCH` around it never
saw the exception (section 26, `t6 c6`). It is now `-1 THROW`
(`ABORTW`), and the top-level loop prints nothing for `-1`.

## `UNLOOP` and `EXIT`: loop frame handling

- `UNLOOP` was a no-op, and `EXIT` discarded 8 bytes of loop frame
  instead of 6. A `DO` frame is three cells (index, limit, `LEAVE` flag),
  6 bytes.
- `UNLOOP` now drops the three-cell frame. `EXIT` does not touch loop
  frames, as the standard requires: use `UNLOOP` before `EXIT`.
- Found by section 12 (control flow), test `GD6`.
