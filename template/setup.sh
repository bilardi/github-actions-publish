#!/usr/bin/env bash
set -euo pipefail

# Setup a repo to use github-actions-publish.
# Run from the target repo directory:
#
#   bash /path/to/github-actions-publish/template/setup.sh \
#     --hashtag "#AWSUserGroupVenezia" \
#     --content-path events \
#     --mastodon-instance https://mastodon.social \
#     --buffer \
#     --instagram-check
#
# Generates: social.yml, .github/workflows/publish.yml, README.md, LICENSE, content directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
HASHTAG=""
CONTENT_PATH="events"
MASTODON_INSTANCE="https://mastodon.social"
MASTODON_ENABLED="true"
BUFFER_ENABLED="true"
DEVTO_ENABLED="false"
INSTAGRAM_CHECK="false"
SAMPLE=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --hashtag)
      HASHTAG="$2"
      shift 2
      ;;
    --content-path)
      CONTENT_PATH="$2"
      shift 2
      ;;
    --mastodon-instance)
      MASTODON_INSTANCE="$2"
      shift 2
      ;;
    --mastodon)
      MASTODON_ENABLED="true"
      shift
      ;;
    --no-mastodon)
      MASTODON_ENABLED="false"
      shift
      ;;
    --buffer)
      BUFFER_ENABLED="true"
      shift
      ;;
    --no-buffer)
      BUFFER_ENABLED="false"
      shift
      ;;
    --devto)
      DEVTO_ENABLED="true"
      shift
      ;;
    --no-devto)
      DEVTO_ENABLED="false"
      shift
      ;;
    --instagram-check)
      INSTAGRAM_CHECK="true"
      shift
      ;;
    --sample)
      SAMPLE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: bash setup.sh --hashtag \"#YourHashtag\" [options]"
      echo ""
      echo "Required:"
      echo "  --hashtag TEXT              Fixed hashtag for the repo"
      echo ""
      echo "Optional:"
      echo "  --content-path PATH         Path for date folders (default: events)"
      echo "  --mastodon-instance URL     Mastodon instance URL (default: https://mastodon.social)"
      echo "  --mastodon / --no-mastodon  Enable/disable Mastodon (default: enabled)"
      echo "  --buffer / --no-buffer      Enable/disable Buffer (default: enabled)"
      echo "  --devto / --no-devto        Enable/disable dev.to (default: disabled)"
      echo "  --instagram-check           Enable Instagram aspect ratio check"
      echo "  --sample YYYY-MM-DD         Create sample event folder with template .md"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage."
      exit 1
      ;;
  esac
done

# Validate required params
if [ -z "$HASHTAG" ]; then
  echo "ERROR: --hashtag is required"
  echo "Run with --help for usage."
  exit 1
fi

# Helper: check if file exists and ask before overwriting
safe_write() {
  local file="$1"
  if [ -f "$file" ]; then
    echo "  WARNING: $file already exists"
    read -rp "  Overwrite? (y/N) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
      echo "  Skipped $file"
      return 1
    fi
  fi
  return 0
}

echo "Setting up repo for github-actions-publish"
echo "  Hashtag: $HASHTAG"
echo "  Content path: $CONTENT_PATH"
echo "  Mastodon: $MASTODON_ENABLED (instance: $MASTODON_INSTANCE)"
echo "  Buffer: $BUFFER_ENABLED"
echo "  dev.to: $DEVTO_ENABLED"
echo "  Instagram check: $INSTAGRAM_CHECK"
echo ""

# Generate social.yml
if safe_write social.yml; then
  cat > social.yml << SOCIALEOF
hashtag: "$HASHTAG"
content_path: "$CONTENT_PATH"
parser: generic
mastodon:
  instance: $MASTODON_INSTANCE
  enabled: $MASTODON_ENABLED
buffer:
  enabled: $BUFFER_ENABLED
devto:
  enabled: $DEVTO_ENABLED
instagram_check: $INSTAGRAM_CHECK
SOCIALEOF
  echo "Created social.yml"
fi

# Generate .github/workflows/publish.yml
mkdir -p .github/workflows
if safe_write .github/workflows/publish.yml; then
  cat > .github/workflows/publish.yml << 'WFEOF'
name: Publish posts
on:
  workflow_dispatch:
jobs:
  publish:
    uses: bilardi/github-actions-publish/.github/workflows/publish.yml@v0.1.0
    secrets:
      MASTODON_ACCESS_TOKEN: ${{ secrets.MASTODON_ACCESS_TOKEN }}
      BUFFER_ACCESS_TOKEN: ${{ secrets.BUFFER_ACCESS_TOKEN }}
      DEV_TO_API_KEY: ${{ secrets.DEV_TO_API_KEY }}
WFEOF
  echo "Created .github/workflows/publish.yml"
fi

# Generate README.md
REPO_NAME=$(basename "$(pwd)")
CURRENT_YEAR=$(date +%Y)
PUBLISH_REPO="bilardi/github-actions-publish"

if safe_write README.md; then
cat > README.md << READMEEOF
# $REPO_NAME

TODO: add description

## Prerequisites

- GitHub secrets configured (see below)
- [$PUBLISH_REPO](https://github.com/$PUBLISH_REPO) provides the reusable workflow and scripts

## Usage

### Writing a post

Create a date folder under \`$CONTENT_PATH/\` and add \`.md\` files:

\`\`\`
$CONTENT_PATH/
  2026-05-20/
    pre.md   # announcement
    post.md  # recap
\`\`\`

Post format:

\`\`\`markdown
---
title: "Event Title"
date: 2026-05-15
images:
  - https://drive.google.com/file/d/FILE_ID/view
url: https://www.meetup.com/your-event/123
tags: [topic1, topic2]
---

# long

Text for LinkedIn and Instagram (up to 3.000 chars).

{url}

{hashtag} {tags}

# medium

Text for Mastodon and Threads (up to 500 chars).

{url}

{hashtag} {tags}

# short

Text for Twitter (< 280 chars) {url} {hashtag} {tags}
\`\`\`

Sections are optional: only needed if the corresponding channel is active. See the [full format reference](https://github.com/$PUBLISH_REPO#file-format).

### Publishing

Trigger the workflow manually from GitHub Actions (\`workflow_dispatch\`).

### Checking character counts

\`\`\`bash
bash /path/to/github-actions-publish/scripts/check-length.sh $CONTENT_PATH/2026-05-20/pre.md
\`\`\`

### Updating setup

Re-run \`setup.sh\` to pick up updates from github-actions-publish (e.g. new workflow version). The script asks before overwriting existing files: review the diff and keep your local changes.

## GitHub secrets

| Secret | Used by |
|--------|---------|
| \`MASTODON_ACCESS_TOKEN\` | Mastodon direct publishing |
| \`BUFFER_ACCESS_TOKEN\` | Buffer draft queuing (LinkedIn, Twitter, Threads, Instagram) |
| \`DEV_TO_API_KEY\` | dev.to draft creation |

## Project structure

\`\`\`
.github/workflows/
  publish.yml   # calls $PUBLISH_REPO workflow
$CONTENT_PATH/            # date folders with .md files
social.yml      # repo configuration (hashtag, socials, parser)
README.md       # this file
LICENSE         # MIT license
\`\`\`

## License

This repo is released under the MIT license. See [LICENSE](LICENSE) for details.
READMEEOF
  echo "Created README.md"
fi

# Generate LICENSE
if safe_write LICENSE; then
cat > LICENSE << LICEOF
MIT License

Copyright (c) $CURRENT_YEAR Alessandra Bilardi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
LICEOF
  echo "Created LICENSE"
fi

# Create content directory
mkdir -p "$CONTENT_PATH"
echo "Created $CONTENT_PATH/"

# Create sample event if requested
if [ -n "$SAMPLE" ]; then
  if ! echo "$SAMPLE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "ERROR: --sample must be a date in YYYY-MM-DD format"
    exit 1
  fi
  SAMPLE_DIR="$CONTENT_PATH/$SAMPLE"
  mkdir -p "$SAMPLE_DIR"
  cp "$SCRIPT_DIR/event.md" "$SAMPLE_DIR/pre.md"
  echo "Created $SAMPLE_DIR/pre.md (template to fill in)"
fi

echo ""
echo "Done. Next steps:"
echo "  1. Add GitHub secrets: MASTODON_ACCESS_TOKEN, BUFFER_ACCESS_TOKEN, DEV_TO_API_KEY"
echo "  2. Create event folders under $CONTENT_PATH/ (e.g. $CONTENT_PATH/2026-05-20/)"
echo "  3. Write .md files using the format in template/event.md"
echo "  4. Trigger the workflow from GitHub Actions (workflow_dispatch)"
