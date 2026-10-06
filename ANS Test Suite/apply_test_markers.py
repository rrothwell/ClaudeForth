#!/usr/bin/env python3
"""
apply_test_markers.py - one-shot, idempotent edit that moves the ANS test
reporting into the test files themselves.

  * 00_test_prelude.fs : defines TEST-BEGIN / TEST-END (and calls them
                         around its own checks)
  * ttester.fs         : the old TEST-REPORT word is removed (TESTCOUNT and
                         FAILCOUNT stay: }T still increments them)
  * every *.tests.fs   : TEST-BEGIN is inserted right after its
                         "MARKER Mnn" line, TEST-END right before the
                         closing "Mnn" (and that line's comment)

Usage:  python3 apply_test_markers.py DIR [--dry-run]
DIR holds the test files (.fs, or .fs.txt as stored in the project).
Safe to run twice: files that already have the calls are left alone.
Line endings are preserved; a .bak copy is NOT made, so run it on a copy
or under version control if in doubt.
"""
import re
import sys
from pathlib import Path

PRELUDE_BLOCK = r"""
\ ---- Test reporting: TEST-BEGIN / TEST-END ----
\ Every test file calls TEST-BEGIN on the line after its MARKER and
\ TEST-END on the line before its closing marker. Together they are
\ the whole per-file report - nothing else is needed, with or without
\ the Python test runner.
\   TEST-BEGIN  zeroes the pass/fail counters (TESTCOUNT, FAILCOUNT,
\               bumped by }T in ttester.fs) and records the data
\               stack depth, so stray cells can be spotted later.
\   TEST-END    prints "TEST SUMMARY: N run, M failed" (always in
\               DECIMAL) then, if the file left the stack deeper than
\               TEST-BEGIN found it, "STACK IMBALANCE: n extra cell(s)
\               dropped" and drops them so the next file starts clean.
\               (A shallower stack is reported as "cell(s) missing".)
VARIABLE TEST-DEPTH
: TEST-BEGIN ( -- )
0 TESTCOUNT ! 0 FAILCOUNT !
DEPTH TEST-DEPTH ! ;
: TEST-END ( -- )
BASE @ >R DECIMAL
CR ." TEST SUMMARY: " TESTCOUNT @ . ." run, "
FAILCOUNT @ . ." failed" CR
DEPTH TEST-DEPTH @ > IF
." STACK IMBALANCE: " DEPTH TEST-DEPTH @ - .
." extra cell(s) dropped" CR
DEPTH TEST-DEPTH @ DO DROP LOOP
THEN
DEPTH TEST-DEPTH @ < IF
." STACK IMBALANCE: " TEST-DEPTH @ DEPTH - .
." cell(s) missing" CR
THEN
R> BASE ! ;

\ Report on the prelude's own checks below, too.
TEST-BEGIN
"""

TTESTER_REPLACEMENT = (
    "\\ TEST-BEGIN / TEST-END (the per-file report that reads TESTCOUNT\n"
    "\\ and FAILCOUNT) are defined in 00_test_prelude.fs.\n"
)


def read(p):
    data = p.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in data else "\n"
    return data.replace("\r\n", "\n"), nl


def write(p, text, nl, dry):
    if not dry:
        p.write_bytes(text.replace("\n", nl).encode("utf-8"))


def do_prelude(p, dry):
    text, nl = read(p)
    if ": TEST-BEGIN" in text:
        return "already done"
    m = re.search(r"^MARKER MTPRELUDE[ \t]*\n(?:.*\n)*?HEX[ \t]*\n", text, re.M)
    if not m:
        return "SKIPPED: could not find 'MARKER MTPRELUDE' followed by 'HEX'"
    text = text[:m.end()] + PRELUDE_BLOCK + text[m.end():]
    if not text.endswith("\n"):
        text += "\n"
    text += "\\ Report on the prelude's own checks and trim any stray cells.\nTEST-END\n"
    write(p, text, nl, dry)
    return "TEST-BEGIN/TEST-END defined; called at head and tail"


def do_ttester(p, dry):
    text, nl = read(p)
    pat = re.compile(r"^: TEST-REPORT\b.*?^0 TESTCOUNT ! 0 FAILCOUNT ! ;[ \t]*\n",
                     re.M | re.S)
    if not pat.search(text):
        return "already done (no TEST-REPORT found)"
    text = pat.sub(lambda m: TTESTER_REPLACEMENT, text, count=1)
    text = text.replace("read by TEST-REPORT (defined alongside }T below)",
                        "read by TEST-END (defined in 00_test_prelude.fs)")
    text = text.replace("TEST-REPORT, just below - see TESTCOUNT's own comment above.",
                        "TEST-END (00_test_prelude.fs) - see TESTCOUNT's comment above.")
    write(p, text, nl, dry)
    return "TEST-REPORT removed"


def do_section(p, dry):
    text, nl = read(p)
    if re.search(r"^TEST-BEGIN[ \t]*$", text, re.M):
        return "already done"
    m = re.search(r"^MARKER (M\d+)[ \t]*$", text, re.M)
    if not m:
        return "SKIPPED: no 'MARKER Mnn' line"
    name = m.group(1)
    ends = [e for e in re.finditer(r"^%s[ \t]*$" % re.escape(name), text, re.M)
            if e.start() > m.end()]
    if not ends:
        return "SKIPPED: no closing '%s' line" % name
    end = ends[-1]
    insert_at = end.start()
    # keep the "undo everything above" comment attached to the marker
    prev = text.rfind("\n", 0, max(insert_at - 1, 0)) + 1
    if re.match(r"\\ -+ section-marker: undo", text[prev:insert_at]):
        insert_at = prev
    tail = ("\\ Print this file's TEST SUMMARY and trim any stray stack cells.\n"
            "TEST-END\n")
    head = ("\n\\ Reset the pass/fail counters, record the stack depth.\n"
            "TEST-BEGIN\n")
    text = text[:insert_at] + tail + text[insert_at:]       # tail first (later offset)
    text = text[:m.end()] + "\n" + head.lstrip("\n") + text[m.end() + 1:]
    write(p, text, nl, dry)
    return "TEST-BEGIN after %s, TEST-END before closing %s" % (name, name)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    d = Path(args[0])
    files = sorted(d.iterdir())
    done = 0
    for p in files:
        n = p.name
        base = n[:-4] if n.endswith(".txt") else n
        if base == "00_test_prelude.fs":
            r = do_prelude(p, dry)
        elif base == "ttester.fs":
            r = do_ttester(p, dry)
        elif base.endswith(".tests.fs"):
            r = do_section(p, dry)
        else:
            continue
        done += 1
        print("%-45s %s" % (n, r))
    print("%d file(s) examined%s" % (done, " (dry run, nothing written)" if dry else ""))


if __name__ == "__main__":
    main()
