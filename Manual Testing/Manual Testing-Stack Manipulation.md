# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Stack manipulation** |        |      |                       ||
| DEPTH | DEPTH   | 0 (0)  | `ok3 5 7 9 DEPTH .4`<br />`ok`|:white_check_mark:|
| DUP  | DUP      | 0 (0)  | `ok2 DUP .S2 2`<br />`ok`          |:white_check_mark:|
| DROP | DROP     | 0 (0)  | `ok1 2`<br />`okDROP`<br />`ok.S1`<br />`ok`         |:white_check_mark:|
| SWAP | SWAP     | 0 (0)  | `ok5 9 SWAP .S5 9`<br />`ok`         |:white_check_mark:|
| OVER | OVER     | 0 (0)  | `ok5 9 OVER .S5 9 5`<br />`ok`         |:white_check_mark:|
| ROT  | ROT      | 0 (0)  | `ok5 7 9 ROT .S5 9 7`<br />`ok`         |:white_check_mark:|
| ?DUP  | QDUP    | 0 (0)  | `ok6 7 3 ?DUP .S3 3 7 6`<br />`ok`<br />`ok6 7 3 ?DUP .S3 3 7 6`<br />`ok`|:white_check_mark:|
| NIP | NIP   | 0 (0)  | `ok3 5 7 NIP .S7 3`<br />`ok`|:white_check_mark:|
| TUCK | TUCK   | 0 (0)  | `ok3 5 7 TUCK .S7 5 7 3 `<br />`ok`|:white_check_mark:|
| PICK | PICK   | 0 (0)  | `ok3 5 7 9 11 13`<br />`ok4 PICK .S5 13 11 9 7 5 3`<br />`ok`|:white_check_mark:|
| ROLL | ROLL   | 0 (0)  | `ok3 5 7 9 11 13`<br />`ok4 ROLL .S5 13 11 9 7 3`<br />`ok`|:white_check_mark:|
| 2DUP | DDUP     | 0 (0)  | `ok6 9 2DUP .S9 6 9 6`<br />`ok`|:white_check_mark:|
| 2DROP | DDROP   | 0 (0)  | `ok.S9 6 9 6`<br />`ok2DROP .S9 6`<br />`ok`|:white_check_mark:|
| 2SWAP | DSWAP   | 0 (0)  | `ok2 5 7 9 2SWAP .S5 2 9 7`<br />`ok`|:white_check_mark:|
| 2OVER | DOVER   | 0 (0)  | `ok2 3 4 5 7 6 2OVER`<br />`ok.S5 4 6 7 5 4 3 2`<br />`ok`|:white_check_mark:|
| 2ROT  | DROT    | 0 (0)  | `ok3 5 7 9 11 13 15 17 2ROT`<br />`ok.S9 7 17 15 13 11 5 3`<br />`ok`|:white_check_mark:|

