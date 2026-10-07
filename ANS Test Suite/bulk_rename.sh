#!/usr/bin/env bash
# ==============================================================================
# Script Name:  run_test.sh
# Description:  Bulk renames a directory of files, 
#               adjusting their suffixes from .fs to .fs.txt
#               so that the iPhone Files app will recognise them as 
#               uploadable to the Claude Project Folder.
# Author:       Richard Rothwell
# Date:         2026-10-07
# Version:      1.0.0
# Usage:        ./run_test.sh
# ==============================================================================

for file in *.fs; do
    mv -- "$file" "${file%.fs}.fs.txt"
done