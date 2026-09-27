# MAME Test Automation

## Background

Within a terminal emulator, the unit testing version of the the forth6809 binary can be created  
and installed into the MAME rom directory, with a command line like:

```bash
lwasm --6809 --format=raw --output=forth6809.bin --list=forth6809.lst --define=UNITTESTS=1 --define=TSTSELECTOR=0 forth6809.asm
cp forth6809.bin "~/Library/Application Support/mame/roms/mecb6809/mecb6809.bin"

```
In another terminal emulator, MAME can be run with a command line like:
```bash
./mecb6809 mecb6809 -rs232 pty -window -resolution 640x480 -debug
```
The pseudo terminal created by MAME, can be found in the MAME settings (via pressing the tab key).
In another terminal emulator use this information to start a minicom session.
```bash
minicom -D /dev/ttys006 -b115200 -8
```

## Automation Script

This process becomes tedious for executing all of the glossary tests,  
so Claude was asked to solve the associated problems 
and to manifest this in an automation script.

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
   from the serial connection and writes them to a log file p;er glossary section.

For an easy setup satisfy the list of dependencies in the header of run_all_tests.sh.
The default configuration has the automation files in the same directory as 
the forth6809.asm and unit_tests.asm files. Override the defaults by providing new 
values as parameters from the command line. Ensure the bash script execute bit is set.

On MacoS a permissions error may be reported, in which case run:
```bash
bash "./run all tests.sh" --mame-bin=$HOME/git/mame0288/mecb6809
```