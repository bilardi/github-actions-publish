#!/usr/bin/env python3
"""Generic parser: reads social.yml and date-folder .md files, outputs posts.json."""

import json
import os
import re
import sys
from datetime import date, timezone, datetime

import yaml

SECTION_HEADERS = {"# long", "# medium", "# short", "# article"}


def parse_frontmatter(content, filepath):
    """Extract frontmatter dict and body string from markdown content."""
    if not content.startswith("---"):
        raise ValueError(f"{filepath}: missing frontmatter (no opening ---)")
    parts = content.split("---", 2)
    if len(parts) < 3:
        raise ValueError(f"{filepath}: malformed frontmatter (no closing ---)")
    fm = yaml.safe_load(parts[1])
    if not isinstance(fm, dict):
        raise ValueError(f"{filepath}: frontmatter is not a YAML mapping")
    return fm, parts[2].strip()


def validate_frontmatter(fm, filepath):
    """Validate required frontmatter fields. Raises ValueError on failure."""
    for field in ("date", "url", "tags", "images"):
        if field not in fm or fm[field] is None:
            raise ValueError(f"{filepath}: missing required field '{field}'")

    post_date = str(fm["date"])
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", post_date):
        raise ValueError(f"{filepath}: invalid date format '{post_date}'")

    images = fm["images"]
    if not isinstance(images, list) or len(images) < 1:
        raise ValueError(f"{filepath}: 'images' must be a list with at least one URL")

    tags = fm["tags"]
    if not isinstance(tags, list) or len(tags) < 1:
        raise ValueError(f"{filepath}: 'tags' must be a list with at least one tag")


def extract_sections(body, filepath):
    """Extract # long, # short, # article sections from body."""
    sections = {}
    current = None
    lines = []
    for line in body.split("\n"):
        stripped = line.strip()
        if stripped in SECTION_HEADERS:
            if current:
                sections[current] = "\n".join(lines).strip()
            current = stripped.split("# ", 1)[1]
            lines = []
        elif current is not None:
            lines.append(line)
    if current:
        sections[current] = "\n".join(lines).strip()

    return sections


def normalize_image_url(url):
    """Convert Google Drive share links to direct download URLs."""
    match = re.match(r"https://drive\.google\.com/file/d/([^/]+)/view", url)
    if match:
        return f"https://drive.google.com/thumbnail?id={match.group(1)}&sz=w1920"
    return url


def filter_existing_tags(text, tags_str):
    """Remove tags that are already literally present in the text."""
    filtered = []
    for tag in tags_str.split():
        # Match whole word: tag followed by space, end of string, or non-alphanumeric
        pattern = re.escape(tag) + r"(?![a-zA-Z0-9_])"
        if not re.search(pattern, text):
            filtered.append(tag)
    return " ".join(filtered)


def substitute(text, url, hashtag, tags_str):
    """Substitute {url}, {hashtag}, {tags} placeholders in text."""
    has_hashtag = "{hashtag}" in text
    has_tags = "{tags}" in text

    # Replace {url}
    text = text.replace("{url}", url)

    # Check if hashtag literal is already in text (before any substitution)
    hashtag_already_present = hashtag in text

    if has_hashtag:
        text = text.replace("{hashtag}", hashtag)

    if has_tags:
        filtered = filter_existing_tags(text, tags_str)
        if not has_hashtag and not hashtag_already_present:
            text = text.replace("{tags}", hashtag + " " + filtered)
        else:
            text = text.replace("{tags}", filtered)
    else:
        # Auto-append tags (and maybe hashtag) at end
        suffix = filter_existing_tags(text, tags_str)
        if not has_hashtag and not hashtag_already_present:
            suffix = hashtag + " " + suffix
        text = text.rstrip() + " " + suffix

    return text


def parse_file(filepath, hashtag):
    """Parse a single .md file into a post dict."""
    with open(filepath) as f:
        content = f.read()

    fm, body = parse_frontmatter(content, filepath)
    validate_frontmatter(fm, filepath)
    sections = extract_sections(body, filepath)

    tags = [str(t) for t in fm["tags"]]
    tags_str = " ".join(f"#{t}" for t in tags)
    url = str(fm["url"])

    long_text = substitute(sections["long"], url, hashtag, tags_str) if "long" in sections else ""
    medium_text = substitute(sections["medium"], url, hashtag, tags_str) if "medium" in sections else ""
    short_text = substitute(sections["short"], url, hashtag, tags_str) if "short" in sections else ""
    article_body = sections.get("article", "")

    return {
        "title": fm.get("title", ""),
        "date": str(fm["date"]),
        "long_text": long_text,
        "medium_text": medium_text,
        "short_text": short_text,
        "article_body": article_body,
        "url": url,
        "images": [normalize_image_url(str(img)) for img in fm["images"]],
        "tags": tags,
    }


def main():
    with open("social.yml") as f:
        config = yaml.safe_load(f)

    hashtag = config["hashtag"]
    content_path = config["content_path"]
    scan_folders = config.get("scan_folders", 3)
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    if not os.path.isdir(content_path):
        print(f"ERROR: content_path '{content_path}' not found", file=sys.stderr)
        sys.exit(1)

    posts = []
    errors = []

    # Scan most recent N date folders (descending order)
    all_folders = [
        f for f in sorted(os.listdir(content_path), reverse=True)
        if os.path.isdir(os.path.join(content_path, f))
        and re.match(r"^\d{4}-\d{2}-\d{2}$", f)
    ]

    for folder_name in all_folders[:scan_folders]:
        folder_path = os.path.join(content_path, folder_name)

        for filename in sorted(os.listdir(folder_path)):
            if not filename.endswith(".md"):
                continue
            filepath = os.path.join(folder_path, filename)

            try:
                post = parse_file(filepath, hashtag)
            except ValueError as e:
                errors.append(str(e))
                continue

            # Skip past publication dates
            if post["date"] < today:
                print(f"  Skipping (past date): {filepath}")
                continue

            posts.append(post)

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        sys.exit(1)

    with open("posts.json", "w") as f:
        json.dump(posts, f, indent=2, ensure_ascii=False)

    print(f"Parsed {len(posts)} post(s) into posts.json")


if __name__ == "__main__":
    main()
