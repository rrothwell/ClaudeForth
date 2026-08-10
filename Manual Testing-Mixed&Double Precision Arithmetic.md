# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Mixed & double<br />precision arithmetic** |        |      |                       ||
| S>D| STOD  | 0 (0)  | `ok36 S>D .S 0 36`<br />`ok-15 S>D .S 0 -15 0 36`<br />`ok`|:white_check_mark:|
| D>S | DTOS  | 0 (0)  | `ok-13 12 D>S .S -13`<br />`ok13 -12 D>S .S 13 -13`<br />`ok`|:white_check_mark:|
| D+| DPLUS  | 0 (0)  | `ok1 2 3 4 D+ .S 6 4`<br />`ok`|:white_check_mark:|
| D- | DMINUS  | 0 (0)  | `ok2 4 1 2 D- .S 2 1 `<br />`ok`|:white_check_mark:|
| DNEGATE | DNEGATEW  | 0 (0)  | `ok1 3 DNEGATE .S -4 -1 `<br />`ok`|:white_check_mark:|
| DABS | DABSW  | 0 (0)  | `ok-4 -1 DABS .S 0 4`<br />`ok`|:white_check_mark:|
| DMAX | DMAXW  | 0 (0)  | `ok4 3 5 2 DMAX .S 3 4`<br />`ok`|:white_check_mark:|
| DMIN | DMINW  | 0 (0)  | `ok4 3 5 2 DMIN .S 2 5`<br />`ok`|:white_check_mark:|
| M+ | MPLUS  | 0 (0)  | `ok4 5 2 M+ .S 5 6`<br />`ok`|:white_check_mark:|
| M* | MSTAR  | 0 (0)  | `ok4 5 2 M* .S 0 10 4`<br />`ok`|:white_check_mark:|
| UM* | UMSTAR  | 0 (0)  | `ok 4 5 2 UM* .S 0 10 4`<br />`ok`|:white_check_mark:|
| UM/MOD | UMSLASHMOD  | 0 (0)  | `ok4 5 3 UM/MOD .S -21844 0`<br />`ok4 5 2 UM/MOD .S -32766 0 -21844 0`<br />`ok`|:negative_squared_cross_mark:[^1]|
| FM/MOD | FMSLASHMOD  | 0 (0)  | `ok 7 5 3 FM/MOD .S -21843 0`<br />`ok 70 5 2 FM/MOD .S-32733 0`<br />`ok`|:negative_squared_cross_mark:[^2]|
| SM/REM | SMSLASHREM  | 0 (0)  | `ok70 5 2 SM/REM .S -32733 0`<br />`ok5 70 2 SM/REM .S 2 1`<br />`ok`|:negative_squared_cross_mark:[^3]|

                                                    
[^1]: UM/MOD in GFORTH produces a divide by zero exception.
[^2]: FM/MOD in GFORTH produces a divide by zero exception.
[^3]: SM/REM in GFORTH produces a divide by zero exception.
