#!/bin/bash
# Dispatch a release from committed main; no local key or build is required.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 0 ]]; then
  echo 'Usage: scripts/release.sh (reads version and build from Resources/Info.plist)' >&2
  exit 2
fi
command -v gh >/dev/null || { echo 'Install GitHub CLI, then run gh auth login.' >&2; exit 1; }
git fetch origin main

# Always describe the source GitHub will build, even when local changes are allowed.
release_identity=$(git show origin/main:Resources/Info.plist | python3 -c '
import plistlib, re, sys
info = plistlib.loads(sys.stdin.buffer.read())
version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version) or not re.fullmatch(r"[1-9][0-9]*", build):
    sys.exit("Invalid release version/build in origin/main:Resources/Info.plist.")
print(version, build)
')
read -r jolt_version jolt_build <<< "$release_identity"
workspace_changes=$(git status --porcelain --untracked-files=all)
read -r behind ahead <<< "$(git rev-list --left-right --count origin/main...HEAD)"
unpushed=$(git rev-list --count HEAD --not --remotes)
if [[ -n "$workspace_changes" || "$ahead" != 0 || "$behind" != 0 || "$unpushed" != 0 ]]; then
  echo 'Git workspace is dirty or differs from origin/main.' >&2
  echo "Current branch: $ahead commit(s) ahead of origin/main, $behind behind; $unpushed unpushed commit(s)." >&2
  echo "Continuing releases remote main: Jolt $jolt_version (Jolt build $jolt_build)." >&2
  echo 'Local file changes and commits absent from remote main will NOT be included. Commit and push them first to include them.' >&2
  answer=''
  printf 'Are you sure you want to continue? [y/N] ' >&2
  if ! read -r answer; then
    echo 'Release cancelled.' >&2
    exit 1
  fi
  case "$answer" in
    y|Y|[yY][eE][sS]) ;;
    *) echo 'Release cancelled.' >&2; exit 1 ;;
  esac
fi
gh workflow run release.yml --ref main
echo "Release $jolt_version (Jolt build $jolt_build) requested. Follow progress with: gh run list --workflow release.yml"
echo 'The website deployment runs separately: gh run list --workflow pages.yml'
