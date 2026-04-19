#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=(
  "$ROOT_DIR"
  "$ROOT_DIR/project-lumen-light"
  "$ROOT_DIR/project-lumen-source"
)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

say() {
  echo -e "$1"
}

fail() {
  say "${RED}ERROR: $1${NC}"
  exit 1
}

warn() {
  say "${YELLOW}$1${NC}"
}

push_repo() {
  local repo_dir="$1"
  local repo_name
  local branch
  local upstream=""
  local ahead_count="0"
  local porcelain_output=""
  local push_exit_code=0
  shift

  if [ ! -d "$repo_dir" ]; then
    fail "Repo directory not found: $repo_dir"
  fi

  if ! git -C "$repo_dir" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    fail "Not a git repo: $repo_dir"
  fi

  repo_name="$(basename "$repo_dir")"
  if [ "$repo_dir" = "$ROOT_DIR" ]; then
    repo_name="project-lumen"
  fi

  branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)"
  if [ "$branch" = "HEAD" ]; then
    fail "$repo_name is in a detached HEAD state. Check out a branch before pushing."
  fi

  upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [ -n "$upstream" ]; then
    ahead_count="$(git -C "$repo_dir" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
  fi

  say ""
  say "${CYAN}Pushing $repo_name (${branch})...${NC}"

  if [ -n "$(git -C "$repo_dir" status --short)" ]; then
    warn "  Working tree has uncommitted changes. Only committed work can be pushed."
  fi

  set +e
  porcelain_output="$(git -C "$repo_dir" push --porcelain "$@" 2>&1)"
  push_exit_code=$?
  set -e

  echo "$porcelain_output"

  if [ $push_exit_code -ne 0 ]; then
    fail "Push failed for $repo_name"
  fi

  if echo "$porcelain_output" | grep -q "Everything up-to-date"; then
    if [ "$ahead_count" != "0" ]; then
      warn "  Remote already had the latest commit. Your local tracking ref was stale."
    else
      warn "  No new commits were pushed."
    fi
    return
  fi

  if echo "$porcelain_output" | grep -Eq '^='; then
    if [ "$ahead_count" != "0" ]; then
      warn "  Remote already had the latest commit. Your local tracking ref may be stale."
    else
      warn "  No new commits were pushed."
    fi
    return
  fi

  if echo "$porcelain_output" | grep -Eq '^[*+-]'; then
    say "${GREEN}Pushed ${repo_name} successfully.${NC}"
    return
  fi

  say "${GREEN}Finished pushing $repo_name.${NC}"
}

say "${YELLOW}Pushing all Lumen repos...${NC}"
for repo_dir in "${REPOS[@]}"; do
  push_repo "$repo_dir" "$@"
done
say ""
say "${GREEN}Push task completed. Review the per-repo output above for pushed, skipped, or unchanged repos.${NC}"
