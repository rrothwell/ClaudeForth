# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Logic, Shifts Arithmetic** |        |      |                       ||
| AND    | ANDW  | 0 (0)  | `okTRUE FALSE AND .S 0`<br />`okFALSE TRUE AND .S 0 0`<br />`okTRUE TRUE AND .S -1 0 0`<br />`okFALSE FALSE AND .S 0 -1 0 0`<br />`ok`|:white_check_mark:|
| OR     | ORW  | 0 (0)  | `okTRUE FALSE OR .S -1`<br />`okFALSE TRUE OR .S -1 -1`<br />`okTRUE TRUE OR .S -1 -1 -1`<br />`okFALSE FALSE OR .S 0 -1 -1 -1`<br />`ok`|:white_check_mark:|
| XOR    | XORW  | 0 (0)  | `okTRUE FALSE XOR .S -1`<br />`okFALSE TRUE XOR .S -1 -1`<br />`okTRUE TRUE XOR .S 0 -1 -1 `<br />`okFALSE FALSE XOR .S 0 0 -1 -1`<br />`ok`|:white_check_mark:|
| INVERT | INVERT  | 0 (0)  | `okBINARY 11001001 INVERT .S -11001010`<br />`ok`|:white_check_mark:|
| LSHIFT | LSHIFT  | 0 (0)  | `okBINARY 11001001 1 LSHIFT .S 110010010`<br />`ok`|:white_check_mark:|
| RSHIFT | RSHIFT  | 0 (0)  | `okBINARY 11001001 1 RSHIFT .S 1100100`<br />`ok`|:white_check_mark:|

                                                          
                                                          
                                                       
                                                     
                                                          
     
    
    
                                                       
  