# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Conditionals & Loops** |        |      |                       ||
| IF   | IF | 0(0) |`ok : ify 6 0> IF ." 6 gt 0." ;`<br />`ERROR -22`|:white_check_mark:|
| IF THEN   | IF THEN | 0(0) |`ok : ify 6 0> IF ." 6 gt 0." THEN ;`<br />`ok ify6 gt 0.`<br />`ok`|:white_check_mark:|
| IF ELSE THEN   | IF ELSE THEN | 0(0) |`ok : ify 0> IF ." gt 0." ELSE ." lt or eq 0." THEN ;`<br />`ok 7 ify gt 0.`<br />`ok -6 ify lt or eq 0.`<br />`ok`|:white_check_mark:|
| IF ELSE THEN   | IF ELSE THEN | 0(0) |`ok : ify 0> IF ." gt 0." ELSE ." lt or eq 0." THEN ;`<br />`ok 7 ify gt 0.`<br />`ok -6 ify lt or eq 0.`<br />`ok`|:white_check_mark:|
| DO I LOOP   | DOTEST IWORD | 3(12) |`ok: lpy 10 3 DO I . LOOP ;`<br />`oklpy3 4 5 6 7 8 9`|:white_check_mark:|
| DO LOOP   | DO LOOP| 0(0) |`ok : lpy 0 DO ." X" LOOP ;`<br />`ok3 lpy XXX`<br />`ok`|:white_check_mark:|
| ?DO LOOP   | QDO LOOP| 0(0) |`ok : lpy 0 ?DO ." Y" LOOP ;`<br />`ok 0 lpy`<br />`ok 2 lpyYY`<br />`ok`|:white_check_mark:|
| DO I +LOOP   | DO IWORD PLUSLOOP| 0(0) |`ok: lpy 4 DO I . 2 +LOOP ; `<br />`ok 6 lpy 4`<br />`ok 9 lpy 4 6 8`<br />`ok`|:white_check_mark:[^1]|
| DO I LEAVE LOOP   | DO IWORD LEAVE LOOP| 0(0) |`: lpy 0 DO I DUP . 2 > IF LEAVE THEN LOOP ; `<br />`ok3 lpy 0 1 2`<br />`ok4 lpy 0 1 2 3`<br />`ok5 lpy 0 1 2 3`<br />`ok`|:white_check_mark:|


[^1]: If the start and limit indices are the same there is an infinite loop.                                                    
  
