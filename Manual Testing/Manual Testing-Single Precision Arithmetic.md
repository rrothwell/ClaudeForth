# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Single precision arithmetic** |        |      |                       ||
| +  | PLUS        | 0 (0)  | `ok5 7 + .12`<br />`ok.S`<br />`ok`|:white_check_mark:|
| -  | MINUS      | 0 (0)  | `ok5 7 - .-2`<br />`ok.S`<br />`1234`<br />`ok`|:white_check_mark:|
| * | STAR  | 0 (0)  | `ok5 7 * .35`<br />`ok.S`<br />`ok`|:white_check_mark:|
| / | SLASH  | 0 (0)  | `ok35 7 / .5`<br />`ok.S`<br />`ok`|:white_check_mark:|
| MOD | MODW  | 0 (0)  | `ok36 7 MOD .1`<br />`ok.S`<br />`ok`|:white_check_mark:|
| /MOD | SLASHMOD  | 0 (0)  | `ok36 7 /MOD .5`<br />`ok.1`<br />`ok.S`<br />`ok`|:white_check_mark:|
| NEGATE  | NEGATE     | 0 (0)  | `ok5 NEGATE .-5 `<br />`ok-7 NEGATE .7`<br />`ok.S`<br />`ok`|:white_check_mark:|
| ABS | ABSW     | 0 (0)  | `ok5 ABS . 5`<br />`ok5 ABS . 5`<br />`ok.S`<br />`ok`|:white_check_mark:|
| MIN | MIN   | 0 (0)  | `ok-6 -1 MIN .-6`<br />`ok-1 -6 MIN .-6`<br />`ok.S`<br />`ok`|:white_check_mark:|
| MAX | MAX   | 0 (0)  | `ok5 7 MAX .7`<br />`ok7 5 MAX .7`<br />`ok.S`<br />`ok`|:white_check_mark:|
| 1+ | ONEPLUS  | 0 (0)  | `ok12 1+ .13`<br />`ok-12 1+ .-11`<br />`ok.S`<br />`ok`|:white_check_mark:|
| 1- | ONEMINUS  | 0 (0)  | `ok15 1- .14`<br />`ok-15 1- .-16`<br />`ok.S`<br />`ok`|:white_check_mark:|
| 2+ | TWOPLUS  | 0 (0)  | `ok25 2+ .27 `<br />`ok-25 2+ .-23`<br />`ok.S`<br />`ok`|:white_check_mark:|
| 2* | TWOSTAR  | 0 (0)  | `ok13 2* .26`<br />`ok-16 2* .-32`<br />`ok.S`<br />`ok`|:white_check_mark:|
| 2/ | TWOSLASH  | 0 (0)  | `ok15 2/ .7`<br />`ok-17 2/ .-9`<br />`ok.S`<br />`ok`|:white_check_mark:|
| */ | STARSLASH  | 0 (0)  | `ok25 2 3 */ .16 `<br />`ok-25 2 3 */ .-16`<br />`ok.S`<br />`ok`|:white_check_mark:|
| */MOD | STARSLASHMOD  | 0 (0)  | `ok25 2 3 */MOD .16`<br />`ok.2`<br />`ok.S`<br />`ok`<br />`ok-25 2 3 */MOD .-16 `<br />`ok.-2`<br />`ok.S`<br />`ok`|:white_check_mark:|
