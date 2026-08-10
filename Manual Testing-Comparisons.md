# Manual Tests

| Test        | Assembly Routine | Bug Count (Fixes)| Example        | Success ? |
|:------------|:-----------------|:--------------|:------------------|----------:|
| **Comparisons** |        |      |                       ||
| =     | EQUALW  | 0 (0)  | `ok5 5 = .S -1`<br />`ok5 6 = .S 0 -1`<br />`ok`|:white_check_mark:|
| <>    | NOTEQUAL  | 0 (0)  | `ok 5 5 <> .S 0`<br />`ok5 6 <> .S -1 0`<br />`ok`|:white_check_mark:|
| <     | LESSW  | 0 (0)  | `ok 5 5 < .S 0`<br />`ok5 6 < .S -1 0`<br />`ok`|:white_check_mark:|
| >     | GREATERW  | 0 (0)  | `ok5 5 > .S 0`<br />`ok6 5 > .S -1 0`<br />`ok`|:white_check_mark:|
| 0=    | ZEROEQ  | 0 (0)  | `ok5 0= .S 0 `<br />`ok0 0= .S -1 0`<br />`ok`|:white_check_mark:|
| 0<    | ZEROLT  | 0 (0)  | `ok5 0< .S 0`<br />`ok-5 0< .S -1 0`<br />`ok`|:white_check_mark:|
| 0>    | ZEROGT  | 0 (0)  | `ok5 0> .S -1`<br />`ok-5 0> .S 0 -1`<br />`ok`|:white_check_mark:|
| 0<>   | ZERONE  | 0 (0)  | `ok5 0<> .S -1`<br />`ok0 0<> .S 0 -1`<br />`ok`|:white_check_mark:|
| U<    | ULESSW  | 0 (0)    | `ok9 8 U< .S 0`<br />`ok8 9 U< .S -1 0`<br />`ok8 8 U< .S 0 -1 0`<br />`ok`|:white_check_mark:|
| U>    | UGREATER  | 0 (0)  | `ok7 8 U> .S 0`<br />`ok8 7 U> .S -1 0`<br />`ok8 8 U> .S 0 -1 0`<br />`ok`|:white_check_mark:|
| D=    | DEQUAL  | 0 (0)    | `ok 5 6 7 8 D= .S 0`<br />`ok 5 6 5 6 D= .S -1 0`<br />`ok -5 6 -5 6 D= .S -1 -1 0`<br />`ok`|:white_check_mark:|
| D<    | DLESSW  | 0 (0)    | `ok 5 6 7 8 D< .S -1`<br />`ok 7 8 5 6 D< .S 0 -1`<br />`ok 7 8 7 8 D< .S 0 0 -1`<br />`ok`|:white_check_mark:|
| DU<   | DULESSW  | 0 (0)   | `ok 16 2 5 9 DU< .S -1 `<br />`ok 5 9 16 2 DU< .S 0 -1`<br />`ook 5 9 5 9 DU< .S 0 0 -1`<br />`ok`|:white_check_mark:|
| WITHIN| WITHINW  | 0 (0)   | `ok 5 3 6 WITHIN .S -1`<br />`ok 3 3 3 WITHIN .S 0 -1`<br />`ok 3 3 6 WITHIN .S -1 0 -1`<br />`ok`|:white_check_mark:|

                                                          
                                                                      
                                                              
                                                                        
                                                         
                                                                
                                                         
                                                 
                                                           
                                                      
                                                                
                                                                      
                                                                               
                                                                     
                                                                
                                            
                                                                        
                                                                               
                                                    
                                                                  
                                                      
                                                          
     
    
    
                                                       
  