# MAME MECB 6809 Testing

The MAME display/console window is inadequate for downloading code,
so a serial connection from an mecb6809 instance to a serial 
terminal application is established.
Following the instructions in [epaell MECB](https://github.com/epaell/MECB/blob/main/MAME/readme.md):
```
cd $HOME/git/mame0288
# Remove old bitbanger device if it exists.
rm ./comms
# Start MAME with the mecb6809 driver and rom file.
# also defining the window size 
# and creating the bitbanger device in the same directory as the MAME instance.
./mecb6809 mecb6809 -window -resolution 640x480 -rs232 null_modem -bitb domain./comms
# Connect to the terminal.
minicom -D unix#./comms
```
Doesn't work.

Instead:

```
# Verify the pty slot is available.
cd $HOME/git/mame0288
./mecb6809 -listslots
# Yes its there, so startup MAME to open the connection.
./mecb6809 mecb6809 -rs232 pty 

```

With the MAME window forward, type the TAB key 
to show the internal user interface menu.
* Activate the Pseudo Terminals option to reveal the created RS232 device.
* Activate the Machine Configuration option to reveal the RS232 parameters including the baud rate. 
Set the baud rate to 115200, xon/xoff hand shaking, 8 bits, no parity, 1 stop bit
then reset the system.

Create a new MacOS terminal window and create a screen 
connected to the other end of the created RS232 device.

```
screen /dev/ttys001 115200,cs8,ixon,ixoff
```

ASSIST 09 can now be tested.

When finished exit using: __CTRL + A__, __CTRL + \__.

Also see [The State of Me](https://blog.thestateofme.com/2022/05/25/attaching-a-terminal-emulator-to-a-mame-serial-port/)