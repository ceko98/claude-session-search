#!/usr/bin/env bash
# Backfill Haiku summaries for existing sessions into ~/.claude/session-index.jsonl
# Usage: session-backfill.sh [--days N] [--limit N] [--project substr] [--dry-run]
set -uo pipefail

PROJECTS_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/session-index.jsonl"
SUMMARIZE="$HOME/.claude/scripts/session-summarize.sh"
DAYS=60
LIMIT=30
PROJECT=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

FILES="$(find "$PROJECTS_DIR" -maxdepth 2 -name '*.jsonl' -not -path '*/subagents/*' -not -path '*session-index-stamps*' -mtime "-$DAYS" 2>/dev/null | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null)"
[[ -n "$PROJECT" ]] && FILES="$(printf '%s\n' "$FILES" | grep -i -- "$PROJECT" || true)"

done_count=0
skipped=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ "$done_count" -ge "$LIMIT" ]] && break
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

  cwd="$(head -50 "$f" | jq -r 'select(.cwd) | .cwd' 2>/dev/null | head -1)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would index: $sid  ($(basename "$(dirname "$f")"))"
    done_count=$((done_count+1)); continue
  fi

  echo "indexing $sid ..."
  jq -cn --arg sid "$sid" --arg t "$f" --arg cwd "${cwd:-$HOME}" \
      '{session_id:$sid, transcript_path:$t, cwd:$cwd}' \
    | SUMMARIZE_SYNC=1 bash "$SUMMARIZE"

  if [[ -f "$INDEX_FILE" ]] && grep -q -- "$sid" "$INDEX_FILE"; then
    echo "  ✓ $(grep -- "$sid" "$INDEX_FILE" | tail -1 | jq -r '.summary' | cut -c1-100)"
    done_count=$((done_count+1))
  else
    echo "  ✗ no summary written (skipped or Haiku failed)"
    skipped=$((skipped+1))
  fi
done <<< "$FILES"

echo
echo "indexed: $done_count, skipped: $skipped (already indexed / too small / failed)"
