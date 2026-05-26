# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-05-26
### Bug Fixes
- Update buffer createPost assets payload to new AssetInput schema

## [0.1.14] - 2026-04-26
### Chores
- Add make-based release flow
- Release v0.1.14

### Documentation
- Add last steps to publish

### Features
- Make setup.sh re-runnable from generated README

### Performance
- Extract setup.sh heredocs into template files

## [0.1.13] - 2026-04-17
### Bug Fixes
- Use Google Drive thumbnail URL for Buffer image compatibility

## [0.1.12] - 2026-04-17
### Bug Fixes
- Read text directly from posts.json in buffer-publish to preserve unicode

## [0.1.11] - 2026-04-17
### Bug Fixes
- Quote POST_URL in dedup python and show dedup debug output

## [0.1.10] - 2026-04-17
### Test
- Add debugging for Buffer

## [0.1.9] - 2026-04-17
### Test
- Add debugging for Buffer

## [0.1.8] - 2026-04-17
### Bug Fixes
- Add shouldShareToFeed for Instagram metadata in Buffer

## [0.1.7] - 2026-04-17
### Bug Fixes
- Use metadata.instagram.type for Buffer Instagram post type

## [0.1.6] - 2026-04-17
### Bug Fixes
- Use metadata.instagram.type for Buffer Instagram post type

## [0.1.5] - 2026-04-17
### Bug Fixes
- Remove local keyword outside function in Instagram buffer block

## [0.1.4] - 2026-04-17
### Bug Fixes
- Google Drive direct URL without redirect and  Instagram post type

## [0.1.3] - 2026-04-17
### Test
- Add try catch for debugging

## [0.1.2] - 2026-04-17
### Bug Fixes
- Use temp files for API responses to avoid JSON quoting issues in mastodon and devto scripts

### Features
- Add dynamic tag version management

## [0.1.1] - 2026-04-17
### Features
- Add scan_folders parameter to limit folder scanning

## [0.1.0] - 2026-04-15
### Features
- Reusable GitHub Action for cross-posting to Mastodon, Buffer, and dev.to

[0.2.0]: https://github.com/bilardi/github-actions-publish/compare/v0.1.14...v0.2.0
[0.1.14]: https://github.com/bilardi/github-actions-publish/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/bilardi/github-actions-publish/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/bilardi/github-actions-publish/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/bilardi/github-actions-publish/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/bilardi/github-actions-publish/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/bilardi/github-actions-publish/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/bilardi/github-actions-publish/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/bilardi/github-actions-publish/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/bilardi/github-actions-publish/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/bilardi/github-actions-publish/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/bilardi/github-actions-publish/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/bilardi/github-actions-publish/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/bilardi/github-actions-publish/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/bilardi/github-actions-publish/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/bilardi/github-actions-publish/compare/...v0.1.0

