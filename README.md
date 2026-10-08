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

* ~~Warning: not functional at this time.~~*
* ~~Warning: all words tested as functional, but with limited test coverage of edge cases. Tagged as version 1.00.~~*
* ~~Warning: all words tested as functional, with extensive automated tests. Tagged as version 1.10.~~*
* Warning: all words tested as functional, complying with ANS Forth Test Suite. Tagged as version 1.20. *

| Item             | Completed   |
|:-----------------|------------:|
|Initial specification and code generation|:white_check_mark:|
|Initial documentation|:white_check_mark:|
|Resolve assembler bugs, missing labels and dictionary entries, fix memory map overlaps & gaps. Assembles without errors. |:white_check_mark:|
|Install MAME. Add configuration file for an existing emulated 6809 computer. |:white_check_mark:|
|Customise MAME with the missing mecb6809 and mecb6502 drivers and providing monitor ROM files . |:white_check_mark:|
|Set up serial communications to MAME mecb6809 to allow upload of testing code. |:white_check_mark:|
|Load forth6809.bin ROM file and verify memory layout and operation. |:white_check_mark:|
|Manual tests and identified/fixed numerous bugs. |:white_check_mark:|
|Update documentation|:white_check_mark:|
|Automated assembler unit tests and identified bug fixes.  |:white_check_mark:|
|Adapted the MAME mecb6809 driver for interrupt driven hardware handshaking.  |:white_check_mark:|
|Optimised MAME emulated 6850 ACIA serial communications, with interrupt driven hardware handshaking |:white_check_mark:|
|Solved reliability issues with MAME emulated 6850 ACIA serial communications, by using XON/XOFF software handshaking |:white_check_mark:|
|Tests against ANS test suite, identifying, diagnosing and correcting bugs.  |:white_check_mark:|
|Update documentation for ANS test suite|:white_check_mark:|
|Retest with assembler test suite and adjust expectations.|:white_check_mark:|
|Update general documentation||
|Optimisation for space, compiler performance & application performance| |
|Update documentation| |
|Burn ROM and install onto real MECB 6809 hardware. | |
|Develop a simple forth application| |
|Refine the documentation| |

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
+ Scripts for automating execution of the ANS test suite .

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
1. Assemble and test a bare bones ANS Forth [DONE].
1. Scan for refactoring opportunities, removing code duplication.
1. Development support words such as [IF], [ELSE], [THEN], FORGET, .(), etc..
1. Debugging support.
1. Reorganise dictionary ordering to improved compilation support.
1. Optimised words for common constants.
1. Dictionary vocabulary support.
1. Inbuilt assembler.
1. Forth decompiler.
1. Interrupt chaining to call forth words.
1. Cooperative multitasking.
1. Mass storage support - SD Card or Flash.
1. Application compilation to the ROM area via ROM emulation.


