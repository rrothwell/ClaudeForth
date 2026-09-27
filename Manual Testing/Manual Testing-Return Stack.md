# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Return stack manipulation** |        |      |                       ||
| >R  | TOR        | 0 (0)  | `ok: tr 1234 5678 .S CR >R .S CR R> .S ;`<br />`oktr5678 1234`<br />`1234`<br />`5678 1234`<br />`ok`|:white_check_mark:|
| <R  | FROMR      | 0 (0)  | `ok: tr 1234 5678 .S CR >R .S CR R> .S ;`<br />`oktr5678 1234`<br />`1234`<br />`5678 1234`<br />`ok`|:white_check_mark:|
| R@  | RFETCH     | 0 (0)  | `ok: tr0 123 456 .S CR >R .S CR R@ .S CR R> .S ;`<br />`oktr0456 123 `<br />`123`<br />`456 123`<br />`456 456 123`<br />`ok`|:white_check_mark:|
| 2>R | TWOTOR     | 0 (0)  | `ok: tr2 12 34 56 78 .S CR 2>R .S CR 2R> .S ;`<br />`oktr278 56 34 12`<br />`34 12`<br />`378 56 34 12`<br />`ok`|:white_check_mark:|
| 2<R | TWOFROMR   | 0 (0)  | `ok: tr2 12 34 56 78 .S CR 2>R .S CR 2R> .S ;`<br />`oktr278 56 34 12`<br />`34 12`<br />`378 56 34 12`<br />`ok`|:white_check_mark:|
| 2R@ | TWORFETCH  | 0 (0)  | `tr3 12 34 56 78 .S CR 2>R .S CR 2R@ .S CR 2R> .S ;`<br />`oktr378 56 34 12`<br />`34 12`<br />`78 56 34 12`<br />`78 56 78 56 34 12`<br />`ok`|:white_check_mark:|

