# MAME Installation notes on Intel Mac

Install MAME using Homebrew via the Terminal:
```
brew install mame
brew install rom-tools
```

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
<span style="color:green">
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
</span>



The instructions followed are from [MAME on Macs](https://mameonmacs.blogspot.com/2025/12/mame-via-homebrew-on-macs-finally-there.html)