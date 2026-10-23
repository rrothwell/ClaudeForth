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

| ANS Section | Family | Wordlist Words | Addressed? |
| ----------- | -------| -------------- | ---------- |
| 16.6.1.2460 | Create       | WORDLIST |:white_check_mark:|
| 16.6.1.1595 | Fetch        | FORTH-WORDLIST |:white_check_mark:|
| 16.6.1.1647 | Search order | GET-ORDER |:white_check_mark:|
| 16.6.1.2197 | Search order | SET-ORDER |:white_check_mark:|
| 16.6.1.1550 | Search       | FIND |:white_check_mark:|
| 16.6.1.2192 | Search       | SEARCH-WORDLIST |:white_check_mark:|
| 16.6.1.1643 | Compilation  | GET-CURRENT |:white_check_mark:|
| 16.6.1.2195 | Compilation  | SET-CURRENT |:white_check_mark:|
| 16.6.1.1180 | Compilation  | DEFINITIONS |:white_check_mark:|

Then later the extension words:

| ANS Section | Wordlist Words | Addressed? |
| ----------- | -------------- | ---------- |
| 16.6.2.1965 | ONLY |:white_check_mark:|
| 16.6.2.2037 | PREVIOUS |:white_check_mark:|
| 16.6.2.0715 | ALSO |:white_check_mark:|
| 16.6.2.1590 | FORTH |:white_check_mark:|
| 16.6.2.1985 | ORDER |:white_check_mark:|

There are also local additions in implementations like 
[GForth wordlists](https://gforth.org/manual/Word-Lists.html)
for compatibility with existing code. This includes; 

| Wordlist Words | Description | Addressed? |
| -------------- | ----------- |---------- | 
| VOCABULARY | Creates a named word list and replaces the wordlist at the start of the search order. |:white_check_mark:|
| ROOT       | The special wordlist that is always visible. It contains the wordlist words. |:white_check_mark:|

There is also an ENVIRONMENT? query to establish the existence of these words.


## Data Structures

Wordlists are identified by a cell-sized number called a WID.

### Predefined Wordlists.

ClaudeForth is a ROMable forth. 
This means predefined wordlists must also be stored in ROM 
along with the pointer to the head of each wordlist. 
Being able to add words to a predefined word list means the 
head is modifiable, so it must be copied from ROM to RAM at startup.

The simplest scheme manages the wordlists as forth words
stored in the special ROOT wordlist. In the simplest case 
a WID can be defined with a name using CONSTANT or
by using the VOCABULARY defining word.

### Mutable wordlists

A scheme compatible with the use of WID's, has a WID
defined as the address of the memory location in global memory RAM. 
This addressed location contains the wordlist's head pointer.

An array of 8 cells (HEAD-PTRS) plus a byte count cell (#HEAD-PTR)
provides for 8 wordlists. The initial contents 
will be initialised from the wordlist information stored
in the ROM wordlist. 

Creating a new word list (WID)is just a matter 
of incrementing the count and zeroing the new location. 
When adding a new word to this new wordlist in the dictionary,
the first new word becomes a fence word with zero signifying 
the last link for SEARCH-WORDLIST.

The search order can be specified by the contents of 
another array of 8 cells (WIDS) and a byte cell count (#WID).
The contents of the array are the WID's.
Managing the search order via GET-ORDER/SET-ORDER then becomes a 
matter of copying this array to the stack and back.
The WID's point back to the corresponding memory location 
containing the head pointer.

The first cell location can be the WID of the ROOT wordlist.
The GET-ORDER/SET-ORDER implementation ignores this first location.
In this way the ROOT wordlist is always available and searched first.
This means it cannot be shadowed by subsequent definitions in other wordlists.

The search order array is not allowed to contain duplicate WID's.

## Pseudo-code

### Options


#### Initialisation

    Zeros HEAD-PTRS, #HEAD-PTR, WIDS, #WID.
    
    It was initially thought that a traversal of the ROOT dictionary would allow
    the HEAD pointers to be located and then copied to RAM. But there was no 
    simple way found of identifying a wordlist entry 
    except by comparing an artifical XT/CFA value assigned to a WID,
    with the known range of RAM addresses assigned to the WID's.  
    
    This approach would give the XT/CFA value a new meaning 
    in addition to it's meaning as a pointer to code.
    In turn this would create complexity elsewhere, 
    for example in creating other dictionary scanning utilities. 
    
    To avoid the complexity it was decided that a block of 8 cells
    just ahead of the dictionary tail would produce a cleaner implementation.
    The contents are then specified by the head pointers of the different
    wordlists in the dictionary. 
    
    The initialization code at startup simply copies this ROM array into the RAM array.
    
    The initialsation routines also need to setup the search order in RAM 
    with the ROOT and FORTH WID's and possibly the ENVIRONMENT WID.
    
#### Create a Wordlist

WORDLIST
    Increment the #HEAD-PTR and return the address it points to.

#### Return the WID of the Principal Wordlist

FORTH-WORDLIST
    Place constant value of WID on stack.
    This would be the second WID address location after ROOT.
    
#### Return the WID of the ROOT Wordlist.

ROOT    
    ROOT simply adds this item to the search list.
    It does not return the WID on the stack.
    It also ensures that there is only one entry of this kind in the search order.
    
    In principle the ROOT wordlist should be unable to be deleted 
    from the search order for safety sake, 
    but in fact it can be deleted and then the system is 
    unrecoverable, according to experiments with gforth.
    
#### Manipulate the Search Order

GET-ORDER/SET-ORDER
    Get order retrieves the WID's from the search order array
    and places them on the stack with the count.
    Manipulating the items on the stack produces a new search order.
    Set order stores the modified stack content back into the search order array.

#### Search for Word Definitions, Often During Compilation.    

FIND/SEARCH-WORDLIST
    The existing FIND that searches the entire dictionary can be refactored
    to search just the wordlists added to the search order array. 
    Find then iterates over the search order array calling SEARCH-WORDLIST
    for each WID it finds.
    
    
    Part of the refactoring would be to extract and specialise the existing code 
    to search a single word list. This would become SEARCH-WORDLIST.

    Currently FIND begins its search with LATEST. 
    This would become multiple values with each one associated with a WID in the 
    HEAD-PTRS array.

#### Set the Wordlist to which New Words will be Added.

GET-CURRENT/SET-CURRENT/DEFINITIONS
    These words manipulate the value of the variable CURRENT,
    thus controlling the target wordlist for new words.
    CURRENT contains a WID and is used as follows.
    
    When a new forth word is defined a dictionary entry is first created, 
    then the actual code. The creation of a dictionary entry begins by 
    populating the HEADER fields at DPHERE. The LATEST value for the wordlist 
    under consideration, is retrieved via the WID stored in CURRENT.
    Once it is retrieved it is then stored in the 
    link field of the HEADER. 
    Then a new LATEST value is created and used to
    update the value associated with the WID kept in CURRENT.
    
    Subsequently DPHERE is also updated.
    
    DEFINITIONS simply assumes that the wordlist at top of the search order
    is the target for new words, so it copies that WID from the search order array into 
    CURRENT. 

### Extensions

Using only words define above if possible.

ONLY
    Retrieve the search order using GET-ORDER, 
    use stack operations to remove every WID except for ROOT,
    then update the search order using SET-ORDER

PREVIOUS
    Retrieve the search order using GET-ORDER, 
    use stack operations to remove only the top WID, except for ROOT,
    then update the search order using SET-ORDER

ALSO 
    Setup is to place a WID on the stack.   
    Retrieve the search order using GET-ORDER, 
    use stack operations to add the WID to the stack,
    then update the search order using SET-ORDER
    
FORTH
    Retrieve the search order using GET-ORDER, 
    retrieve the FORTH-WORDLIST 
    use stack operations to replace the top WID 
    then update the search order using SET-ORDER
    
ORDER
    Use GET-ORDER to obtain the list of WID's on the stack.
    Iterate over the WID's to look up the names,
    print out the names, drop the WID's from the stack.
    Also use GET-CURRENT to retrieve the WID,
    look up its name, print it 
    and drop the WID.
    
    This process assumes there is a reverse look up from 
    WID to name. The only sensible implementation I can think of is
    a parallel 8 cell array that contains a link to the header of the
    word assigning a name. 
    
### Compatibility

VOCABULARY
    The quick and dirty approach is:
        WORDLIST CONSTANT CVOC1
        : VOCAB1 ( -- )
            GET-ORDER SWAP DROP CVOC1 SWAP SET-ORDER ;

    Using a defining word:
    : VOCABULARY ( "name" -- )
		WORDLIST CREATE , 
		DOES> 
			@        ( wid )
			GET-ORDER SWAP DROP 
			ROT      ( wid... -- ... wid )
			SET-ORDER 
	;
    

## Predefined Wordlists

The wordlists predefined here (via GForth) are:

- ROOT
- FORTH
- ENVIRONMENT-WORDLIST

Only ROOT and FORTH are added to the search order automatically.
Its not clear how ENVIRONMENT-WORDLIST is supposed to be used.