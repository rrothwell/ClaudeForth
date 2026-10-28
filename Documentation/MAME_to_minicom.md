# Communications setup between MAME & minicom for hardware handshaking

If the measures below don't improve MAME's character reception reliability. 
check for competition from background processes such as zombie minicom instances,
operating system updates and virus checker activity.

This can be solved by increasing MAME's priority.
For example, on MacOS:
```bash
sudo renice -n -10 -p 1462
```
Substitute your local MAME PID for 1462.



Startup MAME, use the TAB key to open the configuration menu.
Select the Machine Configuration menu and then set the baud rate and handshaking mode 
to 57600 and RTS/CTS.
This is more effective than handshaking managed by hardware running in the emulated CPU.
Shut down MAME so it saves the same configuration for next time.

In a terminal, just once, create a configuration file for minicom:
```bash
vi ~/.minirc.57600_RTSCTS

pu port             /Users/richardrothwell/mame-pty
pu lock             /usr/local/Cellar/minicom/2.11.1/var
pu baudrate         57600
pu bits             8
pu parity           N
pu stopbits         1
pu escape-key       Escape (Meta)
pu rtscts           No
pu xonxoff          Yes
pu msg_ch_delay     20
pu msg_nl_delay     100
```

In another terminal:
```bash
socat PTY,link=$HOME/mame-pty,raw,echo=0,crtscts=1 TCP-LISTEN:11185,reuseaddr
```

In another terminal:
```bash
minicom 57600_RTSCTS
```

In yet another terminal:
```bash
./mecb6809 mecb6809 -rs232 \
   null_modem -bitb socket.127.0.0.1:11185  \
   -throttle  \
   -window -resolution 640x480 -debug
```
socat will now continue running as long as MAME is runnng.

Beware of zombie minicom processes running.

# Communications setup between MAME & minicom for software handshaking

Startup MAME, use the TAB key to open the configuration menu.
Select the Machine Configuration menu and then set the baud rate and handshaking mode 
to 57600 and XON/XOFF.
This is more effective than handshaking managed by software running in the emulated CPU.
Shut down MAME so it saves the same configuration for next time.

In a terminal, just once, create a configuration file for minicom:
```bash
vi ~/.minirc.57600_XONXOFF

pu port             /Users/richardrothwell/mame-pty
pu lock             /usr/local/Cellar/minicom/2.11.1/var
pu baudrate         57600
pu bits             8
pu parity           N
pu stopbits         1
pu escape-key       Escape (Meta)
pu rtscts           No
pu xonxoff          Yes
pu msg_ch_delay     20
pu msg_nl_delay     100
```
In another terminal:
```bash
socat PTY,link=$HOME/mame-pty,raw,echo=0,ixon=1,ixoff=1 TCP-LISTEN:11185,reuseaddr
```

In one terminal:
```bash
minicom 57600_XONXOFF
```

In yet another terminal:
```bash
./mecb6809 mecb6809 -rs232 \
   null_modem -bitb socket.127.0.0.1:11185  \
   -throttle  \
   -window -resolution 640x480 -debug
```
socat will now continue running as long as MAME is runnng.

Beware of zombie minicom processes running.


