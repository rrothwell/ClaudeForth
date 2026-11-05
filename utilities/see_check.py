# Regression check for SEE: define words, SEE them, compare the exact text.
import sys, re
sys.path.insert(0,'/home/claude/w6l')
from fh import make
rom = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/w6l/forth6809_stage_6m.asm'
defs = eval(sys.argv[2]) if len(sys.argv) > 2 else {}
f = make(rom, defs)
CASES = [
 ("A1", ": A1 DUP 0< IF NEGATE THEN ;", ": A1 DUP 0< IF NEGATE THEN ;"),
 ("A2", ": A2 DUP 0= IF DROP 1 ELSE DUP 1- RECURSE * THEN ;", ": A2 DUP 0= IF DROP 1 ELSE DUP 1- A2 * THEN ;"),
 ("A3", ": A3 BEGIN DUP . 1- DUP 0= UNTIL DROP ;", ": A3 BEGIN DUP . 1- DUP 0= UNTIL DROP ;"),
 ("A4", ": A4 BEGIN DUP 5 < WHILE 1+ REPEAT ;", ": A4 BEGIN DUP 5 < WHILE 1+ REPEAT ;"),
 ("A5", ": A5 10 0 DO I . LOOP ;", ": A5 10 0 DO I . LOOP ;"),
 ("A6", ": A6 10 0 ?DO I . 2 +LOOP ;", ": A6 10 0 ?DO I . 2 +LOOP ;"),
 ("A7", ': A7 ." hello" S" abc" TYPE ABORT" bad" ;', ': A7 ." hello" S" abc" TYPE ABORT" bad" ;'),
 ("A8", ": A8 BEGIN KEY DROP AGAIN ;", ": A8 BEGIN KEY DROP AGAIN ;"),
 ("A9", ": A9 DUP IF DUP IF 1 ELSE 2 THEN ELSE 3 THEN DROP ;", ": A9 DUP IF DUP IF 1 ELSE 2 THEN ELSE 3 THEN DROP ;"),
 ("B1", ": B1 5 0 DO 3 0 DO I J + . LOOP LOOP ;", ": B1 5 0 DO 3 0 DO I J + . LOOP LOOP ;"),
 ("B2", ": B2 1 CASE 1 OF 10 ENDOF 2 OF 20 ENDOF 0 ENDCASE ;", ": B2 1 1 OVER = IF DROP 10 ELSE 2 OVER = IF DROP 20 ELSE 0 DROP THEN THEN ;"),
 ("B3", ": B3 DUP IF BEGIN DUP WHILE 1- REPEAT THEN DROP ;", ": B3 DUP IF BEGIN DUP WHILE 1- REPEAT THEN DROP ;"),
 ("B4", ": B4 BEGIN DUP WHILE DUP IF 1 ELSE 2 THEN DROP 1- REPEAT ;", ": B4 BEGIN DUP WHILE DUP IF 1 ELSE 2 THEN DROP 1- REPEAT ;"),
 ("B6", ": B6 -5 EXIT ;", ": B6 -5 EXIT ;"),
 ("B7", ": B7 DUP IF EXIT THEN DROP ;", ": B7 DUP IF EXIT THEN DROP ;"),
 ("C1", ': C1 S" " TYPE DUP DROP ;', ': C1 S" " TYPE DUP DROP ;'),
 ("V", "VARIABLE V", "CREATE V DATA 576"),
 ("K", "5 CONSTANT K", None),
 ("MK", ": MK CREATE , DOES> @ 1+ ;", ": MK CREATE , DOES> @ 1+ ;"),
]
bad = 0
for name, src, want in CASES:
    f.run(src + '\n', limit=200_000_000)
    out, r = f.run('SEE ' + name + '\n', limit=200_000_000)
    out = out.replace('\x11', '').replace('\x13', '')
    got = ' '.join(out.replace('SEE ' + name, '').replace('ok', '').split())
    if want is None:
        print('INFO', name, '->', got); continue
    if got != want:
        bad += 1
        print('BAD', name, '\n   got ', got, '\n   want', want)
print('SEE checks:', len(CASES), 'run,', bad, 'differ')
