# Words to Satisfy the ANS Forth WordList Requirements

## Source
[https://forth-standard.org/standard/search](Search)

## Data Types
1. An array of 8 cells to map WID to head of linked sublist.
1. A cell representing the index of the next available cell in the list
   Address is VOC-HERE. Initialised to 0.
1. A byte CCONSTANT representing the size.
1. A cell containing the CURRENT head of the linked sublist.
1. An array of 8 cells containing a list of WID's to define the search order.
1. A byte CCONSTANT representing the size.

--------------------------------------------------------
| Word      | Where                                    |
--------------------------------------------------------
| WORDLISTS | 3.2.6 Environmental queries.             |
| [https://forth-standard.org/standard/search/SEARCH-WORDLIST](SEARCH-WORDLIST) |
| [https://forth-standard.org/standard/search/FIND](FIND) |
| [https://forth-standard.org/standard/search/DEFINITIONS](DEFINITIONS)|
| Word | Where                                         |
| Word | Where                                         |
| Word | Where                                         |
| Word | Where                                         |
| Word | Where                                         |
| Word | Where                                         |
| Word | Where                                         |
| Word | Where                                         |
| Word | Where                                         |
