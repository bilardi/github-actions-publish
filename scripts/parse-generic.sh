#!/usr/bin/env bash
set -euo pipefail

# Generic parser: reads social.yml and .md files from date folders, outputs posts.json.
# Requires: python3, pyyaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "$SCRIPT_DIR/parse-generic.py"
