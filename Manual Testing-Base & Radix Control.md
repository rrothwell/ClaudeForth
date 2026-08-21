# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Base & Radix Control** |        |      |                       ||
| BASE    | BASEW   | 0(0) |`ok DECIMAL 123 3 BASE ! .11120`<br />`ok DECIMAL 1234567. 3 BASE ! D. 2022201111201`<br />`ok`|:white_check_mark:|
| DECIMAL | DECIMAL | 0(0) |`ok DECIMAL 123 HEX . 7B`<br />`ok DECIMAL 1234567. HEX D. 12D687`<br />`ok`|:white_check_mark:|
| HEX     | HEXW    | 0(0) |`ok DECIMAL 123 HEX . 7B`<br />`ok DECIMAL 1234567. HEX D. 12D687`<br />`ok`|:white_check_mark:|
| BINARY  | BINARYW | 0(0) |`ok DECIMAL 123 BINARY . 1111011`<br />`ok DECIMAL 1234567. BINARY D. 100101101011010000111`<br />`ok`|:white_check_mark:|
