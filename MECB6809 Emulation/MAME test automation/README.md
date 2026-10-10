# MAME Test Automation

## Background

Within a terminal emulator, the unit testing version of the the forth6809 binary can be created  
and installed into the MAME rom directory, with a command line like:

```bash
cd ${HOME}/git/ClaudeForth
lwasm --6809 --format=raw \
   --output=forth6809.bin --list=forth6809.lst \
   --define=UNITTESTS=1 --define=TSTSELECTOR=0 \
   forth6809.asm
cp forth6809.bin "~/Library/Application Support/mame/roms/mecb6809/mecb6809.bin"

```
In another terminal emulator, MAME can be run with a command line like:
```bash
cd $HOME/git/mame0288
./mecb6809 mecb6809 -rs232 pty -window -resolution 640x480 -debug
```
The pseudo terminal created by MAME, can be found in the MAME settings (via pressing the tab key).
In another terminal emulator use this information to start a minicom session.
```bash
minicom -D /dev/ttys006 -b57600 -8
```

## Automation Script

This process becomes tedious for executing all of the glossary tests,  
so Claude was asked to solve the associated problems 
and to manifest this in an automation script.

### Principles of Operation

The problems to solve are:
1. Maintaining a fixed reference for the serial connection.
1. Triggering the unit tests at the right time as the code entered INITCODE.
1. Collecting the test results via the serial connection.

The test runner (run_all_tests.sh) is a bash script that iterates over 
all of the glossary sections in order, creating a new binary 
and installing it into the MAME rom directory each time.
With each new binary it:
1. Runs the python script (mame listener.py) that makes a connection
   to the serial communications null modem.
1. Restarts MAME in debug mode, which breaks at INITCODE
   and then proceeds to run the selected unit tests group
   (triggered by retrigger.cmd, a parameter to the MAME command line).
1. The python script (mame listener.py) captures the test results 
   from the serial connection and writes them to a log file per glossary section.

### Usage

For an easy setup satisfy the list of dependencies in the header of run_all_tests.sh.
The default configuration has the automation files in 
a sub-directory of the directory containing 
the forth6809.asm and unit_tests.asm files. 
Override the defaults by providing new 
values as parameters from the command line. 
Ensure the bash script execute bit is set.

Assume the project was downloaded via git clone.
On MacoS a permissions error may be reported, in which case run:
```bash
cd $HOME/git/ClaudeForth
bash "$HOME/git/ClaudeForth/MECB6809 Emulation/MAME test automation/run all tests.sh" \
   --mame-bin $HOME/git/mame0288/mecb6809
```

### Typical Output

```
==================================================================
=== SUMMARY ===
==================================================================
N    SECTION          STATUS
0    3.1_SysIO        PASS
1    3.2_Stack        PASS
2    3.3_RetStack     PASS
3    3.4_SArith       PASS
4    3.5_DArith       PASS
5    3.6_Logic        PASS
6    3.7_Compare      PASS
7    3.8_CtrlFlow     TEST_FAILURE
8    3.9_DefWords     PASS
9    3.10_CompWords   PASS
10   3.11_Memory      TEST_FAILURE
11   3.12_StrParse    PASS
12   3.13_NumOut      PASS
13   3.14_BaseRadix   PASS
14   3.15_Exception   PASS
15   3.16_Comments    PASS
16   3.17_EnvSys      PASS
17   3.18_Tools       PASS
```

## Utility

To generate a collection of bin files, one per test, run the following
script in the same fashion as the test runner. 

```bash
bash "$HOME/git/ClaudeForth/MECB6809 Emulation/MAME test automation/build all tests.sh"
```
