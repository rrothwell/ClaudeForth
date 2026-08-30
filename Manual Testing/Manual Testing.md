# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Tools*** |        |      |                       ||
| .  | DOT     | 0 (0)  | `ok1234 .1234`<br />`ok`             |:white_check_mark:|
| .S | DOTS    | 0 (0)  | `ok1 2 3 4 5`<br />`ok.S5 4 3 2 1`<br />`okABORT`<br />`ok.S`<br />`ok` |:white_check_mark:|
| ABORT | ABORT    | 0 (0)  | `ok1 2 3 4 5`<br />`ok.S5 4 3 2 1`<br />`ok` |:white_check_mark:|
| **Stack manipulation** |        |      |                       ||
| DUP  | DUP      | 0 (0)  | `ok2 DUP .S2 2`<br />`ok`          |:white_check_mark:|
| DROP | DROP     | 0 (0)  | `ok1 2`<br />`okDROP`<br />`ok.S1`<br />`ok`         |:white_check_mark:|
| SWAP | SWAP     | 0 (0)  | `ok5 9 SWAP .S5 9`<br />`ok`         |:white_check_mark:|
| OVER | OVER     | 0 (0)  | `ok5 9 OVER .S5 9 5`<br />`ok`         |:white_check_mark:|
| ROT  | ROT      | 0 (0)  | `ok5 7 9 ROT .S5 9 7`<br />`ok`         |:white_check_mark:|
| ?DUP  | QDUP    | 0 (0)  | `ok6 7 3 ?DUP .S3 3 7 6`<br />`ok`<br />`ok6 7 3 ?DUP .S3 3 7 6`<br />`ok`|:white_check_mark:|
| **Compilation** |        |      |                       ||
| Define word | WORD     | 2 (8)  | `ok: W0 3 . ;`<br />`okW03`|:white_check_mark:|
| CONSTANT    | CONSTANT | 1 | `ok5 CONSTANT C0`<br />`okC0 .5`|:white_check_mark:|
| DO I LOOP   | DOTEST IWORD | 3(12) |`ok: lpy 10 3 DO I . LOOP ;`<br />`oklpy3 4 5 6 7 8 9`|:white_check_mark:|

Note 1: ABORT needs 2 return key presses.

 ok6 7 3 ?DUP .S3 3 7 6                                                        
  ok
  
   ok6 7 0 ?DUP .S0 7 6                                                          
  ok