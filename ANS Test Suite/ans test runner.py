#!/usr/bin/env python3
"""
ans_test_runner.py - runs the ANS Forth test suite (ans_tests/) against a
live forth6809 image, over either a MAME "-bitb" TCP socket or a real
serial-connected MECB6809 with the Forth binary in EPROM.

Why this exists (vs. minicom): forth6809's outer interpreter (QUIT) is
line-based - it reads one line via ACCEPT, interprets it, then prints
"\r\n  ok" (or "\r\n  ERROR n" on a thrown exception) before reading the
next line. That "ok"/"ERROR" reply is a natural, content-based ready
signal. Instead of pasting a whole file at a fixed baud rate and hoping
end-of-character delays are long enough (the approach currently being
fought with minicom, and the subject of the ongoing interrupt/RTS
handshaking investigation), this script sends exactly one line, then
BLOCKS until it sees that line's own "ok"/"ERROR" reply before sending
the next one. That makes the pacing self-adjusting to however fast the
target actually is - MAME under the debugger, MAME free-running, or real
hardware - with no delay constant to tune per platform.

Three things this script does, per the project's outstanding ANS-test
task list:

  1. Loads the [IF]/[ELSE]/[THEN] tool-extension words first
     (00a_tool_ext_conditionals.fs) - forth6809.asm doesn't implement
     them, but ttester.fs needs them immediately (its own
     HAS-FLOATING / HAS-FLOATING-STACK checks use [IF]/[ELSE]/[THEN]).
  2. Loads the shared preamble: ttester.fs, then 00_test_prelude.fs.
  3. Loads one or more per-section *.tests.fs files. Each of those files
     is now self-contained: 09_outer_interpreter.tests.fs carries its
     own copy of GT1/GT2 rather than depending on section 13 having run
     first, and every section file opens with "MARKER Mnn" and closes by
     invoking Mnn, which erases everything that file itself defined
     (confirmed against forth6809.asm's MARKERW/DOMARKER - it snapshots
     and restores DPHERE/CODEHERE/VARHERE/LATEST, i.e. dictionary,
     value-space and the search-chain all at once). That makes each
     section file independently runnable, in any order, any number of
     times, from a single shared harness+prelude load.

Long test-file lines are re-wrapped before sending: forth6809's TIB is
80 bytes (TIBBUFL EQU 80 in forth6809.asm), but several *.tests.fs lines
run past 1000 characters (many "T{ ... }T" blocks concatenated on one
source line, harmless to a file-based INCLUDE but fatal to a terminal
that ACCEPTs 80 bytes per line). Re-wrapping only ever splits at
whitespace outside of S"/."-delimited strings, so it never changes the
token stream Forth sees, and never splits a "\" line comment (which
would turn its tail into live code on the next line).

Usage examples:

    # Against MAME (spawns it, using the same -rs232 null_modem -bitb
    # socket approach as run_all_tests.sh):
    python3 ans_test_runner.py --target mame \\
        --sections 08 09 10 11 12 13 14 15 16 17 18 19 20 21 23 24 26

    # Against real hardware over a serial port:
    python3 ans_test_runner.py --target serial --serial-port /dev/ttyUSB0 \\
        --baud 19200 --sections 15

Run with --help for every option and its default.
"""

import argparse
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

# ------------------------------------------------------------------
# Constants matching forth6809.asm
# ------------------------------------------------------------------
TIBBUFL = 80          # forth6809.asm: TIBBUFL EQU 80
SAFE_LINE_WIDTH = 72  # leave headroom below TIBBUFL for CR and slop

OK_MARKER = b"  ok"
ERROR_MARKER = b"  ERROR "

# ttester.fs's own failure messages (from ERROR1's S" ... " text, per
# ttester.fs read directly out of this project's ans_tests/ directory)
# plus forth6809's own system-level abort message. Any of these
# appearing in a section's captured transcript means that section did
# NOT fully pass, regardless of whether "ok" also appeared.
FAILURE_PATTERNS = [
    b"INCORRECT RESULT:",
    b"WRONG NUMBER OF RESULTS:",
    b"INCORRECT CELL RESULT:",
    b"NUMBER OF CELL RESULTS BEFORE '->' DOES NOT MATCH",
    b"NUMBER OF CELL RESULTS BEFORE AND AFTER '->' DOES NOT MATCH:",
    b"NUMBER OF RESULTS AFTER '->' BELOW ...}T SPECIFICATION:",
    b"INCORRECT FP RESULT:",
    b"WRONG NUMBER OF FP RESULTS:",
    ERROR_MARKER,
]

DEFAULT_SECTIONS = [
    "08", "09", "10", "11", "12", "13", "14", "15", "16",
    "17", "18", "19", "20", "21", "23", "24", "26",
]


# ------------------------------------------------------------------
# Line re-wrapping: split long lines only on whitespace outside
# S"/."-delimited strings, and never touch a "\" comment line.
# ------------------------------------------------------------------
def rewrap_line(line, width=SAFE_LINE_WIDTH):
    stripped = line.strip("\r\n")
    if len(stripped) <= width:
        return [stripped] if stripped != "" or True else []

    leading = stripped.lstrip(" \t")
    if leading.startswith("\\") and (len(leading) == 1 or leading[1] in " \t"):
        # A "\" line comment: never split (its tail would become live
        # code on a continuation line). Just send it long - the target
        # discards it as a comment before hitting any length limit
        # inside its own text-parsing (parses one BL-delimited "word"
        # per token normally, but the whole rest of the line is inside
        # a comment, so nothing is ever an over-length token here).
        return [stripped]

    # Tokenize preserving S"/."-prefixed string literals as atomic
    # units so a rewrap point never lands inside one.
    tokens = []
    i = 0
    n = len(stripped)
    while i < n:
        while i < n and stripped[i] in " \t":
            i += 1
        if i >= n:
            break
        start = i
        # Detect a string-introducing word: S" / ." / C" / ABORT"
        # followed by exactly one space then a '"'-terminated string.
        word_end = i
        while word_end < n and stripped[word_end] not in " \t":
            word_end += 1
        word = stripped[i:word_end]
        if word in ('S"', '."', 'C"', 'ABORT"') and word_end < n and stripped[word_end] == " ":
            close = stripped.find('"', word_end + 1)
            if close != -1:
                tokens.append(stripped[start:close + 1])
                i = close + 1
                continue
        tokens.append(stripped[start:word_end])
        i = word_end

    lines = []
    cur = ""
    for tok in tokens:
        candidate = tok if cur == "" else cur + " " + tok
        if len(candidate) > width and cur != "":
            lines.append(cur)
            cur = tok
        else:
            cur = candidate
    if cur:
        lines.append(cur)
    return lines


def rewrap_source(text):
    out = []
    for line in text.split("\n"):
        out.extend(rewrap_line(line))
    return out


# ------------------------------------------------------------------
# Transports
# ------------------------------------------------------------------
class SocketTransport:
    """Binds and listens BEFORE the caller spawns MAME, exactly like
    mame_listener.py does - MAME's own "-bitb socket.HOST:PORT" tries to
    CONNECT as a client first, so it connects straight in with no device
    path to discover and no startup race."""

    def __init__(self, host, port, accept_timeout):
        self.srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.srv.bind((host, port))
        self.srv.listen(1)
        self.srv.settimeout(accept_timeout)
        self.conn = None

    def accept(self):
        self.conn, addr = self.srv.accept()
        self.conn.settimeout(0.2)
        return addr

    def write(self, data):
        self.conn.sendall(data)

    def read_some(self):
        try:
            data = self.conn.recv(4096)
        except socket.timeout:
            return b""
        if data == b"":
            raise ConnectionResetError("connection closed by peer")
        return data

    def close(self):
        try:
            if self.conn:
                self.conn.close()
        finally:
            self.srv.close()


class SerialTransport:
    """Real serial-connected MECB6809, Forth binary in EPROM. Requires
    pyserial (pip install pyserial). rtscts=True enables hardware flow
    control at the host-OS/driver level, independent of whatever
    forth6809's own RTS/CTS firmware logic is doing - it is the
    project's stated eventual target alongside MAME."""

    def __init__(self, port, baud, rtscts):
        import serial  # local import: only required for this transport
        self.ser = serial.Serial(
            port=port, baudrate=baud, timeout=0.2, rtscts=rtscts,
        )

    def write(self, data):
        self.ser.write(data)
        self.ser.flush()

    def read_some(self):
        return self.ser.read(4096)

    def close(self):
        self.ser.close()


# ------------------------------------------------------------------
# MAME process management (mirrors run_all_tests.sh's approach)
# ------------------------------------------------------------------
def launch_mame(args):
    cmd = [
        args.mame_bin, args.mame_system,
        "-rs232", "null_modem",
        "-bitb", f"socket.{args.listener_host}:{args.listener_port}",
        "-debug", "-debugscript", args.retrigger_cmd,
        "-window", "-resolution", "640x480",
    ]
    print(f"[mame] launching: {' '.join(cmd)}", file=sys.stderr)
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def assemble_rom(args):
    cmd = [
        args.lwasm_bin, "--6809", "--format=raw",
        f"--output={args.rom_out}", f"--list={args.rom_out}.lst",
        f"--define=UNITTESTS={args.unittests}",
        f"--define=SERIALPOLL={args.serialpoll}",
        args.asm_source,
    ]
    print(f"[asm] {' '.join(cmd)}", file=sys.stderr)
    subprocess.run(cmd, check=True)
    Path(args.rom_out).replace(args.rom_dest)


# ------------------------------------------------------------------
# The line-at-a-time send/wait protocol
# ------------------------------------------------------------------
class LineResult:
    def __init__(self, sent, echoed, ok, error, timed_out):
        self.sent = sent
        self.echoed = echoed
        self.ok = ok
        self.error = error
        self.timed_out = timed_out


def send_line_and_wait(transport, line, char_delay, reply_timeout, log):
    """Send one line, terminated by CR (forth6809's ACCEPT/QUIT treat CR
    ($0D) as end-of-line and silently ignore LF - see ACCEPT's ALOOP:
    CMPB #13 -> ADONE, CMPB #10 -> BRA ALOOP - so CR alone is correct and
    sending CRLF would just cost one ignored byte per line for no
    benefit)."""
    payload = line.encode("ascii", errors="replace") + b"\r"
    if char_delay > 0:
        for b in payload:
            transport.write(bytes([b]))
            time.sleep(char_delay)
    else:
        transport.write(payload)

    buf = b""
    deadline = time.monotonic() + reply_timeout
    saw_ok = False
    saw_error = False
    while time.monotonic() < deadline:
        chunk = transport.read_some()
        if chunk:
            buf += chunk
            log.write(chunk)
            log.flush()
            if OK_MARKER in buf:
                saw_ok = True
                break
            if ERROR_MARKER in buf:
                saw_error = True
                # keep draining briefly to catch the throw-code digits
                drain_deadline = time.monotonic() + 0.5
                while time.monotonic() < drain_deadline:
                    extra = transport.read_some()
                    if extra:
                        buf += extra
                        log.write(extra)
                        drain_deadline = time.monotonic() + 0.5
                break
    timed_out = not (saw_ok or saw_error)
    return LineResult(payload, buf, saw_ok, saw_error, timed_out), buf


def send_file(transport, path, char_delay, reply_timeout, retries, log, transcript):
    text = Path(path).read_text()
    lines = rewrap_source(text)
    fail_hit = False
    for line in lines:
        if line.strip() == "":
            continue
        attempt = 0
        while True:
            attempt += 1
            result, buf = send_line_and_wait(transport, line, char_delay, reply_timeout, log)
            transcript.extend(buf.split(b"\n"))
            if result.timed_out and attempt <= retries:
                print(f"    [retry {attempt}] no ok/ERROR within {reply_timeout}s for: {line[:60]!r}",
                      file=sys.stderr)
                continue
            if result.timed_out:
                print(f"    [FAIL] gave up after {retries} retries on: {line[:60]!r}", file=sys.stderr)
                fail_hit = True
            break
    return fail_hit


def classify(transcript_bytes):
    for pattern in FAILURE_PATTERNS:
        if pattern in transcript_bytes:
            return False
    return True


def run_section(transport, ans_dir, section, char_delay, reply_timeout, retries, log_dir):
    matches = sorted(Path(ans_dir).glob(f"{section}_*.tests.fs"))
    if not matches:
        print(f"[skip] no test file found for section {section}", file=sys.stderr)
        return None
    path = matches[0]
    print(f"=== section {section} ({path.name}) ===")
    log_path = Path(log_dir) / f"{section}.raw.log"
    transcript = []
    with open(log_path, "wb") as log:
        timed_out_any = send_file(transport, path, char_delay, reply_timeout, retries, log, transcript)
    transcript_bytes = b"\n".join(transcript)
    passed = classify(transcript_bytes) and not timed_out_any
    print(f"    -> {'PASS' if passed else 'FAIL'} (log: {log_path})")
    return passed


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--target", choices=["mame", "serial"], required=True)
    p.add_argument("--ans-dir", default="ans_tests", help="directory containing ans_tests/ files")
    p.add_argument("--sections", nargs="+", default=DEFAULT_SECTIONS,
                    help="section number prefixes to run, e.g. 08 09 10 (default: all known sections)")
    p.add_argument("--char-delay", type=float, default=0.0,
                    help="extra seconds between individual characters within a line (default: 0, rely on ok-sync alone)")
    p.add_argument("--reply-timeout", type=float, default=10.0,
                    help="seconds to wait for 'ok'/'ERROR' after a line before treating it as lost (default: 10)")
    p.add_argument("--retries", type=int, default=2,
                    help="retries per line before giving up (default: 2)")
    p.add_argument("--log-dir", default="ans_test_results")

    # mame-target options (mirror run_all_tests.sh's flags/defaults)
    p.add_argument("--asm-source", default="forth6809.asm")
    p.add_argument("--lwasm-bin", default="lwasm")
    p.add_argument("--mame-bin", default="./mecb6809")
    p.add_argument("--mame-system", default="mecb6809")
    p.add_argument("--rom-out", default="forth6809.bin")
    p.add_argument("--rom-dest", default=str(Path.home() / "Library/Application Support/mame/roms/mecb6809/mecb6809.bin"))
    p.add_argument("--retrigger-cmd", default="retrigger.cmd")
    p.add_argument("--listener-host", default="127.0.0.1")
    p.add_argument("--listener-port", type=int, default=2000)
    p.add_argument("--serialpoll", type=int, default=1, choices=[0, 1],
                    help="assemble with polling (1, default - avoids the interrupt/RTS handshake bug currently "
                         "under separate investigation) or interrupt-driven (0) serial I/O")
    p.add_argument("--unittests", type=int, default=0, choices=[0, 1],
                    help="0 (default): a normal end-user image, which is what the ANS suite is meant to exercise")
    p.add_argument("--skip-assemble", action="store_true",
                    help="reuse whatever ROM is already at --rom-dest instead of reassembling")
    p.add_argument("--mame-accept-timeout", type=float, default=30.0,
                    help="seconds to wait for MAME's initial connection (default: 30)")

    # serial-target options
    p.add_argument("--serial-port")
    p.add_argument("--baud", type=int, default=19200)
    p.add_argument("--rtscts", action="store_true", help="enable hardware RTS/CTS flow control")

    args = p.parse_args()

    Path(args.log_dir).mkdir(parents=True, exist_ok=True)

    mame_proc = None
    if args.target == "mame":
        if not args.skip_assemble:
            assemble_rom(args)
        transport = SocketTransport(args.listener_host, args.listener_port, args.mame_accept_timeout)
        mame_proc = launch_mame(args)
        try:
            addr = transport.accept()
            print(f"[mame] connected from {addr}", file=sys.stderr)
        except socket.timeout:
            print("FAIL: MAME never connected - check -rs232/-bitb support with -listslots", file=sys.stderr)
            mame_proc.terminate()
            sys.exit(2)
    else:
        if not args.serial_port:
            p.error("--serial-port is required for --target serial")
        transport = SerialTransport(args.serial_port, args.baud, args.rtscts)

    try:
        # Harness + preamble, loaded once, ahead of every section.
        harness_log = Path(args.log_dir) / "00_harness.raw.log"
        transcript = []
        with open(harness_log, "wb") as log:
            for fname in ("00a_tool_ext_conditionals.fs", "ttester.fs", "00_test_prelude.fs"):
                fpath = Path(args.ans_dir) / fname
                print(f"=== loading {fname} ===")
                send_file(transport, fpath, args.char_delay, args.reply_timeout, args.retries, log, transcript)

        results = {}
        for section in args.sections:
            results[section] = run_section(
                transport, args.ans_dir, section,
                args.char_delay, args.reply_timeout, args.retries, args.log_dir,
            )

        print("\n=== summary ===")
        n_pass = sum(1 for v in results.values() if v)
        n_fail = sum(1 for v in results.values() if v is False)
        n_skip = sum(1 for v in results.values() if v is None)
        for section, v in results.items():
            label = "PASS" if v else ("SKIP" if v is None else "FAIL")
            print(f"  {section}: {label}")
        print(f"{n_pass} passed, {n_fail} failed, {n_skip} skipped")
        sys.exit(0 if n_fail == 0 else 1)
    finally:
        transport.close()
        if mame_proc is not None:
            mame_proc.terminate()
            try:
                mame_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                mame_proc.kill()


if __name__ == "__main__":
    main()
