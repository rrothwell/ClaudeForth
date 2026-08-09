# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Stack manipulation** |        |      |                       ||
| DUP  | DUP      | 0 (0)  | `ok2 DUP .S2 2`<br />`ok`          |:white_check_mark:|
| DROP | DROP     | 0 (0)  | `ok1 2`<br />`okDROP`<br />`ok.S1`<br />`ok`         |:white_check_mark:|
| SWAP | SWAP     | 0 (0)  | `ok5 9 SWAP .S5 9`<br />`ok`         |:white_check_mark:|
| OVER | OVER     | 0 (0)  | `ok5 9 OVER .S5 9 5`<br />`ok`         |:white_check_mark:|
| ROT  | ROT      | 0 (0)  | `ok5 7 9 ROT .S5 9 7`<br />`ok`         |:white_check_mark:|
| ?DUP  | QDUP    | 0 (0)  | `ok6 7 3 ?DUP .S3 3 7 6`<br />`ok`<br />`ok6 7 3 ?DUP .S3 3 7 6`<br />`ok`|:white_check_mark:|
