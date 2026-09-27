# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **System & Console I/O** |        |      |                       |      |
| KEY    | KEY     | 1(1) |`ok CR KEY`<br />`ok .S 65`<br />`ok`|:white_check_mark:|
| KEY?   | KEYQ    | 1(1) |`ok : done? [CHAR] * = ;`<br />`: echo EMIT [CHAR] * EMIT ;`<br />`: key-press? `<br />`BEGIN`<br />`KEY? IF KEY DUP done? IF DROP EXIT ELSE echo THEN THEN`<br />`AGAIN ;`<br />`ok`<br />`okkey-press?g*h*e*r*t*h*h*j*`<br />`ok`|:white_check_mark:|
| EMIT   | EMIT    | 1(1) |`ok CHAR & EMIT .S &`<br />`ok`|:white_check_mark:|
| ACCEPT | ACCEPT  | 0(0) |`ok: user? CR ." Username? " PAD 10 ACCEPT 2 SPACES ." Ok " PAD SWAP TYPE ;`<br />`ok user?`<br />`Username? John3  Ok John3`<br />`ok`|:white_check_mark:|
| EXPECT | EXPECTW | 0(0) |`ok 80 BUFFER: aline`<br />`ok : input-line CR ." >> " aline 80 EXPECT CR ." Received: "  aline SPAN @ TYPE ;`<br />`>> burlesque`<br />`Received: burlesque`<br />`ok`|:white_check_mark:|
| QUERY  | QUERY   | 0(0) |`ok : valid-word? CR ." Word? " QUERY BL WORD FIND ;`<br />`ok valid-word?`<br />`Word? QUIT`<br />`ok .S -1 -8390`<br />`ok`|:white_check_mark:|
| TYPE   | TYPE    | 0(0) |`ok S" Quite Interesting" TYPE Quite Interesting`<br />`ok`|:white_check_mark:|
| CR     | CRW     | 0(0) |`ok CR`<br />` `<br />`ok`|:white_check_mark:|
| SPACE  | SPACEW  | 0(0) |`ok CR CHAR > EMIT SPACE CHAR < EMIT`<br />`> <`<br />`ok`|:white_check_mark:|
| SPACES | SPACESW | 0(0) |`ok CR CHAR > EMIT 10 SPACES  CHAR < EMIT`<br />>          <`<br />`ok`|:white_check_mark:|
