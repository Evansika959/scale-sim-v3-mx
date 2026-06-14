#!/bin/bash
# Remove everything a run generates; keep source (*.py, run_*.sh, README.md, and
# accelergy_input/components/). Safe to run anytime, from anywhere.
cd "$(dirname "$0")"
rm -f  accelergy_input/architecture.yaml accelergy_input/action_count.yaml
rm -f  create_action_count.sh run_accelergy.sh architecture.yaml
rm -rf accelergy_output output __pycache__
echo "cleaned generated artifacts (kept sources + accelergy_input/components/)"
