#!/bin/bash
# Opens a new gnome-terminal tab and runs the nested LOSO v2 script in R.
# Usage: bash scripts/launch_loso.sh

cd /home/yeli/PAGe

gnome-terminal --tab \
  --title="Nested LOSO v2" \
  -- bash -c "
    cd /home/yeli/PAGe
    echo '=== Nested LOSO v2 ==='
    echo 'Starting R...'
    Rscript scripts/run_nested_loso_v2.R 2>&1 | tee logs/nested_loso_v2.log
    echo ''
    echo 'Done. Press Enter to close.'
    read
  "
