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

There is also an ENVIRONMENT? query to establish 
the existence of the word list collection of words.
It does not confirm the existence of individual words.
The query key used for this purpose is the string "WORDLISTS".


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
This addressed location contains the pointer to the wordlist's latest word.

An array of 8 cells (LATEST-PTRS) plus a byte count cell (#LATEST-PTR)
provides for 8 wordlists. The initial contents 
will be initialised from the wordlist information stored
in the ROM wordlist. 

Creating a new word list (WID)is just a matter 
of incrementing the count and zeroing the newly addressed location. 
When adding a new word to this new wordlist in the dictionary,
the first new word becomes a fence word with zero signifying 
the last link for SEARCH-WORDLIST.

The search order can be specified by the contents of 
another array of 8 cells (WIDS) and a byte cell count (#WID).
The contents of the array are the WID's.
Managing the search order via GET-ORDER/SET-ORDER then becomes a 
matter of copying this array to the stack and back.
The WID's point back to the corresponding memory location 
containing the latest pointer.

The separate cell location can be the WID of the ROOT wordlist.
The GET-ORDER/SET-ORDER implementation ignores this location.
In this way the ROOT wordlist is always available and searched first.
This means it cannot be shadowed by subsequent definitions in other wordlists.

The search order array is allowed to contain duplicate WID's.

## Pseudo-code

### Options


#### Initialisation

    Zeros LATEST-PTRS, #LATEST, WIDS, #WID.
    
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
    The contents are then determined by the LATEST pointers of the different
    wordlists in the dictionary. 
    
    The initialization code at startup copies the ROM ROOT WID cell contents
    into ROM ROOT WID cell and the ROM WID array into the RAM WID array.
    #LATEST is set to 1 as the initial count will be the 
    one occupied FORTH dictionary. This value can be compared directly to the maximum
    cell count of 8 to ensure the array does not overflow.
    
    The initialisation routines also need to setup the search order in RAM 
    initially with the FORTH WID.
    
#### Create a Wordlist

WORDLIST

    Increment the #LATEST and return the address it points to.
    
    The implementation proposed assigns #LATEST to be a byte count
    of pointers in the LATEST-PTRS array. 
    Accessing an element in the array will typically be done 
    for the WID acting as a cell address.
    
    Adding an element/creating a WID means taking the count value, 
    subracting 1 to convert it into an array index, doubling the value, and then adding
    the starting address of the array. Thats the WID.
    This address is then cleared as a double.
    The count value is then incremente by 1. 

    On the other hand the code might be more compact 
    if pointer arithmetic was used throughout.
    Then the end of the LATEST-PTRS array can be stored 
    as a cell memory pointer called LASTEST-END instead of a byte count. 
    Adding an element/creating a WID means taking the LASTEST-END value, 
    and adding 2 to convert it into an array pointer. Thats the WID.
    This address is then cleared as a cell.
    A count value is then not needed. 
    
    Deleting a WID does not make much sense 
    once words have been defined in that wordlist.

#### Return the WID of the Principal Wordlist

FORTH-WORDLIST

    Place constant value of WID on stack.
    This would be the first WID address location.
    
#### Return the WID of the ROOT Wordlist.

ROOT  
  
    ROOT simply replaces the top item in the search list.
    It does not return the WID on the stack.
    
    In principle the ROOT wordlist should be unable to be deleted 
    from the search order for safety sake. 
    On the contrary in GForth ROOT can be deleted and then the system is 
    unrecoverable. This was proven by experiment.
        
    In the proposed implementation ROOT is a special WID slot.
    It is represented by a vocabulary.
    
    ROOT is always present in the search order.
    It is always searched last as it is a collection 
    of developer utilities and it should not be allowed to slow
    application compilation. 
    However as duplicates are allowed, in special circumstances,
    a duplicate can be placed at the head of the search order.
    
    It principle the words in ROOT can be shadowed, 
    but this is deemed to be unlikely and manageable.
    
    The words that are present in ROOT include:
    WORDLIST, FORTH-WORDLIST, GET-ORDER,  SET-ORDER,  
    FIND,  SEARCH-WORDLIST,  
    GET-CURRENT, SET-CURRENT & DEFINITIONS. 
    Presumably the extension words are also included:
    ONLY, PREVIOUS, ALSO, FORTH, ORDER & VOCABULARY.
   
        
#### Manipulate the Search Order

GET-ORDER/SET-ORDER

    Get order retrieves the WID's from the search order array
    and places them on the stack with the count.
    Manipulating the items on the stack produces a new search order.
    
    Set order stores the modified stack content back into the search order array.
    Duplicates are accepted.
    A size mismatch should thrown an exception.
    
    On calling set order, if the stack is empty of WID's and size is -1, 
    then the minimum search order is applied. This is the FORTH WID, 
    with the ROOT WID requiring no action, as it is always 
    implicitly in the search order.
    
    On calling set order, if the stack is empty of WID's and size is 0, 
    then the search order is emptied. The ROOT WID is still accessible, 
    as it is always implicitly in the search order. This behavior needs
    to be documented as standards non-complient in the glossary.
    
    For search order array transfer, to/from the stack, a simple copy of the count 
    followed by a simple move loop using autoindexing is all that is required. 
    
    On the other hand the code might be more compact if pointer arithmetic was used
    throughout, with the count being calculated in a register on the fly.
    Then the end of the search order array can be stored 
    as a cell memory pointer instead of a byte count. 
    
    The stack effect of GET-ORDER with the search order is:
    – WIDN(last) .. WID1(first) N(count/TOS).
    Pushing items onto the stack uses decrement addressing, 
    so the stack grows towards low memory as the last to first item is 
    transfered. 
    
    In the WID array, if the first WID to be searched is the last WID added,
    it can be assumed that it grows the search list towards high memory.
    Then the array would be traversed 
    from low to high memory during GET-ORDER.

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
    LATEST-PTRS array.

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

    Retrieve the search order using GET-ORDER, 
    use stack operations to duplicate the top WID on the stack,
    then update the search order using SET-ORDER.
    
    Implemented as : ALSO GET-ORDER OVER SWAP 1+ SET-ORDER ;
    Throws a -49 exceptiopm when the order array is full.
    
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
			@  >R     ( wid )
			GET-ORDER NIP  
			R> SWAP    ( wid... -- ... wid )
			SET-ORDER 
	;
    

## Implementation Decisions

### Predefined Wordlists

Wordlists predefined in GForth are:

- ROOT
- FORTH

Only ROOT and FORTH are added to the search order automatically.
In this implementation the same policy is applied.

ENVIRONMENT-WORDLIST is also defined in Gforth,
but not automatically added to the search order.
 
Its not clear how ENVIRONMENT-WORDLIST is supposed to be used.
It is suggested that the current implementation of ENVIRONMENT?
be kept as a table lookup and that the ENVIRONMENT-WORDLIST
be excluded from the implementation. 
This decision would need to be described in the documentation. 

### Marker

Marker is typically used during development with the 
most common use case being the rollback of a coding dead-end.
This suggests a simple prune of the CURRENT wordlist is all that is required.

Supporting more complex and robust rollback schemes occurs in more 
sophisticated systems like GForth, but this is inappropriate here 
as the target is an 8 bit system with limited memory.

I am hoping that a minimal change to the 
existing implementation will be sufficient.

In the case of MARKER deleting a portion of a wordlist 
containing a vocabulary word definition, that vocabulary 
is no longer findable by name, but the WID still exists.
That means its words are still in the search order 
and can be compiled as part of new words. 

The impact of executing MARKER
is limited as its a development problem, not a run time problem.
On the face of it no special action is required. 

Dealing with it by scanning the MARKER's wordlist and flagging vocabularies
in the chain and then throwing an exception seems difficult.

### Search order and Errors

The most likely error is attempting to alter the search order via SET-ORDER
and passing in an invalid WID due to a stack manipulation error.
Therefore it makes sense to validate any numbers being used as WID's.
The predefined [ANS Forth](https://forth-standard.org/standard/exception) 
exception codes are:
| Code | Name | Meaning         |
| ---- | ---- | -------         |
| -49  | search-order overflow  | An attempt was made to overfill the search order. |
| -50  | search-order underflow | An attempt was made to empty the search order. |
| -11  | result out of range    | An attempt was made to use an invalid WID. |

Note: The LATEST-PTRS and WIDS array sizes are defined with different sizes
that just happen to be 8. 

### Order

Lets see if a 2 cell parallel array pointing to the 
vocabulary NFA makes sense, print that name and print the raw
WID when a WID has no corresponding name.
