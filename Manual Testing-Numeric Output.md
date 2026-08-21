# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Numeric Output** |        |      |                       ||
| <#   | LTNUM    | 0(0) |`ok : least2digits <# # # #> ;`<br />`ok 123. least2digits TYPE 23`<br />`ok`|:white_check_mark:|
| #    | NUMSIGN  | 2(2) |`ok : least5digits <# # # # # # #> ;`<br />`ok 1234567. least5digits TYPE 34567`<br />`ok`|:white_check_mark:[^1]|
| #S   | NUMSIGNS | 0(0) |`ok : alldigits <# #S #> ;`<br />`ok 12345678. alldigits TYPE 12345678`<br />`ok`|:white_check_mark:|
| #>   | NUMGT    | 0(0) |`ok : alldigits <# #S #> ;`<br />`ok 123 S>D alldigits TYPE 123`<br />`ok`|:white_check_mark:|
| HOLD | HOLD     | 0(0) |`ok : .dollars <# # # [CHAR]  . HOLD #S  [CHAR] $ HOLD #> ;`<br />`ok 65789012. .dollars TYPE $657890.12`<br />`ok`|:white_check_mark:|
| HOLDS | HOLDS   | 0(0) |`ok : .serial <# #S S" Serial:" HOLDS #> ;`<br />`ok 567890. .serial TYPE Serial:567890`<br />`ok`|:white_check_mark:|
| SIGN | SIGN     | 1(1) |`ok : .signed DUP >R ABS S>D <# #S R> SIGN #> ;`<br />`ok123 .signed TYPE 123`<br />`ok -123 .signed TYPE -123`<br />`ok`|:white_check_mark:[^2]|
| .    | DOT      | 1(1) |`ok 123 . 123`<br />`ok -123 . -123`<br />`ok`|:white_check_mark:|
| U.   | UDOT     | 1(1) |`ok 123 U. 123`<br />`ok -123 U. 65413`<br />`ok`|:white_check_mark:|
| .R   | DOTR     | 0(0) |`ok 123 4 .R  123`<br />`ok -123 4 .R -123`<br />`ok`|:white_check_mark:|
| U.R  | UDOTR    | 0(0) |`ok  123 8 U.R     123`<br />`ok -123 8 U.R   65413`<br />`ok`|:white_check_mark:|
| ?    | QMARK    | 0(0) |`ok VARIABLE v0`<br />`ok 456 v0 !`<br />`ok v0 ? 456`<br />`ok`|:white_check_mark:|
| D.   | DDOT     | 0(0) |`ok  123456. D. CHAR < EMIT 123456 <`<br />`ok -123456. D. CHAR < EMIT-123456 <`<br />`ok`|:white_check_mark:|
| D.R  | DDOTR    | 2(2) |`ok  123456. 8 D.R  CHAR < EMIT  123456<`<br />`ok -123456. 8 D.R  CHAR < EMIT -123456<`<br />`ok`|:white_check_mark:|


[^1]: the number parsing code had to be modified to recognise the double number dot format. 
      Then a bug in the double negate code was fixed.
[^2]: Subtle bug involving non-setting of conditions codes was fixed.

  
                                                                                           
                                                                                         
                                                                                          
                                                                              
                                                                             
                                                             
                                                             
                                                                          
  
                                                           
                                                               
 