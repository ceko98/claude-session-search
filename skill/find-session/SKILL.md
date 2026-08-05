---
name: find-session
description: Find a past Claude Code session by describing what it was about, and get a ready-to-paste resume command. Use when the user says "find my session", "which session was I working on...", "lost my session", "resume the session where...", or invokes /find-session.
---

# Find Session

Search past Claude Code sessions by content and give the user a resume command.

## How

1. Run the search script with the user's words as query terms:

   ```bash
   bash ~/.claude/scripts/session-search.sh <term1> <term2> ...
   ```

   Flags: `--days N` (default 60), `--project <substring>` (project dir slug), `--all-text` (search assistant text too, not just user messages).

2. **Too many hits** → narrow: add more distinctive terms (ticket IDs, service names), or `--project`, or smaller `--days`.

3. **Zero hits** → loosen: fewer/shorter terms, add `--all-text`, raise `--days` (e.g. `--days 365`).

4. Present top results (max ~10): date, title (Haiku summary when available), match snippet, and the `cd <dir> && claude --resume <session-id>` command ready to paste. Newest first. Keep output short.

## Notes

- Titles come from `~/.claude/session-index.jsonl` (Haiku summaries written by the Stop hook `~/.claude/scripts/session-summarize.sh`); sessions without an index entry fall back to their first user message.
- Multi-term query = AND, case-insensitive.
- Resume must run from the session's original cwd — the printed command includes the `cd`.
