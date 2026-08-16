# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Defining Words** |        |      |                       ||
| : ;   | COLON SEMICOLON | 0(0) |`ok : defy ." Hi " ;`<br />`ok defy Hi`<br />`ok`|:white_check_mark:|
| CREATE DOES>   | CREATE DOESGT | 1(1) |`: ENUM CREATE , DOES> @ ;`<br />`ok 17 ENUM e0`<br />`ok e0 .S 28690`<br />`ok`|:negative_squared_cross_mark:[^1]|
| VARIABLE   | VARIABLE | 0(0) |`ok VARIABLE v3 4444 v3 !`<br />`ok VARIABLE v3 4444 v3 !`<br />`ok`|:white_check_mark:|
| CONSTANT   | CONSTANT | 0(0) |`ok333 CONSTANT c0`<br />`ok c0 .333`<br />`ok`|:white_check_mark:|
| VALUE   | VALUEW | 0(0) |`ok 222 VALUE v7`<br />`ok v7 .S 222`|:white_check_mark:|
| TO   | TO | 0(0) |`333 TO v7`<br />`ok v7 .S 333 222`<br />`ok`|:white_check_mark:|
| 2VARIABLE   | TWOVARIABLE | 0(0) |`ok 2VARIABLE vv0`<br />`ok 333 444 vv0`<br />` ok 2+ !`<br />`ok vv0 !`<br />`ok vv0 2@ .S 333 444`<br />`ok`|:white_check_mark:|
| 2CONSTANT   | TWOCONSTANT | 0(0) |`ok 666 777 2CONSTANT cc0`<br />`ok cc0 .S 666 777`<br />`ok`|:white_check_mark:[^2]|
| BUFFER:   | BUFFERCOLON | 0(0) |`100 BUFFER: bf0`<br />`ok bf0 .21F`<br />`ok 111 bf0 ! 222 bf0 2+ !`<br />`ok 111 bf0 ! 222 bf0 2+ ! 2 BUFFER: bf1 bf1 .31F`<br />`ok`|:white_check_mark:[^3]|
| DEFER IS | DEFERW ISW | 0(0) |`ok DEFER df0`<br />`ok : w0 ." hi" CR ;`<br />`ok ' w0 IS df0`<br />`ok df0hi`<br />`ok`|:white_check_mark:[^4]|
| DEFER!   | DEFERSTORE | 0(0) |`ok ' w1 ' df0 DEFER!`<br />`ok df0ho`<br />`ok`|:white_check_mark:[^4]|
| DEFER@   | DEFERFETCH | 0(0) |`ok HEX ' df0 DEFER@ . 700A`<br />`ok`|:white_check_mark:[^4]|
| ACTION-OF| ACTIONOF | 0(0) |`ok ACTION-OF df0 . 700A`<br />`ok`|:white_check_mark:[^4]|
| MARKER | MARKERW | 0(0) |`ok MARKER snap`<br />`ok: w2 ." hii" ;`<br />`ok: w3 ." hoo" ;`<br />`ok: w4 ." huu" ;`<br />`ok w2 w3 w4hiihoohuu`<br />`ok snap`<br />`okw2 w3 w4w2 ERROR -D`<br />`ok`|:white_check_mark:|


[^1]: DOES> is returning a self reference 
      instead of a reference to the numerical value 1 cell further on. 
      Bug is fixed. 
[^2]: Originally cc0 is returning the lower address value then the address 
      instead of the lower address then the higher address value.                                                    
      Bug is fixed. 
[^3]: BUFFER: tested by examining memeory effect in mutable variable area.                                                
[^4]: Setup is: DEFER df0. : w0 ." hi" ;.: w1 ." ho" ;. 

Extras:
( - ) is not compiling properly inside a colon definition
.R is not printing correctly. Eg, 33 instead of 3.
