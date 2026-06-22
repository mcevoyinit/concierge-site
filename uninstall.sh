#!/usr/bin/env bash
# Concierge uninstaller — removes exactly what Concierge installed, nothing else.
#
# Run:  curl -fsSL https://mcevoyinit.github.io/concierge-site/uninstall.sh | bash
#
# Reads ~/.claude/concierge/owned.txt (the manifest the installer wrote) and
# removes only those items. Your own skills, your settings, and your to-dos are
# left untouched. Claude Code itself is NOT removed.
set -uo pipefail

HOME_DIR="${CLAUDE_HOME:-$HOME}"
CLAUDE_DIR="$HOME_DIR/.claude"
CONC_DIR="$CLAUDE_DIR/concierge"
OWNED="$CONC_DIR/owned.txt"

if [ -t 1 ]; then C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
else C_B=; C_G=; C_Y=; C_0=; fi
step(){ printf '%s==>%s %s%s\n' "$C_B" "$C_0" "$C_B" "$1$C_0"; }
ok(){ printf '    %s%s%s\n' "$C_G" "$1" "$C_0"; }
warn(){ printf '    %s%s%s\n' "$C_Y" "$1" "$C_0"; }

printf '%sConcierge uninstaller%s\n\n' "$C_B" "$C_0"

if [ ! -f "$OWNED" ]; then
  warn "Concierge isn't installed here (no manifest at $OWNED). Nothing to do."
  exit 0
fi

ver="$(cat "$CONC_DIR/version" 2>/dev/null || echo "?")"
step "Removing Concierge v$ver (only what it installed)"

removed=0
while IFS= read -r key; do
  [ -z "$key" ] && continue
  target="$CLAUDE_DIR/$key"
  if [ -e "$target" ]; then rm -rf "$target"; removed=$((removed+1)); fi
done < "$OWNED"
ok "Removed $removed installed items (skills, commands, agents, configs)."

# Remove any parked copies Concierge created, then its state dir.
parked=0
for d in skills commands agents; do
  for p in "$CLAUDE_DIR/$d"/*.concierge; do
    [ -e "$p" ] || continue; rm -rf "$p"; parked=$((parked+1))
  done
done
[ "$parked" -gt 0 ] && ok "Removed $parked parked .concierge copies."
rm -rf "$CONC_DIR"
ok "Removed Concierge state."

step "Done"
cat <<EOF
    Your own skills, settings, memory, and ~/todo.md were left untouched.
    Claude Code itself is still installed — remove it separately if you want.
    You can reinstall Concierge any time from the website.
EOF
