# Wordlist Design

## Introduction

The wordlist concept is a simplified scheme 
derived from the original forth vocabulary concept.

Wordlist is an optional implementation in ANS forth,
but it seems to be required here to manage the visibility of word collections 
in developer utilities like ASSEMBLER.

## Scope

It is proposed to implement the minimum set first.

The minimum set of words to be ANS compliant is as follows:

16.6.1.1180 DEFINITIONS
16.6.1.1550 FIND
16.6.1.1595 FORTH-WORDLIST
16.6.1.1643 GET-CURRENT
16.6.1.1647 GET-ORDER
16.6.1.2192 SEARCH-WORDLIST
16.6.1.2195 SET-CURRENT
16.6.1.2197 SET-ORDER
16.6.1.2460 WORDLIST

The extension words are:

16.6.2.0715 ALSO
16.6.2.1590 FORTH
16.6.2.1965 ONLY
16.6.2.1985 ORDER
16.6.2.2037 PREVIOUS

There is also an ENVIRONMENT? query to establish the existence of these words.

There are also local additions in implementations like 
[GForth wordlists](https://gforth.org/manual/Word-Lists.html)
for compatibility with existing code. This includes; 

VOCABULARY - Creates a named word list and replaces the wordlist at the start of the search order.
ROOT - The special wordlist that is always visible. It contains the wordlist words. 

## Data Structures

Wordlists are identified by a cell-sized number called a WID.

### Predefined wordlists.

ClaudeForth is a ROMable forth. 
This means predefined wordlists must also be stored in ROM 
along with the pointer to the head of each wordlist. 
Being able to add words to a predefined word list means the 
head is modifiable so it must be copied from ROM to RAM at startup.

The simplest scheme manages the wordlists as forth words
stored in the special ROOT wordlist.

### Mutable wordlists

A scheme compatible with the use of WID's has a WID
defined as the memory location in global memory RAM 
of the wordlist's head pointer.

A array of 8 cells (HEAD-PTRS) plus a byte count cell (#HEAD-PTR)
provides for 8 wordlists. The initial population 
will be initialised from the wordlist information stored
in the CORE wordlist. 

Creating a new word list (WID)is just a matter 
of incrementing the count and zeroing the new location. 
When adding a new word to this new wordlist in the dictionary,
the first new word becomes a fence word with zero signifying the last link for find.

The search order can be another array of 8 cells (WIDS) and a byte cell count (#WID).
The contents of the array are the WID's.
Managing the search order via GET-ORDER/SET-ORDER then becomes a 
matter of copying this array to the stack and back.
The WID's point back to the corresponding memory location 
containing the head pointer.

# Pseudo-code

## Initialisation

    Zeros HEAD-PTRS, #HEAD-PTR, WIDS, #WID
    Traverses the CORE dictionary and for each wordlist found copies 
    the head pointers into the corresponding RAM location.
    

## Create a Wordlist

WORDLIST
    Increment 

## Return the WID of the principal Wordlist

FORTH-WORDLIST
    Place constant value of WID on stack.
    
## 