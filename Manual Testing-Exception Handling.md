# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Exception Handling** |        |      |                       ||
| CATCH | BASEW   | 0(0) |`ok -4000 CONSTANT cUnavailable`<br />`ok : acquire? 0<> IF cUnavailable THROW THEN ;`<br />`: loge DUP >R ABS S>D <# #S R> SIGN S" Err: " HOLDS #> TYPE ;`<br />`ok : process ['] acquire? CATCH DUP 0<> IF loge ELSE DROP ." OK." THEN ;`<br />`ok 90 process Err: -4000`<br />`ok-90 process Err: -4000`<br />`ok 0 process OK.`<br />`ok`|:white_check_mark:|
| THROW | DECIMAL | 0(0) |`ok -4000 CONSTANT cUnavailable`<br />`ok : acquire? 0<> IF cUnavailable THROW THEN ;`<br />`: loge DUP >R ABS S>D <# #S R> SIGN S" Err: " HOLDS #> TYPE ;`<br />`ok : process ['] acquire? CATCH DUP 0<> IF loge ELSE DROP ." OK." THEN ;`<br />`ok 90 process Err: -4000`<br />`ok-90 process Err: -4000`<br />`ok 0 process OK.`<br />`ok`|:white_check_mark:|
