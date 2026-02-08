#!/usr/bin/env bash
set -euo pipefail

# Copy selected skills from Claude's local skills directory into this repo.
#
# Usage:
#   scripts/copy-claude-skills.sh
#   scripts/copy-claude-skills.sh <skill-name> [<skill-name> ...]
#
# Defaults (when no args are provided):
#   - create-plan
#   - execute-plan
#   - fetch-rules
#   - lint-build-loop

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST_ROOT="${REPO_ROOT}/skills"

if ! command -v rsync >/dev/null 2>&1; then
  echo "Error: rsync is required but not found on PATH." >&2
  exit 1
fi

DEFAULT_SKILLS=(
  "create-plan"
  "execute-plan"
  "fetch-rules"
  "lint-build-loop"
)

if [[ "$#" -gt 0 ]]; then
  SKILLS=("$@")
else
  SKILLS=("${DEFAULT_SKILLS[@]}")
fi

for skill in "${SKILLS[@]}"; do
  src="${SRC_ROOT}/${skill}"
  if [[ ! -d "$src" ]]; then
    echo "Error: source skill not found: ${src}" >&2
    exit 1
  fi
done

mkdir -p "$DEST_ROOT"

for skill in "${SKILLS[@]}"; do
  src="${SRC_ROOT}/${skill}"
  dest="${DEST_ROOT}/${skill}"

  mkdir -p "$dest"
  rsync -a --delete \
    --exclude ".DS_Store" \
    --exclude ".git" \
    "${src}/" "${dest}/"

  echo "Copied ${skill} -> ${dest}"
done

echo "Done."
