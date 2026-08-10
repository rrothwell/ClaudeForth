# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Address Arithmetic** |        |      |                       ||
| CELLS  | DMAXW  | 0 (0)  | `ok 5 CELLS .S 10`<br />`ok`|:white_check_mark:|
| CELL+  | DMINW  | 0 (0)  | `ok5000 CELL+ .S 5002`<br />`ok`|:white_check_mark:|
| CHARS  | MPLUS  | 0 (0)  | `ok3 CHARS .S 3 `<br />`ok`|:white_check_mark:|
| CHAR+  | MSTAR  | 0 (0)  | `ok5 CHAR+ .S 6`<br />`ok`|:white_check_mark:|
| ALIGN  | UMSTAR  | 0 (0)  | `okHERE .S ALIGN .S 28723 28723`<br />`ok`|:white_check_mark:|
| ALIGNED| UMSLASHMOD  | 0 (0)  | `ok5003 ALIGNED .S 5003`<br />`ok`|:white_check_mark:|

                                                          
  ok