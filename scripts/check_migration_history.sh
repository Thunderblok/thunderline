#!/usr/bin/env bash
set -euo pipefail

# Prevent editing of non-latest migration files. Allow only creating new ones.
# Strategy: find git modified/staged migration files whose timestamp is not the max per repo.

MIGRATIONS_DIR="priv/repo/migrations"

if [ ! -d "$MIGRATIONS_DIR" ]; then
  echo "[migration-guard] No migrations directory found; skipping." >&2
  exit 0
fi

latest_file=$(ls -1 ${MIGRATIONS_DIR} | sort | tail -n1)

# Gather changed migration files (staged + unstaged) relative to HEAD
changed=$(git diff --name-only HEAD -- ${MIGRATIONS_DIR} || true)
changed_staged=$(git diff --name-only --cached -- ${MIGRATIONS_DIR} || true)
all_changed=$(printf "%s\n%s" "$changed" "$changed_staged" | grep -E "^${MIGRATIONS_DIR}" | sort -u || true)

violations=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base=$(basename "$f")
  if [ "$base" != "$latest_file" ] && [ -f "$f" ]; then
    # If it's a brand new file (untracked), allow if it's lexicographically greater than latest_file
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      violations+=("$f")
    else
      # new file - ensure timestamp > latest_file
      if [[ "$base" < "$latest_file" ]]; then
        violations+=("$f (timestamp older than existing latest)")
      fi
    fi
  fi
done <<< "$all_changed"

if [ ${#violations[@]} -gt 0 ]; then
  echo "[migration-guard] Detected edits to non-latest migration(s):" >&2
  for v in "${violations[@]}"; do echo "  - $v" >&2; done
  echo "Refuse commit. Create a new forward migration instead." >&2
  exit 1
fi

echo "[migration-guard] OK (no illegal historical migration edits)."
