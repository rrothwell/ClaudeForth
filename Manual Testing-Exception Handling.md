# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Exception Handling** |        |      |                       ||
| CATCH | CATCH | 0(0) |`ok -4000 CONSTANT cUnavailable`<br />`ok : acquire? 0<> IF cUnavailable THROW THEN ;`<br />`ok : loge DUP >R ABS S>D <# #S R> SIGN S" Err: " HOLDS #> TYPE ;`<br />`ok : process ['] acquire? CATCH DUP 0<> IF loge DROP ELSE DROP ." OK." THEN ;`<br />`ok 5 process Err: -4000`<br />`ok -90 process Err: -4000`<br />`ok 0 process OK.`<br />`ok`|:white_check_mark:[^1][^2]|
| THROW | THROW | 0(0) |`ok -4000 CONSTANT cUnavailable`<br />`ok : acquire? 0<> IF cUnavailable THROW THEN ;`<br />`ok : loge DUP >R ABS S>D <# #S R> SIGN S" Err: " HOLDS #> TYPE ;`<br />`ok : process ['] acquire? CATCH DUP 0<> IF loge DROP ELSE DROP ." OK." THEN ;`<br />`ok 5 process Err: -4000`<br />`ok -90 process Err: -4000`<br />`ok 0 process OK.`<br />`ok`|:white_check_mark:[^1][^2]|

[^1]: This also works : acquire? 0<> IF cUnavailable ELSE 0 THEN THROW ;
      When THROW is passed 0 it does nothing. 
[^2]: Watch out for return of more than one value by CATCH.
      The extra values are junk.
      ASsume the TOS value is OK.
      MAME appeared to broken for a while as it was not returning 0 
      on a no throw condition. 
      It also appeared that the current line and PC were out of sync.
