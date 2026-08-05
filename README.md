# claude-session-search

Find your lost Claude Code sessions by describing what they were about — not by scrolling the `/resume` picker's first-message titles.

```
/find-session netsuite deposit export CT-59976
```

```
2026-08-05  Investigated CT-59976: deposits failing to export to NetSuite...
    resume: cd /Users/you/work && claude --resume 83856ddf-797e-4634-81aa-ed63407e0988
```

## What you get

| Piece | What it does |
|---|---|
| `/find-session` skill | Ask Claude "find my session about X" → ranked results + ready-to-paste resume command |
| `session-search.sh` | The search engine. Also works standalone from your shell |
| `session-summarize.sh` | Stop hook: after each turn, Haiku writes a one-line summary + keywords per session into a tiny index. Search titles become meaningful |

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
- `--project <substring>` — filter by project dir slug (e.g. `work`, `my-repo`).
- `--all-text` — also search assistant messages, not just yours.

## How summaries work

The Stop hook fires when Claude finishes a turn. It backgrounds itself (never delays your session), debounces to once per 10 minutes per session, skips sessions with fewer than 2 user messages, and calls `claude -p --model haiku` on your messages only. Result is upserted into `~/.claude/session-index.jsonl`:

```json
{"sessionId":"abc-123","cwd":"/Users/you/work","project":"-Users-you-work","updatedAt":"2026-08-05T09:00:00Z","summary":"Investigated CT-1234: ...","keywords":"CT-1234, netsuite, deposits"}
```

Cost: one small Haiku call per active session per 10+ minutes. Failures are silent — the hook never breaks your session.

## Uninstall

```bash
rm -rf ~/.claude/skills/find-session ~/.claude/scripts/session-search.sh ~/.claude/scripts/session-summarize.sh ~/.claude/session-index.jsonl ~/.claude/session-index-stamps
```

Then remove the `Stop` hook entry from `~/.claude/settings.json`.
