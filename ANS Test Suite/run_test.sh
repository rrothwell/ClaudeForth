#!/usr/bin/env python3
# ==============================================================================
# Script Name:  ans_test_runner.py
# Description:  Triggers an ANS Test run with typical options.
# Author:       Claude Chat
# Date:         2026-10-07
# Version:      1.0.0
# Usage:        ./ans_test_runner.py
# ==============================================================================

# The command line to run the ans test runner 
# with typical developer options.
python3 ans_test_runner.py \
    --target mame \
    --mame-bin "$HOME/git/mame0288/mecb6809" \
    --retrigger-cmd $HOME/git/ClaudeForth/ANS\ Test\ Suite/retrigger.cmd \
    --skip-assemble \
    --ans-dir $HOME/git/ClaudeForth/ANS\ Test\ Suite/ans_tests \
    --sections 08 \
    --char-delay 0.05 \
    --retries 0
    --log-dir $HOME/git/ClaudeForth/ANS\ Test\ Suite/ans_test_results


# Options deleted but archive here:
# The full command line options are documented in ans_test_runner.py
#    --sections 08 09 10 11 12 13 14 15 16 17 18 19 20 21 23 24 26
#    --rom-dest "$HOME/Library/Application Support/mame/roms/mecb6809/mecb6809.bin" \
#    --serialpoll 0

