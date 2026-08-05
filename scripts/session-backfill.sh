#!/usr/bin/env bash
# Backfill Haiku summaries for existing sessions into ~/.claude/session-index.jsonl
# Usage: session-backfill.sh [--days N] [--limit N] [--project substr] [--jobs N] [--dry-run]
set -uo pipefail

PROJECTS_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/session-index.jsonl"
SUMMARIZE="$HOME/.claude/scripts/session-summarize.sh"
DAYS=60
LIMIT=30
JOBS=4
PROJECT=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

FILES="$(find "$PROJECTS_DIR" -maxdepth 2 -name '*.jsonl' -not -path '*/subagents/*' -not -path '*session-index-stamps*' -mtime "-$DAYS" 2>/dev/null | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null)"
[[ -n "$PROJECT" ]] && FILES="$(printf '%s\n' "$FILES" | grep -i -- "$PROJECT" || true)"

# --- collect candidates (cheap sequential pre-checks) ---
CANDIDATES=()
skipped=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ "${#CANDIDATES[@]}" -ge "$LIMIT" ]] && break
  sid="$(basename "$f" .jsonl)"

  # already indexed?
  if [[ -f "$INDEX_FILE" ]] && grep -q -- "$sid" "$INDEX_FILE"; then
    skipped=$((skipped+1)); continue
  fi

  # cheap pre-check: needs >= 2 real user messages (same rule as the hook)
  msg_count="$(jq -r 'select(.type=="user" and (.message.content | type)=="string")
      | .message.content
      | select(startswith("<local-command") or startswith("<command-name") or startswith("Caveat:") or startswith("You generate search-index entries") | not)
      | "MSG"' "$f" 2>/dev/null | grep -c MSG || true)"
  if [[ "$msg_count" -lt 2 ]]; then
    skipped=$((skipped+1)); continue
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would index: $sid  ($(basename "$(dirname "$f")"))"
  fi
  CANDIDATES+=("$f")
done <<< "$FILES"

if [[ "$DRY_RUN" -eq 1 || "${#CANDIDATES[@]}" -eq 0 ]]; then
  echo
  echo "candidates: ${#CANDIDATES[@]}, skipped: $skipped (already indexed / too small)"
  exit 0
fi

# --- summarize candidates in parallel (index writes are lock-serialized) ---
echo "indexing ${#CANDIDATES[@]} sessions with $JOBS parallel jobs..."
export SUMMARIZE INDEX_FILE
printf '%s\n' "${CANDIDATES[@]}" | xargs -P "$JOBS" -n 1 bash -c '
  f="$1"
  sid="$(basename "$f" .jsonl)"
  cwd="$(head -50 "$f" | jq -r "select(.cwd) | .cwd" 2>/dev/null | head -1)"
  jq -cn --arg sid "$sid" --arg t "$f" --arg cwd "${cwd:-$HOME}" \
      "{session_id:\$sid, transcript_path:\$t, cwd:\$cwd}" \
    | SUMMARIZE_SYNC=1 bash "$SUMMARIZE"
  if grep -q -- "$sid" "$INDEX_FILE" 2>/dev/null; then
    echo "  ✓ $sid: $(grep -- "$sid" "$INDEX_FILE" | tail -1 | jq -r ".summary" | cut -c1-90)"
  else
    echo "  ✗ $sid: no summary written (Haiku failed?)"
  fi
' _

done_count=0
for f in "${CANDIDATES[@]}"; do
  grep -q -- "$(basename "$f" .jsonl)" "$INDEX_FILE" 2>/dev/null && done_count=$((done_count+1))
done
echo
echo "indexed: $done_count/${#CANDIDATES[@]}, skipped: $skipped (already indexed / too small)"
