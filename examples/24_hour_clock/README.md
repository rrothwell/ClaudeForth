# Interrupt driven 24 hour clock

## Introduction

This example tests a common realtime scenario,
multitasking via interrupt-driven code.

The MECB 6809 is a bus-based card computer that runs at 2 MHz, 
has a complete complement of RAM (48k) and 
has a ROM addressed from $C100 to $FFF (16k).

An IO card provides serial communications, parallel IO, and a timer module.
The IO memory-mapped block assigned to the IO card is $100 bytes beginning at $C000.

The 
[MECB_Motorola_IO schematic](https://github.com/rrothwell/MECB_digicoolthings/blob/main/MECB_Motorola_IO/MECB_Motorola_IO_Schematic.pdf) 
can be found on GitHub.
Visit [Digicool Things](https://digicoolthings.com/minimalist-europe-card-bus-mecb-motorola-i-o-card-sound/) for documentation, updates 
or [purchases](https://www.tindie.com/stores/digicoolthings/?ref=offsite_badges&utm_source=sellers_DigicoolThings&utm_medium=badges&utm_campaign=badge_small).

Serial communications are provided by a MC6850 ACIA chip, 
with hardware handshaking provided by IRQ interrupts
and ring buffers for receive and transmit data streams. 

## Discussion 

### The Timer Hardware

A MC6840 programmable module (PTM) is a triple timer IC 
that is addressed at an offset of $0 in the IO block.

In this example time keeping relies on the MC6840 timer chip,
with its tick set by the system clock (2MHz) from the MECB 6809 card.

Timer 1 can be used already to generate a non-maskable interrupt 
to support the monitor-in-ROM ASSIST09 (not available in the current ROM) breakpoints.
This feature can be enabled by installing a jumper on the PCB. 
Considering its potential usage it is not used in this code.

Timer 2 could be used in this demonstration.
Timer 2 registers are at offsets from the base chip address as follows:
| Offset| Read | Write |
| ----- | ---- |  ---- |
| $1 | Read status                  | Write control             |
| $4 | Read counter                 | Write MSB buffer register | 
| $5 | Read LSB buffer register     | Write latches             |

However time 3 has a prescaler, making the time division code a little simpler.
Therefore timer 3 is used here, though control register access is more complicated.
Timer 3 registers are at offsets from the base chip address as follows:
| Offset| Read | Write |
| ----- | ---- |  ---- |
| $0 | No operation                 | Write control after reset or set bit CR20=0 |
| $1 | Read status                  | Write control CR20=0 to access CR3 |
| $6 | Read counter                 | Write MSB buffer register | 
| $7 | Read LSB buffer register     | Write latches             |

[MC6840 registers](MC6840_registers.png)

[Full datasheet](https://colorcomputerarchive.com/repo/Documents/Datasheets/MC6840%20Programmable%20Timer%20Module%20(Motorola).pdf)

### Interrupt Handler

The machine code for the interrupt handler is patched into
the interrupt chain that begins with the 6809 IRQ vector at address $FFF8.
The serial communications (ACIA) interrupt handler 
is addressed by the contents of the IRQ vector
so it is first in the interrupt handler chain. 

The serial communications handler exits 
in the usual way via an RTI instruction, 
but it reaches that instruction via an indirect branch
through a memory location in page zero, named: IRQCHAIN.
This is the first insertion point for an additional interrupt handler.

Inserting an additional interrupt handler is performed by the sequence:

```
ONLY FORTH
HERE CONSTANT MY-HANDLER
\ Some assembler as opcodes.
HEX
A5 C, A5 C, A5 C, A5 C, A5 C, A5 C, A5 C, A5 C, A5 C, A5 C, 

VARIABLE MY-FOLLOWER
IRQ-CHAIN @ MY-FOLLOWER ! 
MY-HANDLER IRQ-CHAIN !
```
The interrupt handler in this case is written using conventional Motorola mnemonics
and assembled using the lwasm assembler as follows:

```bash
cd $HOME/git/ClaudeForth/examples/24_hour_clock
lwasm --6809 --format=raw \
   --output=irq_handler.bin --list=irq_handler.lst \
   irq_handler.asm

```
The list file is then processed to extract the bare opcodes and formatted 
with C, as above. Then the codes are inserted into the forth source code.

INIT_CLOCK
```
1A C,  50 C,  0F C,  F0 C,  0F C,  F1 C,  0F C,  F2 C,  0F C,  F3 C,  
7F C,  C0 C,  01 C,  86 C,  43 C,  B7 C,  C0 C,  00 C,  CC C,  61 C,  
A7 C,  FD C,  C0 C,  06 C,  86 C,  01 C,  B7 C,  C0 C,  01 C,  7F C,  
C0 C,  00 C,  1C C,  EF C,  39 C,  
```

IRQ_ISR
```     
B6 C,  C0 C,  01 C,  85 C,  04 C,  27 C,  2C C,  FC C,  C0 C,  06 C,  
0C C,  F0 C,  96 C,  F0 C,  81 C,  0A C,  25 C,  20 C,  0F C,  F0 C,  
0C C,  F1 C,  96 C,  F1 C,  81 C,  3C C,  25 C,  16 C,  0F C,  F1 C,  
0C C,  F2 C,  96 C,  F2 C,  81 C,  3C C,  25 C,  0C C,  0F C,  F2 C,  
0C C,  F3 C,  96 C,  F3 C,  81 C,  18 C,  25 C,  02 C,  0F C,  F3 C,  
3B C,  6E C,  9F C,  00 C,  83 C,  
```

DISABLE_CLK_IRQ
```
7F C,  C0 C,  01 C,  86 C,  03 C,  B7 C,  C0 C,  00 C,  86 C,  01 C,  
B7 C,  C0 C,  01 C,  39 C,  
```

ENABLE_CLK_IRQ
```
7F C,  C0 C,  01 C,  86 C,  43 C,  B7 C,  C0 C,  00 C,  86 C,  01 C,  
B7 C,  C0 C,  01 C,  39 C,        
```

RESET_CLK_TICK
```
0F C,  F0 C,  B6 C,  C0 C,  01 C,  FC C,  C0 C,  06 C,  39 C,  
```
### Main Processing and Display Loop


