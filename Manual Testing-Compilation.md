# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Compilation** |        |      |                       ||
| Define word | WORD     | 2 (8)  | `ok: W0 3 . ;`<br />`okW03`|:white_check_mark:|
| CONSTANT    | CONSTANT | 1 | `ok5 CONSTANT C0`<br />`okC0 .5`|:white_check_mark:|
