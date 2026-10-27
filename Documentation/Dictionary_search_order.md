# Proposed Forth Dictionary Ordering

## Introduction

The intent is to improve the speed of compilation  
by reducing the search time for frequently used dictionary words.
To this end commonly used words should be near the head of the linked list
and words rarely used should be near the tail of the list.

For the sake of reading the assembly code, 
the link order and the dictionary entry order should be the same. 

## Ordering

The proposed ordering from head to tail is as follows:
1. 3.16 Comments - especially \
1. 3.2 Stack Manipulation — Data Stack - especially DIUP, DROP, SWAP, OVER and ?DUP.
1. 3.4 Arithmetic — Single Cell - especially the simple addition and subtraction words.
1. 3.7 Comparison
1. 3.8 Control Flow — Conditionals & Loops
1. 3.6 Logic, Shifts & Address Arithmetic
1. 3.11 Memory - especially @ and !.
1. 3.13 Numeric Output, especially . (DOT)
1. 3.1 System / Console I/O - especially ." and SPACE
1. 3.15 Exception Handling
1. 3.3 Stack Manipulation — Return Stack
1. 3.5 Arithmetic — Mixed & Double Precision
1. 3.12 Strings & Parsing
1. 3.10 Compiling Words
1. 3.9 Defining Words
1. 3.17 Environmental & System Queries
1. 3.18 Tools