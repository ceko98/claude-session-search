# claude-session-search

Find your lost Claude Code sessions by describing what they were about — not by scrolling the `/resume` picker's first-message titles.

```
/find-session flaky webhook retry bug
```

```
2026-08-05  Fixed flaky retry logic in the webhook handler: added exponential backoff...
    resume: cd /Users/you/projects/my-app && claude --resume 1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d
```

## What you get

| Piece | What it does |
|---|---|
| `/find-session` skill | Ask Claude "find my session about X" → ranked results + ready-to-paste resume command |
| `session-search.sh` | The search engine. Also works standalone from your shell |
| `session-summarize.sh` | Stop hook: after each turn, Haiku writes a one-line summary + keywords per session into a tiny index. Search titles become meaningful |
| `/index-sessions` skill + `session-backfill.sh` | Backfill summaries for sessions from before install |

Search checks the Haiku summary index first (high signal), then falls back to grepping raw transcripts under `~/.claude/projects/` — so sessions from before install are still findable.

## Install

```bash
git clone https://github.com/ceko98/claude-session-search.git && cd claude-session-search
./setup.sh
```

Requirements: `claude` CLI, `jq` (`brew install jq`). The script verifies both, copies files into `~/.claude/`, and registers the Stop hook in `~/.claude/settings.json` (idempotent — safe to re-run). Restart open Claude sessions afterwards.

## Usage

In Claude Code:

```
/find-session <whatever you remember>
```

From the shell:

```bash
~/.claude/scripts/session-search.sh <terms...> [--days N] [--project <slug>] [--all-text]
```

- Multi-term query = AND, case-insensitive.
- `--days N` — how far back (default 60).
- `--project <substring>` — filter by project dir slug (e.g. `my-app`, `dotfiles`).
- `--all-text` — also search assistant messages, not just yours.

## How summaries work

The Stop hook fires when Claude finishes a turn. It backgrounds itself (never delays your session), debounces to once per 10 minutes per session, skips sessions with fewer than 2 user messages, and calls `claude -p --model haiku` on your messages only. Result is upserted into `~/.claude/session-index.jsonl`:

```json
{"sessionId":"abc-123","cwd":"/Users/you/projects/my-app","project":"-Users-you-projects-my-app","updatedAt":"2026-08-05T09:00:00Z","summary":"Fixed flaky retry logic in the webhook handler...","keywords":"webhooks, retry, exponential backoff, payments API"}
```

Cost: one small Haiku call per active session per 10+ minutes. Failures are silent — the hook never breaks your session.

The index self-prunes: every summary write drops entries (and debounce stamps) for sessions whose transcript no longer exists, so it only ever holds live sessions. It's also safe to delete `~/.claude/session-index.jsonl` entirely — it rebuilds as you work.

## Indexing existing sessions

New sessions index themselves via the hook. For history from before install, run `/index-sessions` in Claude Code, or from the shell:

```bash
~/.claude/scripts/session-backfill.sh --dry-run          # preview candidates
~/.claude/scripts/session-backfill.sh                    # index (default: last 60 days, max 30 sessions)
~/.claude/scripts/session-backfill.sh --days 365 --limit 100
```

Idempotent — already-indexed sessions are skipped. One sequential Haiku call per session (~5-10s each).

## Uninstall

```bash
rm -rf ~/.claude/skills/find-session ~/.claude/scripts/session-search.sh ~/.claude/scripts/session-summarize.sh ~/.claude/session-index.jsonl ~/.claude/session-index-stamps
```

Then remove the `Stop` hook entry from `~/.claude/settings.json`.
