#!/usr/bin/env bash
# Install the claude-session-search skill, scripts, and Stop hook into ~/.claude
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_CMD="bash ~/.claude/scripts/session-summarize.sh"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

echo "claude-session-search setup"
echo
echo "Checking prerequisites..."
command -v jq >/dev/null 2>&1 && ok "jq" || fail "jq missing — install with: brew install jq"
command -v claude >/dev/null 2>&1 && ok "claude CLI" || fail "claude CLI missing — https://claude.com/claude-code"
[[ -d "$CLAUDE_DIR" ]] && ok "~/.claude exists" || fail "~/.claude not found — run claude once first"

echo
echo "Installing files..."
mkdir -p "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/skills"
cp "$REPO_DIR/scripts/session-search.sh" "$REPO_DIR/scripts/session-summarize.sh" "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/session-search.sh" "$CLAUDE_DIR/scripts/session-summarize.sh"
ok "scripts → ~/.claude/scripts/"
cp -R "$REPO_DIR/skill/find-session" "$CLAUDE_DIR/skills/"
ok "skill → ~/.claude/skills/find-session/"

echo
echo "Registering Stop hook (Haiku session summaries)..."
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi
if jq -e --arg cmd "$HOOK_CMD" '.hooks.Stop[]?.hooks[]? | select(.command == $cmd)' "$SETTINGS" >/dev/null 2>&1; then
  ok "Stop hook already registered"
else
  TMP="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" \
    '.hooks.Stop = ((.hooks.Stop // []) + [{"hooks":[{"type":"command","command":$cmd}]}])' \
    "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
  ok "Stop hook added to ~/.claude/settings.json"
fi

echo
echo "Smoke test..."
if bash "$CLAUDE_DIR/scripts/session-search.sh" 2>&1 | grep -q usage; then
  ok "session-search.sh runs"
else
  fail "session-search.sh did not run"
fi

echo
echo "Done. Usage:"
echo "  • In Claude Code:  /find-session <what you remember>"
echo "  • From shell:      ~/.claude/scripts/session-search.sh <terms> [--days N] [--project slug] [--all-text]"
echo "  • Summaries build automatically as you use Claude (Stop hook, Haiku, debounced 10 min)."
echo "  • Restart open Claude sessions to pick up the new skill and hook."
