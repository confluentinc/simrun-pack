#!/usr/bin/env bash
#
# Cut the next semver tag from the merged commit's conventional-commit type:
#   feat... -> minor, everything else -> patch. Never major (a v2+ tag would force
#   a Go module-path change to /v2).
#
# Runs on a push to the default branch. PRs are squash-merged, so HEAD is a single
# commit whose subject is the merged PR's conventional-commit message — no range
# scan, no unshallow, no git-describe needed.
set -euo pipefail

# Latest released tag, read straight from the remote (works on Semaphore's shallow,
# tagless checkout). --sort ascending + tail = highest version. The `|| true` guards
# the first release, where grep matches nothing and would otherwise trip pipefail/set -e;
# a genuine ls-remote failure still propagates and fails the job.
latest="$(git ls-remote --tags --refs --sort='v:refname' origin \
  | { grep -Eo 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' || true; } \
  | sed 's,refs/tags/,,' | tail -n1)"
latest="${latest:-v0.0.0}"

subject="$(git log -1 --pretty=%s)"
echo "Latest tag:    ${latest}"
echo "Merge commit:  ${subject}"

base="${latest#v}"
major="${base%%.*}"
rest="${base#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"

if echo "${subject}" | grep -Eq '^feat(\(.+\))?!?:'; then
  minor=$((minor + 1)); patch=0; bump="minor"
else
  patch=$((patch + 1)); bump="patch"
fi

next="v${major}.${minor}.${patch}"
echo "Bump:          ${bump} -> ${next}"

git tag "${next}"
git push origin "${next}"
echo "Pushed tag ${next}"
