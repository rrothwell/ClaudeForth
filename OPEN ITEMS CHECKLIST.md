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
      grow toward each other or toward the stacks. `UNUSED`/`VUNUSED`
      *report* the distance to each boundary but nothing enforces it —
      a runaway compile can silently corrupt an adjacent region.
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

