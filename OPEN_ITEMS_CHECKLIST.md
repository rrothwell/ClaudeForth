# 6809 Forth — Open Items Checklist

Everything below was explicitly flagged during the build as incomplete,
unverified, or deliberately deferred. Nothing here is a surprise — each
item was named at the point it came up. This is a consolidated list to
work from, not a new set of findings. Regenerated to reflect fixes and
design decisions made since the original version.

## Known bugs — resolved since the original checklist

- [x] **`DUMP`'s partial-final-line bug** — fixed via `DUVALID` tracking
      (`25_tools_word_set.asm`). The ASCII column no longer reads past
      the valid bytes on a short final line.
- [x] **`SUBSTITUTE`** — completed. It now performs a real bounds-checked
      copy (prefix / replacement / suffix) via a shared `SUBCOPY` helper,
      reusing `SEARCHW` for the match. Still scoped to a single
      registered name/value pair, not a full table — see "Open design
      questions" below; that scope limit is a deliberate simplification,
      not a bug.
- [x] **`VALUE`'s PFA** — moved from `CODEHERE` (immutable space) to
      `VARHERE` (mutable space), matching `VARIABLE`'s pattern, so every
      `TO`-driven update now writes into the correct region instead of
      into code space. Not on the original checklist (found and fixed
      after this list was first generated); logged here for the record.
- [x] **Every scratch/global cell now has a real `RMB`-assigned
      address in page zero** (`00_memory_map_and_globals.asm`), applied
      rather than left as a placeholder. Two real findings came out of
      doing this: the budget is **253 of 256 bytes used — only 3 bytes
      of headroom** in the GLOBALS page, and `SNEND` (documented in the
      original placeholder list) turned out to be genuinely dead —
      never read or written anywhere — and was dropped rather than
      given an address. Any future scratch cell added to this system
      will need to fit in that remaining 3 bytes or the page-zero
      fast-addressing property (DP = `$00`) stops covering it.
- [x] **The ROM base dictionary is now real** (`27_forth_dictionary.asm`)
      — every primitive with actual code got a real header, chained via
      `LINK`, `CFA` pointing straight at its code label. `ABORTHDR`'s
      `LINK` field, a placeholder `0` since it was first built, is now
      resolved to the chain's newest entry. Building this surfaced
      two real findings, not just mechanical work: the original
      1024-byte `BASEDICT` could not hold the header table (ultimately
      1954 bytes needed, once `DOES>` was added — see below), so it was
      resized to 2048 bytes, taking the space from `BASECODE` (now
      6080 bytes, was 7104) — a resize based purely on the header-table
      budget, not on any actual measurement of `BASECODE`'s assembled
      size, which has never been checked with a real 6809 assembler.
      Generating this table also surfaced that **`DOES>` had no
      corresponding code anywhere in the file** — resolved in a
      follow-up pass, see below.
- [x] **`DOES>` — resolved.** `SETDOES` (the patching runtime) was added
      beside `DODOES`/`DOESRT0`, and `DOES>` itself (code label
      `DOESGT`, since a literal `">"` is not a valid 6809 assembler
      label) was added right after `CREATE`. `DOESBEH` was added to the
      GLOBALS layout to support it, using 2 of the page's last 3 free
      bytes — only 1 byte of headroom now remains in page zero.
      `DOES>` also has a real dictionary header now (`H_DOESGT`, the
      chain's newest entry); `ABORTHDR`'s `LINK` was updated again to
      point at it.
- [x] **Four internal loop-label names were reused across unrelated
      routines: `FLOOP`, `UDLOOP`, `DRPOS`, `CMLOOP`.** Resolved — each
      pair renamed to a distinct name scoped to its own routine:
      `FIND`'s `FLOOP` → `FFLOOP`; `FILLW`'s `FLOOP` → `FILLOOP`;
      `UDIV16`'s `UDLOOP` → `UD16LOOP`; `UDDIGIT`'s `UDLOOP` →
      `UDDLOOP`; `DIVCOMMON`'s `DRPOS` → `DCRPOS`; `DDOTR`'s `DRPOS` →
      `DDRPOS`; `CMOVEW`'s `CMLOOP` → `CMVLOOP`; `COMPAREW`'s `CMLOOP`
      → `CMPLOOP`. Verified zero duplicate labels and zero stray
      references to any of the old names remain anywhere in the file.
- [x] **Hardware (RTS) serial handshaking — implemented.** `IRQH`'s
      receive path and `KEY` now toggle RTS based on the input ring's
      fill level (`INFILL`, `RTSCHECKHI`, `RTSCHECKLO` against
      `INHIWATER`=48/`INLOWATER`=16, with hysteresis between them) via a
      new `CR_RTSHI` control byte and `RTSSTATE` flag — the last free
      byte in the GLOBALS page, which is now fully packed at 256/256.
      CTS (the other handshaking direction) needed no firmware logic at
      all: confirmed against the 6850 datasheet that TDRE is
      automatically inhibited while CTS is deasserted, so this system's
      existing TDRE-gated transmit logic already respects it. A real
      race was identified and closed: mainline code (`KEY`, via
      `RTSCHECKLO`) and the ISR (`IRQH`'s `TXOFF`) can both decide to
      write the control register, so `RTSCHECKLO` masks IRQ around its
      critical section and `TXOFF` checks `RTSSTATE` before writing.
      Software (XON/XOFF) handshaking remains unimplemented — see
      below.
- [x] **`TRUE` and `FALSE` — implemented.** Surfaced while organizing
      the ANS test suite: neither existed as an actual dictionary word,
      only as the internal `TRUEV`/`FALSEV` assembler constants. Added
      as `CONSTANT TRUE -1` / `CONSTANT FALSE 0` (`TRUEBODY`/
      `FALSEBODY`, section 26; headers `H_TRUE`/`H_FALSE`, chain's two
      newest entries, section 27) — the first `CONSTANT`-pattern
      ROM-resident words in this system. Every other ROM word's CFA is
      a plain code label; a `CONSTANT`'s CFA is the `DODOES`-trampoline
      pattern instead, built here with fixed, assemble-time addresses
      rather than a `CODEHERE` snapshot, since there is no interactive
      `CREATE`/`CONSTANT` phase for ROM content.
- [x] **One genuine 6309-only instruction (`TSTD`) was in use — fixed.**
      Found by auditing every mnemonic in the file against the real
      6809 instruction set, rather than trusting the Build
      Instructions section's earlier claim that no 6309 extensions
      were used (that claim was wrong until this fix). `TRYNUM`
      (section 9) used `TSTD` with no operand to test whether `D` was
      zero after `PULU D` — `PULU`/`PULS` don't affect condition codes
      on genuine 6809 hardware, unlike a load, so this relied on a
      6309-only convenience instruction. Replaced with `CMPD #0`, a
      real 6809 instruction with identical behavior for this purpose.
      A full mnemonic audit after the fix found zero remaining
      non-6809 instructions anywhere in the file.
- [x] **`BASELATEST` was an undefined symbol — a real assembly-breaking
      bug, not a placeholder.** `COLD` (section 4) has referenced
      `LDD #BASELATEST` to initialize `LATEST` since this file's
      earliest version, and the SECTION 27 header comment has long
      asserted "`BASELATEST` remains `QUITHDR`" - but no `EQU` or label
      actually named `BASELATEST` existed anywhere in the file. This
      would have failed to assemble outright. Fixed by adding
      `BASELATEST EQU QUITHDR` directly after `QUITHDR`'s own
      definition (section 26), matching what the comment always said
      it should equal. Verified: exactly one definition, no duplicate
      symbols, and `COLD`'s forward reference to it resolves under
      standard two-pass assembly.
- [x] **`JSR CR` (bare, undefined) appeared at five call sites — a real
      assembly-breaking bug, not a naming inconsistency.** The actual
      routine has always been labeled `CRW` (section 22), following
      this file's own convention of giving short/symbolic ANS names a
      distinct code label. `ABORT`, `QUIT`'s error-report path, `QUIT`'s
      `ok`-prompt path, `WORDS` (`WWDONE`), and `DUMP` (`DULEND`) all
      called the bare, undefined `CR` instead. Fixed at each site to
      `JSR CRW`, preserving each call site's original spacing exactly.
      Verified: `CRW` defined exactly once, referenced 7 times total,
      zero remaining bare-`CR` instruction operands anywhere in the
      file (the two harmless bare "CR" occurrences that remain are a
      section-title comment and the dictionary header's `FCC "CR"`
      name string, neither of which is a bug).
- [x] **Two ALU instructions used invalid register-to-register syntax
      (`ADDA B`, `EORA B`) — the 6809 has no such addressing mode, so
      the assembler read `B` as an undefined direct-page symbol.**
      Found in the single-cell multiply routine (`ADDA B`, twice) and
      `DOPLUSTEST`'s sign comparison for `+LOOP` (`EORA B`). Fixed with
      the standard 6809 idiom for combining two registers: `PSHS B`
      followed by `ADDA ,S+` / `EORA ,S+` (push B, then operate through
      the auto-incrementing stack-indexed operand). Verified: a full
      sweep of every ALU instruction (`ADDA`/`ADDB`/`SUBA`/`SUBB`/
      `ANDA`/`ANDB`/`ORA`/`ORB`/`EORA`/`EORB`/`CMPA`/`CMPB`/`ADCA`/
      `ADCB`/`SBCA`/`SBCB`/`BITA`/`BITB`) against a bare `A`/`B` operand
      found zero remaining instances; every other bare `B` in the file
      (in `STA`/`LDA`/`LEAX ...,X` and `PSHS B`) is genuine, valid 6809
      accumulator-offset indexed addressing or register-list syntax.
- [x] **Nine scratch symbols (`MRESULT`, `MVCNT`, `MVDST`, `MVSRC`,
      `FILLCHR`, `FILLCNT`, `FILLADDR`, `HSLEN`, `HSADDR`) were used
      throughout `MOVE`/`CMOVE`/`CMOVE>`, `FILL`, `HOLDS`, and the
      single-cell multiply routine but never declared anywhere — a
      real, assembly-breaking gap.** Auditing every one of the 142
      already-declared GLOBALS cells for actual use found zero dead
      cells to reclaim this time (unlike `SNEND` earlier), and the
      GLOBALS page was independently confirmed at exactly 256/256
      bytes with no headroom. Since `MOVE`-family, `FILL`, `HOLDS`, and
      the multiply routine never call each other or run concurrently
      in this single-threaded interpreter, they now share physical
      storage: three new cells (`MVCNT`, `MVDST`, `MVSRC`) hold the
      real storage, and `FILLCNT`/`HSLEN` alias `MVCNT`,
      `FILLADDR`/`HSADDR` alias `MVDST`, and `MRESULT`/`FILLCHR` alias
      `MVSRC`, all via `EQU`. These three new cells could not fit in
      the full GLOBALS page, so they live at `$0100`, carved from the
      front of `USER0` (shrunk from 128 to 122 bytes, now starting at
      `$0106`) — a real, documented tradeoff: these three cells use
      ordinary extended addressing, not direct-page, including inside
      `CMOVEW`'s per-byte copy loop.
- [x] **`JSR SPACE` (bare, undefined) — same class of bug as `CR`,
      fixed the same way.** `WORDS` called the bare, undefined `SPACE`
      instead of the actual routine label `SPACEW` (section 22).
      Fixed to `JSR SPACEW`. Checked `SPACES` for the same pattern
      (none found — `SPACESW` correctly calls `EMIT` directly) and
      swept the file for any other bare `SPACE` instruction reference
      (none remain; the two harmless bare "SPACE" occurrences left are
      a section-title comment and the dictionary header's `FCC
      "SPACE"` name string).
- [x] **Three short branches (`BHS`, `BEQ`, `BNE`) overflowed the
      8-bit short-branch range (±127 bytes) — a real assembler error,
      not a style issue.** `SUBCOPY`'s overflow check (`BHS
      SUBOVERFLOW`, ~87 source lines to target), `DUMPW`'s per-line
      loop test (`BEQ DUDONE`, ~76 lines), and `DUMPW`'s loop-back
      (`BNE DULINE`, ~76 lines) all spanned too much code for an
      8-bit displacement. Fixed by converting each to its long-branch
      equivalent (`LBHS`/`LBEQ`/`LBNE`), which uses a 16-bit
      displacement (±32767 bytes) - functionally identical, just not
      range-limited.
- [ ] **Ten more short branches have a large (41-51 source line) span
      to their target and were not individually confirmed safe.**
      Found by a heuristic sweep (line-count as a rough proxy for byte
      distance, since no real assembler is available in this
      environment to get an exact count) after fixing the three
      confirmed overflows above, all of which spanned 76+ lines - these
      ten are meaningfully shorter but not verified within range:
      `QUERY`'s `QLOOP` (three branches, lines 579/582/589), `FIND`'s
      `NOTFOUND`/`FFLOOP` (lines 1210/1256), `ACCEPT`'s `ALOOP`/`ADONE`
      (lines 1501/1462), `UNESCAPE`'s `UEDONE`/`UELOOP` (lines
      3888/3931), and `EMPTY` (line 1153). None of these were reported
      as failing and none have been changed; if a real assembler flags
      any of them, the fix is the same: convert to the matching `LBxx`
      long-branch form.
- [x] **`ORG BASECODE` was missing entirely — a fundamental placement
      bug, not a cosmetic gap.** `VECTORS` ($FFF0) and `INIT` ($FFC0)
      both had their own `ORG`, but `SECTION 3` (`IRQH`) — and every
      routine through `SECTION 26`, i.e. nearly the entire interpreter
      — had no `ORG` placing it in `BASECODE` at all. Without it, this
      code would have continued growing from wherever `INIT`'s WARM
      message left the location counter, inside `INIT`'s own 48-byte
      `$FFC0-$FFEF` budget, overflowing directly into `VECTORS` rather
      than landing in `BASECODE` ($E800-$FFBF) anywhere. Fixed by
      adding `ORG BASECODE` immediately before `SECTION 3` begins.
- [ ] **Adding the missing ORG makes `BASECODE`'s byte budget
      concretely checkable for the first time — and a rough estimate
      suggests it may not fit.** This was previously flagged only as
      "unverified" (no real assembler has ever been run against this
      file); with a real `ORG` boundary now in place, a heuristic
      per-instruction byte count (inherent/direct-page/indexed/
      immediate/extended opcode sizes, correctly distinguishing
      direct-page GLOBALS operands from extended ones) over every
      instruction from `SECTION 3` through `SECTION 26` estimates
      roughly **8660 bytes against a 6080-byte budget — about 2580
      bytes over**. This is a rough approximation, not a real
      assembler's output, and could be wrong in either direction, but
      it's a strong enough signal to treat as a real, likely problem
      rather than a formality. Not resolved here — resizing
      `BASECODE`/`BASEDICT` again would cascade into the memory map,
      the documentation, and the SVG diagram, and a real LWASM pass
      would give a far more reliable number than this estimate before
      deciding how much room is actually needed.
- [x] **`USER0` and `USER1` (250 bytes of unallocated reserve space,
      never read or written by any code) were deleted, and the region
      from `MVSCRATCH` through `APPDICT` was made fully contiguous.**
      `SERBUF`, `INBUF`, `OUTBUF`, `TIBBUF`, `WORDBUF`, and `SIBUF` all
      shifted down to sit immediately after `MVSCRATCH` ($0106) with no
      gaps between any of them. This also closed a separate,
      pre-existing 11-byte gap between `WORDBUF` and `SIBUF`
      ($02F5-$02FF) that had nothing to do with `USER0`/`USER1` but was
      caught while verifying the region was genuinely contiguous end to
      end. `APPDICT` was extended downward to close the resulting gap
      too (new start $021B, was $0320) — its end ($6EFF) is unchanged,
      so this is a pure 261-byte gain in application dictionary space,
      not a resize of its budget. This was an interpretation of
      "contiguous," not something explicitly asked for beyond the 6
      buffers themselves; flagged here in case a fixed `APPDICT` start
      was actually intended instead. Verified: zero duplicate symbols,
      zero remaining references to `USER0`/`USER1` anywhere in the
      code, and the full `GLOBALS`->`MVSCRATCH`->buffers->`APPDICT`
      span checked programmatically for zero gaps.
- [x] **`APPVARS` and `APPDICT` swapped positions - `APPVARS` now sits
      below `APPDICT`.** `APPDICT` moved from `$021B` to `$031B`
      (still ending at `$6FFF`, directly below `APPCODE`); `APPVARS`
      moved from `$6F00` down to `$021B` (same 256-byte size, now
      sitting directly above the buffers instead of directly below
      `APPCODE`). Checked before making the change: only two code
      references exist for either symbol (`COLD` initializing
      `VARHERE`/`DPHERE` to each region's start) and neither depends on
      their relative order, so the swap was safe. Verified: zero
      duplicate symbols, the whole region from `GLOBALS` through
      `APPCODE`'s start remains contiguous with zero gaps, dictionary
      chain unaffected (219 entries, since this change doesn't touch
      it at all).
- [x] **`APPVARS` grown from 256 to 8000 bytes, taking the space
      directly from `APPDICT`.** `APPVARS` now spans `$021B-$215A`
      (start address unchanged); `APPDICT` shrank by the same 7744
      bytes to `$215B-$6FFF` (end unchanged, still directly below
      `APPCODE`), giving 20133 bytes of application dictionary space,
      down from 27877. Checked before making the change: still only
      two code references to either symbol (`COLD`'s `VARHERE`/
      `DPHERE` initialization), neither size-dependent. Verified: zero
      duplicate symbols, `APPVARS` size is exactly 8000 bytes, the
      whole region stays contiguous end to end, dictionary chain
      unaffected.
- [x] **`ACIA` (the 256-byte memory-mapped I/O block) renamed to
      `INOUT`, and the actual 6850 ACIA chip's registers moved to
      `INOUT+8` instead of the block's base.** The block still spans
      the same 256 bytes ($DF00-$DFFF); it's now modeled as a general
      I/O region with the ACIA chip occupying one small part of it
      (`ACIACR`/`ACIASR` = `INOUT+8` = `$DF08`, and the data register
      `ACIADR` at `$DF09`), leaving `INOUT+0`..`INOUT+7` free for other
      memory-mapped devices sharing the block. Doing this rename
      surfaced a real, previously-hidden bug: `COLDSTRT`'s ACIA reset
      sequence used `STA ACIA` (the block's base) instead of `STA
      ACIACR` (the control register) in two places - this only ever
      worked because `ACIA` and `ACIACR` happened to be the same
      address in the old scheme. Once `ACIACR` moved to `INOUT+8`,
      writing to the bare block base would have silently stopped
      resetting the ACIA at all. Fixed both to `STA ACIACR`. Verified:
      `INOUT` defined once, the bare `ACIA` symbol (at the time)
      no longer existed anywhere, and every other ACIA register access
      in the file already used the correctly-named register symbols
      rather than the bare block name.
- [x] **`ACIA` reintroduced as an explicit base symbol
      (`ACIA EQU INOUT+8`), with `ACIACR`/`ACIASR` now defined relative
      to it (`EQU ACIA`) rather than directly to `INOUT+8`.** The data
      register was briefly renamed to `ACIRDR` in the same pass, then
      reverted back to `ACIADR` immediately afterward once flagged as
      a typo - both code sites (`IRQH`'s receive and transmit paths)
      were updated each time the name changed. Verified: each of
      `ACIA`/`ACIACR`/`ACIASR`/`ACIADR` defined exactly once, resolving
      to the expected values (`ACIA` = `INOUT+8`, `ACIACR`/`ACIASR` =
      `ACIA`, `ACIADR` = `ACIA+1`), zero remaining references to
      `ACIRDR` anywhere, zero duplicate symbols, dictionary chain
      unaffected.
- [x] **`INITEND`/`INITSIZE` landmark constants added at the true end
      of the INIT block** (`INITEND EQU *`, `INITSIZE EQU *-COLDSTRT`),
      right after `WARMMSGL`. The request referenced a `COLDSTART`
      label, which doesn't exist in this file - used the actual
      existing label `COLDSTRT` instead of introducing a new undefined
      symbol.
- [x] **`INITEND`'s comment now states the invariant explicitly
      ("value should match vector ORG") - and checking it confirms
      it currently holds.** The precise instruction-by-instruction
      byte count from when the `VECTORS` collision was first found
      (78 bytes exactly, `COLDSTRT` through `WARMMSGL`) gives
      `INITCODE start ($FFA2) + 78 = $FFF0`, exactly matching
      `VECTORS`' `ORG`. Zero gap, zero overlap - unlike the still-open
      `INITCODE`/`BASECODE` overlap at the other end of this same
      region, which remains a real problem. Same caveat as always:
      this is a manual count, not a real assembler's output, so
      `INITSIZE` (computed automatically at assembly time) is the
      figure to trust once this file is actually assembled.
- [x] **`BASECODESTRT`/`BASECODEEND`/`BASECODESIZE` and
      `BASEDICTSTRT`/`BASEDICTEND`/`BASEDICTSIZE` landmark constants
      added, matching the `INITEND`/`INITSIZE` pattern - and checking
      the two stated invariants gives one clean confirmation and one
      confirmation of an already-known problem.** `BASEDICTEND` (`$D85D`
      + the exact 1973-byte dictionary content = `$E012`) matches `ORG
      BASECODE` (`$E012`) precisely - this boundary is genuinely
      correct, not just close. `BASECODEEND`, using the same rough
      heuristic estimate flagged much earlier (~8660 bytes, never
      confirmed with a real assembler) starting from `BASECODESTRT`
      (`$E012`), lands around `$101E6` - not only failing to match
      `ORG INITCODE` (`$FFA2`) as the comment expects, but overflowing
      past `$FFFF` entirely on that estimate. The exact amount of room
      actually available between `BASECODESTRT` and `INITCODE`
      ($FFA2 - $E012 = 8080 bytes) is itself less than the ~8660-byte
      estimate, meaning even filling every available byte up to
      `INITCODE` with zero gap would still likely fall short. This is
      the same underlying problem already tracked elsewhere (`BASECODE`
      possibly not fitting its budget, and separately the
      `INITCODE`/`BASECODE` overlap), now independently reachable via
      these new landmarks once the file is actually assembled, rather
      than a new, different issue.
- [ ] **Follow-up: a real instruction-by-instruction count (not the
      rough heuristic above) puts `BASECODE`'s actual size at 7984
      bytes (`$1F30`), 96 bytes (1.2%) short of a target assembler-
      listing value of `$1F90` (8080 bytes) given for comparison.**
      Built a mnemonic-and-addressing-mode-aware counter distinguishing
      inherent/immediate/direct/extended/indexed forms, correct prefix
      requirements (`$10`/`$11` for `LDY`/`STY`/`LDS`/`STS`/`CMPD`/
      `CMPY`/`CMPU`/`CMPS`), and true direct-page symbols (only
      `$0000`-`$00FF`, matching `DP`) - a meaningfully more rigorous
      pass than the original ~8660-byte estimate. Every one of the
      3751 instructions in the region was classified (zero
      "unrecognized" remaining after fixing early misses like `LSLB`/
      `LSLA` as `ASLB`/`ASLA` synonyms). Checked for likely sources of
      the remaining 96-byte gap before accepting it: zero indexed
      operands use an offset outside the 5-bit range that would need
      extra encoding bytes (all 125 numeric-offset operands found are
      small, e.g. `1,X`/`-1,Y`), and the two apparent "indirect `[ ]`"
      matches were a false positive (a section-title comment, not real
      indirect addressing). The target value `$1F90` is notable in its
      own right: `BASECODE + $1F90 = $FFA2` exactly, meaning if the
      real assembled size actually matched it, `BASECODE` and
      `INITCODE` would be perfectly contiguous with zero gap and zero
      overlap - which would also resolve the separate, still-open
      `INITCODE`/`BASECODE` overlap noted elsewhere. My count doesn't
      confirm that, though it's close (1.2% off). This is still not a
      real assembler's output - the standing caveat throughout this
      file - and the gap could come from encoding edge cases a manual
      model can approximate but not guarantee against.
- [x] **`ROMSTRT`/`ROMEND` added as the outer ROM boundary
      (`$C100`/`VECTORS-1`), and `INITCODE`/`BASECODE`/`BASEDICT`
      verified contained within it - all three pass.** `ROMEND` was
      initially defined as `$10000` ("one past `VECTORS`'s end," a
      symbolic value that doesn't fit as a real 16-bit address), then
      corrected to `VECTORS-1` (`$FFEF`, one before `VECTORS`'s start)
      - a genuine 16-bit address usable directly in comparisons or as
      a memory operand, not just symbolic arithmetic. Re-checked after
      the correction rather than assumed still valid: `INITCODE`
      ($FFA2-$FFEF), `BASECODE` ($E012-$FFBF), and `BASEDICT`
      ($D85D-$E011) are all still genuinely within `ROMSTRT..ROMEND`
      - `INITCODE`'s own end now lands exactly on the new boundary, a
      tighter and more meaningful check than before, not a violation.
      This containment check passes cleanly, independent of the other
      open problems below.
- [x] **`ROMSTRT`/`ROMEND` renamed to `USROMSTRT`/`USROMEND`, each
      with a short "Usable ROM start"/"Usable ROM end" comment.**
      Cosmetic, not functional - neither symbol was referenced by any
      code, only by nearby comments (three sites, all updated: the
      pair's own definitions and `INOUT`'s cross-reference). Verified:
      zero remaining bare `ROMSTRT`/`ROMEND` references anywhere, zero
      duplicate symbols, dictionary chain unaffected.
- [x] **`VECTOREND`/`VECTORSIZE` landmark constants added at the true
      end of the vector table, matching the `INITEND`/`INITSIZE`
      pattern - and checking the stated invariant confirms it exactly,
      not approximately.** Unlike `INITEND`/`BASECODEEND` (which
      needed a manual, approximate instruction-by-instruction byte
      count since real 6809 instructions have variable-length
      encoding), the vector table is pure `FDB` data with a fixed,
      unambiguous 2-byte width per entry - counting the 8 entries
      (`VRESV` through `VRESET`) gives exactly 16 bytes, matching the
      comment's stated `$10` expectation precisely. Verified: zero
      duplicate symbols, dictionary chain unaffected.
- [x] **`BASECODESTRT` removed as requested - but `BASECODESIZE`
      depended on it, so removing it alone would have left a genuine
      dangling undefined-symbol reference, the same bug class found
      and fixed several times earlier in this file.** Confirmed first
      that `BASECODESTRT` was numerically identical to `BASECODE`
      itself (only comments sit between `ORG BASECODE` and where
      `BASECODESTRT` was defined, zero emitted bytes), then fixed
      `BASECODESIZE` to read `BASECODEEND-BASECODE` directly instead -
      matching the same pattern just applied to `INITSIZE`/`INITCODE`,
      not a new approach invented for this case. Verified: zero
      remaining `BASECODESTRT` references anywhere, `BASECODESIZE`
      resolves cleanly, zero duplicate symbols, dictionary chain
      unaffected.
- [x] **`BASEDICTSTRT` removed the same way, for the same reason -
      `BASEDICTSIZE` depended on it too.** Same fix pattern as
      `BASECODESTRT` immediately above, applied to its counterpart:
      confirmed `BASEDICTSTRT` was numerically identical to `BASEDICT`
      (only `ORG BASEDICT` sits before it, zero emitted bytes), removed
      it, and repointed `BASEDICTSIZE` to `BASEDICTEND-BASEDICT`
      directly. Verified: zero remaining `BASEDICTSTRT` references
      anywhere, `BASEDICTSIZE` resolves cleanly, zero duplicate
      symbols, dictionary chain unaffected.
- [x] **`INOUT` moved from `$DF00` to `$C000` (with `INOUTEND EQU
      INOUT+$FF` added immediately after), and every ACIA-related
      address verified between the two - also passes.** `ACIA`/
      `ACIACR`/`ACIASR` (`$C008`) and `ACIADR` (`$C009`) all fall
      within `INOUT`-`INOUTEND` (`$C000`-`$C0FF`), checked numerically.
      Confirmed there is no other memory-mapped I/O device anywhere in
      this file besides the ACIA family - nothing else needed checking.
      This move has a real, positive side effect worth naming clearly:
      it resolves the INOUT portion of the three-way collision flagged
      when `BASEDICT` moved to `$D85D` two turns ago (`INOUT` no longer
      overlaps `BASEDICT`, since `$C0FF < $D85D`). The `DSTACK` and
      `RSTACK` portions of that same collision were untouched by this
      specific change, but have since been resolved separately - see
      below.
- [x] **`INOUT`'s new collision with `APPCODE` is resolved, and so is
      the rest of the original `BASEDICT` collision - `RSTACK`,
      `DSTACK`, `CODETOP`, `APPCODE`, and `APPDICT` all moved down
      `$2000`.** `RSTACK` ($BC00-$BEFF) and `DSTACK` ($B800-$BBFF) no
      longer overlap `BASEDICT` at all - the three-way collision first
      found when `BASEDICT` moved to `$D85D` is now fully resolved
      (`INOUT` resolved it two turns ago, this resolves the remaining
      two thirds). `APPCODE`'s move ($5000-$B7FF) also separately
      resolves its overlap with `INOUT` from the previous entry, as a
      side effect of the same shift, not a second fix. Re-verified with
      a full pairwise sweep after the move, not assumed: the only
      overlap remaining from the four found last turn is the original,
      unrelated `INITCODE`/`BASECODE` one (30 B) - `INITCODE`/
      `BASECODE`/`BASEDICT`/`RSTACK`/`DSTACK`/`INOUT`/`APPCODE` are all
      now mutually clean.
- [x] **`APPDICT`'s collision with `APPVARS` is now resolved -
      `APPVARSEND` changed from a static `APPVARS+8000` to
      `APPDICT-1`, making it self-derive from wherever `APPDICT`
      actually sits instead of a fixed size.** `APPVARSEND` is now
      `$1FFF` (was `$215B`), giving `APPVARS` 7653 bytes of actual
      usable space (down from the originally-intended 8000 - the
      347-byte reduction exactly matches the overlap this closes).
      `APPVARS`'s own `EQU` still starts at `$021B` and its comment
      still cites the historical "8000 bytes" intent, now explicitly
      marked as the original intent rather than the current usable
      size. Functionally, `APPVARS`'s enforced range (`$021B-$1FFF`)
      no longer reaches `APPDICT` (`$2000-$6EA4`) at all - checked
      numerically, not assumed. This also makes the boundary
      self-correcting: if `APPDICT` moves again, `APPVARSEND` moves
      with it automatically, rather than needing another manual fix
      like the last several turns' worth of address changes required.
      `VUNUSEDW`'s own code is unchanged - it already computed against
      `APPVARSEND` (see below), so this fix took effect purely by
      changing what that symbol means. Verified: zero duplicate
      symbols, dictionary chain unaffected.
- [x] **`DSTACK` moved up `$200` (to `$BCFF`), resolving both the
      `CODETOP`/`DSTACK` mismatch and the `RSTACK`/`DSTACK` gap from
      last turn in one move.** `DSTACK`'s new occupied bottom
      (`$B900`, from its `$BCFF` top and 1024-byte size) now matches
      `CODETOP` (`$B900`) exactly - `APPCODE`'s nominal ceiling no
      longer overstates safe growth room, and the 512-byte overlap
      that created between `APPCODE`'s nominal range and `DSTACK`'s
      true range is gone. As a bonus, not something separately
      requested: `DSTACK`'s new top (`$BCFF`) is now exactly
      contiguous with `RSTACK`'s bottom (`$BD00`), closing the
      512-byte gap that had opened between them too. Verified with a
      full pairwise sweep after the move: exactly two overlaps remain
      in the current memory map - the still-open `APPDICT`/`APPVARS`
      one (347 B) and the original, unrelated `INITCODE`/`BASECODE`
      overlap (30 B) - down from three last turn.

- [x] **The VECTORS collision found by verifying `INITEND` is now
      resolved - `INIT`'s ORG moved from `$FFC0` to `$FFA0`.** Widened
      `INIT` from 48 to 80 bytes ($FFA0-$FFEF), comfortably covering
      the ~78 bytes `COLDSTRT`+`WARM`+`WARMMSG` actually needs (2 bytes
      of margin) - still an estimate from manual byte-counting, not a
      real assembler's output. `INIT`'s own `ORG` was also converted
      from a literal `$FFC0` to symbolic `ORG INIT`, matching
      `BASECODE`/`BASEDICT`'s convention, so the `EQU` and the actual
      placement can no longer drift apart the way `BASECODE`'s did
      before that was caught. One real, unresolved interaction worth
      naming: `INIT`'s new start ($FFA0) is 32 bytes below the old
      documented `BASECODE` end ($FFBF), tightening the still-open
      `BASECODE` overflow risk below by that much further - not a new
      problem in kind, since that risk was already estimated at
      roughly 2580 bytes over budget, dwarfing this additional 32-byte
      reduction, but worth tracking alongside it rather than treated
      as independent.
- [ ] **`INIT` moved again, from `$FFA0` to `$FFA2` (request contained
      a `&FFA2` typo - used the correct `$` hex prefix instead).**
      `INIT` is now exactly 78 bytes ($FFA2-$FFEF), matching the
      `COLDSTRT`+`WARM`+`WARMMSG` byte-count estimate with zero margin
      (was 80 bytes, with 2 bytes of slack). This is a genuinely
      tighter fit than before, worth naming as a real tradeoff: any
      inaccuracy in the manual byte count, or any future addition to
      `COLDSTRT`/`WARM`, now has zero room to absorb. The overlap with
      `BASECODE` noted above is **not resolved by this change, only
      reduced** - from 32 bytes to 30 bytes ($FFA2-$FFBF). This was a
      real, pre-existing problem before this turn touched anything
      (`$FFA0` already overlapped `BASECODE`'s declared end by 32
      bytes), not something newly introduced. Not fixed here, in
      either direction (shrinking `BASECODE` further or moving `INIT`
      above it instead of below): both are bigger architectural
      decisions than "change one EQU," and a real assembler run would
      settle the actual `BASECODE` byte count this depends on.
- [x] **`INIT` renamed to `INITCODE`** (`EQU` and its `ORG` reference,
      both in the memory-map constants). The section-title comment
      ("SECTION 2: INIT CODE") and one historical narrative comment
      describing a past bug scenario (with the byte figures true at
      that time, not today) were deliberately left referring to "INIT"
      as plain English/history, not the symbol - renaming a symbol
      doesn't obligate rewriting prose that correctly describes what
      was true before the rename existed. Doing this rename surfaced
      that the documentation's "ROM Size Required" section (Section 2)
      had gone stale independent of the rename itself: it still
      asserted the four ROM regions were contiguous at exactly 8192
      bytes, which stopped being true as soon as `INIT` moved to
      `$FFA2` last turn and started overlapping `BASECODE`. Rewritten
      to state the overlap plainly instead of the now-false claim.
      Verified: `INITCODE` defined exactly once, zero duplicate
      symbols, dictionary chain unaffected.
- [x] **`BASEDICT` and `BASECODE` addresses applied exactly as
      requested, and the documented ROM requirement widened to a 16K
      part - but this surfaced a severe, unresolved collision, not a
      minor tradeoff.** `BASEDICT` moved from `$E000` to `$D85D` -
      verified before making the change that `$E012 - $D85D = 1973`
      bytes exactly matches SECTION 27's real, measured dictionary
      content, a genuine zero-padding exact fit (was 2048 bytes, 75
      bytes of slack). `BASECODE` moved from `$E800` down to `$E012`
      to match; its own upper bound was not given and stayed at
      `$FFBF`, growing it from 6080 to 8110 bytes.
- [ ] **`BASEDICT`'s new range ($D85D-$E011) entirely overlaps three
      other live regions: `DSTACK` (931 of its 1024 bytes,
      `$D85D-$DBFF`), `RSTACK` (all 768 bytes, `$DC00-$DEFF`), and
      `INOUT` (all 256 bytes, `$DF00-$DFFF`).** Found by checking the
      new address against every other region's boundaries before
      updating the documentation - not caught until then. This is a
      fundamental, system-breaking conflict, not a byte-budget
      tightness issue like the `INITCODE`/`BASECODE` overlap noted
      elsewhere: as configured, the ROM dictionary, the data stack,
      the return stack, and the ACIA's registers would all be mapped
      to the same physical addresses simultaneously, which cannot work
      on real hardware without bank switching (which this system does
      not have). The requested `EQU` values were applied exactly as
      given, since that's what was asked; resolving the collision
      itself was not attempted here, since it requires a decision this
      response can't make alone - moving `DSTACK`/`RSTACK`/`INOUT`
      elsewhere, choosing a smaller `BASEDICT`/`BASECODE` split that
      doesn't reach down this far, or reconsidering whether `$D85D` was
      the address actually intended. The documented ROM part was still
      widened from 8K to 16K per the request (real total usage of
      `BASEDICT`+`BASECODE`+`INITCODE`+`VECTORS` alone, ignoring the
      collision, is about 10.15K, leaving roughly 6.2K of spare
      capacity within a 16K×8 EPROM), but that figure is secondary to
      the collision above. Verified: zero duplicate symbols, dictionary
      chain unaffected (219 entries, since this doesn't touch it).
- [x] **The `INITCODE`/`BASECODE` overlap - open since it was first
      found, mentioned in at least five separate entries above across
      several turns - is finally resolved. `BASECODE` and `BASEDICT`
      both shifted down exactly 30 bytes** (`BASECODE`: `$E012` ->
      `$DFF4`; `BASEDICT`: `$D85D` -> `$D83F`), chosen precisely: 30
      bytes is exactly the overlap amount, so `BASECODE`'s nominal end
      (`$FFA1`, unchanged 8110-byte budget) now lands exactly one byte
      below `INITCODE`'s start (`$FFA2`) - zero gap, zero overlap.
      `BASEDICT` shifted the same amount to stay perfectly contiguous
      with `BASECODE`'s new start, preserving its own exact,
      zero-padding fit. Verified with a full pairwise sweep across
      every region in the memory map, not just the two that moved:
      **zero overlaps anywhere** - the first time that's been true
      since this whole sequence of address changes began. `USROMSTRT`/
      `USROMEND` containment re-checked and still passes for all three
      ROM regions. Also cleaned up the accumulated resolved-issue
      narrative in the top-of-file note (previously ~40 lines
      chronicling the `BASEDICT`/`DSTACK`/`RSTACK`/`INOUT`/`CODETOP`/
      `APPDICT` saga turn by turn, including one claim - the
      `APPDICT`/`APPVARS` overlap being open - that was already stale
      before this edit) down to a short, current-state summary,
      matching the same cleanup already applied to the documentation.

## Structural duplication (identified, some resolved, some not)

- [x] `:`/`CREATE`/`VARIABLE`'s header-building — resolved via `HEADER`
      (section 7).
- [x] `COMMA`/`CODECOMMA`/`CCOMMA`/`VCOMMA`/`VCCOMMA`/`CCOMMA1` —
      resolved via `APPENDCELL`/`APPENDBYTE` (section 6).
- [x] `<#`/`#>` recomputing PAD's address inline — resolved, both now
      call `PADW` (section 20 / section 6).
- [ ] No further known duplication, but the codebase was never given a
      full pass specifically hunting for more.

## Real, load-bearing gaps

- [ ] **Software (XON/XOFF) handshaking is still not implemented.** Now
      that hardware RTS/CTS handshaking is in place, this is the one
      remaining flow-control gap: this system still never transmits
      XON/XOFF and would not recognize either byte as a control signal
      if the remote device sent them — an incoming `$11`/`$13` is just
      queued as an ordinary character. Only relevant for links with no
      RTS/CTS wiring (plain 3-wire serial); would need a byte-
      interception layer between the input ring and `KEY`'s caller.

- [ ] **No hard boundary checks** anywhere `DPHERE`/`CODEHERE`/`VARHERE`
      grow toward each other or toward the stacks. `UNUSED` and
      `VUNUSED` both correctly *report* the distance to their boundary
      now (`CODETOP` and the newly-added `APPVARSEND` respectively),
      but nothing enforces either — a runaway compile can silently
      corrupt an adjacent region.
- [x] **`VUNUSEDW` (the `VUNUSED` word) computed a meaningless number,
      not "how much `APPVARS` space remains" - a real, distinct bug,
      not just the absence of a check. Fixed.** `LDD #APPCODE / SUBD
      VARHERE` computed `APPCODE - VARHERE` (roughly `$7000` minus
      wherever `VARHERE` currently sits within `APPVARS`), which had
      nothing to do with `APPVARS`'s own boundary - looked like a
      copy-paste slip from `UNUSEDW` immediately above it (`LDD
      #CODETOP / SUBD CODEHERE`, correct for `CODEHERE`'s own
      boundary). Surfaced directly by a question about how `APPVARS`'s
      size is actually set: it wasn't - `APPVARS EQU $021B` defined
      only its start; there was no end/size constant anywhere. Fixed
      by adding `APPVARSEND EQU APPVARS+8000` (an exclusive upper
      bound, `$215B`, matching `CODETOP`'s own convention for
      `APPCODE`) and changing `VUNUSEDW` to `LDD #APPVARSEND / SUBD
      VARHERE`. Verified: at cold start (`VARHERE`=`APPVARS`), this
      computes exactly 8000, matching `APPVARS`'s documented size
      precisely; zero duplicate symbols; dictionary chain unaffected.
      `APPVARSEND` initially fell within `APPDICT`'s current range -
      expected at the time, the same, already-tracked `APPDICT`/
      `APPVARS` overlap, not something this fix caused. Since resolved
      by redefining `APPVARSEND` as `APPDICT-1` - see above.
- [ ] **`ENVTABLE` is incomplete.** Missing entries: `/HOLD`, `/PAD`
      (this build never fixed a capacity for either — filling them in
      would mean deciding a real bound first, not just picking a
      number), `MAX-D`, `MAX-UD` (need the dispatcher extended to push
      *two* cells for double-cell answers — current `ENVQUERY` only
      handles one), `WORDLISTS`/`FLOORED` (need the dispatcher to be
      able to report a recognized-but-false answer, distinct from
      "unrecognized name" — no such path exists yet).
- [ ] **`CATCH`-wrapped `QUIT`/`INTERPRET` rollback is scoped to one
      input line only.** A colon definition spanning multiple lines
      that fails partway through a later line only rolls back that
      line's contribution, not the whole definition back to `:`. A
      complete fix needs the region-pointer snapshot taken once at `:`
      and held until `;` or an error, not refreshed every `QLOOP` pass.
- [ ] **`ABORTHDR`'s `LINK` field is a placeholder `0`** in the
      consolidated/split source — must be set to the real prior
      `LATEST` value once final ROM layout/assembly order is fixed.

## Never resolved after being explicitly raised

- [ ] **`J` doesn't generalize past one level of loop nesting.** No
      `J2`/deeper equivalent exists. A triple-nested loop's innermost
      body has no built-in way to reach the outermost index without
      manually replicating `J`'s offset arithmetic one frame further.
- [ ] **`LEAVE`'s correctness depends on always being textually inside
      the loop it affects** — never verified against a `LEAVE` called
      from a separately-defined word invoked from within a loop (which
      would read/set the wrong stack frame, or crash).
- [ ] **`WORD`'s 31-character cap is now inconsistent within the
      system.** `PARSE`/`PARSE-NAME` were deliberately rewritten to
      not share it, but `WORD` itself — and everything still built on
      it (`CHAR`, `[CHAR]`, header names, `FIND`) — still has it.
- [ ] **The optional Search-Order word set is not implemented.** Every
      word resolves through one unified dictionary chain rooted at
      `LATEST`; there is no multi-wordlist support (`WORDLIST`,
      `GET-ORDER`/`SET-ORDER`, `ALSO`/`ONLY`, etc.). This was a
      foundational decision fixed since `COLDSTRT`'s first version, not
      an oversight — now documented explicitly (ClaudeForth
      documentation, Section 4.5) along with what adding it later would
      actually require: restructuring `FIND` into a loop over an active
      search order, changing `HEADER` to link into a selectable
      "current" wordlist instead of unconditionally into `LATEST`, and
      fixing the few words (`RECURSE`, `;`'s unsmudge step, `WORDS`)
      that read `LATEST` directly today.

## Open design questions (not defects — deliberate unresolved choices)

- [ ] Whether `ALLOT`/`VALLOT`/`PICK`/`ROLL`/`BASE` should range-check
      their inputs against actual stack/region bounds. Currently none
      of them do, consistently, by choice rather than oversight.
- [ ] Whether any additional distinction like `TIB`/`SOURCE` (fixed
      terminal buffer vs. current input source) is needed anywhere
      else in the system where `EVALUATE`'s redirection might still
      cause a mismatch.
- [ ] `SWIH`'s throw code (`-99` in the consolidated source) was never
      assigned a real, deliberate value — it's a placeholder for
      "some hardware trap occurred," not a considered ANS-style code.
- [ ] `REPLACES`/`SUBSTITUTE` remain single-slot (one registered
      name/value pair, overwritten by the next `REPLACES` call) rather
      than a true multi-entry table. A real table needs its own storage
      layout and lookup structure — a deliberate scope decision made
      when `SUBSTITUTE` was completed, not an oversight.

## What's solid (for reference, not action)

Stack manipulation (Core + Core Ext + return-stack transfer), all
arithmetic (single + double + mixed precision), logic, comparison
(single + double), full control flow including `CASE`, all defining
words including `DEFER`/`MARKER`/`VALUE`/`TO` (`VALUE` now correctly
targeting mutable space), memory and string operations (including a
completed `SUBSTITUTE`), `SOURCE`/`EVALUATE`/`REFILL` mechanics, and the
Tools word set (`.S`/`WORDS`/`DUMP`, with `DUMP`'s edge-case bug fixed)
are complete and were traced/verified against concrete cases during the
build, not merely asserted correct.

