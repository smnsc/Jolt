#!/bin/bash
# Dispatch a release from committed main; no local key or build is required.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 || ! "${1:-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'Usage: scripts/release.sh MAJOR.MINOR.PATCH BUILD_NUMBER' >&2
  exit 2
fi
if [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
  echo 'BUILD_NUMBER must be a positive integer without leading zeros.' >&2
  exit 2
fi
project_dir="$PWD"
MARKETING_VERSION="$1"
BUILD_NUMBER="$2"
source scripts/version.sh
command -v gh >/dev/null || { echo 'Install GitHub CLI, then run gh auth login.' >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
  echo 'Commit and push your changes first; releases build the remote main branch.' >&2
  exit 1
fi
git fetch origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo 'Your checkout must match origin/main. Push or update your checkout first.' >&2
  exit 1
fi
test -s "dev-docs/releases/$1.md" || { echo "Missing release notes: dev-docs/releases/$1.md" >&2; exit 1; }
gh workflow run release.yml --ref main -f "version=$1" -f "build_number=$2"
echo "Release $1 (Jolt build $2) requested. Follow progress with: gh run list --workflow release.yml"
echo 'The website deployment runs separately: gh run list --workflow pages.yml'
