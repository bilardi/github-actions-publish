#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0

run_test() {
  local name="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

run_test_expect_fail() {
  local name="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  FAIL (expected error): $name"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS (expected error): $name"
    PASS=$((PASS + 1))
  fi
}

echo "=== Parser integration tests ==="

# --- Test 1: Valid files produce correct JSON ---
echo "Test 1: Valid files"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp "$FIXTURES/social.yml" "$TMPDIR/"
cp -r "$FIXTURES/events" "$TMPDIR/"

cd "$TMPDIR"
bash "$REPO_ROOT/scripts/parse-generic.sh"

run_test "posts.json exists" test -f posts.json
run_test "At least one post parsed" python3 -c "
import json
posts = json.load(open('posts.json'))
assert len(posts) >= 1, f'Expected >= 1 post, got {len(posts)}'
"

run_test "Only future-date posts included" python3 -c "
import json
from datetime import date, timezone, datetime
posts = json.load(open('posts.json'))
today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
for p in posts:
    assert p['date'] >= today, f'Post date {p[\"date\"]} is in the past'
"

run_test "Hashtag auto-appended in long (no {hashtag}/{tags} in source)" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert '#TestRepo' in p['long_text'], 'Auto-appended hashtag not found in long_text'
    assert '#python' in p['long_text'], 'Auto-appended tags not found in long_text'
"

run_test "Placeholder {hashtag} substituted in short" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert '{hashtag}' not in p['short_text'], 'Unsubstituted {hashtag} in short_text'
    assert '#TestRepo' in p['short_text'], 'Hashtag not found in short_text'
"

run_test "Placeholder {url} substituted" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert '{url}' not in p['long_text'], 'Unsubstituted {url}'
    assert p['url'] in p['long_text'], f'URL {p[\"url\"]} not in long_text'
"

run_test "Placeholder {tags} substituted in short" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert '{tags}' not in p['short_text'], 'Unsubstituted {tags}'
    assert '#python' in p['short_text'], '#python tag not found in short_text'
"

run_test "Past date file from old folder skipped" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert 'old-event' not in p['url'], 'Post with past date from old folder was included'
"

run_test "Past file date skipped" python3 -c "
import json
posts = json.load(open('posts.json'))
urls = [p['url'] for p in posts]
assert 'https://www.meetup.com/test-event/123/recap' not in urls, 'Post with past date was included'
"

run_test "Required fields present" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert p['url'], 'Missing url'
    assert p['long_text'], 'Missing long_text'
    assert p['medium_text'], 'Missing medium_text'
    assert p['short_text'], 'Missing short_text'
    assert p['images'], 'Missing images'
    assert p['tags'], 'Missing tags'
"

run_test "medium_text has placeholder substituted" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert '{hashtag}' not in p['medium_text'], 'Unsubstituted {hashtag} in medium_text'
    assert '#TestRepo' in p['medium_text'], 'Hashtag not found in medium_text'
    assert p['url'] in p['medium_text'], 'URL not in medium_text'
"

cd - > /dev/null

# --- Test 2: Malformed .md produces error ---
echo "Test 2: Malformed .md"
TMPDIR2=$(mktemp -d)
cp "$FIXTURES/social.yml" "$TMPDIR2/"
mkdir -p "$TMPDIR2/events/2099-12-20"
cat > "$TMPDIR2/events/2099-12-20/bad.md" << 'EOF'
This file has no frontmatter at all.
Just plain text.
EOF

cd "$TMPDIR2"
run_test_expect_fail "Malformed .md causes error" bash "$REPO_ROOT/scripts/parse-generic.sh"
cd - > /dev/null
rm -rf "$TMPDIR2"

# --- Test 3: Missing required field produces error ---
echo "Test 3: Missing required field"
TMPDIR3=$(mktemp -d)
cp "$FIXTURES/social.yml" "$TMPDIR3/"
mkdir -p "$TMPDIR3/events/2099-12-20"
cat > "$TMPDIR3/events/2099-12-20/no-url.md" << 'EOF'
---
date: 2099-12-20
images:
  - https://example.com/img.jpg
tags: [test]
---

# long

Text {url} {hashtag} {tags}

# short

Short {url} {hashtag} {tags}
EOF

cd "$TMPDIR3"
run_test_expect_fail "Missing url causes error" bash "$REPO_ROOT/scripts/parse-generic.sh"
cd - > /dev/null
rm -rf "$TMPDIR3"

# --- Test 4: Non-.md files ignored ---
echo "Test 4: Non-.md files ignored"
TMPDIR4=$(mktemp -d)
cp "$FIXTURES/social.yml" "$TMPDIR4/"
cp -r "$FIXTURES/events" "$TMPDIR4/"
echo "not a markdown file" > "$TMPDIR4/events/2099-12-15/notes.txt"

cd "$TMPDIR4"
run_test "Non-.md files ignored" bash "$REPO_ROOT/scripts/parse-generic.sh"
cd - > /dev/null
rm -rf "$TMPDIR4"

# --- Test 5: Hashtag non-duplication ---
echo "Test 5: Hashtag non-duplication"
TMPDIR5=$(mktemp -d)
cp "$FIXTURES/social.yml" "$TMPDIR5/"
mkdir -p "$TMPDIR5/events/2099-12-20"
cat > "$TMPDIR5/events/2099-12-20/dup.md" << 'EOF'
---
date: 2099-12-20
images:
  - https://example.com/img.jpg
url: https://example.com/event
tags: [test]
---

# long

#TestRepo is great! {url} {tags}

# short

#TestRepo event {url} {tags}
EOF

cd "$TMPDIR5"
bash "$REPO_ROOT/scripts/parse-generic.sh"
run_test "Hashtag not duplicated" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    count = p['long_text'].count('#TestRepo')
    assert count == 1, f'Hashtag appears {count} times, expected 1'
"
cd - > /dev/null
rm -rf "$TMPDIR5"

# --- Test 6: Tag non-duplication ---
echo "Test 6: Tag non-duplication"
TMPDIR6=$(mktemp -d)
cp "$FIXTURES/social.yml" "$TMPDIR6/"
mkdir -p "$TMPDIR6/events/2099-12-20"
cat > "$TMPDIR6/events/2099-12-20/tagdup.md" << 'EOF'
---
date: 2099-12-20
images:
  - https://example.com/img.jpg
url: https://example.com/tagtest
tags: [python, testing]
---

# long

Great #python talk! {url} {tags}

# short

#python talk {url} {hashtag} {tags}
EOF

cd "$TMPDIR6"
bash "$REPO_ROOT/scripts/parse-generic.sh"
run_test "Tag #python not duplicated in long" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    count = p['long_text'].count('#python')
    assert count == 1, f'#python appears {count} times in long_text, expected 1'
"
run_test "Tag #testing still present in long" python3 -c "
import json
posts = json.load(open('posts.json'))
for p in posts:
    assert '#testing' in p['long_text'], '#testing missing from long_text'
"
run_test "#PythonDeveloper would not block #python" python3 -c "
# Verify the regex uses word boundary: #python should not match inside #PythonDeveloper
import re
text = 'Join #PythonDeveloper meetup'
tag = '#python'
pattern = re.escape(tag) + r'(?![a-zA-Z0-9_])'
assert not re.search(pattern, text), '#python should NOT match inside #PythonDeveloper'
"
cd - > /dev/null
rm -rf "$TMPDIR6"

# --- Test 7: Google Drive URL normalization ---
echo "Test 7: Google Drive URL normalization"
TMPDIR7=$(mktemp -d)
cp "$FIXTURES/social.yml" "$TMPDIR7/"
mkdir -p "$TMPDIR7/events/2099-12-20"
cat > "$TMPDIR7/events/2099-12-20/gdrive.md" << 'EOF'
---
date: 2099-12-20
images:
  - https://drive.google.com/file/d/ABC123/view
  - https://example.com/normal.jpg
url: https://example.com/gdrive-test
tags: [test]
---

# long

Test {url} {hashtag} {tags}

# short

Test {url} {hashtag} {tags}
EOF

cd "$TMPDIR7"
bash "$REPO_ROOT/scripts/parse-generic.sh"
run_test "Google Drive URL converted to direct link" python3 -c "
import json
posts = json.load(open('posts.json'))
imgs = posts[0]['images']
assert imgs[0] == 'https://drive.google.com/thumbnail?id=ABC123&sz=w1920', f'Expected thumbnail link, got {imgs[0]}'
"
run_test "Normal URL unchanged" python3 -c "
import json
posts = json.load(open('posts.json'))
imgs = posts[0]['images']
assert imgs[1] == 'https://example.com/normal.jpg', f'Normal URL changed: {imgs[1]}'
"
cd - > /dev/null
rm -rf "$TMPDIR7"

# --- Test 8: Missing sections produce empty fields (no error) ---
echo "Test 8: Missing sections produce empty fields"
TMPDIR8=$(mktemp -d)
cp "$FIXTURES/social.yml" "$TMPDIR8/"
mkdir -p "$TMPDIR8/events/2099-12-20"
cat > "$TMPDIR8/events/2099-12-20/minimal.md" << 'EOF'
---
date: 2099-12-20
images:
  - https://example.com/img.jpg
url: https://example.com/minimal
tags: [test]
---

# long

Only long text here {url} {hashtag} {tags}
EOF

cd "$TMPDIR8"
bash "$REPO_ROOT/scripts/parse-generic.sh"
run_test "Parser succeeds with only # long" test -f posts.json
run_test "medium_text is empty when # medium absent" python3 -c "
import json
posts = json.load(open('posts.json'))
assert posts[0]['medium_text'] == '', f'Expected empty medium_text, got: {posts[0][\"medium_text\"]}'
"
run_test "short_text is empty when # short absent" python3 -c "
import json
posts = json.load(open('posts.json'))
assert posts[0]['short_text'] == '', f'Expected empty short_text, got: {posts[0][\"short_text\"]}'
"
cd - > /dev/null
rm -rf "$TMPDIR8"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
