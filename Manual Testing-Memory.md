# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Memory** |        |      |                       ||
| @   | FETCH  | 0(0) |`ok VARIABLE v0`<br />`ok 123 v0 ! .S`<br />`ok v0 @ . 123 .S`<br />`ok`|:white_check_mark:|
| !   | STORE  | 0(0) |`ok VARIABLE v0`<br />`ok 123 v0 ! .S`<br />`ok v0 @ . 123 .S`<br />`ok`|:white_check_mark:|
| C@  | CFETCH | 0(0) |`ok VARIABLE v0`<br />`ok 145 v0 C! .S `<br />`ok v0 C@ . .S 145 .S `<br />`ok`|:white_check_mark:|
| C!  | CSTORE | 0(0) |`ok VARIABLE v0`<br />`ok 145 v0 C! .S `<br />`ok v0 C@ . .S 145 .S `<br />`ok`|:white_check_mark:|
| 2@  | DFETECH | 0(0) |`ok 2VARIABLE vv0`<br />`ok 'ok 123 456 vv0 2! .S `<br />`ok vv0 2@ . . 456 123 .S `<br />`ok`|:white_check_mark:|
| 2!  | DSTORE | 0(0) |`ok 2VARIABLE vv0`<br />`ok 'ok 123 456 vv0 2! .S `<br />`ok vv0 2@ . . 456 123 .S `<br />`ok`|:white_check_mark:|
| +!  | PLUSSTORE | 0(0) |`ok VARIABLE v1 `<br />`ok 100 v1 ! .S `<br />`ok 2 v1 +! .S `<br />`ok v1 @ . .S 102  `<br />`ok`|:white_check_mark:|
| MOVE    | MOVEW   | 0(0) |`ok VARIABLE buf0 10 VALLOT`<br />`ok VARIABLE buf1 10 VALLOT`<br />`ok buf0 12 123 FILL`<br />`ok buf1 12 456 FILL`<br />`ok buf0 buf1 12 MOVE `<br />`ok buf0 24 DUMP ##..`<br />`ok`|:white_check_mark:|
| CMOVE   | CMOVEW  | 1(1) |`ok VARIABLE buf0 10 VALLOT`<br />`ok VARIABLE buf1 10 VALLOT`<br />`ok buf0 12 123 FILL`<br />`ok buf1 12 456 FILL`<br />`ok buf0 buf1 12 CMOVE`<br />`ok buf0 24 DUMP {{..`<br />`ok`|:white_check_mark:|
| CMOVE>  | CMOVEGT | 0(0) |`ok VARIABLE buf0 10 VALLOT`<br />`ok VARIABLE buf1 10 VALLOT`<br />`ok buf0 12 123 FILL`<br />`ok buf1 12 456 FILL`<br />`ok buf1 buf0 12 CMOVE>`<br />`ok buf0 24 DUMP ....`<br />`ok`|:white_check_mark:|
| FILL    | FILLW   | 0(0) |`ok VARIABLE buf0 10 VALLOT`<br />`ok VARIABLE buf1 10 VALLOT`<br />`ok buf0 12 123 FILL`<br />`ok buf1 12 456 FILL`<br />`ok buf0 buf1 12 MOVE `<br />`ok buf0 24 DUMP ##..`<br />`ok`|:white_check_mark:|
| ERASE   | ERASEW | 0(0) |`ok VARIABLE buf0 10 VALLOT`<br />`ok buf0 12 123 FILL`<br />`ok buf0 12 ERASE`<br />`ok buf0 12 DUMP ....`<br />`ok`|:white_check_mark:|
| ,   | COMMA | 0(0) |`ok CREATE cons0 123 , 456 ,`<br />`ok cons0 @ . 123`<br />`ok cons0 2+ @ . 456 `<br />`ok`|:white_check_mark:|
| C, | CCOMMA | 0(0) |`ok CREATE ccons0 123 C, 456 C,`<br />`ok ccons0 C@ . 123`<br />`ok ccons0 1+ C@ . 200 `<br />`ok`|:white_check_mark:[^1]|
| ALLOT   | ALLOT | 0(0) |`ok CREATE lkup0 6 ALLOT`<br />`ok 1 lkup0 ! `<br />`ok 2 lkup0 2+ !`<br />`ok 4 lkup0 4 + !`<br />`ok lkup0 6 DUMP 00 01 00 02 00 04`<br />`ok`|:white_check_mark:|
| HERE | HEREW | 0(0) |`ok HERE .702F`<br />`ok CREATE name0 HERE . 7036`<br />`ok 1234 , HERE .7038`<br />`ok 456 , HERE .703A`<br />`ok`|:white_check_mark:|
| UNUSED   | UNUSEDW | 0(0) |`ok HERE .7000`<br />`ok UNUSED . 4900`<br />`ok CREATE name0 890 ,`<br />`ok HERE . 7009`<br />`ok NUSED . 48F7`<br />`ok`|:white_check_mark:|
| V,    | VCOMMA | 0(0) |`ok VARIABLE buf0 -2 VALLOT 12 V, 34 V, 56 V,`<br />`ok buf0 @ .12`<br />`ok buf0 2+ @ . 34 `<br />`ok buf0 4 + @ . 56`<br />`ok`|:white_check_mark:|
| VC,   | VCCOMMA | 0(0) |`ok VARIABLE buf0 -2 VALLOT 11 VC, 22 VC, 33 VC, 44 VC,`<br />`ok buf0 C@ . 11`<br />`ok buf0 1+ C@ . 22`<br />`ok buf0 2+ C@ . 33`<br />`ok buf0 3 + C@ . 44`<br />`ok`|:white_check_mark:|
| VALLOT   | VALLOT | 0(0) |`ok: ARRAY CREATE VHERE , CELLS VALLOT DOES> @ ;`<br />`: [I] CELLS + ;`<br />`6666 arr1 1 [I] !`<br />`arr1 1 [I] @ .`<br />`ok`|:white_check_mark:[^2]|
| VHERE    | VHEREW | 0(0) |`ok: ARRAY CREATE VHERE , CELLS VALLOT DOES> @ ;`<br />`: [I] CELLS + ;`<br />`6666 arr1 1 [I] !`<br />`arr1 1 [I] @ .`<br />`ok`|:white_check_mark:|
| VUNUSED  | VUNUSEDW | 0(0) |`ok VHERE . 225`<br />`ok VUNUSED . 1DDA`<br />`ok VARIABLE v0 v0 8888 !`<br />`ok VHERE . 227`<br />`ok VUNUSED . 1DD8`<br />`ok`|:white_check_mark:|
| PAD   | PADW | 0(0) |`ok: : >ASCII [CHAR] 0 + ;`<br />`: .error >ASCII S" Error: " DUP >R PAD SWAP CMOVE PAD R@ + C! PAD R> 1+ TYPE ;`<br />`ok 9 .error Error: 9`<br />`ok`|:white_check_mark:|

[^1]: The 200 result exists because 456 is truncated to a byte.
[^2]: VALLOT, is tested using the setup below: 
      ```
      : ARRAY CREATE VHERE , CELLS VALLOT DOES> @ ;
      : [I] CELLS + ;    
      ```
      Usage: 6 ARRAY arr1
      
      Usage: 6666 arr1 1 [I] !
             arr1 1 [I] @ .

Comments:
1. A CVARIABLE might be a useful addition.
2. DUMP had a bug with the loop not terminating.
3. 2- might be useful.
4. An error from non-balanced return stack usage and not meeting a semicolon can get stuck. 
   May need to force to interpretive mode on such an error.
