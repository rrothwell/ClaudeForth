# MAME Installation notes on Intel Mac

MAME as of July 2026, version 0.288, does not have drivers 
for the MECB 6809 provided as part of the offical distribution. 
However the contributor "epaell" is working on building 
a custom version with [mecb6809](https://github.com/epaell/MECB/tree/main/MAME) support.

Install MAME using Homebrew via the Terminal:
```
brew install mame
brew install rom-tools
```
Note: [ROM Tools](https://chdman.com) might be useful for fixing checksums.

Setup MAME with a modified directory structure
to isolate user data from future MAME upgrades 
performed via Homebrew.
This requires the generation of a mame.ini file 
and adjustments to the paths in this file.

```
# create a temporary directory that can be deleted afterwards.`
mkdir $HOME/Games
mkdir $HOME/Games/mame
cd HOME/Games/mame
mame -cc
ls -al
```

Modify the mame.ini file shown as follows:
```
#
# CORE SEARCH PATH OPTIONS
#
homepath                  "$HOME/Library/Application Support/mame/"
rompath                   "$HOME/Library/Application Support/mame/roms"
hashpath                  /usr/local/share/mame/hash
samplepath                "$HOME/Library/Application Support/mame/samples"
artpath                   "$HOME/Library/Application Support/mame/artwork"
ctrlrpath                 "$HOME/Library/Application Support/mame/ctrlr"
inipath                   "$HOME/Library/Application Support/mame;$HOME/.mame;.;ini"
fontpath                  "$HOME/Library/Application Support/mame/fonts"
cheatpath                 "$HOME/Library/Application Support/mame/cheat"
crosshairpath             "$HOME/Library/Application Support/mame/crosshair"
pluginspath               /usr/local/share/mame/plugins
languagepath              /usr/local/share/mame/language
swpath                    "$HOME/Library/Application Support/mame/software"

#
# CORE OUTPUT DIRECTORY OPTIONS
#
cfg_directory             "$HOME/Library/Application Support/mame/cfg"
nvram_directory           "$HOME/Library/Application Support/mame/nvram"
input_directory           "$HOME/Library/Application Support/mame/inp"
state_directory           "$HOME/Library/Application Support/mame/sta"
snapshot_directory        "$HOME/Library/Application Support/mame/snap"
diff_directory            "$HOME/Library/Application Support/mame/diff"
comment_directory         "$HOME/Library/Application Support/mame/comments"
share_directory           /usr/local/share/mame/share
```

Create the directory structure as follows:
```
cd $HOME/Library/Application\ Support/mame
mkdir artwork
mkdir cabinets
mkdir cheat   
mkdir cfg   
mkdir comments 
mkdir cpanel  
mkdir crosshair
mkdir ctrlr    
mkdir diff 
mkdir fonts
mkdir hiscore
mkdir ini    
mkdir inp
mkdir marquees
mkdir nvram   
mkdir roms 
mkdir samples
mkdir snap   
mkdir software
mkdir sta     
mkdir videosnaps
```

Move the mame.ini file to its new home:
```
mv $HOME/Games/mame/mame.ini $HOME/Library/Application\ Support/mame
```

Start mame:
```
mame
```


The instructions followed above are from: 
[MAME on Macs](https://mameonmacs.blogspot.com/2025/12/mame-via-homebrew-on-macs-finally-there.html)

Test the installation against the Grant Searle minimalist 6809 emulation.
The manufacturer is listed under "Grant Searle", 
the long name is "Simple 6809 Machine",
the short name is gs6809.

As the driver is already present, only the ROM file needs to be provided 
and copied into the ROM directory as a .bin file that has been zipped.
The ROM file containing a monitor (ASSIST09) and Basic language (Microsoft Basic)
is distributed by Jeff Tranter as a [combined](https://github.com/jefftranter/6809/tree/master/sbc/combined) hex file.

Download the .hex file (text format) and convert it into a .bin file,
then .zip file and move it into the MAME rom directory:
```
cd $HOME/git
git clone https://github.com/jefftranter/6809.git
cd 6809
cd sbc
cd combined
brew install binutils
/usr/local/opt/binutils/bin/objcopy --input-target=ihex --output-target=binary combined.hex gs6809.bin
cp gs6809.bin $HOME/Library/Application\ Support/mame/roms
cd $HOME/Library/Application\ Support/mame/roms
zip gs6809.zip gs6809.bin
mame gs6809
```
If succesfull ASSIST09 should present itself in the MAME window.