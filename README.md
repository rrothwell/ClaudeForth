# ClaudeForth
An ANS forth for the MC6809 microprocessor, 
generated using the iPhone Claude app. 

This is a 16-bit subroutine threaded forth.
It is designed to be ROMable 
and to target the Minimalist Eurocard Board (MECB) 6809 computer, 
with the MECB IO card providing an
MC6850 ACIA for serial IO.

## Scope

The objective is to refamiliarise myself with the Forth language and the MC6809 microprocessor.
There will an assessment of the effectiveness of a mature AI system (circa mid-2026),
for developing code with a moderately complex logical structure.

## Strategy

The initial development of the source code according to the requirements occurred over 
a couple of days. The result was not remotely functional. 

Manual testing, over 3 weeks, one glossary section at a time, 
show numerous logic bugs, some arising from subtleties of the 6809 instruction set. 
This included aliasing of A:B to D and variations in instructions setting condition codes.

When a bug was isolated, the description  was pushed to Claude often resulting in 
a sophisticated analysis and resolution. Failing that the code was single stepped 
using the MAME debugger, identified and the result passed to Claude for verification
and rectification. Claude generated all of the project artefacts.

Claude would often pursue any dependencies, 
including inspecting the code for similar bug patterns
and updating the documentation.

After several weeks of consistent effort the following was accomplished:
1. Several problems with MAME serial communications were resolved.
This allows cut/paste style development.
1. ANS Test Suite execution was automated. 
1. The ANS Test Suite was adapted for development purposes.
1. Faults in ANS Test Suite expectations were corrected.
1. Subtle bugs in the Claude Forth implementation were exposed, diagnosed and corrected.

## Development Environment

The development machine is a MacMini with i7 Intel processor running MacOS Sonoma 14.7.4.
An updated Homebrew installation is present as are the Xcode Command Line Tools (Xcode 16.2).
[Homebrew](https://brew.sh) is used to install software dependencies.

```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install binutils

```

## Progress

* ~~Warning: not functional at this time.~~
* ~~Warning: all words tested as functional, but with limited test coverage of edge cases. Tagged as version 1.00.~~
* ~~Warning: all words tested as functional, with extensive automated tests. Tagged as version 1.10.~~
* ~~Warning: most words tested as functional, complying with the ANS Forth Test Suite. Tagged as version 1.20.~~
* ~~Usable: all words tested as functional & performant, nearly all complying with the ANS Forth Test Suite. Tagged as version 1.30.~~
* Trustworthy: all words tested as functional & performant, with complete test coverage, complying with the ANS Forth Test Suite. Tagged as version 1.40. 

| Item             | Version   | Completed   |
|:-----------------|----------:|------------:|
|Initial specification and code generation| 0.00|:white_check_mark:|
|Initial documentation| 0.00|:white_check_mark:|
|Resolve assembler bugs, missing labels and dictionary entries, fix memory map overlaps & gaps. Assembles without errors. | 0.00|:white_check_mark:|
|Install MAME. Add configuration file for an existing emulated 6809 computer. | 0.00|:white_check_mark:|
|Customise MAME with the missing mecb6809 and mecb6502 drivers and providing monitor ROM files. | 0.00|:white_check_mark:|
|Set up serial communications to MAME mecb6809 to allow upload of testing code. | 0.00|:white_check_mark:|
|Load forth6809.bin ROM file and verify memory layout and operation. | 0.00|:white_check_mark:|
|Manual tests and identified/fixed numerous bugs. |1.00|:white_check_mark:|
|Update documentation|1.00|:white_check_mark:|
|Automated assembler unit tests and identified bug fixes.  | 1.10|:white_check_mark:|
|Adapted the MAME mecb6809 driver for interrupt driven hardware handshaking.  | 1.10|:white_check_mark:|
|Optimised MAME emulated 6850 ACIA serial communications, with interrupt driven hardware handshaking | 1.10|:white_check_mark:|
|Solved reliability issues with MAME emulated 6850 ACIA serial communications, by using simplified XON/XOFF software handshaking, a lower 57600 baud rate and a 20ms character delay. | 1.10|:white_check_mark:|
|Tests against ANS test suite, identifying, diagnosing and correcting bugs.  | 1.20|:white_check_mark:|
|Update documentation for ANS test suite| 1.20|:white_check_mark:|
|Retest with assembler test suite and adjust expectations.| 1.20|:white_check_mark:|
|Update general documentation, including applying style rules to assembler code and introducing shadow files.| 1.20|:white_check_mark:|
|Optimisation for space & application performance| 1.30|:white_check_mark:|
|Test coverage audit and completions| 1.30|:white_check_mark:|
|Optimisation for compiler performance| 1.40|:white_check_mark:|
|Update documentation| 1.40|:white_check_mark:|
|Burn ROM and install onto real MECB 6809 hardware. | 1.40| |
|Develop a simple forth application| 1.40| |
|Refine the documentation| 1.40| |

## Assets
### Manifest
+ Documentation
+ Recording of Claude chats
+ A Claude generated file listing remaining issues.
+ A unified assembler file.
+ A collection of assembler files
  obtained by splitting the above file.
+ A conditional assembler unit testing file with automation scripts.
+ An updated MAME mecb6809.cpp driver file.
+ An updated MAME 6850acia.cpp ACIA emulation file with bugfixes 
  and communication improvements.
+ A memory map graphic.
+ An interpreter graphic in UML.
+ Improved, corrected ANS test suite, with logs of finalised test results.
+ Scripts for automating execution of the ANS test suite.
+ Project artifacts such as assembler .lst, .bin and .shd files.

### File types
| File extension             | Description of contents   |
|-----------------:|:------------|
|.asm| 6809 assembly language [lwasm syntax](https://www.lwtools.ca)|
|.cpp| C++ source code file compiled via make|
|.lst| 6809 assembly listing  |
|.bin| 6809 raw binary opcodes as ROM content |
|.svg| Scalable Vector Graphics text XML format |
|.png| Portable Network Graphics raster image format |
|.jpg/.jpeg| JEPEG compressed graphics format |
|.pdf| Portable Document Format |
|.docx| Microsoft Word XML format |
|.mmd| [Mermaid](https://mermaid.js.org) graphics text format for UML |
|.cmd| A command file for MAME startup |
|.fs| Forth source code |
|.py| Python source code |
|.bs| Bash script file |
|.log| A logfile. Likely for accepting test results |
|.shd| A shadow file with content corresponding to the same named assembler file[^1].|


[^1]: A shadow file is a text file with sections corresponding 
      to those of the same named assembler files.
      This lists expanded block comments, operating principles,
      bug fixes explanations and obsolete asembler code.


### Documentation

#### Portable Document format

[ClaudeForth Document](Documentation/ClaudeForth%20preview.pdf)

#### Memory Map

![alt Memory Map](Documentation/forth6809%20memory%20map.svg)

#### MAME Test Harness
1. Chapter 1: [MAME installation notes](MECB6809%20Emulation/MAME%20installation%20notes.md)
1. Chapter 2: [MAME_Customization](MECB6809%20Emulation/MAME_Customization.md)
1. Chapter 3: [MAME_Usage](MECB6809%20Emulation/MAME_Usage.md)
1. Chapter 4: [MAME Serial Communications](MECB6809%20Emulation//MAME%20Serial%20Communications.md)
1. Chapter 5: [MAME Testing.](MECB6809%20Emulation//MAME%20Testing.md)


## Plans
| Item             | Version   | Completed   |
|:-----------------|----------:|------------:|
| Assemble and test a bare bones ANS Forth . | |:white_check_mark:|
| Scan for refactoring opportunities, removing code duplication.  | |:white_check_mark:|
| Optimised words for common constants.  | |:white_check_mark:|
| Complete ANS double word implementation with tests.  | |:white_check_mark:|
| Complete ANS string implementation with tests  | |:white_check_mark:|.
| Development support words such as [IF], [ELSE], [THEN], .(), etc..  | |:white_check_mark:|
| Reorganise dictionary ordering to improved compilation speed.  | |:white_check_mark:|
| Run some benchmarks.  | ||
| Forth decompiler.  | | |
| Reorganise memory map so that the stacks are below $8000. Move the in-RAM code and dictionary up to fill the gap below $C000. | | |
| Adjust DICT:CODE ratio to 1:4| | |
| Vectored I/O. In particular the ability to programatically change the behavior of EMIT, etc..  | | |
| Dictionary vocabulary support. | | |
| Format the output of WORDS to 10 forth words per line. Possibly pad each word to 8 character width and if longer to 16 character width.  | | |
| Format the output of DUMP to show an address per line. | | |
| Inbuilt assembler.  | | |
| Interrupt chaining to call forth words.  | | |
| Cooperative multitasking.  | | |
| Mass storage support - SD Card or Flash.  | | |
| Application compilation to the ROM area via ROM emulation.  | | |
| Hardware/software floating point support.  | | |
| Buffered serial communications with software XON/XOFF handshaking.  | | |
| Change formatting of ok line output to match GForth.  | | |
| Improve the number parser to recognise binary and hexadecimal numbers.  | | |
| Move the serial communications code to an include file.  | | |
| Debugging support. | | |


