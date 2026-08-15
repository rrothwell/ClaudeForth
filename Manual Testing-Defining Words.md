# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Defining Words** |        |      |                       ||
| : ;   | COLON SEMICOLON | 0(0) |`ok : defy ." Hi " ;`<br />`ok defy Hi`<br />`ok`|:white_check_mark:|
| CREATE DOES>   | CREATE DOESGT | 1(1) |`: ENUM CREATE , DOES> @ ;`<br />`ok 17 ENUM e0`<br />`ok e0 .S 28690`<br />`ok`|:negative_squared_cross_mark:[^1]|
| VARIABLE   | VARIABLE | 0(0) |`ok VARIABLE v3 4444 v3 !`<br />`ok VARIABLE v3 4444 v3 !`<br />`ok`|:white_check_mark:|
| CONSTANT   | CONSTANT | 0(0) |`ok333 CONSTANT c0`<br />`ok c0 .333`<br />`ok`|:white_check_mark:|
| VALUE   | VALUE | 0(0) |`ok 222 VALUE v7`<br />`ok v7 .S 222`|:white_check_mark:|
| TO   | TO | 0(0) |`333 TO v7`<br />`ok v7 .S 333 222`<br />`ok`|:white_check_mark:|
| 2VARIABLE   | DO LOOP | 0(0) |`ok : lpy 0 DO ." X" LOOP ;`<br />`ok3 lpy XXX`<br />`ok`|:white_check_mark:|
| 2CONSTANT   | QDO LOOP | 0(0) |`ok : lpy 0 ?DO ." Y" LOOP ;`<br />`ok 0 lpy`<br />`ok 2 lpyYY`<br />`ok`|:white_check_mark:|
| BUFFER:   | DO IWORD PLUSLOOP | 0(0) |`ok: lpy 4 DO I . 2 +LOOP ; `<br />`ok 6 lpy 4`<br />`ok 9 lpy 4 6 8`<br />`ok`|:white_check_mark:[^2]|
| DEFER   | DO IWORD LEAVE LOOP | 0(0) |`: lpy 0 DO I DUP . 2 > IF LEAVE THEN LOOP ; `<br />`ok3 lpy 0 1 2`<br />`ok4 lpy 0 1 2 3`<br />`ok5 lpy 0 1 2 3`<br />`ok`|:white_check_mark:|
| DEFER@   | BEGIN UNTIL | 0(0) |`ok : lpy BEGIN TRUE UNTIL ;`<br />`ok lpy`<br />`ok.S`<br />`ok`|:white_check_mark:|
| DEFER!   | BEGIN UNTIL | 0(0) |`ok : lpy 2 BEGIN DUP . 1- DUP 0= UNTIL DROP ;`<br />`ok lpy2 1`<br />`ok.S`<br />`ok`|:white_check_mark:|
| IS   | BEGIN LEAVE UNTIL | 0(0) |`ok : lpy 4 BEGIN DUP . 1- DUP 2 = IF LEAVE THEN DUP 0= UNTIL DROP ;`<br />`ok lpy 4 3 2 1 6809 FORTH v1.0`|:white_check_mark:[^3]|
| ACTION-OF| BEGIN IF EXIT THEN AGAIN | 0(0) |`ok : lpy 4 BEGIN DUP . 1- DUP 2 = IF DROP EXIT THEN AGAIN ;`<br />`ok lpy 4 3`<br />`ok .S`<br />`ok`|:white_check_mark:|
| MARKER | BEGIN WHILE REPEAT | 0(0) |`ok: lpy 4 BEGIN DUP . 1- DUP 2 >  WHILE REPEAT DROP ;`<br />`ok lpy 4 3`<br />`ok .S`<br />`ok`|:white_check_mark:|


[^1]: DOES> is returning a self reference 
      instead of a reference to the numerical value 1 cell further on. 
[^2]: If the start and limit indices are the same there is an infinite loop.                                                    
[^3]: Freeze requiring soft reboot. LEAVE only supports DO/LOOP or DO/+LOOP.                                                
[^4]: Using UNLOOP causes a branch into random memory requiring a warm reboot. 
     It seems that Claude has EXIT also applying UNLOOP behavior, leading to a clash. 
     Violation of the ANS docs. 
     Decided to make UNLOOP a NOOP.
     A bugfix is coming. 
[^5]: Compilation fails reporting ERROR -22. 
     Via MAME this was tracked down to a CSP mismatch reported by SEMICOLON. 
     The mismatch occurs as CASE was placing a spurious 0 on the stack that was never used or consumed.
     A bugfix is coming. 

Extras:
( - ) is not compiling properly inside a colon definition
.R is not printing correctly. Eg, 33 instead of 3.

                                                                       
  