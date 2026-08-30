# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Conditionals & Loops** |        |      |                       ||
| IF   | IF | 0(0) |`ok : ify 6 0> IF ." 6 gt 0." ;`<br />`ERROR -22`|:white_check_mark:|
| IF THEN   | IF THEN | 0(0) |`ok : ify 6 0> IF ." 6 gt 0." THEN ;`<br />`ok ify6 gt 0.`<br />`ok`|:white_check_mark:|
| IF ELSE THEN   | IF ELSE THEN | 0(0) |`ok : ify 0> IF ." gt 0." ELSE ." lt or eq 0." THEN ;`<br />`ok 7 ify gt 0.`<br />`ok -6 ify lt or eq 0.`<br />`ok`|:white_check_mark:|
| IF ELSE THEN   | IF ELSE THEN | 0(0) |`ok : ify 0> IF ." gt 0." ELSE ." lt or eq 0." THEN ;`<br />`ok 7 ify gt 0.`<br />`ok -6 ify lt or eq 0.`<br />`ok`|:white_check_mark:|
| DO I LOOP   | DOTEST IWORD | 3(12) |`ok: lpy 10 3 DO I . LOOP ;`<br />`oklpy3 4 5 6 7 8 9`|:white_check_mark:|
| DO J LOOP   | DOTEST JWORD | 3(12) |`: MULT-TABLE CR 11 1 DO 11 1 DO J  .  LOOP CR LOOP ;`<br />`okMULT-TABLE`<br />`11 11 11 11 11 11 11 11 11 11...`<br />`ok`|:negative_squared_cross_mark:[^1]|
| DO LOOP   | DO LOOP | 0(0) |`ok : lpy 0 DO ." X" LOOP ;`<br />`ok3 lpy XXX`<br />`ok`|:white_check_mark:|
| ?DO LOOP   | QDO LOOP | 0(0) |`ok : lpy 0 ?DO ." Y" LOOP ;`<br />`ok 0 lpy`<br />`ok 2 lpyYY`<br />`ok`|:white_check_mark:|
| DO I +LOOP   | DO IWORD PLUSLOOP | 0(0) |`ok: lpy 4 DO I . 2 +LOOP ; `<br />`ok 6 lpy 4`<br />`ok 9 lpy 4 6 8`<br />`ok`|:white_check_mark:[^2]|
| DO I LEAVE LOOP   | DO IWORD LEAVE LOOP | 0(0) |`: lpy 0 DO I DUP . 2 > IF LEAVE THEN LOOP ; `<br />`ok3 lpy 0 1 2`<br />`ok4 lpy 0 1 2 3`<br />`ok5 lpy 0 1 2 3`<br />`ok`|:white_check_mark:|
| BEGIN UNTIL   | BEGIN UNTIL | 0(0) |`ok : lpy BEGIN TRUE UNTIL ;`<br />`ok lpy`<br />`ok.S`<br />`ok`|:white_check_mark:|
| BEGIN UNTIL   | BEGIN UNTIL | 0(0) |`ok : lpy 2 BEGIN DUP . 1- DUP 0= UNTIL DROP ;`<br />`ok lpy2 1`<br />`ok.S`<br />`ok`|:white_check_mark:|
| BEGIN LEAVE UNTIL   | BEGIN LEAVE UNTIL | 0(0) |`ok : lpy 4 BEGIN DUP . 1- DUP 2 = IF LEAVE THEN DUP 0= UNTIL DROP ;`<br />`ok lpy 4 3 2 1 6809 FORTH v1.0`|:white_check_mark:[^3]|
| BEGIN IF EXIT THEN AGAIN   | BEGIN IF EXIT THEN AGAIN | 0(0) |`ok : lpy 4 BEGIN DUP . 1- DUP 2 = IF DROP EXIT THEN AGAIN ;`<br />`ok lpy 4 3`<br />`ok .S`<br />`ok`|:white_check_mark:|
| BEGIN WHILE REPEAT | BEGIN WHILE REPEAT | 0(0) |`ok: lpy 4 BEGIN DUP . 1- DUP 2 >  WHILE REPEAT DROP ;`<br />`ok lpy 4 3`<br />`ok .S`<br />`ok`|:white_check_mark:|
| IF ELSE RECURSE THEN | IF ELSE RECURSE THEN  | 0(0) |`ok : factorial  DUP 2 < IF DROP 1 ELSE DUP 1- RECURSE * THEN ;`<br />`ok 1 factorial . 1`<br />`ok 2 factorial . 2`<br />`ok 3 factorial . 6`<br />`ok .S`<br />`ok`|:white_check_mark:|
| IF UNLOOP EXIT THEN LOOP | IF UNLOOP EXIT THEN LOOP | 0(0) |`: find3  DO  I 3 = IF I UNLOOP EXIT THEN LOOP 0 ;`<br />` ok 10 0 find3 ?6809 FORTH v1.0`|:negative_squared_cross_mark:[^4]|
| IF ELSE RECURSE THEN | IF ELSE RECURSE THEN | 0(0) |`ok : factorial  DUP 2 < IF DROP 1 ELSE DUP 1- RECURSE * THEN ;`<br />`ok 1 factorial . 1`<br />`ok 2 factorial . 2`<br />`ok 3 factorial . 6`<br />`ok .S`<br />`ok`|:white_check_mark:|
| CASE OF ENDOF ENDCASE | CASE OF ENDOF ENDCASE | 0(0) |`: digit-name CASE 0 OF ." zero" ENDOF 1 OF ." one" ENDOF ROT DROP ." other" ENDCASE ;`<br />`ERROR -22`|:negative_squared_cross_mark:[^5]|


[^1]: J is returning the outer loop limit value, not the outer loop index value. 
      Via MAME the offset in the return stack should be 8,                                                   
     A bugfix is coming. 
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
