---
name: index-sessions
description: Backfill Haiku summaries for existing Claude Code sessions into the search index used by /find-session. Use when the user says "index my sessions", "index existing sessions", "backfill session summaries", "build the session index", or invokes /index-sessions.
---

# Index Sessions

Backfill the session search index (`~/.claude/session-index.jsonl`) with Haiku summaries for past sessions that aren't indexed yet.

## How

1. Preview first — show the user what would be indexed:

   ```bash
   bash ~/.claude/scripts/session-backfill.sh --dry-run [--days N] [--limit N] [--project <slug>]
   ```

2. Then run it for real (drop `--dry-run`). Defaults: `--days 60`, `--limit 30`, `--jobs 4`. Each session = one small Haiku call (~5-10s), run in parallel batches of `--jobs` — ~30s per 8 sessions at default parallelism.

3. Report the final `indexed: N, skipped: M` line. Skipped = already indexed, fewer than 2 user messages, or Haiku failure.

## Flags

- `--days N` — how far back to look (default 60).
- `--limit N` — max sessions to index this run (default 30, caps cost).
- `--jobs N` — parallel Haiku calls (default 4).
- `--project <substring>` — only sessions from matching project dirs.
- `--dry-run` — list candidates without calling Haiku.

## Notes

- Idempotent: already-indexed sessions are skipped, so re-running is safe and cheap.
- The Stop hook (`session-summarize.sh`) keeps NEW sessions indexed automatically; this skill is only for history from before install.
- To rebuild everything: delete `~/.claude/session-index.jsonl` and re-run with a big `--days`/`--limit`.
