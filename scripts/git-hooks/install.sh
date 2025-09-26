#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
TARGET="$REPO_ROOT/scripts/git-hooks/pre-push"

if [ ! -d "$REPO_ROOT/.git" ]; then
  echo "[git-hooks] This script must be run from inside a git repository." >&2
  exit 1
fi

mkdir -p "$HOOKS_DIR"
ln -sf "$TARGET" "$HOOKS_DIR/pre-push"
chmod +x "$TARGET"

echo "[git-hooks] Installed pre-push hook -> $HOOKS_DIR/pre-push"
