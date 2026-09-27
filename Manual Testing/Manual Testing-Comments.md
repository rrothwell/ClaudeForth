# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Comments** |        |      |                       ||
| ( | LPAREN    | 1(1) |`ok ( Math for */ )`<br />`ok .S`<br />`ok : reciprocal ( n -- 1 n ) 1 ;`<br />`ok .S`<br />`ok 6 reciprocal .S 1 6`<br />`ok`|:white_check_mark:|
| \ | BACKSLASH | 0(0) |`ok : square DUP * ; \ Multiply number by itself.`<br />`ok .S`<br />`ok`|:white_check_mark:|
