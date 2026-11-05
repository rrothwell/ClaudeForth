#!/bin/bash
#
# build_all_tests.sh - assembles every glossary section's own unit test
# group (TSTSELECTOR 0-20) into its own binary and listing, one at a
# time, and prints a summary of which groups assembled.
#
# Requires: lwasm. Assumes forth6809.asm. All overridable, run with
# --help to see every flag.
#
# DISASM and DECOMP: when UNITTESTS=1 the source defaults DISASM to 0, so
# every group fits. --disasm 1 (and --decomp 1) build with the
# disassembler (and decompiler) in; only the groups that fit below
# BASEDICT are built then, the others are reported SKIPPED.

set -uo pipefail

ASM_SOURCE="forth6809.asm"
LWASM_BIN="lwasm"
SERIALPOLL=1
DISASM=""
DECOMP=""

usage() {
  cat <<EOF2
Usage: $0 [OPTIONS]

All options have built-in defaults (shown below); only pass what you
need to override for your own machine.

  --asm-source PATH      Path to forth6809.asm (default: $ASM_SOURCE)
  --lwasm-bin PATH       lwasm executable (default: $LWASM_BIN)
  --serialpoll 0|1       Serial driver to build: 1 = polled, 0 = interrupt
                         driven (default: $SERIALPOLL)
  --disasm 0|1           Pass DISASM to the assembler (default: not passed,
                         so the source default applies: 0 for unit tests)
  --decomp 0|1           Pass DECOMP to the assembler (default: not passed;
                         DECOMP=1 needs DISASM=1)
  -h, --help             Show this help and exit
EOF2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --asm-source)    ASM_SOURCE="$2"; shift 2 ;;
    --lwasm-bin)     LWASM_BIN="$2"; shift 2 ;;
    --serialpoll)    SERIALPOLL="$2"; shift 2 ;;
    --disasm)        DISASM="$2"; shift 2 ;;
    --decomp)        DECOMP="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

for v in "$SERIALPOLL" "$DISASM" "$DECOMP"; do
  if [[ -n "$v" && "$v" != "0" && "$v" != "1" ]]; then
    echo "--serialpoll, --disasm and --decomp must be 0 or 1 (got '$v')" >&2
    exit 1
  fi
done

# Glossary section names, in TSTSELECTOR order (0-20), matching the table
# in the ClaudeForth documentation's Build Instructions (Section 6.6).
SECTION_NAMES=(
  "3.1_SysIO" "3.2_Stack" "3.3_RetStack" "3.4_SArith" "3.5_DArith"
  "3.6_Logic" "3.7_Compare" "3.8_CtrlFlow" "3.9_DefWords" "3.10_CompWords"
  "3.11_Memory" "3.12_StrParse" "3.13_NumOut" "3.14_BaseRadix"
  "3.15_Exception" "3.16_Comments" "3.17_EnvSys" "3.18_Tools"
  "3.12_StrParse2" "3.9_DefWords2" "3.10_CompWords2"
)

# Groups that fit below BASEDICT when the disassembler is built in.
FIT_DISASM=" 0 2 5 13 14 15 16 17 "   # DISASM=1, DECOMP=0 (1920 bytes)
FIT_DECOMP=" 13 15 "                  # DISASM=1, DECOMP=1 (1016 bytes)

fits() {   # $1 = group number; returns 0 if it can be built
  local eff_disasm="${DISASM:-0}"
  local eff_decomp="${DECOMP:-$DISASM}"
  eff_decomp="${eff_decomp:-0}"
  if [[ "$eff_disasm" == "0" ]]; then return 0; fi
  if [[ "$eff_decomp" == "1" ]]; then [[ "$FIT_DECOMP" == *" $1 "* ]]; return; fi
  [[ "$FIT_DISASM" == *" $1 "* ]]
}

EXTRA=()
[[ -n "$DISASM" ]] && EXTRA+=(--define=DISASM="$DISASM")
[[ -n "$DECOMP" ]] && EXTRA+=(--define=DECOMP="$DECOMP")

echo "SERIALPOLL=$SERIALPOLL DISASM=${DISASM:-default} DECOMP=${DECOMP:-default}"

declare -a RESULTS

for ((n=0; n<21; n++)); do
  name="${SECTION_NAMES[$n]}"

  echo "=================================================================="
  echo "=== TSTSELECTOR=$n ($name) ==="
  echo "=================================================================="

  if ! fits "$n"; then
    echo "SKIPPED: group does not fit with this DISASM/DECOMP setting"
    RESULTS+=("$n $name SKIPPED")
    echo
    continue
  fi

  "$LWASM_BIN" --6809 --format=raw --output=forth6809."$n".bin \
    --list=forth6809."$n".lst \
    --define=SERIALPOLL="$SERIALPOLL" \
    --define=UNITTESTS=1 --define=TSTSELECTOR="$n" \
    ${EXTRA[@]+"${EXTRA[@]}"} \
    "$ASM_SOURCE"
  if [ $? -ne 0 ]; then
    echo "FAIL: lwasm failed for TSTSELECTOR=$n"
    RESULTS+=("$n $name ASSEMBLE_FAIL")
    continue
  fi
  RESULTS+=("$n $name ASSEMBLED")
  echo
done

echo "=================================================================="
echo "=== SUMMARY (SERIALPOLL=$SERIALPOLL) ==="
echo "=================================================================="
printf "%-4s %-16s %s\n" "N" "SECTION" "STATUS"
for r in "${RESULTS[@]}"; do
  printf "%-4s %-16s %s\n" $r
done
