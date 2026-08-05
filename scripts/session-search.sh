#!/usr/bin/env bash
# Search past Claude Code sessions by content. Prints resume commands.
# Usage: session-search.sh [--days N] [--project substr] [--all-text] <query terms...>
set -uo pipefail

PROJECTS_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/session-index.jsonl"
DAYS=60
PROJECT=""
ALL_TEXT=0
TERMS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --all-text) ALL_TEXT=1; shift ;;
    *) TERMS+=("$1"); shift ;;
  esac
done

if [[ ${#TERMS[@]} -eq 0 ]]; then
  echo "usage: session-search.sh [--days N] [--project substr] [--all-text] <query terms...>" >&2
  exit 1
fi

# --- Pass 0: index hits (Haiku summaries) ---
INDEX_IDS=""
if [[ -f "$INDEX_FILE" ]]; then
  INDEX_MATCHES="$(cat "$INDEX_FILE")"
  for t in "${TERMS[@]}"; do
    INDEX_MATCHES="$(printf '%s\n' "$INDEX_MATCHES" | grep -i -- "$t" || true)"
  done
  if [[ -n "$PROJECT" ]]; then
    INDEX_MATCHES="$(printf '%s\n' "$INDEX_MATCHES" | grep -i -- "$PROJECT" || true)"
  fi
  INDEX_IDS="$(printf '%s\n' "$INDEX_MATCHES" | jq -r '.sessionId' 2>/dev/null || true)"
fi

# --- Pass 1: candidate transcript files ---
FILES="$(find "$PROJECTS_DIR" -maxdepth 2 -name '*.jsonl' -not -path '*/subagents/*' -not -path '*session-index-stamps*' -mtime "-$DAYS" 2>/dev/null)"
if [[ -n "$PROJECT" ]]; then
  FILES="$(printf '%s\n' "$FILES" | grep -i -- "$PROJECT" || true)"
fi

HITS="$FILES"
for t in "${TERMS[@]}"; do
  [[ -z "$HITS" ]] && break
  HITS="$(printf '%s\n' "$HITS" | tr '\n' '\0' | xargs -0 grep -lis -- "$t" 2>/dev/null || true)"
done

# Add transcript files for index-matched sessions (even if raw grep missed them)
if [[ -n "$INDEX_IDS" ]]; then
  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    f="$(printf '%s\n' "$FILES" | grep -- "$sid" | head -1 || true)"
    [[ -n "$f" ]] && HITS="$(printf '%s\n%s' "$HITS" "$f")"
  done <<< "$INDEX_IDS"
fi

HITS="$(printf '%s\n' "$HITS" | grep -v '^$' | sort -u)"
if [[ -z "$HITS" ]]; then
  echo "no matches"
  exit 0
fi

# newest first
HITS="$(printf '%s\n' "$HITS" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null)"

# --- Pass 2: render ---
FIRST_TERM="${TERMS[0]}"
printf '%s\n' "$HITS" | head -15 | while IFS= read -r f; do
  sid="$(basename "$f" .jsonl)"
  date="$(stat -f '%Sm' -t '%Y-%m-%d' "$f" 2>/dev/null || date -r "$f" '+%Y-%m-%d' 2>/dev/null)"
  proj="$(basename "$(dirname "$f")")"

  # index summary if present
  summary=""
  if [[ -f "$INDEX_FILE" ]]; then
    summary="$(grep -- "$sid" "$INDEX_FILE" | tail -1 | jq -r '.summary // empty' 2>/dev/null || true)"
  fi

  cwd="$(head -50 "$f" | jq -r 'select(.cwd) | .cwd' 2>/dev/null | head -1)"
  [[ -z "$cwd" ]] && cwd="$(jq -r 'select(.cwd) | .cwd' "$f" 2>/dev/null | head -1)"

  title="$summary"
  if [[ -z "$title" ]]; then
    title="$(jq -r 'select(.type=="user" and (.message.content | type)=="string")
        | .message.content
        | select(startswith("<local-command") or startswith("<command-name") or startswith("Caveat:") | not)' \
        "$f" 2>/dev/null | head -1 | cut -c1-120)"
  fi

  if [[ $ALL_TEXT -eq 1 ]]; then
    snippet="$(grep -io -- ".\{0,80\}${FIRST_TERM}.\{0,80\}" "$f" 2>/dev/null | head -2)"
  else
    snippet="$(jq -r 'select(.type=="user" and (.message.content | type)=="string") | .message.content' "$f" 2>/dev/null \
      | grep -io -- ".\{0,80\}${FIRST_TERM}.\{0,80\}" | head -2)"
  fi

  echo "$date  $proj  $sid"
  echo "    title:  ${title:-<untitled>}"
  [[ -n "$snippet" ]] && printf '%s\n' "$snippet" | sed 's/^/    match:  …/;s/$/…/'
  echo "    resume: cd ${cwd:-$HOME} && claude --resume $sid"
  echo "    in-app: /resume $sid"
  echo
done
