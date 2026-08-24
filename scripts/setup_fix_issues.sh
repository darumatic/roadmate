#!/usr/bin/env bash
# One-time (idempotent) setup for the issue auto-fixer (scripts/fix_issues.py).
# Run it as the user that will run the cron — the personal user, not root:
#
#   ./scripts/setup_fix_issues.sh                # labels, clone, identity, hook, dirs
#   ./scripts/setup_fix_issues.sh --install-cron # also append the crontab entry
#
# The bot works in a dedicated clone (~/roadmate-bot/roadmate), never in the
# interactive workspace. Full model in specs.md ("Issue auto-fixer").
set -euo pipefail

export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$HOME/.local/bin:$PATH"

REPO="darumatic/roadmate"
BOT_HOME="$HOME/roadmate-bot"
CLONE="$BOT_HOME/roadmate"

echo "==> Labels"
ensure_label() { # name color description
  if gh label list -R "$REPO" --json name --jq '.[].name' | grep -qx "$1"; then
    echo "    $1 already exists"
  else
    gh label create "$1" -R "$REPO" --color "$2" --description "$3"
    echo "    $1 created"
  fi
}
ensure_label approved 0e8a16 \
  "Owner approval: the auto-fixer may implement and release this issue"
ensure_label claude-working fbca04 \
  "The auto-fixer is implementing this issue"
ensure_label claude-blocked d93f0b \
  "The auto-fixer gave up - needs a human; re-apply approved to retry"

echo "==> Directories"
mkdir -p "$BOT_HOME/logs" "$BOT_HOME/state/scratch"

echo "==> Bot clone"
if [ ! -d "$CLONE/.git" ]; then
  git clone "git@github.com:$REPO.git" "$CLONE"
else
  echo "    already cloned"
fi
# Identity is repo-local on this box; a fresh clone cannot commit without it.
git -C "$CLONE" config user.name "Adrian Deccico"
git -C "$CLONE" config user.email "adrian@darumatic.com"

echo "==> commit-msg attribution hook"
# Deterministic backstop for the house hard rule (commits are attributed to
# the owner only): the claude --settings flag fails silently on bad JSON, this
# hook cannot. Lives only in the bot clone's .git — never pushed.
HOOK="$CLONE/.git/hooks/commit-msg"
cat > "$HOOK" <<'EOF'
#!/bin/sh
# House hard rule: commits are attributed to the owner only.
if grep -qiE 'Co-Authored-By|Generated with \[?Claude' "$1"; then
  echo "commit-msg hook: Claude/Co-Authored-By attribution is forbidden" >&2
  exit 1
fi
EOF
chmod +x "$HOOK"

CRON_LINE="*/15 * * * * $HOME/Projects/roadmate/scripts/fix_issues.py --quiet >> $BOT_HOME/logs/fix_issues.log 2>&1"
if [ "${1:-}" = "--install-cron" ]; then
  echo "==> Crontab"
  if crontab -l 2>/dev/null | grep -q "fix_issues.py"; then
    echo "    entry already present"
  else
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo "    installed: $CRON_LINE"
  fi
else
  echo "==> Cron entry (re-run with --install-cron to install):"
  echo "    $CRON_LINE"
fi

echo "==> Done. Verify with: scripts/fix_issues.py --dry-run"
