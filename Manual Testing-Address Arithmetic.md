# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Address Arithmetic** |        |      |                       ||
| CELLS  | CELLSW  | 0 (0)  | `ok 5 CELLS .S 10`<br />`ok`|:white_check_mark:|
| CELL+  | CELLPLUS  | 0 (0)  | `ok5000 CELL+ .S 5002`<br />`ok`|:white_check_mark:|
| CHARS  | CHARSW  | 0 (0)  | `ok3 CHARS .S 3 `<br />`ok`|:white_check_mark:|
| CHAR+  | CHARPLUS  | 0 (0)  | `ok5 CHAR+ .S 6`<br />`ok`|:white_check_mark:|
| ALIGN  | ALIGNW  | 0 (0)  | `okHERE .S ALIGN .S 28723 28723`<br />`ok`|:white_check_mark:|
| ALIGNED| ALIGNEDW  | 0 (0)  | `ok5003 ALIGNED .S 5003`<br />`ok`|:white_check_mark:|
