# MAME MECB 6809 Serial Testing

The .bin file for the forth code has been compile with mecb6809 as the target.
To build after generating the forth6809.asm file and downloading it via Claude:
```bash
cd $HOME/git/mame0288
lwasm --6809 --format=raw --output=forth6809.bin forth6809.asm
```
For more details see the build section in [ClaudeForth_preview](https://github.com/rrothwell/ClaudeForth/blob/master/ClaudeForth_preview.pdf)

Copy this file into the roms directory packaged in a folder of the same name,
```bash
mkdir $HOME/Library/Application\ Support/mame/roms/mecb6809
cp $HOME/git/ClaudeForth/forth6809.bin  $HOME/Library/Application\ Support/mame/roms/mecb6809/mecb6809.bin
cd $HOME/git/mame0288/
./mecb6809 mecb6809 -rs232 pty -window -resolution 640x480 -debug
```
The forth6809.bin file has to be renamed to mecb6809.bin,
 otherwise the mecb6809 driver does not recognise the rom file.

In another terminal
```bash
minicom -D /dev/ttys001 -b115200 -8
```
Forth6809 failed to start. 
An investigation with the debugger shows that memory is scrambled,
 as is the forth6809.bin binary file contents, 
 with the vectors at the start of the data instead of the end
 and other data in the wrong place.
 
In another terminal, check the binary file contents,
```bash
hexdump -C $HOME/git/ClaudeForth/forth6809.bin
```
 Suspect an assembler bug not laying out ORG blocks correctly, 
 so reorganised the assembler source file contents in memory order.
 Claude was asked to reorder the forth6809.asm file.

The reassembled forth6809.asm file was checked again with hexdump.
Most of the issues are fixed.

The vectors are however displaced from the end of the file.
It appears that the assembler will generate the .lst file
with the instructions having the correct addresses, 
but the binary opcodes will be placed into the .bin file sequentially,
filling the gaps established by the ORG directives. 
To solve this problem requires either packing the code with no gaps,
or using the FILL directive to place $FF in the gaps.

In addition the FILL directive was used to pad the empty ROM area from 
$C100 to BASEDICT at $D83F. The ROM file then has the corect size expected
by the driver so the opcodes with be properly located, butting at top of memory.
Evidently the driver is coded to not overlay the IO area containingf the ACIA.