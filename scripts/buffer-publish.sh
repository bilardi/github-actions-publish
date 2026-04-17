#!/usr/bin/env bash
set -euo pipefail

# Queue posts to Buffer (LinkedIn, Twitter, Threads, Instagram) as drafts from posts.json.
# Uses Buffer GraphQL API. Requires BUFFER_ACCESS_TOKEN environment variable.
# Posts go to Buffer drafts; the user reviews and approves them manually.
#
# API limits: 100 requests/24h rolling window.

if [ -z "${BUFFER_ACCESS_TOKEN:-}" ]; then
  echo "BUFFER_ACCESS_TOKEN not set, skipping Buffer publish"
  exit 0
fi

# Check enabled in social.yml
ENABLED=$(python3 -c "
import yaml
config = yaml.safe_load(open('social.yml'))
print(config.get('buffer', {}).get('enabled', False))
")
if [ "$ENABLED" != "True" ]; then
  echo "Buffer disabled in social.yml, skipping"
  exit 0
fi

INSTAGRAM_CHECK=$(python3 -c "
import yaml
config = yaml.safe_load(open('social.yml'))
print(config.get('instagram_check', False))
")

DRY_RUN="${DRY_RUN:-false}"
BUFFER_API="https://api.buffer.com"
AUTH_HEADER="Authorization: Bearer ${BUFFER_ACCESS_TOKEN}"

# Helper: run a GraphQL query via curl (Cloudflare blocks Python urllib)
gql() {
  local query="$1"
  curl -s -X POST "${BUFFER_API}" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}" \
    -d "{\"query\": $(echo "$query" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")}"
}

# Query 1: get org ID
setup_json=$(gql 'query { account { organizations { id } } }')
org_id=$(echo "$setup_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
orgs = data.get('data', {}).get('account', {}).get('organizations', [])
if orgs:
    print(orgs[0]['id'])
")

if [ -z "$org_id" ]; then
  echo "No Buffer organization found, skipping"
  exit 0
fi

echo "Buffer organization: ${org_id}"

# Query 2: get channels
channels_json=$(gql "query { channels(input: { organizationId: \"${org_id}\" }) { id name service } }")

eval "$(echo "$channels_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
channels = data.get('data', {}).get('channels', [])
twitter = []
threads = []
instagram = []
long_ch = []
all_ids = []
for ch in channels:
    cid = ch['id']
    svc = ch.get('service', '')
    print(f'  {svc}: {ch[\"name\"]} ({cid})', file=sys.stderr)
    all_ids.append(cid)
    if svc == 'twitter':
        twitter.append(cid)
    elif svc == 'threads':
        threads.append(cid)
    elif svc == 'instagram':
        instagram.append(cid)
    else:
        long_ch.append(cid)
print(f'twitter_ids=\"{chr(10).join(twitter)}\"')
print(f'threads_ids=\"{chr(10).join(threads)}\"')
print(f'instagram_ids=\"{chr(10).join(instagram)}\"')
print(f'long_ids=\"{chr(10).join(long_ch)}\"')
print(f'all_ids=\"{chr(10).join(all_ids)}\"')
")"

if [ -z "$all_ids" ]; then
  echo "No Buffer channels found, skipping"
  exit 0
fi

# Query 3: get all existing posts for dedup
dedup_json=$(gql "query { posts(first: 50, input: { organizationId: \"${org_id}\", filter: { status: [draft, scheduled, sent] } }) { edges { node { text channelId } } } }")

# Instagram aspect ratio check (if enabled)
check_instagram() {
  local image_url="$1"
  if [ "$INSTAGRAM_CHECK" != "True" ]; then
    return 0
  fi
  local tmpimg
  tmpimg=$(mktemp /tmp/ig_check.XXXXXX)
  curl -sL -o "$tmpimg" "$image_url"
  local ok
  ok=$(python3 -c "
import struct, os
path = '$tmpimg'
size = os.path.getsize(path)
if size == 0:
    print('skip')
else:
    # Try to read dimensions via identify (ImageMagick)
    import subprocess
    result = subprocess.run(['identify', '-format', '%w %h', path],
                          capture_output=True, text=True)
    if result.returncode == 0:
        w, h = result.stdout.strip().split()
        ratio = int(w) / int(h)
        if 1.7 <= ratio <= 1.85:
            print('ok')
        else:
            print(f'WARNING: image aspect ratio {ratio:.2f} (expected ~1.78 for 16:9): {path}')
    else:
        print('skip')
" 2>/dev/null || echo "skip")
  rm -f "$tmpimg"
  if [[ "$ok" == WARNING* ]]; then
    echo "  $ok"
  fi
}

# Save dedup data to temp file
DEDUP_FILE=$(mktemp /tmp/buffer_dedup.XXXXXX)
echo "$dedup_json" > "$DEDUP_FILE"

# Process each post: python3 reads posts.json directly to preserve unicode
POST_COUNT=$(python3 -c "import json; print(len(json.load(open('posts.json'))))")

for i in $(seq 0 $((POST_COUNT - 1))); do
  # Extract only URL for bash logging (no text through bash)
  POST_URL=$(python3 -c "import json; print(json.load(open('posts.json'))[$i]['url'])")

  echo "  Processing: $POST_URL"

  # Instagram check on first image
  FIRST_IMAGE=$(python3 -c "
import json
imgs = json.load(open('posts.json'))[$i].get('images', [])
print(imgs[0] if imgs else '')
")
  if [ -n "$FIRST_IMAGE" ]; then
    check_instagram "$FIRST_IMAGE"
  fi

  # Check which channels already have this post
  channels_with_post=$(python3 -c "
import json
dedup = json.load(open('${DEDUP_FILE}'))
url = json.load(open('posts.json'))[$i]['url']
edges = dedup.get('data', {}).get('posts', {}).get('edges', [])
print(f'  DEBUG dedup: searching for {url} in {len(edges)} posts', file=__import__('sys').stderr)
for e in edges:
    node = e.get('node', {})
    text = node.get('text', '')
    cid = node.get('channelId', '')
    found = url in text
    if found:
        print(f'  DEBUG dedup: channel={cid} found=True', file=__import__('sys').stderr)
        print(cid)
" || true)

  # Helper: create draft on a channel, reading text directly from posts.json
  # Args: channel_id label text_field [extra_metadata_json]
  create_draft() {
    local channel_id="$1"
    local label="$2"
    local text_field="$3"
    local extra_metadata="${4:-}"

    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY RUN] Would queue to Buffer (${label}): $POST_URL"
      return
    fi

    local payload
    payload=$(python3 -c "
import json

post = json.load(open('posts.json'))[$i]
text = post.get('${text_field}', '')
channel_id = '${channel_id}'
images = [{'url': img} for img in post.get('images', [])]
extra_metadata = '${extra_metadata}'

mutation = '''mutation CreateDraftPost(\$input: CreatePostInput!) {
  createPost(input: \$input) {
    ... on PostActionSuccess { post { id } }
    ... on MutationError { message }
  }
}'''

variables = {
    'input': {
        'text': text,
        'channelId': channel_id,
        'schedulingType': 'automatic',
        'mode': 'addToQueue',
        'saveToDraft': True
    }
}

if images:
    variables['input']['assets'] = {'images': images}

if extra_metadata:
    variables['input']['metadata'] = json.loads(extra_metadata)

print(json.dumps({'query': mutation, 'variables': variables}))
")

    local response
    response=$(curl -s -X POST "${BUFFER_API}" \
      -H "Content-Type: application/json" \
      -H "${AUTH_HEADER}" \
      -d "$payload")

    local success
    success=$(echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
post = data.get('data', {}).get('createPost', {}).get('post')
if post:
    print('ok')
else:
    err = data.get('data', {}).get('createPost', {}).get('message', '')
    errs = data.get('errors', [])
    if errs:
        err = errs[0].get('message', '')
    print(f'error: {err}')
" 2>/dev/null || echo "error: parse failed")

    if [ "$success" = "ok" ]; then
      echo "  Queued to Buffer (${label}): $POST_URL"
    else
      echo "  Error queuing to Buffer ${label}: $success"
    fi
  }

  # Check text presence for each channel type
  has_long=$(python3 -c "import json; t=json.load(open('posts.json'))[$i].get('long_text',''); print('yes' if t.strip() else 'no')")
  has_medium=$(python3 -c "import json; t=json.load(open('posts.json'))[$i].get('medium_text',''); print('yes' if t.strip() else 'no')")
  has_short=$(python3 -c "import json; t=json.load(open('posts.json'))[$i].get('short_text',''); print('yes' if t.strip() else 'no')")

  # Queue to LinkedIn - skip if already posted
  for cid in $long_ids; do
    if [ "$has_long" = "no" ]; then
      echo "  ERROR: long_text is empty for $POST_URL, skipping LinkedIn (add # long section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (LinkedIn): $POST_URL"
    else
      create_draft "$cid" "LinkedIn" "long_text"
    fi
  done

  # Queue to Instagram - skip if already posted
  for cid in $instagram_ids; do
    if [ "$has_long" = "no" ]; then
      echo "  ERROR: long_text is empty for $POST_URL, skipping Instagram (add # long section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (Instagram): $POST_URL"
    else
      create_draft "$cid" "Instagram" "long_text" '{"instagram": {"type": "post", "shouldShareToFeed": true}}'
    fi
  done

  # Queue to Threads - skip if already posted
  for cid in $threads_ids; do
    if [ "$has_medium" = "no" ]; then
      echo "  ERROR: medium_text is empty for $POST_URL, skipping Threads (add # medium section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (Threads): $POST_URL"
    else
      create_draft "$cid" "Threads" "medium_text"
    fi
  done

  # Queue to Twitter - skip if already posted
  for cid in $twitter_ids; do
    if [ "$has_short" = "no" ]; then
      echo "  ERROR: short_text is empty for $POST_URL, skipping Twitter (add # short section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (Twitter): $POST_URL"
    else
      create_draft "$cid" "Twitter" "short_text"
    fi
  done
done

rm -f "$DEDUP_FILE"
echo "--- Buffer publish done ---"
