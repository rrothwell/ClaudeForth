\ ============================================================
\ ANS test suite - HEADER and SMUDGE
\ These two words are ClaudeForth extensions, not in the standard.
\ They are the building blocks of CODE ... END-CODE, which is
\ defined here as the first user of them.
\ Requires ttester.fs then 00_test_prelude.fs to be loaded first.
\ Written for this project (forth6809_stage_6i and later).
\ ============================================================
MARKER M34
TEST-BEGIN
DECIMAL

\ ---- CODE and END-CODE built from HEADER and SMUDGE
VOCABULARY TASM
: CODE ( "name" -- ) -1 HEADER ALSO TASM ;
: END-CODE ( -- ) 57 C, SMUDGE PREVIOUS ;

T{ GET-ORDER NIP -> 1 }T
CODE T1 204 C, 0 C, 1 C, 54 C, 6 C, END-CODE
T{ GET-ORDER NIP -> 1 }T
T{ T1 -> 1 }T
T{ T1 T1 + -> 2 }T

\ ---- the word is hidden until SMUDGE (flag true)
CODE T2 57 C,
T{ GET-ORDER NIP NIP -> 2 }T
T{ S" T2" FORTH-WORDLIST SEARCH-WORDLIST -> 0 }T
SMUDGE PREVIOUS
T{ S" T2" FORTH-WORDLIST SEARCH-WORDLIST NIP -> -1 }T
T{ GET-ORDER NIP -> 1 }T

\ ---- flag 0: the word is visible at once
0 HEADER T3 57 C,
T{ S" T3" FORTH-WORDLIST SEARCH-WORDLIST NIP -> -1 }T
T{ ' T3 EXECUTE -> }T

\ ---- the xt is the code address (HERE) at the time of HEADER
HERE 0 HEADER T4 CONSTANT T4HERE
T{ ' T4 T4HERE = -> -1 }T

\ ---- SMUDGE toggles the newest header
: T5 ;
T{ SMUDGE S" T5" FORTH-WORDLIST SEARCH-WORDLIST -> 0 }T
T{ SMUDGE S" T5" FORTH-WORDLIST SEARCH-WORDLIST NIP -> -1 }T

\ ---- HEADER links into the current wordlist
WORDLIST CONSTANT TW
GET-CURRENT TW SET-CURRENT 0 HEADER T6 SET-CURRENT
T{ S" T6" TW SEARCH-WORDLIST NIP -> -1 }T
T{ S" T6" FORTH-WORDLIST SEARCH-WORDLIST -> 0 }T

\ ---- an empty name is not accepted by the system: nothing to test

HEX
TEST-END
M34
