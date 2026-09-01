# MAME MECB 6809 Serial Communications

The MAME display/console window is inadequate for downloading code,
so a serial connection from an mecb6809 instance to a serial 
terminal application is established.
Following the instructions in [epaell MECB](https://github.com/epaell/MECB/blob/main/MAME/readme.md):
```bash
cd $HOME/git/mame0288
# Remove old bitbanger device if it exists.
rm ./comms
# Start MAME with the mecb6809 driver and rom file.
# also defining the window size 
# and creating the bitbanger device in the same directory as the MAME instance.
./mecb6809 mecb6809 -window -resolution 640x480 -rs232 null_modem -bitbanger ./comms
# Connect to the terminal.
minicom -D ./comms -b 115200 -8b 
```
Minicom fails to startup as it is unable to set the baud rate.

The variations with domain and unix# had to be deleted due to other errors.
According to Google: 
> MAME does not natively support creating or binding to a 
> POSIX Local IPC Socket (Unix Domain Socket file) via the command line.

Instead:

```bash
# Verify the pty slot is available.
cd $HOME/git/mame0288
./mecb6809 -listslots
# Yes its there, so startup MAME to open the connection.
./mecb6809 mecb6809 -rs232 pty  -window -resolution 640x480
```

With the MAME window forward, type the TAB key 
to show the internal user interface menu.
* Activate the Pseudo Terminals option to reveal the created RS232 device.
* Activate the Machine Configuration option to reveal the RS232 parameters including the baud rate. 
Set the baud rate to 115200, xon/xoff hand shaking, 8 bits, no parity, 1 stop bit,
then reset the system.

Create a new MacOS terminal window and create a screen 
connected to the other end of the created RS232 device.

```bash
screen /dev/ttys001 115200,cs8,ixon,ixoff
```
When finished exit using: __CTRL + A__, __CTRL + \\__.

OR
```bash
brew install minicom
minicom -D /dev/ttys001 -b115200 -8
```
When finished (on MacOS) exit using: __ESC + Z__, __X__.

ASSIST 09 can now be exercised from the terminal new terminal window/screen.
Start Basic and write FOR NEXT loop:
```bash
G C100
```

Starting Basic continues to be flakey.
However a short Basic program completed successfully.


Also see [The State of Me](https://blog.thestateofme.com/2022/05/25/attaching-a-terminal-emulator-to-a-mame-serial-port/)