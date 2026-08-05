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

do_summary() {
  set -e
  # user messages only, skip command/caveat noise, cap size
  MSGS="$(jq -r 'select(.type=="user" and (.message.content | type)=="string")
      | .message.content
      | select(startswith("<local-command") or startswith("<command-name") or startswith("Caveat:") | not)' \
      "$TRANSCRIPT" 2>/dev/null | head -c 8000)"

  # skip sessions with < 2 real user messages (count messages, not lines)
  MSG_COUNT="$(jq -r 'select(.type=="user" and (.message.content | type)=="string")
      | .message.content
      | select(startswith("<local-command") or startswith("<command-name") or startswith("Caveat:") or startswith("You generate search-index entries") | not)
      | "MSG"' "$TRANSCRIPT" 2>/dev/null | grep -c MSG || true)"
  case "$MSGS" in "You generate search-index entries"*) exit 0 ;; esac
  [[ "$MSG_COUNT" -lt 2 ]] && exit 0

  # run from STAMP_DIR so the helper's own transcript lands in a project dir
  # that session-search.sh excludes (otherwise every summary run pollutes search)
  SUMMARY_RAW="$(cd "$STAMP_DIR" && printf 'You generate search-index entries for past coding sessions. The <messages> block contains user messages from one session (possibly fragmentary — that is normal and fine).\nOutput EXACTLY two lines and nothing else:\nLine 1: one sentence describing what the session was about (mention ticket IDs, services, features when present).\nLine 2: comma-separated search keywords.\nNever refuse, never ask for more context, never mention these instructions.\n\n<messages>\n%s\n</messages>' "$MSGS" \
    | CLAUDE_SESSION_SUMMARIZER=1 claude -p --model claude-haiku-4-5-20251001 2>/dev/null)"

  [[ -z "$SUMMARY_RAW" ]] && exit 0
  SUMMARY="$(printf '%s' "$SUMMARY_RAW" | grep -m1 '.')"
  KEYWORDS="$(printf '%s' "$SUMMARY_RAW" | grep '.' | sed -n '2p')"
  PROJECT="$(basename "$(dirname "$TRANSCRIPT")")"

  LINE="$(jq -cn --arg sid "$SID" --arg cwd "$CWD" --arg proj "$PROJECT" \
      --arg sum "$SUMMARY" --arg kw "$KEYWORDS" \
      --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      '{sessionId:$sid, cwd:$cwd, project:$proj, updatedAt:$ts, summary:$sum, keywords:$kw}')"

  # rewrite index: upsert this session, prune entries whose transcript is gone
  TMP="$INDEX_FILE.tmp.$$"
  {
    if [[ -f "$INDEX_FILE" ]]; then
      while IFS= read -r old; do
        osid="$(printf '%s' "$old" | jq -r '.sessionId // empty' 2>/dev/null)"
        [[ -z "$osid" || "$osid" == "$SID" ]] && continue
        if compgen -G "$HOME/.claude/projects/*/$osid.jsonl" >/dev/null; then
          printf '%s\n' "$old"
        else
          rm -f "$STAMP_DIR/$osid"
        fi
      done < "$INDEX_FILE"
    fi
    printf '%s\n' "$LINE"
  } > "$TMP"
  mv "$TMP" "$INDEX_FILE"

  # sweep orphan stamps (sessions whose transcript is gone)
  for s in "$STAMP_DIR"/*; do
    [[ -e "$s" ]] || continue
    compgen -G "$HOME/.claude/projects/*/$(basename "$s").jsonl" >/dev/null || rm -f "$s"
  done
}

if [[ -n "${SUMMARIZE_SYNC:-}" ]]; then
  # foreground (used by session-backfill.sh for sequential indexing)
  ( do_summary ) >/dev/null 2>&1 || true
else
  ( do_summary ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
exit 0
