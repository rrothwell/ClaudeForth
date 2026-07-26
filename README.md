# ClaudeForth
An ANS forth for the MC6809 microprocessor, 
generated using the iPhone Claude app. 

This is a subroutine threaded forth.
It is designed to be ROMable 
and to target the Minimalist Eurocard Board (MECB) 6809 computer, 
with the MECB IO card providing an
MC6850 ACIA for serial IO.

## Progress

| Item             | Completed   |
|:-----------------|------------:|
|Initial soecification and code generation|- [x]|
|Initial documentation|- [x]|
|Resolve assembler bugs, missing labels and dictionary entries, fix memory map overlaps & gaps|- [x]|
|Manual tests & tests against ANS test suite|- [x]|
|Develop a simple forth application|- [x]|
|Refine the documentation|- [x]|

## Assets

+ Documentation
+ A unified assembler file.
+ A collection of assembler files
  obtained by splitting the above file.
+ A file listing remaining issues.
+ The ANS test suit.

![alt Memory Map](forth6809_memory_map.svg)

