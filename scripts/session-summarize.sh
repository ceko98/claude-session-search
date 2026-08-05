#!/usr/bin/env bash
# Stop hook: keep a Haiku-written one-line summary of the session in ~/.claude/session-index.jsonl
# Reads hook JSON on stdin: {"session_id":..., "transcript_path":..., "cwd":...}
# Always exits 0; real work runs in background so the UI is never delayed.
set -u

# recursion guard: this script's own `claude -p` call fires Stop hooks too
[[ -n "${CLAUDE_SESSION_SUMMARIZER:-}" ]] && exit 0

INPUT="$(cat)"
INDEX_FILE="$HOME/.claude/session-index.jsonl"
STAMP_DIR="$HOME/.claude/session-index-stamps"
DEBOUNCE_MIN=10

SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"

[[ -z "$SID" || -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

mkdir -p "$STAMP_DIR"
STAMP="$STAMP_DIR/$SID"

# debounce: skip if summarized in the last N minutes
if [[ -f "$STAMP" && -n "$(find "$STAMP" -mmin "-$DEBOUNCE_MIN" 2>/dev/null)" ]]; then
  exit 0
fi
touch "$STAMP"

(
  set -e
  # user messages only, skip command/caveat noise, cap size
  MSGS="$(jq -r 'select(.type=="user" and (.message.content | type)=="string")
      | .message.content
      | select(startswith("<local-command") or startswith("<command-name") or startswith("Caveat:") | not)' \
      "$TRANSCRIPT" 2>/dev/null | head -c 8000)"

  # skip sessions with < 2 real user messages (count messages, not lines)
  MSG_COUNT="$(jq -r 'select(.type=="user" and (.message.content | type)=="string")
      | .message.content
      | select(startswith("<local-command") or startswith("<command-name") or startswith("Caveat:") or startswith("Summarize this coding session") | not)
      | "MSG"' "$TRANSCRIPT" 2>/dev/null | grep -c MSG || true)"
  case "$MSGS" in "Summarize this coding session"*) exit 0 ;; esac
  [[ "$MSG_COUNT" -lt 2 ]] && exit 0

  # run from STAMP_DIR so the helper's own transcript lands in a project dir
  # that session-search.sh excludes (otherwise every summary run pollutes search)
  SUMMARY_RAW="$(cd "$STAMP_DIR" && printf 'Summarize this coding session from the user messages below.\nLine 1: one sentence, what the session was about (specific: ticket IDs, services, features).\nLine 2: comma-separated search keywords.\nNo other output.\n\n%s' "$MSGS" \
    | CLAUDE_SESSION_SUMMARIZER=1 claude -p --model claude-haiku-4-5-20251001 2>/dev/null)"

  [[ -z "$SUMMARY_RAW" ]] && exit 0
  SUMMARY="$(printf '%s' "$SUMMARY_RAW" | grep -m1 '.')"
  KEYWORDS="$(printf '%s' "$SUMMARY_RAW" | grep '.' | sed -n '2p')"
  PROJECT="$(basename "$(dirname "$TRANSCRIPT")")"

  LINE="$(jq -cn --arg sid "$SID" --arg cwd "$CWD" --arg proj "$PROJECT" \
      --arg sum "$SUMMARY" --arg kw "$KEYWORDS" \
      --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      '{sessionId:$sid, cwd:$cwd, project:$proj, updatedAt:$ts, summary:$sum, keywords:$kw}')"

  TMP="$INDEX_FILE.tmp.$$"
  { [[ -f "$INDEX_FILE" ]] && grep -v -- "$SID" "$INDEX_FILE" || true; printf '%s\n' "$LINE"; } > "$TMP"
  mv "$TMP" "$INDEX_FILE"
) >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
