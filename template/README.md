# {{REPO_NAME}}

TODO: add description

## Prerequisites

- GitHub secrets configured (see below)
- [{{PUBLISH_REPO}}](https://github.com/{{PUBLISH_REPO}}) provides the reusable workflow and scripts

## Usage

### Writing a post

Create a date folder under `{{CONTENT_PATH}}/` and add `.md` files. The folder name is the event date.

```
{{CONTENT_PATH}}/
  2026-05-21/
    pre.md   # announcement
    post.md  # recap
```

Inside the frontmatter, `date:` is the earliest publication date: posts with `date` in the future are skipped until that day arrives.

Post format:

```markdown
---
title: "Event Title"
date: 2026-04-27
images:
  - https://drive.google.com/file/d/FILE_ID/view
url: https://www.meetup.com/your-event/123
tags: [topic1, topic2]
---

# long

Text for LinkedIn and Instagram (up to 3,000 chars).

{url}

{hashtag} {tags}

# medium

Text for Mastodon and Threads (up to 500 chars).

{url}

{hashtag} {tags}

# short

Text for Twitter (up to 280 chars) {url} {hashtag} {tags}
```

Sections are optional: include a section only if the corresponding channel is active. See the [full format reference](https://github.com/{{PUBLISH_REPO}}#file-format).

### Publishing

Trigger the workflow manually from GitHub Actions (`workflow_dispatch`).

### Checking character counts

```bash
bash /path/to/github-actions-publish/scripts/check-length.sh {{CONTENT_PATH}}/2026-05-21/pre.md
```

### Updating setup

Re-run `setup.sh` to pick up updates from github-actions-publish (e.g. new workflow version):

```bash
{{SETUP_COMMAND}}
```

The script asks before overwriting existing files: review the diff and keep your local changes.

## GitHub secrets

| Secret | Used by |
|--------|---------|
| `MASTODON_ACCESS_TOKEN` | Mastodon direct publishing |
| `BUFFER_ACCESS_TOKEN` | Buffer draft queuing (LinkedIn, Twitter, Threads, Instagram) |
| `DEV_TO_API_KEY` | dev.to draft creation |

## Project structure

```
.github/
  workflows/
    publish.yml  # calls {{PUBLISH_REPO}} workflow
{{CONTENT_PATH}}/  # date folders with .md files
social.yml  # repo configuration (hashtag, socials, parser)
README.md  # this file
LICENSE  # MIT license
```

## License

This repo is released under the MIT license. See [LICENSE](LICENSE) for details.
