# ANS Forth Test Suite

## Introduction

The ANS Forth Test Suite is intended to prove that a forth distribution 
is in compliance with the ANS Forth standard. 
However full compliance requires other conditions to be satisfied. 

> Source: [https://forth-standard.org/standard/testsuite (Annex F)](https://forth-standard.org/standard/testsuite), fetched
> 2026-07-15. Explicitly redistributable per the test harness's own header:
> "(C) 1995 JOHNS HOPKINS UNIVERSITY / APPLIED PHYSICS LABORATORY - MAY BE
> DISTRIBUTED FREELY AS LONG AS THIS COPYRIGHT NOTICE REMAINS."

The test suite files here have been modified 
to facilitate development testing, instead of compliance testing. 
This includes development by manual cut/paste of forth source into a terminal emulator  
or by running the supplied automation script. 

Modifications include: 
1. File splits by section.
1. Sections can be executed individually, without dependencies on prior tests.
1. Performance enhancements.
1. Improved reporting.
1. Corrections for test expectations that violate the standard.

Testing can target serial-connected hardware (MECB 6809) 
or the MAME software emulation of a 6809 SBC with a 6850 ACIA.

## Running the Suite

### MAME Emulator Setup

The MAME emulator needs to be setup in advance.
Refer to the instructions in 
```bash
${HOME}/git/ClaudeForth/MECB6809\ Emulation.
```
This includes, from one terminal:

1. Replacing the buggy 6850acia.cpp file  
provided in the MAME git project with the modified version
provide in the ClaudForth git project.
1. Installing the mecb6809.cpp driver source file.
1. Building the MAME project.
1. Assembling. then installing the forth6809.asm 
   as a .bin file into the MAME rom directory.

```bash
cp \
    ${HOME}/git/ClaudeForth/MECB6809\ Emulation/6850acia.cpp \
    ${HOME}/git/mame0288/src/devices/machine/6850acia.cpp    
cp \
    ${HOME}/git/ClaudeForth/MECB6809 Emulation/mecb6809.cpp \
    ${HOME}/git/mame0288/src/mame/homebrew/mecb6809.cpp 
cd ${HOME}/git/mame0288    
make SUBTARGET=mecb6809 SOURCES=src/mame/homebrew/mecb6809.cpp TOOLS=1 REGENIE=1 -j2
```

Then in another terminal: 
```bash
cd ${HOME}/git/ClaudeForth
lwasm --6809 --format=raw '
   --output=forth6809.bin --list=forth6809.lst \
   --define=UNITTESTS=0 --define=TSTSELECTOR=15 \
   --define=SERIALPOLL=1 \
   forth6809.asm
mkdir "${HOME}/Library/Application Support/mame/roms/mecb6809"
cp forth6809.bin "${HOME}/Library/Application Support/mame/roms/mecb6809/mecb6809.bin"
```

### Python Test Runner

#### Usage

Then in another terminal,
assuming a git clone to download this project,
 
Navigate to the top level ClaudeForth directory. 
and then to the ANS Test Suite. Execute the test runner script:

```bash
# Go there
cd ${HOME}/git/ClaudeForth/ANS\ Test\ Suite
# Verify
ls -al
# Execute the tests suite
python3 ans_test_runner.py \
    --target mame \
    --mame-bin "$HOME/git/mame0288/mecb6809" \
    --retrigger-cmd $HOME/git/ClaudeForth/ANS\ Test\ Suite/retrigger.cmd \
    --skip-assemble \
    --ans-dir $HOME/git/ClaudeForth/ANS\ Test\ Suite/ans_tests \
    --sections 08 09 10 11 12 13 14 15 16 17 18 19 20 21 23 24 26 \
    --char-delay 0.05 \
    --retries 0 \
    --log-dir $HOME/git/ClaudeForth/ANS\ Test\ Suite/ans_test_results

```
`ans_test_runner.py` automates loading the setup forth files
into a running forth6809 image.
Then it loads the forth tests.
The test runner reports summary PASS/FAIL 
per section into the stderr of the terminal.
The forth code via the test runner also reports detailed PASS/FAIL 
per section into the the log files.

#### Operating Principles

The python test runner talks to either a MAME instance 
(spawned the same way `run_all_tests.sh` does, 
over a `-rs232 null_modem -bitb socket.host:port` TCP connection) 
or a real serial-connected MECB6809 with the Forth
binary in EPROM (via pyserial). 

The test runner applies per character delays, but doesn't apply end-of-line delays.
Instead it uses forth6809's *own* line-by-line ok/"ERROR reply 
as the pacing signal.
In other words: one line goes out, 
the runner blocks until that line's own reply comes back, 
then the next line goes out.
Long test-file lines (some exceed 1000 characters) are automatically
re-wrapped to fit under `TIBBUFL` (80 bytes) 
without ever splitting inside a `S"`/`."`/`\` construct. 

See the script's own `--help` and
module docstring for every option.

### Manual Cut and Paste Via Terminal Emulator

### Usage

For full communication details refer to the file: 
```bash
more ${HOME}/git/ClaudeForth/MAME_to_minicom.md
```

In yet another terminal start up the socat bridge:
```bash
socat PTY,link=$HOME/mame-pty,raw,echo=0,ixon=1,ixoff=1 TCP-LISTEN:11185,reuseaddr
```
This must be started first.

In yet another terminal startup minicom:
```bash
minicom 57600_XONXOFF
```

In yet another terminal startup MAME as the MECB 6809 emulator:
```bash
cd $HOME/git/mame0288
./mecb6809 mecb6809 \
   -rs232 null_modem -bitb socket.127.0.0.1:11185  \
   -throttle  \
   -window -resolution 640x480 \
   -debug
```

The terminal emulator should now respond to keyboard input,
with the per character delay and handshaking preset.

In a text editor supporting copy and paste, choose a forth source code file,
select the text, copy it to the clipboard and then paste it into the minicome window.
All the files are load in this way, 
in the same order as used by the python test runner.

## Manifest

1. Python test runner to automate testing.
1. Support files used by the python test runner.
1. Forth setup files that are loaded into the test target prior to running tests. 
   These are located in the sub-directory ans_tests.
1. The ans_tests sub-directory containing the forth test files
   organised according to the glossary sections for forth6809.
1. The ans_test_results sub-directory containing the log files
   recording previois test run results.
1. Miscellaneous utility scripts.

What follows is a more detailed description of the contents of ans_tests 
and the function of each file.

### Forth Conditional Compilation Support

The utility file 00a_tool_ext_conditionals.fs is loaded first to provide
conditional forth compilation for floating point testing support when
the following ttester.fs file is compiled.

This file provides `[IF]`/`[ELSE]`/`[THEN]` 
from the Programming-Tools word set. 
These words are not provide by Claude Forth.

`ttester.fs` needs them immediately, in its own `HAS-FLOATING`/
`HAS-FLOATING-STACK` checks, so this file loads first, ahead of even
`ttester.fs`. It's the informative reference implementation given by
the standard itself (forth-standard.org/standard/tools/BracketELSE),
built only from words forth6809.asm already has (`BL WORD COUNT S"
COMPARE REFILL IF/ELSE/THEN BEGIN/WHILE/REPEAT/UNTIL ?DUP EXIT
IMMEDIATE`) — nothing further needs to be assembled into the ROM to
run the ANS suite.

### ANS Forth Test Harness
  
`ttester.fs` — represents the test harness itself
(ANS Forth Standard, Annex F, Section F.2.3). 

It defines the test setup/assertion words`T{`/`->`/`}T` 
and every supporting word, including:
1. `ERROR`
1. `EMPTY-STACK`
1. `HAS-FLOATING`/`HAS-FLOATING-STACK` detection.
1. `X}T`/`R}T`assertion words for mixed cell/float stack pictures). 

Load this file first, before the prelude or any section file. 

The extraction of this file was validated by checking nesting of: 
1. `[IF]` and `[THEN]`. Counts match exactly (8/8) 
1. `:`/`;` counts match exactly (63/63). 

No unbalanced conditional-compilation or colon
definitions were introduced while extracting it from the original source page.

### ANS Forth Test Prelude

The prelude file `00_test_prelude.fs` is loaded after `ttester.fs`, 
but before the test section files.
It provides shared section setup utilities with support for: 
1. Two's-complement assumptions (BITSSET?). 
1. Bound constants (MAX-UINT,MAX-INT, MIN-INT, MID-UINT, MID-UINT+1, MSB). 
1. Boolean constants (0S/1S via <FALSE>/<TRUE>). 
1. Floored-vs-symmetric division helpers(IFFLOORED/IFSYM). 
1. String-compare helper (S=). 
1. Shared memory buffers used by the FILL/MOVE tests (FBUF/SBUF/SEEBUF). 

### ANS Forth Tests

The ANS Forth test files `NN_name.tests.fs` are aligned 
with one file per forth6809.asm section 
(matching the exact same numbering and filenames as `forth6809_split/`).
These contain every ANS test block for the words that each section implements.

There are 153 test blocks placed across 17 section files. 
Sections that implement no words with an official ANS test 
have no corresponding file.
For example: section 5's inner-interpreter primitives like LIT/BRANCH, 
have no directly-callable ANS name, so there are no tests.

## ANS Forth Test Change Notes

### Test File Section Independence

The original ANS suite is one continuous stream where later tests reuse
words and constants defined by earlier ones (explicit in the standard's
own F.3 narrative: "these are included in the appropriate test").
Splitting it by forth6809.asm section preserved the *word groupings* but
broke that original ordering — this has since been fixed so every
section file is independently runnable, in any order, any number of
times, from a single shared harness+prelude load:

- `09_outer_interpreter.tests.fs` (FIND) used to depend on `GT1`/`GT2`
  from `13_compiling_words.tests.fs`. It now carries its own copy of
  both (`: GT1 123 ; : GT2 ['] GT1 ; IMMEDIATE`), so section 13 no
  longer needs to run first.
- Every section file now opens with `MARKER Mnn` (nn = the section
  number, e.g. `M08`) right after its header comment, and closes with a
  bare invocation of `Mnn` as its last line. `MARKER` snapshots
  `DPHERE`/`CODEHERE`/`VARHERE`/`LATEST` when created and restores all
  four when invoked (confirmed directly against forth6809.asm's
  `MARKERW`/`DOMARKER`), so running a section file and then letting it
  invoke its own marker leaves the dictionary, value-space and search
  chain exactly as they were right after `ttester.fs` +
  `00_test_prelude.fs` were loaded — no leftover state for the next
  section file to trip over, whatever order they run in.
- `18_memory.tests.fs`'s `MOVE` test still depends on the `FBUF`/`SBUF`/
  `SEEBUF` state left behind by the immediately preceding `FILL` test —
  this is fine, since both are in the same file and thus inside the same
  `MARKER` bracket.
- Several `20_numeric_output.tests.fs` tests use `MAX-BASE`, `#BITS-UD`,
  and `S=`, all provided by `00_test_prelude.fs`, which sits outside
  every section's own `MARKER` bracket and is loaded once, up front.

The fixed load order is now simply: `00a_tool_ext_conditionals.fs`,
`ttester.fs`, `00_test_prelude.fs`, then any subset of section files, in
any sequence — see `ans_test_runner.py` (one level up), which automates
exactly this against either MAME or a real serial-connected MECB6809.

### Unresolved Issues

The issues below appear to be resolved 
and should probably be deleted as no longer irrelevant.
 
- **`TRUE` and `FALSE` were not implemented as dictionary words** when
  this test suite was first organized — checked directly against
  `forth6809.asm`'s dictionary section at the time: only the internal
  assembler constants `TRUEV`/`FALSEV` existed, never exposed as
  `CONSTANT TRUE` / `CONSTANT FALSE` a running program could call. This
  has since been resolved: both are now real dictionary words
  (`CONSTANT TRUE -1` / `CONSTANT FALSE 0`), and their tests
  (`F.6.2.1485 FALSE`, `F.6.2.2298 TRUE`) are now included at the end of
  `26_abort_quit_headers.tests.fs`, alongside that section's other
  ROM-resident, hand-built words.
- Everything else in Core (F.6.1) and the Core Extension subset this
  system implements (F.6.2) mapped cleanly to exactly one section.
- **Transcription bug, since fixed**: several "See F.x.x.xxxx WORD."
  cross-reference notes (and one "The following tests..." narrative
  line, in `08_defining_words.tests.fs`) had lost their leading `\ `
  comment marker when the original web page's text was extracted —
  each would have been fed to the interpreter as literal, undefined
  words ("See", "F.6.1.0450", "The", "following", ...) the moment that
  file loaded. Found and fixed across all 17 section files while
  wiring up `ans_test_runner.py`.


## Tests Not Included

The following tests have no corresponding implementation 
so they are not included:

1. Double-Number.
1. Facility.
1. File-Access.
1. Floating-Point.
1. Memory-Allocation,
1. Search-Order 

Search-Order's absence is documented explicitly
in the ClaudeForth documentation, Section 4.5). 

Most of the Programming-Tools word set is also omitted
(AHEAD, CS-PICK, CS-ROLL, N>R, [THEN] etc..
They have no ANS test coverage relevant here.

The Tools word set — `.S`, `WORDS`, `DUMP` are non-standard extensions
with no official ANS test cases to begin with).
