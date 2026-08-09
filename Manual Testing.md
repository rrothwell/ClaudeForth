# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| Compilation | WORD     | 2 (8)  |                               |:white_check_mark:|
| CONSTANT    | CONSTANT | 1 |                |:white_check_mark:|
| DO I LOOP   | DOTEST IWORD | 3(12) |`ok: lpy 10 3 DO I . LOOP ;` `oklpy3 4 5 6 7 8 9`|:white_check_mark:|
