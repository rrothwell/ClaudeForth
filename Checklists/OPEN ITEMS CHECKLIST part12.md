# OPEN ITEMS CHECKLIST — part 12 (16 November 2026)

Changes since part 11. Stage 6p improves SEE: machine code now stops at its real
end. Source: `forth6809_stage_6p.asm`; documentation: `ClaudeForth 20261105`
(rebuilt, 263 pages); shadow file: SEE.1.

## Done in stage 6p (tested in my emulator, polled build)

- [x] **SEE stops machine code correctly.** Was: stop at the first RTS, so `=`,
      `<`, `>`, `0=`, `0<`, `0>`, `U<`, `U>`, `MIN`, `MAX`, `WITHIN`, `D=`, `D<`
      were cut short. Now: stop at RTS, RTI, JMP, BRA, LBRA, or PULS/PULU with PC,
      unless an earlier branch in the word targets an address beyond it (within
      512 bytes). New routine `DTERM`, new cell `DSMAXF`.
- [x] **Compared all 53 ROM dictionary words, 6o vs 6p:** 13 differ, in every case
      the new text is the old text plus the missing tail. `.(` and `DEFER` verified.
- [x] SEE regression script: 19 cases, 0 differ. ANS 37 (disassembler): 64 run, 0 failed.
      Unit groups 0-23 as before.
- [x] **Space:** +149 bytes of code, +2 page-zero bytes (`GLOBALS_USED`
      139+19*DISASM+23*DECOMP). `BASECODE`/`BASEDICT` with both flags on moved
      from `$CE00/$C40A` to `$CD90/$C39A`. Interrupt build now has **10 bytes spare**
      (was 47); polled 358. Unit-test region with both flags on: 666 bytes (no
      group fits either way). DISASM=1/DECOMP=0 and DISASM=0 builds unchanged.

## For Richard to confirm

- [ ] Assemble with lwasm for both SERIALPOLL values, DISASM/DECOMP 1/1, 1/0, 0/0
      (my assembler reports no overflow; the interrupt build is tight).
- [ ] Run MAME / board: `SEE =`, `SEE MIN`, `SEE DEFER`, `SEE .(` and
      `SEE` of one of your own CODE words.
- [ ] Unit groups on the interrupt build (SERIALPOLL=0) as before.

## Still open for SEE (not selected)

- [ ] Constant values, `[']` names, CASE/OF/ENDOF rebuild (about 300-350 bytes),
      the 255-item cap. AGAIN vs REPEAT at the end of a branch is genuinely the
      same code and cannot be told apart.

## Documentation added after the SEE fix (Richard's request, 16 Nov)

- [x] Section 4.8: SEE now has one example per limitation, each run in my
      emulator: CASE shown as nested IF, RECURSE, numbers/[CHAR]/constants,
      ['] and POSTPONE (shown as numbers), DEFER and VALUE, nested loops and
      EXIT, a JSR to a headerless routine (MOD). Manual is 265 pages.
- [x] Richard's decision: no further SEE features (ROM space); only the fix.
