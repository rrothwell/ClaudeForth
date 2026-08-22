# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Environmental & System Queries** |        |      |                       ||
| ENVIRONMENT? | ENVQUERY  | 1(1) |`ok : counted-string? S" /COUNTED-STRING" ENVIRONMENT? ; `<br />`ok counted-string? .S -1 255`<br />`ok`|:white_check_mark:[^1]|
| ENVIRONMENT? | ENVQUERY  | 1(1) |`ok : hold? S" /HOLD" ENVIRONMENT? ;`<br />`ok hold? .S -1 34`<br />`ok`|:white_check_mark:[^1]|
| ENVIRONMENT? | ENVQUERY  | 1(1) |`ok : pad? S" /PAD" ENVIRONMENT? ;`<br />`ok pad? .S -1 84`<br />`ok`|:white_check_mark:[^1]|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : address-unit-bits? S" /ADDRESS-UNIT-BITS" ENVIRONMENT? ;`<br />`ok address-unit-bits? .S-1 8`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : floored? S" FLOORED" ENVIRONMENT? ;`<br />`ok floored? .S -1 0`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : maxchar? S" MAX-CHAR" ENVIRONMENT? ;`<br />`ok maxchar? .S -1 0`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : maxd? S" MAX-D" ENVIRONMENT? ;`<br />`ok maxd? .S -1 32767 -1`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : maxn? S" MAX-N" ENVIRONMENT? ;`<br />`ok maxn? .S -1 32767`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : maxu? S" MAX-U" ENVIRONMENT? ;`<br />`ok maxu? .S -1 -1 `<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : maxud? S" MAX-UD" ENVIRONMENT? ;`<br />`ok maxud? .S -1 -1 -1`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : returnstackcells? S" RETURN-STACK-CELLS" ENVIRONMENT? ;`<br />`ok returnstackcells? .S -1 384`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : stackcells? S" STACK-CELLS" ENVIRONMENT? ;`<br />`ok stackcells? .S -1 0`<br />`ok`|:white_check_mark:|
| ENVIRONMENT? | ENVQUERY  | 0(0) |`ok : wordlists? S" WORDLISTS" ENVIRONMENT? ;`<br />`ok wordlists? .S -1 0`<br />`ok`|:white_check_mark:|
| SOURCE       | SOURCEW   | 0(0) |`ok : address-unit-bits? S" /ADDRESS-UNIT-BITS" ENVIRONMENT? ;`<br />`ok .S`<br />`ok`|:white_check_mark:|
| SOURCE-ID    | SOURCEID  | 1(1) |`ok ( Math for */ )`<br />`ok .S`<br />`ok : reciprocal ( n -- 1 n ) 1 ;`<br />`ok .S`<br />`ok 6 reciprocal .S 1 6`<br />`ok`|:white_check_mark:|
| REFILL       | REFILLW   | 0(0) |`ok : square DUP * ; \ Multiply number by itself.`<br />`ok .S`<br />`ok`|:white_check_mark:|
| EVALUATE     | EVALUATEW | 1(1) |`ok ( Math for */ )`<br />`ok .S`<br />`ok : reciprocal ( n -- 1 n ) 1 ;`<br />`ok .S`<br />`ok 6 reciprocal .S 1 6`<br />`ok`|:white_check_mark:|
| TIB          | TIBW      | 0(0) |`ok : square DUP * ; \ Multiply number by itself.`<br />`ok .S`<br />`ok`|:white_check_mark:|
| #TIB         | NTIBW     | 1(1) |`ok ( Math for */ )`<br />`ok .S`<br />`ok : reciprocal ( n -- 1 n ) 1 ;`<br />`ok .S`<br />`ok 6 reciprocal .S 1 6`<br />`ok`|:white_check_mark:|
| >IN          | TOINW     | 0(0) |`ok : square DUP * ; \ Multiply number by itself.`<br />`ok .S`<br />`ok`|:white_check_mark:|
| SPAN         | SPANW     | 1(1) |`ok ( Math for */ )`<br />`ok .S`<br />`ok : reciprocal ( n -- 1 n ) 1 ;`<br />`ok .S`<br />`ok 6 reciprocal .S 1 6`<br />`ok`|:white_check_mark:|
| BL           | BLW       | 0(0) |`ok : square DUP * ; \ Multiply number by itself.`<br />`ok .S`<br />`ok`|:white_check_mark:|


## Environmental Query Strings
| String Value | Data Type  | Constant?| Meaning        | 
|:-------------|:-----------|:---------|:---------------|
| /COUNTED-STRING    | n	 | yes | maximum size of a counted string, in characters |
| /HOLD	             | n	 | yes | size of the pictured numeric output string buffer, in characters |
| /PAD               | n	 | yes | size of the scratch area pointed to by PAD, in characters |
| ADDRESS-UNIT-BITS  | n	 | yes | size of one address unit, in bits |
| FLOORED	         | flag	 | yes | true if floored division is the default |
| MAX-CHAR	         | u	 | yes | maximum value of any character in the implementation-defined character set |
| MAX-D	             | d	 | yes | largest usable signed double number |
| MAX-N              | n	 | yes | largest usable signed integer |
| MAX-U	             | u	 | yes | largest usable unsigned integer |
| MAX-UD	         | ud	 | yes | largest usable unsigned double number |
| RETURN-STACK-CELLS | n	 | yes | maximum size of the return stack, in cells |
| STACK-CELLS	     | n	 | yes | maximum size of the data stack, in cells |
| WORDLISTS	         | n	 | yes | maximum size of the data stack, in cells |

 