#!/usr/bin/env bash
# Bump version, update CHANGELOG.md, commit, tag and push.
# Usage: bash scripts/release.sh major|minor|patch
set -euo pipefail

PART="${1:?Usage: $0 major|minor|patch}"

case "$PART" in
  major|minor|patch) ;;
  *) echo "ERROR: part must be major, minor or patch" >&2; exit 1 ;;
esac

# git-cliff must be available
if ! command -v git-cliff > /dev/null; then
  echo "ERROR: git-cliff not found in PATH. Install with one of:" >&2
  echo "  uv tool install git-cliff   # if you use uv" >&2
  echo "  cargo install git-cliff     # if you have Rust toolchain" >&2
  echo "  see https://git-cliff.org for prebuilt binaries" >&2
  exit 1
fi

# No staged changes: they would silently end up in the release commit.
# Unstaged modifications and untracked files are fine: they are not committed.
if ! git diff --cached --quiet; then
  echo "ERROR: there are staged changes. Commit or unstage them first." >&2
  git diff --cached --stat >&2
  exit 1
fi

# Get latest tag, default to v0.0.0 if none
LATEST=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
echo "Latest tag: $LATEST"

# Strip 'v' prefix and parse semver
VER="${LATEST#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VER"

case "$PART" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW="v${MAJOR}.${MINOR}.${PATCH}"
echo "New tag: $NEW"

# Generate CHANGELOG.md from conventional commits
git-cliff --tag "$NEW" --output CHANGELOG.md
sed -i 's/<!-- [0-9]* -->//g' CHANGELOG.md

# Commit, tag and push
git add CHANGELOG.md
git commit -m "chore: release $NEW"
git tag -a "$NEW" -m "Release $NEW"
git push -u origin HEAD && git push origin --tags

echo "Released $NEW"
