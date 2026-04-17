#!/usr/bin/env bash
set -euo pipefail

# Publish posts to dev.to as drafts from posts.json.
# Requires DEV_TO_API_KEY environment variable.

if [ -z "${DEV_TO_API_KEY:-}" ]; then
  echo "DEV_TO_API_KEY not set, skipping dev.to publish"
  exit 0
fi

# Check enabled in social.yml
ENABLED=$(python3 -c "
import yaml
config = yaml.safe_load(open('social.yml'))
print(config.get('devto', {}).get('enabled', False))
")
if [ "$ENABLED" != "True" ]; then
  echo "dev.to disabled in social.yml, skipping"
  exit 0
fi

DRY_RUN="${DRY_RUN:-false}"

# Get existing articles for dedup (save to temp file to avoid quoting issues)
ARTICLES_FILE=$(mktemp /tmp/devto_articles.XXXXXX)
curl -s -H "api-key: ${DEV_TO_API_KEY}" \
  "https://dev.to/api/articles/me?per_page=100" > "$ARTICLES_FILE"

# Process each post
python3 -c "
import json, subprocess, sys, os

posts = json.load(open('posts.json'))
dry_run = '${DRY_RUN}' == 'true'
api_key = os.environ['DEV_TO_API_KEY']
existing = json.load(open('${ARTICLES_FILE}'))

for post in posts:
    url = post['url']
    title = post.get('title', '')
    article_body = post.get('article_body', '')
    tags = post.get('tags', [])[:4]

    # Check if title and article_body are present
    if not title:
        print(f'  WARNING: no title for {url}, skipping dev.to')
        continue
    if not article_body:
        print(f'  WARNING: no # article section for {url}, skipping dev.to')
        continue

    # Dedup: check if canonical_url already exists
    canonical_url = url
    already = any(a.get('canonical_url', '') == canonical_url for a in existing)
    if already:
        print(f'  Already on dev.to: {url}')
        continue

    print(f'  Publishing draft to dev.to: {title}')

    if dry_run:
        print(f'  [DRY RUN] Would create draft: {title}')
        continue

    payload = json.dumps({
        'article': {
            'title': title,
            'body_markdown': article_body,
            'canonical_url': canonical_url,
            'published': False,
            'tags': tags
        }
    })

    result = subprocess.run(
        ['curl', '-s', '-w', '\\n%{http_code}', '-X', 'POST',
         'https://dev.to/api/articles',
         '-H', f'api-key: {api_key}',
         '-H', 'Content-Type: application/json',
         '-d', payload],
        capture_output=True, text=True
    )

    lines = result.stdout.strip().split('\\n')
    http_code = lines[-1] if lines else '0'

    if http_code == '201':
        print(f'  Draft created on dev.to: {title}')
    else:
        print(f'  Error publishing to dev.to (HTTP {http_code}): {result.stdout[:200]}')
"

rm -f "$ARTICLES_FILE"
echo "--- dev.to publish done ---"
