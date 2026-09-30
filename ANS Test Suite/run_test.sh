#!/bin/bash

python3 ans_test_runner.py \
    --target mame \
    --mame-bin "$HOME/git/mame0288/mecb6809" \
    --retrigger-cmd $HOME/git/ClaudeForth/ANS\ Test\ Suite/retrigger.cmd \
    --skip-assemble \
    --ans-dir $HOME/git/ClaudeForth/ANS\ Test\ Suite/ans_tests \
    --sections 08 \
    --char-delay 0.02 \
    --retries 0
    --log-dir $HOME/git/ClaudeForth/ANS\ Test\ Suite/ans_test_results


#    --sections 08 09 10 11 12 13 14 15 16 17 18 19 20 21 23 24 26
#    --rom-dest "$HOME/Library/Application Support/mame/roms/mecb6809/mecb6809.bin" \
#    --serialpoll 0