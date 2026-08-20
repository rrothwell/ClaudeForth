# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Strings & Parsing** |        |      |                       ||
| COUNT   | COUNT  | 0(0) |`ok HEX CREATE str0 7 C, 45 C, 72 C, 72 C, 6F C, 72 C, 3A C, 20 C,`<br />`ok str0 .7101`<br />`ok str0 C@ .7`<br />`ok str0 COUNT .S 7 7102`<br />`ok TYPE Error:`<br />`ok`|:white_check_mark:|
| WORD   | WORD  | 2(2) |`ok: .stream BL WORD COUNT TYPE CR ; `<br />`ok .stream  band of brothers band`<br />`of`<br />`ERROR -D`<br />`ok`|:white_check_mark:|
| CHAR  | CHARW | 0(0) |`ok CHAR A . 41`<br />`ok CHAR BCD . 42`<br />`ok`|:white_check_mark:|
| [CHAR]  | BRACKCHAR | 0(0) |`ok : upper? [CHAR] A  [CHAR] Z 1+ WITHIN ;`<br />`ok CHAR A upper? . -1 `<br />`ok CHAR Z upper? . -1`<br />`ok CHAR a upper? . 0`<br />`ok`|:white_check_mark:|
| PARSE  | PARSEW | 0(0) |`ok 32 BUFFER: str0 `<br />`ok : PLACE 2DUP C!  CHAR+ SWAP  MOVE ;`<br />`: instream BL PARSE str0 PLACE ;`<br />`instream fair thee well thee`<br />`ERROR -D`<br />`ok str0 COUNT TYPE fair`<br />`ok`|:white_check_mark:|
| PARSE-NAME  | PARSENAME | 0(0) |`ok : ?stream PARSE-NAME  S" Forth" COMPARE 0= IF ." Yes!" ELSE ." No!" THEN ;`<br />`ok ?stream Forth Yes! `<br />`ok ?stream Java No!`<br />`ok`|:white_check_mark:|
| S"  | SQUOTE | 1(1) |`ok : .greeting S" Hi! " TYPE ;`<br />`ok .greeting Hi!`<br />`ok`|:white_check_mark:|
| ."    | DOTQUOTE   | 1(1) |`ok : .greeting ." Hello, World!" ;`<br />`ok .greeting Hello, World!`<br />`ok`|:white_check_mark:|
| COMPARE   | COMPAREW  | 1(1) |`ok : str3 S" abb" ;`<br />`ok : str2 S" abc" ;`<br />`ok str3 str2 COMPARE . -1`<br />`str2 str3 COMPARE . 1 `<br />`ok`|:white_check_mark:|
| SEARCH  | SEARCHW | 0(0) |`ok : str0 S" Hello ANS Forth World" ;`<br />`ok : str1 S" Forth" ; `<br />`ok HEX str0 2DUP + ROT ROT`<br />`ok str1 SEARCH DROP 2DUP TYPE`<br />`ok + TUCK - TYPE  World >`<br />`ok`|:white_check_mark:|
| -TRAILING    | DASHTRAILING   | 0(0) |`ok : regreet S" Hi  " -TRAILING TYPE SPACE S" again!" SPACE TYPE ;`<br />`ok regreet Hi  again!`<br />`ok`|:white_check_mark:|
| /STRING   | SLASHSTRING | 0(0) |`ok : trimn> S" xxxEND" 3 /STRING SPACE TYPE ;`<br />`ok trimn>  END`<br />`ok`|:white_check_mark:|
| REPLACES   | REPLACESW | 0(0) |`ok CREATE cons0 123 , 456 ,`<br />`ok cons0 @ . 123`<br />`ok cons0 2+ @ . 456 `<br />`ok`|:white_check_mark:|
| SUBSTITUTE | SUBSTITUTEW | 2(2) |`ok : name0 S" Agnetha" ;`<br />`ok : label S" girl" ;`<br />`ok name0 label REPLACES`<br />`ok 80 BUFFER: poem`<br />`ok S" Dancing, %girl%!" poem 80 SUBSTITUTE DROP SPACE TYPE  Dancing, Agnetha!`<br />`ok`|:white_check_mark:|
| SUBSTITUTE | SUBSTITUTEW | 2(2) |`ok poem 80 SUBSTITUTE `<br />`ok DROP SPACE TYPE Two dancing girls- Agnetha! Agnetha!`<br />`ok`|:white_check_mark:[^1]|
| SUBSTITUTE | SUBSTITUTEW | 2(2) |`ok : template S" Two dancing girls- %girl%! %girl%!" ;`<br />`template poem 80 SUBSTITUTE DROP SPACE TYPE Two dancing girls- Agnetha! Agnetha! `<br />`ok`|:white_check_mark:|
| SUBSTITUTE | SUBSTITUTEW | 2(2) |`ok : expand S" Two dancing girls- %girl%! %girl%!" poem 80`<br />`SUBSTITUTE DROP SPACE TYPE ; `<br />`ok expand  Two dancing girls- Agnetha! Agnetha!`<br />`ok`|:white_check_mark:|
| UNESCAPE | UNESCAPEW |2(2) |`ok 80 BUFFER: .finished`<br />`ok S" 100% complete" .finished  UNESCAPE TYPE 100%% complete`<br />`ok S" 100% complete % " .finished  UNESCAPE TYPE100%% complete %%`<br />`ok`|:white_check_mark:|
| SNAME   | SNAMEW | 0(0) |`ok ' SUBSTITUTE`<br />`ok SNAME TYPE SUBSTITUTE`<br />`ok`|:white_check_mark:|

Comments:
1. A -ROT might be a useful addition in place of ROT ROT.
2. C" might be a useful addition.
3. 2- might be useful.
4. An error from non-balanced return stack usage and not meeting a semicolon can get stuck. 
   May need to force to interpretive mode on such an error.

  
## Bug count by word

| Word	| Bugs found | Nature |
| ----- | -----------| ------ |
| WORD	| 2 |	(1) Register-clobber: TFR X,D destroyed the true scan count, corrupting the stored length for any token followed by more input. (2) Buffer undersized below even the ANS minimum: fixed 31-character cap via a separate WORDBUF, below the standard’s own 33-character floor — redesigned to use the CODEHERE-to-PAD gap, now 46 characters. |
| S"	| 1	| Compiled-mode collision, self-introduced and caught before delivery: the runtime trampoline compiled at CODEHERE overwrote the text WORD had just staged there, once WORD’s own redesign made both use the same address. |
| ."	| 1	| Identical collision to S"’s, same root cause, fixed the same way. |
| ABORT"	| 1	| Identical collision again, third instance of the same class. |
| CREATE	| 1	| Self-referential PFA pointer — the field meant to point to the value area pointed at itself instead, off by one cell. |
| SUBSTITUTE	| 2 (1) | Missing third return value (substitution count) — ANS requires ( -- addr len n ), only addr len was returned. (2) Wrong algorithm entirely — plain substring search-and-replace on the bare registered name, instead of scanning for %-delimited pairs as the spec requires. |
| UNESCAPE	| 2	(1) | Argument-popping order completely wrong — only one of three arguments was ever popped, into the wrong variable. (2) Wrong algorithm entirely — decoded backslash escape sequences (\n, \t, etc.), which has nothing to do with what UNESCAPE actually does (doubling % characters). |
| FILL	| 1	| Register-clobber: loading the fill character into A corrupted the in-progress count held in D, running the fill far past the requested length. |
| CMOVE	| 1	| Same register-clobber class as FILL — fetching the byte to copy corrupted the count. |
| SEARCH	| 0	| Checked directly while tracing SUBSTITUTE’s original bug — logic was correct. |
| COMPARE	| 0	| Reused as a helper in the SUBSTITUTE rewrite — no defect found. |

Total: 12 distinct bugs across 9 words, plus 