#!/usr/bin/env bash
set -euo pipefail

# Check character count of # long, # medium, # short sections in a .md file.
# Substitutes placeholders using social.yml from the current directory.
# Shows both raw count and adjusted count (URLs counted as 23 chars, like Mastodon/Twitter).
#
# Usage: bash check-length.sh <file.md>
# Run from the repo root (where social.yml is).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: bash check-length.sh <file.md>"
  echo "Run from the repo root (where social.yml is)."
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "ERROR: file not found: $FILE"
  exit 1
fi

if [ ! -f "social.yml" ]; then
  echo "ERROR: social.yml not found in current directory"
  exit 1
fi

python3 << PYEOF
import sys, re
sys.path.insert(0, "$SCRIPT_DIR")
from importlib.util import spec_from_file_location, module_from_spec
spec = spec_from_file_location("parser", "$SCRIPT_DIR/parse-generic.py")
parser = module_from_spec(spec)
spec.loader.exec_module(parser)
import yaml

with open("social.yml") as f:
    config = yaml.safe_load(f)

hashtag = config["hashtag"]

try:
    post = parser.parse_file("$FILE", hashtag)
except ValueError as e:
    print(f"ERROR: {e}")
    sys.exit(1)

URL_PATTERN = re.compile(r"https?://\S+")
URL_LENGTH = 23  # Mastodon and Twitter count every URL as 23 chars

limits = {
    "long": ("LinkedIn/Instagram", 3000),
    "medium": ("Mastodon/Threads", 500),
    "short": ("Twitter", 280),
}

print(f"File: $FILE")
print()

any_over = False
for section, (platforms, limit) in limits.items():
    text = post.get(f"{section}_text", "")
    if not text:
        print(f"  {section:8s}: (empty)")
        continue

    raw = len(text.encode("utf-16-le")) // 2

    # Adjusted: replace each URL with 23-char equivalent
    urls = URL_PATTERN.findall(text)
    adjusted = raw
    for u in urls:
        url_chars = len(u.encode("utf-16-le")) // 2
        adjusted -= (url_chars - URL_LENGTH)

    status = "OK" if adjusted <= limit else f"OVER by {adjusted - limit}"
    if adjusted > limit:
        any_over = True

    print(f"  {section:8s}: {raw:4d} raw -> {adjusted:4d} adjusted / {limit} char  {platforms:25s}  {status}")

if any_over:
    print()
    print("Some sections exceed the character limit (adjusted).")
    sys.exit(1)
PYEOF
