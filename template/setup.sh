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
PUBLISH_REPO="bilardi/github-actions-publish"

# Defaults
HASHTAG=""
CONTENT_PATH="events"
SCAN_FOLDERS="3"
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
    --scan-folders)
      SCAN_FOLDERS="$2"
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
      echo "  --scan-folders N            Number of most recent folders to scan (default: 3)"
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
echo "  Scan folders: $SCAN_FOLDERS"
echo "  Mastodon: $MASTODON_ENABLED (instance: $MASTODON_INSTANCE)"
echo "  Buffer: $BUFFER_ENABLED"
echo "  dev.to: $DEVTO_ENABLED"
echo "  Instagram check: $INSTAGRAM_CHECK"
echo ""

# Generate social.yml
if safe_write social.yml; then
  sed -e "s|{{HASHTAG}}|$HASHTAG|g" \
      -e "s|{{CONTENT_PATH}}|$CONTENT_PATH|g" \
      -e "s|{{SCAN_FOLDERS}}|$SCAN_FOLDERS|g" \
      -e "s|{{MASTODON_INSTANCE}}|$MASTODON_INSTANCE|g" \
      -e "s|{{MASTODON_ENABLED}}|$MASTODON_ENABLED|g" \
      -e "s|{{BUFFER_ENABLED}}|$BUFFER_ENABLED|g" \
      -e "s|{{DEVTO_ENABLED}}|$DEVTO_ENABLED|g" \
      -e "s|{{INSTAGRAM_CHECK}}|$INSTAGRAM_CHECK|g" \
      "$SCRIPT_DIR/social.yml" > social.yml
  echo "Created social.yml"
fi

# Detect latest tag from github-actions-publish repo
LATEST_TAG=$(git -C "$SCRIPT_DIR/.." describe --tags --abbrev=0 2>/dev/null || echo "main")
echo "  Using tag: $LATEST_TAG"

# Generate .github/workflows/publish.yml
mkdir -p .github/workflows
if safe_write .github/workflows/publish.yml; then
  sed -e "s|{{PUBLISH_REPO}}|$PUBLISH_REPO|g" \
      -e "s|{{LATEST_TAG}}|$LATEST_TAG|g" \
      "$SCRIPT_DIR/publish.yml" > .github/workflows/publish.yml
  echo "Created .github/workflows/publish.yml"
fi

# Generate README.md
REPO_NAME=$(basename "$(pwd)")
CURRENT_YEAR=$(date +%Y)

if safe_write README.md; then
  sed -e "s|{{REPO_NAME}}|$REPO_NAME|g" \
      -e "s|{{CONTENT_PATH}}|$CONTENT_PATH|g" \
      -e "s|{{PUBLISH_REPO}}|$PUBLISH_REPO|g" \
      "$SCRIPT_DIR/README.md" > README.md
  echo "Created README.md"
fi

# Generate LICENSE
if safe_write LICENSE; then
  sed -e "s|{{CURRENT_YEAR}}|$CURRENT_YEAR|g" \
      "$SCRIPT_DIR/LICENSE" > LICENSE
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
