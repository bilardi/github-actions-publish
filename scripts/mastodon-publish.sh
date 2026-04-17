#!/usr/bin/env bash
set -euo pipefail

# Publish posts to Mastodon from posts.json.
# Reads mastodon config from social.yml.
# Requires: MASTODON_ACCESS_TOKEN environment variable.

if [ -z "${MASTODON_ACCESS_TOKEN:-}" ]; then
  echo "MASTODON_ACCESS_TOKEN not set, skipping Mastodon publish"
  exit 0
fi

# Check enabled in social.yml
ENABLED=$(python3 -c "
import yaml
config = yaml.safe_load(open('social.yml'))
print(config.get('mastodon', {}).get('enabled', False))
")
if [ "$ENABLED" != "True" ]; then
  echo "Mastodon disabled in social.yml, skipping"
  exit 0
fi

MASTODON_INSTANCE=$(python3 -c "
import yaml
config = yaml.safe_load(open('social.yml'))
print(config.get('mastodon', {}).get('instance', ''))
")

if [ -z "$MASTODON_INSTANCE" ]; then
  echo "ERROR: mastodon.instance not set in social.yml"
  exit 1
fi

DRY_RUN="${DRY_RUN:-false}"

# Get account ID
ACCOUNT_ID=$(curl -s -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" \
  "${MASTODON_INSTANCE}/api/v1/accounts/verify_credentials" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo "Mastodon account ID: ${ACCOUNT_ID}"

# Get recent statuses for dedup (save to temp file to avoid quoting issues)
STATUSES_FILE=$(mktemp /tmp/mastodon_statuses.XXXXXX)
curl -s -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" \
  "${MASTODON_INSTANCE}/api/v1/accounts/${ACCOUNT_ID}/statuses?limit=40" > "$STATUSES_FILE"

# Process each post
python3 -c "
import json, subprocess, sys, os, tempfile

posts = json.load(open('posts.json'))
instance = '${MASTODON_INSTANCE}'
token = os.environ['MASTODON_ACCESS_TOKEN']
dry_run = '${DRY_RUN}' == 'true'
try:
    statuses = json.load(open('${STATUSES_FILE}'))
except json.JSONDecodeError as e:
    raw = open('${STATUSES_FILE}').read()
    pos = e.pos or 0
    start = max(0, pos - 50)
    end = min(len(raw), pos + 50)
    print(f'ERROR: invalid JSON from Mastodon API at position {pos}', file=sys.stderr)
    print(f'Context: ...{repr(raw[start:end])}...', file=sys.stderr)
    print(f'Total response length: {len(raw)}', file=sys.stderr)
    sys.exit(1)

for post in posts:
    url = post['url']
    text = post.get('medium_text', '')
    images = post.get('images', [])[:4]

    # Check medium_text is present and not empty
    if not text.strip():
        print(f'  ERROR: medium_text is empty for {url}, skipping (add # medium section)')
        continue

    # Dedup: check if url is in recent statuses
    already_posted = any(url in s.get('content', '') for s in statuses)
    if already_posted:
        print(f'  Already on Mastodon: {url}')
        continue

    print(f'  Publishing to Mastodon: {url}')

    if dry_run:
        print(f'  [DRY RUN] Would post: {text[:80]}...')
        continue

    # Upload images
    media_ids = []
    for img_url in images:
        tmpfile = tempfile.mktemp(suffix='.img')
        subprocess.run(['curl', '-sL', '-o', tmpfile, img_url], check=True)
        result = subprocess.run(
            ['curl', '-s',
             '-H', f'Authorization: Bearer {token}',
             '-F', f'file=@{tmpfile}',
             '-F', f'description={post.get(\"title\", \"\")}',
             f'{instance}/api/v2/media'],
            capture_output=True, text=True, check=True
        )
        media_id = json.loads(result.stdout).get('id', '')
        if media_id:
            media_ids.append(media_id)
            print(f'  Image uploaded: {media_id}')
        os.unlink(tmpfile)

    # Wait for media processing
    if media_ids:
        import time
        time.sleep(2)

    # Post status
    cmd = ['curl', '-s', '-w', '\\n%{http_code}', '-X', 'POST',
           f'{instance}/api/v1/statuses',
           '-H', f'Authorization: Bearer {token}',
           '-F', f'status={text}',
           '-F', 'visibility=public']
    for mid in media_ids:
        cmd.extend(['-F', f'media_ids[]={mid}'])

    result = subprocess.run(cmd, capture_output=True, text=True)
    lines = result.stdout.strip().split('\\n')
    http_code = lines[-1] if lines else '0'

    if http_code == '200':
        print(f'  Posted to Mastodon: {url}')
    else:
        print(f'  Error posting to Mastodon (HTTP {http_code})')
        print(f'  Response: {result.stdout[:200]}')
"

rm -f "$STATUSES_FILE"
echo "--- Mastodon publish done ---"
