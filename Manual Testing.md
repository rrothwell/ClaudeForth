# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| *Tools* |        |      |                       |:white_check_mark:|
| .  | DOT     | 0 (0)  | ` ok1234 .1234`<br />`ok`             |:white_check_mark:|
| .S | DOTS    | 0 (0)  | ` ok1 2 3 4 5`<br />`ok.S5 4 3 2 1`<br />`ok` |:white_check_mark:|
| *Stack manipulation* |        |      |                       |:white_check_mark:|
| DUP | DUP     | 0 (0)  | ` ok2 DUP .S2 2`<br />`ok`          |:white_check_mark:|
| Compilation | WORD     | 2 (8)  | `ok: W0 3 . ;`<br />`okW03`|:white_check_mark:|
| CONSTANT    | CONSTANT | 1 | `ok5 CONSTANT C0`<br />`okC0 .5`|:white_check_mark:|
| DO I LOOP   | DOTEST IWORD | 3(12) |`ok: lpy 10 3 DO I . LOOP ;`<br />`oklpy3 4 5 6 7 8 9`|:white_check_mark:|
