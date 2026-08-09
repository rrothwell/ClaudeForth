# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Tools*** |        |      |                       ||
| .  | DOT     | 0 (0)  | `ok1234 .1234`<br />`ok`             |:white_check_mark:|
| .S | DOTS    | 0 (0)  | `ok1 2 3 4 5`<br />`ok.S5 4 3 2 1`<br />`okABORT`<br />`ok.S`<br />`ok` |:white_check_mark:|
| ABORT | ABORT    | 0 (0)  | `ok1 2 3 4 5`<br />`ok.S5 4 3 2 1`<br />`ok` |:white_check_mark:|

Note 1: ABORT needs 2 return key presses.
