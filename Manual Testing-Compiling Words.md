# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Compiling Words** |        |      |                       ||
| IMMEDIATE   | IMMEDIATE | 0(0) |`ok: im0   ." Im not " ; `<br />`ok: im1   ." Im immediate " ; IMMEDIATE`<br />`ok: tstimm im0 im1 ;Im immediate`<br />`ok`|:white_check_mark:|
| STATE   | STATEW | 2(2) |`ok .stateNow interpreting`<br />`ok`|:white_check_mark:[^1]|
| [ ]  | LBRACKET RBRACKET | 0(0) |`ok: c144 [ 12 12 * ] LITERAL ;`<br />`ok c144 . 144`<br />`ok`|:white_check_mark:|
| '   | TICK | 0(0) |`ok : hi0  ." Hi!" ;`<br />`ok ' hi0 EXECUTE Hi!`<br />`ok`|:white_check_mark:|
| [']  | BRACKTICK | 0(0) |`ok : english  ." Hi!" ;`<br />`ok : greet  ['] english EXECUTE ;`<br />`ok greet Hi!`<br />`ok`|:white_check_mark:|
| >BODY   | TOBODY | 0(0) |`ok CREATE d0  123 ,  456 ,`<br />`ok ' d0 >BODY @ . 123`<br />`ok`|:white_check_mark:|
| COMPILE,   | COMPILECOMMA | 0(0) |`ok : calc0 1 + macro-sq ;`<br />`ok 5 calc0 . 36`|:white_check_mark:[^2]|
| LITERAL   | LITERALW | 0(0) |`ok: c144 [ 12 12 * ] LITERAL ;`<br />`ok c144 . 144`<br />`ok`|:white_check_mark:|
| SLITERAL | SLITERALW | 0(0) |`ok: S\| [CHAR] \| PARSE POSTPONE SLITERAL ; IMMEDIATE`<br />`ok : tst\| S\| piping\| TYPE ;`<br />`ok tst\| piping`<br />`ok`|:white_check_mark:[^4]|
| POSTPONE   | POSTPONEW | 0(0) |`ok ok: ENDIF  POSTPONE THEN ; IMMEDIATE`<br />`ok : testendif DUP 0 > IF ." Positive" ENDIF ;`<br />`ok 5 testendifPositive`<br />`ok`|:white_check_mark:[^2]|
| EXECUTE | EXECUTE | 0(0) |``ok : hi0  ." Hi!" ;`<br />`ok ' hi0 EXECUTE Hi!`<br />`ok`|:white_check_mark:|
| ABORT"   | ABORTQUOTE | 0(0) |`ok: div-chk DUP 0= ABORT" Error: Division by zero!" / ;`<br />`ok 17 0 div-chk Error: Division by zero! ERROR -2`<br />`ok`|:white_check_mark:[^4]|


[^1]: STATE was tested using the word definition below. 
      This exposed 2 bugs in multiline word definitions. 
      Only single line definitions were used previously.
      1. The QLOOP was reseting the interpreter mode on each line.
      1. The compilation mode was not echoing the CR.
      Bug is fixed. 
      ```
      : .state
          STATE @ 
          0= IF  
              ." Now interpreting"  
        ELSE  
            ." Now compiling"
        THEN ;
   
       .state
       ```

[^2]: COMPILE, is tested using the setup below: 
      ```
      : square DUP * ;
      ' square CONSTANT cons-sq
      : macro-sq cons-sq COMPILE, ; IMMEDIATE     
      ```
