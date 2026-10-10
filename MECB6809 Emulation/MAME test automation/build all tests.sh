#!/bin/bash
#
# run_all_tests.sh - automates building every glossary section's own unit
# test group through MAME, one at a time, capturing each group's output
# to its own log file.
#
# Requires: lwasm, python3. Assumes forth6809.asm
# All overridable, run with --help to see every flag. 
#

set -uo pipefail

# ------------------------------------------------------------------
# Configuration - built-in defaults, all overridable from the command
# line below (run with --help to see every flag)
# ------------------------------------------------------------------
ASM_SOURCE="forth6809.asm"
LWASM_BIN="lwasm"
SERIALPOLL=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF2
Usage: $0 [OPTIONS]

All options have built-in defaults (shown below); only pass what you
need to override for your own machine.

  --asm-source PATH      Path to forth6809.asm (default: $ASM_SOURCE)
  --lwasm-bin PATH       lwasm executable (default: $LWASM_BIN)
  --serialpoll 0|1       Serial driver to build: 1 = polled, 0 = interrupt
                         driven (default: $SERIALPOLL)
  -h, --help             Show this help and exit
EOF2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --asm-source)    ASM_SOURCE="$2"; shift 2 ;;
    --lwasm-bin)     LWASM_BIN="$2"; shift 2 ;;
    --serialpoll)    SERIALPOLL="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$SERIALPOLL" != "0" && "$SERIALPOLL" != "1" ]]; then
  echo "--serialpoll must be 0 or 1 (got '$SERIALPOLL')" >&2
  exit 1
fi

# Glossary section names, in TSTSELECTOR order (0-17), matching the
# table in the ClaudeForth documentation's own Build Instructions
# section - used only for readable log file names and the summary.
SECTION_NAMES=(
  "3.1_SysIO" "3.2_Stack" "3.3_RetStack" "3.4_SArith" "3.5_DArith"
  "3.6_Logic" "3.7_Compare" "3.8_CtrlFlow" "3.9_DefWords" "3.10_CompWords"
  "3.11_Memory" "3.12_StrParse" "3.13_NumOut" "3.14_BaseRadix"
  "3.15_Exception" "3.16_Comments" "3.17_EnvSys" "3.18_Tools"
)

echo "SERIALPOLL=$SERIALPOLL"

# ------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------
declare -a RESULTS

for ((n=0; n<18; n++)); do

  name="${SECTION_NAMES[$n]}"

  echo "=================================================================="
  echo "=== TSTSELECTOR=$n ($name) ==="
  echo "=================================================================="

  # Step 1: assemble this specific test group into the ROM image
  "$LWASM_BIN" --6809 --format=raw --output=forth6809."$n".bin \
    --list=forth6809.lst \
    --define=SERIALPOLL="$SERIALPOLL" \
    --define=UNITTESTS=1 --define=TSTSELECTOR="$n" \
    "$ASM_SOURCE"
  if [ $? -ne 0 ]; then
    echo "FAIL: lwasm failed for TSTSELECTOR=$n"
    RESULTS+=("$n $name ASSEMBLE_FAIL")
    continue
  fi
  
  echo
done
