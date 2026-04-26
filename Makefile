# github-actions-publish makefile

.PHONY: help # print this help list
help:
	grep PHONY Makefile | sed 's/.PHONY: /make /' | grep -v grep

.PHONY: major # bump major version, update CHANGELOG.md and push with tags
major:
	bash scripts/release.sh major

.PHONY: minor # bump minor version, update CHANGELOG.md and push with tags
minor:
	bash scripts/release.sh minor

.PHONY: patch # bump patch version, update CHANGELOG.md and push with tags
patch:
	bash scripts/release.sh patch
