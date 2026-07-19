; ============================================================
; 6809 FORTH - 27_forth_dictionary
; Part of the consolidated build; see 00_memory_map_and_globals.asm
; for shared constants and the GLOBALS layout this file depends on.
; ============================================================

; SECTION 27: FORTH DICTIONARY (ROM base dictionary headers)
; Every primitive word in the Glossary gets a real header here,
; chained via LINK, living in BASEDICT ($D85D-$E011, an exact fit
; for this dictionary's 1973 bytes - was $E000-$E7FF). CFA points
; directly at each primitive's own code label for almost every
; entry - these are raw code entries, not DODOES trampolines, so
; CFA = the label itself. The two exceptions are TRUE and FALSE
; (added in a later pass, chain's newest entries): their CFA is
; the DODOES-trampoline pattern instead, matching what CONSTANT
; would compile interactively - see TRUEBODY/FALSEBODY, section
; 26, for why and how.
;
; DOES> is included (H_DOESGT) - added in a follow-up pass after
; the original 214-entry generation flagged it as missing, then
; moved again so it sits immediately after CREATE in the chain
; (H_CREATE -> H_DOESGT -> H_VARIABLE) rather than at the chain's
; newest end, since the two words are tightly coupled and read
; better adjacent. SETDOES (the runtime it compiles a call to)
; lives beside DODOES/DOESRT0; DOESGT is DOES>'s code label,
; since a literal ">" is not valid in a 6809 assembler label.
;
; ABORT and QUIT already have hand-built headers (ABORTHDR/
; QUITHDR, section 26) and are NOT duplicated here. This chain
; is spliced in below them: QUITHDR -> ABORTHDR -> (newest entry
; below) -> ... -> (oldest entry) -> 0. BASELATEST remains QUITHDR.
;
; ABORTHDR's LINK field, a placeholder 0 since it was first built,
; is resolved here: it now points to this chain's newest entry.
;
; Names containing a literal double-quote (S", .", ABORT") have
; that character split into a standalone FCB $22 rather than
; escaped inside FCC - see emit_name's comment for why.
; ============================================================

         ORG   BASEDICT       ; BASEDICT is $E000

H_KEY:
         FCB   $03
         FCC   "KEY"
         FDB   0
         FDB   KEY
H_KEYQ:
         FCB   $04
         FCC   "KEY?"
         FDB   H_KEY
         FDB   KEYQ
H_EMIT:
         FCB   $04
         FCC   "EMIT"
         FDB   H_KEYQ
         FDB   EMIT
H_ACCEPT:
         FCB   $06
         FCC   "ACCEPT"
         FDB   H_EMIT
         FDB   ACCEPT
H_EXPECTW:
         FCB   $06
         FCC   "EXPECT"
         FDB   H_ACCEPT
         FDB   EXPECTW
H_QUERY:
         FCB   $05
         FCC   "QUERY"
         FDB   H_EXPECTW
         FDB   QUERY
H_TYPE:
         FCB   $04
         FCC   "TYPE"
         FDB   H_QUERY
         FDB   TYPE
H_CRW:
         FCB   $02
         FCC   "CR"
         FDB   H_TYPE
         FDB   CRW
H_SPACEW:
         FCB   $05
         FCC   "SPACE"
         FDB   H_CRW
         FDB   SPACEW
H_SPACESW:
         FCB   $06
         FCC   "SPACES"
         FDB   H_SPACEW
         FDB   SPACESW
H_DUP:
         FCB   $03
         FCC   "DUP"
         FDB   H_SPACESW
         FDB   DUP
H_DROP:
         FCB   $04
         FCC   "DROP"
         FDB   H_DUP
         FDB   DROP
H_SWAP:
         FCB   $04
         FCC   "SWAP"
         FDB   H_DROP
         FDB   SWAP
H_OVER:
         FCB   $04
         FCC   "OVER"
         FDB   H_SWAP
         FDB   OVER
H_ROT:
         FCB   $03
         FCC   "ROT"
         FDB   H_OVER
         FDB   ROT
H_QDUP:
         FCB   $04
         FCC   "?DUP"
         FDB   H_ROT
         FDB   QDUP
H_DEPTH:
         FCB   $05
         FCC   "DEPTH"
         FDB   H_QDUP
         FDB   DEPTH
H_DDUP:
         FCB   $04
         FCC   "2DUP"
         FDB   H_DEPTH
         FDB   DDUP
H_DDROP:
         FCB   $05
         FCC   "2DROP"
         FDB   H_DDUP
         FDB   DDROP
H_DSWAP:
         FCB   $05
         FCC   "2SWAP"
         FDB   H_DDROP
         FDB   DSWAP
H_DOVER:
         FCB   $05
         FCC   "2OVER"
         FDB   H_DSWAP
         FDB   DOVER
H_NIP:
         FCB   $03
         FCC   "NIP"
         FDB   H_DOVER
         FDB   NIP
H_TUCK:
         FCB   $04
         FCC   "TUCK"
         FDB   H_NIP
         FDB   TUCK
H_PICK:
         FCB   $04
         FCC   "PICK"
         FDB   H_TUCK
         FDB   PICK
H_ROLL:
         FCB   $04
         FCC   "ROLL"
         FDB   H_PICK
         FDB   ROLL
H_DROT:
         FCB   $04
         FCC   "2ROT"
         FDB   H_ROLL
         FDB   DROT
H_TOR:
         FCB   $02
         FCC   ">R"
         FDB   H_DROT
         FDB   TOR
H_FROMR:
         FCB   $02
         FCC   "R>"
         FDB   H_TOR
         FDB   FROMR
H_RFETCH:
         FCB   $02
         FCC   "R@"
         FDB   H_FROMR
         FDB   RFETCH
H_TWOTOR:
         FCB   $03
         FCC   "2>R"
         FDB   H_RFETCH
         FDB   TWOTOR
H_TWOFROMR:
         FCB   $03
         FCC   "2R>"
         FDB   H_TWOTOR
         FDB   TWOFROMR
H_TWORFETCH:
         FCB   $03
         FCC   "2R@"
         FDB   H_TWOFROMR
         FDB   TWORFETCH
H_PLUS:
         FCB   $01
         FCC   "+"
         FDB   H_TWORFETCH
         FDB   PLUS
H_MINUS:
         FCB   $01
         FCC   "-"
         FDB   H_PLUS
         FDB   MINUS
H_STAR:
         FCB   $01
         FCC   "*"
         FDB   H_MINUS
         FDB   STAR
H_SLASH:
         FCB   $01
         FCC   "/"
         FDB   H_STAR
         FDB   SLASH
H_MODW:
         FCB   $03
         FCC   "MOD"
         FDB   H_SLASH
         FDB   MODW
H_SLASHMOD:
         FCB   $04
         FCC   "/MOD"
         FDB   H_MODW
         FDB   SLASHMOD
H_NEGATE:
         FCB   $06
         FCC   "NEGATE"
         FDB   H_SLASHMOD
         FDB   NEGATE
H_ABSW:
         FCB   $03
         FCC   "ABS"
         FDB   H_NEGATE
         FDB   ABSW
H_MIN:
         FCB   $03
         FCC   "MIN"
         FDB   H_ABSW
         FDB   MIN
H_MAX:
         FCB   $03
         FCC   "MAX"
         FDB   H_MIN
         FDB   MAX
H_ONEPLUS:
         FCB   $02
         FCC   "1+"
         FDB   H_MAX
         FDB   ONEPLUS
H_ONEMINUS:
         FCB   $02
         FCC   "1-"
         FDB   H_ONEPLUS
         FDB   ONEMINUS
H_TWOPLUS:
         FCB   $02
         FCC   "2+"
         FDB   H_ONEMINUS
         FDB   TWOPLUS
H_TWOSTAR:
         FCB   $02
         FCC   "2*"
         FDB   H_TWOPLUS
         FDB   TWOSTAR
H_TWOSLASH:
         FCB   $02
         FCC   "2/"
         FDB   H_TWOSTAR
         FDB   TWOSLASH
H_STARSLASH:
         FCB   $02
         FCC   "*/"
         FDB   H_TWOSLASH
         FDB   STARSLASH
H_STARSLASHMOD:
         FCB   $05
         FCC   "*/MOD"
         FDB   H_STARSLASH
         FDB   STARSLASHMOD
H_UMSTAR:
         FCB   $03
         FCC   "UM*"
         FDB   H_STARSLASHMOD
         FDB   UMSTAR
H_UMSLASHMOD:
         FCB   $06
         FCC   "UM/MOD"
         FDB   H_UMSTAR
         FDB   UMSLASHMOD
H_MSTAR:
         FCB   $02
         FCC   "M*"
         FDB   H_UMSLASHMOD
         FDB   MSTAR
H_FMSLASHMOD:
         FCB   $06
         FCC   "FM/MOD"
         FDB   H_MSTAR
         FDB   FMSLASHMOD
H_SMSLASHREM:
         FCB   $06
         FCC   "SM/REM"
         FDB   H_FMSLASHMOD
         FDB   SMSLASHREM
H_DPLUS:
         FCB   $02
         FCC   "D+"
         FDB   H_SMSLASHREM
         FDB   DPLUS
H_DMINUS:
         FCB   $02
         FCC   "D-"
         FDB   H_DPLUS
         FDB   DMINUS
H_DNEGATEW:
         FCB   $07
         FCC   "DNEGATE"
         FDB   H_DMINUS
         FDB   DNEGATEW
H_DABSW:
         FCB   $04
         FCC   "DABS"
         FDB   H_DNEGATEW
         FDB   DABSW
H_MPLUS:
         FCB   $02
         FCC   "M+"
         FDB   H_DABSW
         FDB   MPLUS
H_STOD:
         FCB   $03
         FCC   "S>D"
         FDB   H_MPLUS
         FDB   STOD
H_DTOS:
         FCB   $03
         FCC   "D>S"
         FDB   H_STOD
         FDB   DTOS
H_DMAXW:
         FCB   $04
         FCC   "DMAX"
         FDB   H_DTOS
         FDB   DMAXW
H_DMINW:
         FCB   $04
         FCC   "DMIN"
         FDB   H_DMAXW
         FDB   DMINW
H_ANDW:
         FCB   $03
         FCC   "AND"
         FDB   H_DMINW
         FDB   ANDW
H_ORW:
         FCB   $02
         FCC   "OR"
         FDB   H_ANDW
         FDB   ORW
H_XORW:
         FCB   $03
         FCC   "XOR"
         FDB   H_ORW
         FDB   XORW
H_INVERT:
         FCB   $06
         FCC   "INVERT"
         FDB   H_XORW
         FDB   INVERT
H_LSHIFT:
         FCB   $06
         FCC   "LSHIFT"
         FDB   H_INVERT
         FDB   LSHIFT
H_RSHIFT:
         FCB   $06
         FCC   "RSHIFT"
         FDB   H_LSHIFT
         FDB   RSHIFT
H_CELLSW:
         FCB   $05
         FCC   "CELLS"
         FDB   H_RSHIFT
         FDB   CELLSW
H_CELLPLUS:
         FCB   $05
         FCC   "CELL+"
         FDB   H_CELLSW
         FDB   CELLPLUS
H_CHARSW:
         FCB   $05
         FCC   "CHARS"
         FDB   H_CELLPLUS
         FDB   CHARSW
H_CHARPLUS:
         FCB   $05
         FCC   "CHAR+"
         FDB   H_CHARSW
         FDB   CHARPLUS
H_ALIGNW:
         FCB   $05
         FCC   "ALIGN"
         FDB   H_CHARPLUS
         FDB   ALIGNW
H_ALIGNEDW:
         FCB   $07
         FCC   "ALIGNED"
         FDB   H_ALIGNW
         FDB   ALIGNEDW
H_EQUALW:
         FCB   $01
         FCC   "="
         FDB   H_ALIGNEDW
         FDB   EQUALW
H_LESSW:
         FCB   $01
         FCC   "<"
         FDB   H_EQUALW
         FDB   LESSW
H_GREATERW:
         FCB   $01
         FCC   ">"
         FDB   H_LESSW
         FDB   GREATERW
H_ZEROEQ:
         FCB   $02
         FCC   "0="
         FDB   H_GREATERW
         FDB   ZEROEQ
H_ZEROLT:
         FCB   $02
         FCC   "0<"
         FDB   H_ZEROEQ
         FDB   ZEROLT
H_ULESSW:
         FCB   $02
         FCC   "U<"
         FDB   H_ZEROLT
         FDB   ULESSW
H_NOTEQUAL:
         FCB   $02
         FCC   "<>"
         FDB   H_ULESSW
         FDB   NOTEQUAL
H_ZERONE:
         FCB   $03
         FCC   "0<>"
         FDB   H_NOTEQUAL
         FDB   ZERONE
H_ZEROGT:
         FCB   $02
         FCC   "0>"
         FDB   H_ZERONE
         FDB   ZEROGT
H_UGREATER:
         FCB   $02
         FCC   "U>"
         FDB   H_ZEROGT
         FDB   UGREATER
H_WITHINW:
         FCB   $06
         FCC   "WITHIN"
         FDB   H_UGREATER
         FDB   WITHINW
H_DEQUAL:
         FCB   $02
         FCC   "D="
         FDB   H_WITHINW
         FDB   DEQUAL
H_DLESSW:
         FCB   $02
         FCC   "D<"
         FDB   H_DEQUAL
         FDB   DLESSW
H_DULESSW:
         FCB   $03
         FCC   "DU<"
         FDB   H_DLESSW
         FDB   DULESSW
H_IF:
         FCB   $82
         FCC   "IF"
         FDB   H_DULESSW
         FDB   IF
H_THEN:
         FCB   $84
         FCC   "THEN"
         FDB   H_IF
         FDB   THEN
H_ELSE:
         FCB   $84
         FCC   "ELSE"
         FDB   H_THEN
         FDB   ELSE
H_BEGIN:
         FCB   $85
         FCC   "BEGIN"
         FDB   H_ELSE
         FDB   BEGIN
H_UNTIL:
         FCB   $85
         FCC   "UNTIL"
         FDB   H_BEGIN
         FDB   UNTIL
H_AGAIN:
         FCB   $85
         FCC   "AGAIN"
         FDB   H_UNTIL
         FDB   AGAIN
H_WHILE:
         FCB   $85
         FCC   "WHILE"
         FDB   H_AGAIN
         FDB   WHILE
H_REPEAT:
         FCB   $86
         FCC   "REPEAT"
         FDB   H_WHILE
         FDB   REPEAT
H_RECURSE:
         FCB   $87
         FCC   "RECURSE"
         FDB   H_REPEAT
         FDB   RECURSE
H_DO:
         FCB   $82
         FCC   "DO"
         FDB   H_RECURSE
         FDB   DO
H_QDO:
         FCB   $83
         FCC   "?DO"
         FDB   H_DO
         FDB   QDO
H_LOOP:
         FCB   $84
         FCC   "LOOP"
         FDB   H_QDO
         FDB   LOOP
H_PLUSLOOP:
         FCB   $85
         FCC   "+LOOP"
         FDB   H_LOOP
         FDB   PLUSLOOP
H_IWORD:
         FCB   $01
         FCC   "I"
         FDB   H_PLUSLOOP
         FDB   IWORD
H_JWORD:
         FCB   $01
         FCC   "J"
         FDB   H_IWORD
         FDB   JWORD
H_LEAVE:
         FCB   $05
         FCC   "LEAVE"
         FDB   H_JWORD
         FDB   LEAVE
H_UNLOOP:
         FCB   $06
         FCC   "UNLOOP"
         FDB   H_LEAVE
         FDB   UNLOOP
H_EXIT:
         FCB   $84
         FCC   "EXIT"
         FDB   H_UNLOOP
         FDB   EXIT
H_CASEW:
         FCB   $84
         FCC   "CASE"
         FDB   H_EXIT
         FDB   CASEW
H_OF:
         FCB   $82
         FCC   "OF"
         FDB   H_CASEW
         FDB   OF
H_ENDOF:
         FCB   $85
         FCC   "ENDOF"
         FDB   H_OF
         FDB   ENDOF
H_ENDCASE:
         FCB   $87
         FCC   "ENDCASE"
         FDB   H_ENDOF
         FDB   ENDCASE
H_COLON:
         FCB   $01
         FCC   ":"
         FDB   H_ENDCASE
         FDB   COLON
H_SEMI:
         FCB   $81
         FCC   ";"
         FDB   H_COLON
         FDB   SEMI
H_CREATE:
         FCB   $06
         FCC   "CREATE"
         FDB   H_SEMI
         FDB   CREATE
H_DOESGT:
         FCB   $85          ; $80 IMMEDIATE | 5 (length of "DOES>")
         FCC   "DOES>"
         FDB   H_CREATE
         FDB   DOESGT
H_VARIABLE:
         FCB   $08
         FCC   "VARIABLE"
         FDB   H_DOESGT
         FDB   VARIABLE
H_CONSTANT:
         FCB   $08
         FCC   "CONSTANT"
         FDB   H_VARIABLE
         FDB   CONSTANT
H_VALUEW:
         FCB   $05
         FCC   "VALUE"
         FDB   H_CONSTANT
         FDB   VALUEW
H_TOW:
         FCB   $82
         FCC   "TO"
         FDB   H_VALUEW
         FDB   TOW
H_TWOVARIABLE:
         FCB   $09
         FCC   "2VARIABLE"
         FDB   H_TOW
         FDB   TWOVARIABLE
H_TWOCONSTANT:
         FCB   $09
         FCC   "2CONSTANT"
         FDB   H_TWOVARIABLE
         FDB   TWOCONSTANT
H_BUFFERCOLON:
         FCB   $07
         FCC   "BUFFER:"
         FDB   H_TWOCONSTANT
         FDB   BUFFERCOLON
H_DEFERW:
         FCB   $05
         FCC   "DEFER"
         FDB   H_BUFFERCOLON
         FDB   DEFERW
H_DEFERFETCH:
         FCB   $06
         FCC   "DEFER@"
         FDB   H_DEFERW
         FDB   DEFERFETCH
H_DEFERSTORE:
         FCB   $06
         FCC   "DEFER!"
         FDB   H_DEFERFETCH
         FDB   DEFERSTORE
H_ISW:
         FCB   $82
         FCC   "IS"
         FDB   H_DEFERSTORE
         FDB   ISW
H_ACTIONOF:
         FCB   $89
         FCC   "ACTION-OF"
         FDB   H_ISW
         FDB   ACTIONOF
H_MARKERW:
         FCB   $06
         FCC   "MARKER"
         FDB   H_ACTIONOF
         FDB   MARKERW
H_IMMEDIATE:
         FCB   $09
         FCC   "IMMEDIATE"
         FDB   H_MARKERW
         FDB   IMMEDIATE
H_STATEW:
         FCB   $05
         FCC   "STATE"
         FDB   H_IMMEDIATE
         FDB   STATEW
H_LBRACKET:
         FCB   $81
         FCC   "["
         FDB   H_STATEW
         FDB   LBRACKET
H_RBRACKET:
         FCB   $81
         FCC   "]"
         FDB   H_LBRACKET
         FDB   RBRACKET
H_TICK:
         FCB   $01
         FCC   "'"
         FDB   H_RBRACKET
         FDB   TICK
H_COMPILECOMMA:
         FCB   $08
         FCC   "COMPILE,"
         FDB   H_TICK
         FDB   COMPILECOMMA
H_LITERALW:
         FCB   $87
         FCC   "LITERAL"
         FDB   H_COMPILECOMMA
         FDB   LITERALW
H_BRACKTICK:
         FCB   $83
         FCC   "[']"
         FDB   H_LITERALW
         FDB   BRACKTICK
H_POSTPONEW:
         FCB   $88
         FCC   "POSTPONE"
         FDB   H_BRACKTICK
         FDB   POSTPONEW
H_TOBODY:
         FCB   $05
         FCC   ">BODY"
         FDB   H_POSTPONEW
         FDB   TOBODY
H_EXECUTE:
         FCB   $07
         FCC   "EXECUTE"
         FDB   H_TOBODY
         FDB   EXECUTE
H_SLITERALW:
         FCB   $88
         FCC   "SLITERAL"
         FDB   H_EXECUTE
         FDB   SLITERALW
H_ABORTQUOTE:
         FCB   $86
         FCC   "ABORT"
         FCB   $22        ; '"' - split out of FCC, not escaped within it
         FDB   H_SLITERALW
         FDB   ABORTQUOTE
H_ATSIGN:
         FCB   $01
         FCC   "@"
         FDB   H_ABORTQUOTE
         FDB   ATSIGN
H_STOREW:
         FCB   $01
         FCC   "!"
         FDB   H_ATSIGN
         FDB   STOREW
H_CFETCH:
         FCB   $02
         FCC   "C@"
         FDB   H_STOREW
         FDB   CFETCH
H_CSTOREW:
         FCB   $02
         FCC   "C!"
         FDB   H_CFETCH
         FDB   CSTOREW
H_PLUSSTORE:
         FCB   $02
         FCC   "+!"
         FDB   H_CSTOREW
         FDB   PLUSSTORE
H_DFETCH:
         FCB   $02
         FCC   "2@"
         FDB   H_PLUSSTORE
         FDB   DFETCH
H_DSTORE:
         FCB   $02
         FCC   "2!"
         FDB   H_DFETCH
         FDB   DSTORE
H_COMMA:
         FCB   $01
         FCC   ","
         FDB   H_DSTORE
         FDB   COMMA
H_CCOMMA:
         FCB   $02
         FCC   "C,"
         FDB   H_COMMA
         FDB   CCOMMA
H_ALLOT:
         FCB   $05
         FCC   "ALLOT"
         FDB   H_CCOMMA
         FDB   ALLOT
H_HEREW:
         FCB   $04
         FCC   "HERE"
         FDB   H_ALLOT
         FDB   HEREW
H_VCOMMA:
         FCB   $02
         FCC   "V,"
         FDB   H_HEREW
         FDB   VCOMMA
H_VCCOMMA:
         FCB   $03
         FCC   "VC,"
         FDB   H_VCOMMA
         FDB   VCCOMMA
H_VALLOT:
         FCB   $06
         FCC   "VALLOT"
         FDB   H_VCCOMMA
         FDB   VALLOT
H_VHEREW:
         FCB   $05
         FCC   "VHERE"
         FDB   H_VALLOT
         FDB   VHEREW
H_PADW:
         FCB   $03
         FCC   "PAD"
         FDB   H_VHEREW
         FDB   PADW
H_UNUSEDW:
         FCB   $06
         FCC   "UNUSED"
         FDB   H_PADW
         FDB   UNUSEDW
H_VUNUSEDW:
         FCB   $07
         FCC   "VUNUSED"
         FDB   H_UNUSEDW
         FDB   VUNUSEDW
H_MOVEW:
         FCB   $04
         FCC   "MOVE"
         FDB   H_VUNUSEDW
         FDB   MOVEW
H_FILLW:
         FCB   $04
         FCC   "FILL"
         FDB   H_MOVEW
         FDB   FILLW
H_ERASEW:
         FCB   $05
         FCC   "ERASE"
         FDB   H_FILLW
         FDB   ERASEW
H_CMOVEW:
         FCB   $05
         FCC   "CMOVE"
         FDB   H_ERASEW
         FDB   CMOVEW
H_CMOVEGT:
         FCB   $06
         FCC   "CMOVE>"
         FDB   H_CMOVEW
         FDB   CMOVEGT
H_COUNT:
         FCB   $05
         FCC   "COUNT"
         FDB   H_CMOVEGT
         FDB   COUNT
H_WORD:
         FCB   $04
         FCC   "WORD"
         FDB   H_COUNT
         FDB   WORD
H_CHARW:
         FCB   $04
         FCC   "CHAR"
         FDB   H_WORD
         FDB   CHARW
H_BRACKCHAR:
         FCB   $86
         FCC   "[CHAR]"
         FDB   H_CHARW
         FDB   BRACKCHAR
H_PARSEW:
         FCB   $05
         FCC   "PARSE"
         FDB   H_BRACKCHAR
         FDB   PARSEW
H_PARSENAME:
         FCB   $0A
         FCC   "PARSE-NAME"
         FDB   H_PARSEW
         FDB   PARSENAME
H_SQUOTE:
         FCB   $82
         FCC   "S"
         FCB   $22        ; '"' - split out of FCC, not escaped within it
         FDB   H_PARSENAME
         FDB   SQUOTE
H_DOTQUOTE:
         FCB   $82
         FCC   "."
         FCB   $22        ; '"' - split out of FCC, not escaped within it
         FDB   H_SQUOTE
         FDB   DOTQUOTE
H_COMPAREW:
         FCB   $07
         FCC   "COMPARE"
         FDB   H_DOTQUOTE
         FDB   COMPAREW
H_SEARCHW:
         FCB   $06
         FCC   "SEARCH"
         FDB   H_COMPAREW
         FDB   SEARCHW
H_DASHTRAILING:
         FCB   $09
         FCC   "-TRAILING"
         FDB   H_SEARCHW
         FDB   DASHTRAILING
H_SLASHSTRING:
         FCB   $07
         FCC   "/STRING"
         FDB   H_DASHTRAILING
         FDB   SLASHSTRING
H_REPLACESW:
         FCB   $08
         FCC   "REPLACES"
         FDB   H_SLASHSTRING
         FDB   REPLACESW
H_SUBSTITUTEW:
         FCB   $0A
         FCC   "SUBSTITUTE"
         FDB   H_REPLACESW
         FDB   SUBSTITUTEW
H_SNAMEW:
         FCB   $05
         FCC   "SNAME"
         FDB   H_SUBSTITUTEW
         FDB   SNAMEW
H_UNESCAPEW:
         FCB   $08
         FCC   "UNESCAPE"
         FDB   H_SNAMEW
         FDB   UNESCAPEW
H_LTNUM:
         FCB   $02
         FCC   "<#"
         FDB   H_UNESCAPEW
         FDB   LTNUM
H_NUMSIGN:
         FCB   $01
         FCC   "#"
         FDB   H_LTNUM
         FDB   NUMSIGN
H_NUMSIGNS:
         FCB   $02
         FCC   "#S"
         FDB   H_NUMSIGN
         FDB   NUMSIGNS
H_NUMGT:
         FCB   $02
         FCC   "#>"
         FDB   H_NUMSIGNS
         FDB   NUMGT
H_HOLD:
         FCB   $04
         FCC   "HOLD"
         FDB   H_NUMGT
         FDB   HOLD
H_HOLDS:
         FCB   $05
         FCC   "HOLDS"
         FDB   H_HOLD
         FDB   HOLDS
H_SIGN:
         FCB   $04
         FCC   "SIGN"
         FDB   H_HOLDS
         FDB   SIGN
H_DOT:
         FCB   $01
         FCC   "."
         FDB   H_SIGN
         FDB   DOT
H_UDOT:
         FCB   $02
         FCC   "U."
         FDB   H_DOT
         FDB   UDOT
H_DOTR:
         FCB   $02
         FCC   ".R"
         FDB   H_UDOT
         FDB   DOTR
H_UDOTR:
         FCB   $03
         FCC   "U.R"
         FDB   H_DOTR
         FDB   UDOTR
H_QMARK:
         FCB   $01
         FCC   "?"
         FDB   H_UDOTR
         FDB   QMARK
H_DDOT:
         FCB   $02
         FCC   "D."
         FDB   H_QMARK
         FDB   DDOT
H_DDOTR:
         FCB   $03
         FCC   "D.R"
         FDB   H_DDOT
         FDB   DDOTR
H_BASEW:
         FCB   $04
         FCC   "BASE"
         FDB   H_DDOTR
         FDB   BASEW
H_DECIMAL:
         FCB   $07
         FCC   "DECIMAL"
         FDB   H_BASEW
         FDB   DECIMAL
H_HEXW:
         FCB   $03
         FCC   "HEX"
         FDB   H_DECIMAL
         FDB   HEXW
H_BINARYW:
         FCB   $06
         FCC   "BINARY"
         FDB   H_HEXW
         FDB   BINARYW
H_CATCH:
         FCB   $05
         FCC   "CATCH"
         FDB   H_BINARYW
         FDB   CATCH
H_THROW:
         FCB   $05
         FCC   "THROW"
         FDB   H_CATCH
         FDB   THROW
H_LPAREN:
         FCB   $81
         FCC   "("
         FDB   H_THROW
         FDB   LPAREN
H_BACKSLASH:
         FCB   $81
         FCC   "\"
         FDB   H_LPAREN
         FDB   BACKSLASH
H_ENVQUERY:
         FCB   $0C
         FCC   "ENVIRONMENT?"
         FDB   H_BACKSLASH
         FDB   ENVQUERY
H_SOURCEW:
         FCB   $06
         FCC   "SOURCE"
         FDB   H_ENVQUERY
         FDB   SOURCEW
H_SOURCEID:
         FCB   $09
         FCC   "SOURCE-ID"
         FDB   H_SOURCEW
         FDB   SOURCEID
H_REFILLW:
         FCB   $06
         FCC   "REFILL"
         FDB   H_SOURCEID
         FDB   REFILLW
H_EVALUATEW:
         FCB   $08
         FCC   "EVALUATE"
         FDB   H_REFILLW
         FDB   EVALUATEW
H_TIBW:
         FCB   $03
         FCC   "TIB"
         FDB   H_EVALUATEW
         FDB   TIBW
H_NTIBW:
         FCB   $04
         FCC   "#TIB"
         FDB   H_TIBW
         FDB   NTIBW
H_TOINW:
         FCB   $03
         FCC   ">IN"
         FDB   H_NTIBW
         FDB   TOINW
H_SPANW:
         FCB   $04
         FCC   "SPAN"
         FDB   H_TOINW
         FDB   SPANW
H_BLW:
         FCB   $02
         FCC   "BL"
         FDB   H_SPANW
         FDB   BLW
H_DOTS:
         FCB   $02
         FCC   ".S"
         FDB   H_BLW
         FDB   DOTS
H_WORDSW:
         FCB   $05
         FCC   "WORDS"
         FDB   H_DOTS
         FDB   WORDSW
H_DUMPW:
         FCB   $04
         FCC   "DUMP"
         FDB   H_WORDSW
         FDB   DUMPW

H_TRUE:
         FCB   $04
         FCC   "TRUE"
         FDB   H_DUMPW
         FDB   TRUEBODY

H_FALSE:
         FCB   $05
         FCC   "FALSE"
         FDB   H_TRUE
         FDB   FALSEBODY

DICTTOP  EQU   H_FALSE   ; newest entry in this base chain

; Verify no collision with base code.
; Value should match ORG BASECODE
BASEDICTEND  EQU   *
BASEDICTSIZE EQU   BASEDICTEND-BASEDICT

; ============================================================
