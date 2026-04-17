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

# Process each post
POST_COUNT=$(python3 -c "import json; print(len(json.load(open('posts.json'))))")

for i in $(seq 0 $((POST_COUNT - 1))); do
  eval "$(python3 -c "
import json
post = json.load(open('posts.json'))[$i]
print(f'POST_URL={json.dumps(post[\"url\"])}')
print(f'POST_TITLE={json.dumps(post.get(\"title\", \"\"))}')
print(f'LONG_TEXT={json.dumps(post.get(\"long_text\", \"\"))}')
print(f'MEDIUM_TEXT={json.dumps(post.get(\"medium_text\", \"\"))}')
print(f'SHORT_TEXT={json.dumps(post.get(\"short_text\", \"\"))}')
imgs = post.get('images', [])
for idx, img in enumerate(imgs):
    print(f'POST_IMAGE_{idx}={json.dumps(img)}')
print(f'POST_IMAGE_COUNT={len(imgs)}')
")"

  echo "  Processing: $POST_URL"

  # Instagram check on first image
  if [ "${POST_IMAGE_COUNT:-0}" -gt 0 ]; then
    check_instagram "$POST_IMAGE_0"
  fi

  # Check which channels already have this post
  channels_with_post=$(echo "$dedup_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
url = $POST_URL
edges = data.get('data', {}).get('posts', {}).get('edges', [])
for e in edges:
    node = e.get('node', {})
    if url in node.get('text', ''):
        print(node.get('channelId', ''))
" 2>/dev/null || true)

  # Helper: create draft post on a channel
  create_draft() {
    local text="$1"
    local channel_id="$2"
    local label="$3"

    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY RUN] Would queue to Buffer (${label}): $POST_URL"
      return
    fi

    # Build images array for payload
    local images_json="[]"
    if [ "${POST_IMAGE_COUNT:-0}" -gt 0 ]; then
      images_json=$(python3 -c "
import json
imgs = []
for idx in range(${POST_IMAGE_COUNT}):
    import os
    url = os.environ.get(f'POST_IMAGE_{idx}', '')
    if url:
        imgs.append({'url': url})
print(json.dumps(imgs))
")
    fi

    local payload
    payload=$(python3 -c "
import json, sys

text = sys.stdin.read().strip()
channel_id = '${channel_id}'
images = json.loads('${images_json}')

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

print(json.dumps({'query': mutation, 'variables': variables}))
" <<< "$text")

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

  # Export image URLs as env vars for the create_draft helper
  for idx in $(seq 0 $((POST_IMAGE_COUNT - 1))); do
    eval "export POST_IMAGE_${idx}"
  done

  # Queue to long-text channels (LinkedIn) - skip if already posted
  for cid in $long_ids; do
    if [ -z "$LONG_TEXT" ] || [ "$LONG_TEXT" = '""' ]; then
      echo "  ERROR: long_text is empty for $POST_URL, skipping LinkedIn (add # long section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (LinkedIn): $POST_URL"
    else
      create_draft "$LONG_TEXT" "$cid" "LinkedIn"
    fi
  done

  # Queue to Instagram with long text + instagramPostType - skip if already posted
  for cid in $instagram_ids; do
    if [ -z "$LONG_TEXT" ] || [ "$LONG_TEXT" = '""' ]; then
      echo "  ERROR: long_text is empty for $POST_URL, skipping Instagram (add # long section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (Instagram): $POST_URL"
    else
      # Instagram needs instagramPostType in the payload
      if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY RUN] Would queue to Buffer (Instagram): $POST_URL"
      else
        images_json="[]"
        if [ "${POST_IMAGE_COUNT:-0}" -gt 0 ]; then
          images_json=$(python3 -c "
import json
imgs = []
for idx in range(${POST_IMAGE_COUNT}):
    import os
    url = os.environ.get(f'POST_IMAGE_{idx}', '')
    if url:
        imgs.append({'url': url})
print(json.dumps(imgs))
")
        fi

        payload=$(python3 -c "
import json, sys

text = sys.stdin.read().strip()
channel_id = '${cid}'
images = json.loads('${images_json}')

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
        'saveToDraft': True,
        'metadata': {'instagram': {'type': 'post', 'shouldShareToFeed': True}}
    }
}

if images:
    variables['input']['assets'] = {'images': images}

print(json.dumps({'query': mutation, 'variables': variables}))
" <<< "$LONG_TEXT")

        response=$(curl -s -X POST "${BUFFER_API}" \
          -H "Content-Type: application/json" \
          -H "${AUTH_HEADER}" \
          -d "$payload")

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
          echo "  Queued to Buffer (Instagram): $POST_URL"
        else
          echo "  Error queuing to Buffer Instagram: $success"
        fi
      fi
    fi
  done

  # Queue to Threads with medium text - skip if already posted
  for cid in $threads_ids; do
    if [ -z "$MEDIUM_TEXT" ] || [ "$MEDIUM_TEXT" = '""' ]; then
      echo "  ERROR: medium_text is empty for $POST_URL, skipping Threads (add # medium section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (Threads): $POST_URL"
    else
      create_draft "$MEDIUM_TEXT" "$cid" "Threads"
    fi
  done

  # Queue to Twitter with short text - skip if already posted
  for cid in $twitter_ids; do
    if [ -z "$SHORT_TEXT" ] || [ "$SHORT_TEXT" = '""' ]; then
      echo "  ERROR: short_text is empty for $POST_URL, skipping Twitter (add # short section)"
      break
    fi
    if echo "$channels_with_post" | grep -qF "$cid"; then
      echo "  Already in Buffer (Twitter): $POST_URL"
    else
      create_draft "$SHORT_TEXT" "$cid" "Twitter"
    fi
  done
done

echo "--- Buffer publish done ---"
