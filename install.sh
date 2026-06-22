#!/usr/bin/env bash
# Concierge installer — set up Claude Code with a curated, branded skill pack.
#
# Run:  curl -fsSL https://raw.githubusercontent.com/OWNER/concierge/main/install.sh | bash
#
# Idempotent: safe to re-run. Backs up an existing ~/.claude before writing, and
# never overwrites your settings, memory, or saved API keys.
#
# Env knobs (advanced / testing):
#   CONCIERGE_VERSION       bundle version            (default 0.1.0)
#   CONCIERGE_BASE_URL      where to fetch the bundle (default GitHub release)
#   CONCIERGE_TARBALL       use a local tarball instead of downloading
#   CONCIERGE_SKIP_CLAUDE=1 skip installing the Claude binary (testing)
#   CONCIERGE_NONINTERACTIVE=1  skip the guided prompts
#   CLAUDE_HOME             target home               (default $HOME)
set -uo pipefail

VERSION="${CONCIERGE_VERSION:-0.2.0}"
BASE_URL="${CONCIERGE_BASE_URL:-https://mcevoyinit.github.io/concierge-site}"
HOME_DIR="${CLAUDE_HOME:-$HOME}"
CLAUDE_DIR="$HOME_DIR/.claude"
CLAUDE_INSTALL_URL="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"

# --- pretty output -----------------------------------------------------------
if [ -t 1 ]; then C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_D=$'\033[2m'; C_0=$'\033[0m'
else C_B=; C_G=; C_Y=; C_R=; C_D=; C_0=; fi
step() { printf '%s\n' "${C_B}==>${C_0} ${C_B}$1${C_0}"; }
ok()   { printf '    %s%s%s\n' "$C_G" "$1" "$C_0"; }
warn() { printf '    %s%s%s\n' "$C_Y" "$1" "$C_0"; }
info() { printf '    %s\n' "$1"; }
die()  { printf '%sConcierge: %s%s\n' "$C_R" "$1" "$C_0" >&2; exit 1; }

# Read a line from the real terminal even when piped via curl|bash.
ask() { # ask "prompt" -> echoes the reply (empty if non-interactive)
  local reply=""
  if [ "${CONCIERGE_NONINTERACTIVE:-0}" = "1" ] || [ ! -e /dev/tty ]; then echo ""; return; fi
  printf '%s' "$1" > /dev/tty
  IFS= read -r reply < /dev/tty || reply=""
  echo "$reply"
}

banner() {
  cat <<'EOF'
   ____                 _
  / ___|___  _ __   ___(_) ___ _ __ __ _  ___
 | |   / _ \| '_ \ / __| |/ _ \ '__/ _` |/ _ \
 | |__| (_) | | | | (__| |  __/ | | (_| |  __/
  \____\___/|_| |_|\___|_|\___|_|  \__, |\___|
                                   |___/
        your AI, set up in one command
EOF
}

printf '%s' "$C_B"; banner; printf '%s\n' "$C_0"

# --- 1. preflight ------------------------------------------------------------
step "Checking your Mac"
[ "$(uname -s)" = "Darwin" ] || die "Concierge is macOS-only right now."
command -v curl >/dev/null 2>&1 || die "curl not found (it ships with macOS — odd)."
command -v tar  >/dev/null 2>&1 || die "tar not found."
ARCH="$(uname -m)"
ok "macOS on $ARCH — good to go."

# --- 2. install Claude Code (native binary, no Node needed) -------------------
step "Installing Claude Code"
if command -v claude >/dev/null 2>&1; then
  ok "Claude Code already installed ($(claude --version 2>/dev/null | head -1))."
elif [ "${CONCIERGE_SKIP_CLAUDE:-0}" = "1" ]; then
  warn "Skipping Claude install (CONCIERGE_SKIP_CLAUDE=1)."
else
  info "Downloading the official Claude Code installer..."
  if curl -fsSL "$CLAUDE_INSTALL_URL" | bash; then
    ok "Claude Code installed."
  else
    die "Claude install failed. Install it manually from docs.claude.com then re-run."
  fi
fi
# Make sure ~/.local/bin is on PATH now and in every future shell.
# zsh is the macOS default — ensure ~/.zshrc has it even if the file doesn't
# exist yet (a truly fresh Mac has no ~/.zshrc). Add to bash too if present.
if [ -d "$HOME_DIR/.local/bin" ]; then
  export PATH="$HOME_DIR/.local/bin:$PATH"
  added=""
  ZRC="$HOME_DIR/.zshrc"
  if ! grep -qs '\.local/bin' "$ZRC" 2>/dev/null; then
    printf '\n# Added by Concierge\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$ZRC" && added="yes"
  fi
  if [ -f "$HOME_DIR/.bash_profile" ] && ! grep -qs '\.local/bin' "$HOME_DIR/.bash_profile"; then
    printf '\n# Added by Concierge\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME_DIR/.bash_profile"
  fi
  [ -n "$added" ] && ok "Put Claude on your PATH for new terminal windows."
fi

# --- 3. fetch the Concierge bundle -------------------------------------------
step "Fetching the Concierge pack (v$VERSION)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
TARBALL="$WORK/concierge.tar.gz"
if [ -n "${CONCIERGE_TARBALL:-}" ]; then
  [ -f "$CONCIERGE_TARBALL" ] || die "CONCIERGE_TARBALL not found: $CONCIERGE_TARBALL"
  cp "$CONCIERGE_TARBALL" "$TARBALL"
  ok "Using local bundle."
else
  curl -fsSL "$BASE_URL/concierge-v$VERSION.tar.gz" -o "$TARBALL" \
    || die "Could not download the bundle from $BASE_URL"
  # Verify checksum if published alongside.
  if curl -fsSL "$BASE_URL/concierge-v$VERSION.tar.gz.sha256" -o "$WORK/sum" 2>/dev/null; then
    want="$(awk '{print $1}' "$WORK/sum")"
    got="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
    [ "$want" = "$got" ] || die "Checksum mismatch — refusing to install."
    ok "Bundle downloaded and checksum verified."
  else
    warn "No checksum published; skipping verification."
  fi
fi
mkdir -p "$WORK/bundle"
tar xzf "$TARBALL" -C "$WORK/bundle" || die "Could not extract the bundle."

# --- 4. install into ~/.claude — OWN-ONLY, self-flushing, never clobbers ------
# Concierge tracks exactly what it installed (concierge/owned.txt + version).
# Every run re-applies its own pack to a known-good state and leaves everything
# else alone. A same-named skill the user already had (and Concierge did NOT
# install) is kept; ours is parked as <name>.concierge. Re-runs are idempotent.
step "Installing into ~/.claude"
mkdir -p "$CLAUDE_DIR"
B="$WORK/bundle"
CONC_DIR="$CLAUDE_DIR/concierge"
MARKER="$CONC_DIR/version"
OWNED="$CONC_DIR/owned.txt"
mkdir -p "$CONC_DIR"
PREV_VER="$(cat "$MARKER" 2>/dev/null || echo "")"

was_owned() { grep -qxF "$1" "$OWNED" 2>/dev/null; }
NEWOWNED="$(mktemp)"
kept=0

install_items() { # $1 = subdir under skills/commands/agents
  local sub="$1"; [ -d "$B/$sub" ] || return 0
  mkdir -p "$CLAUDE_DIR/$sub"
  local path name key target
  for path in "$B/$sub"/*; do
    [ -e "$path" ] || continue
    name="$(basename "$path")"; key="$sub/$name"; target="$CLAUDE_DIR/$sub/$name"
    if [ -e "$target" ] && ! was_owned "$key" && ! diff -rq "$path" "$target" >/dev/null 2>&1; then
      # user's OWN different version exists -> keep theirs, park ours, don't claim it
      cp -R "$path" "$target.concierge" 2>/dev/null || true
      warn "Kept your own $key (Concierge's saved as $name.concierge)."
      kept=$((kept+1))
    else
      rm -rf "$target"; cp -R "$path" "$target"   # absent / ours / identical -> (re)flush ours
      echo "$key" >> "$NEWOWNED"
    fi
  done
}
install_items skills
install_items commands
install_items agents

# statusline + branding are Concierge-owned
[ -f "$B/statusline.sh" ] && { cp "$B/statusline.sh" "$CLAUDE_DIR/statusline.sh"; chmod +x "$CLAUDE_DIR/statusline.sh"; echo "statusline.sh" >> "$NEWOWNED"; }
[ -d "$B/concierge" ] && cp -R "$B/concierge/." "$CONC_DIR/" 2>/dev/null || true

# Config files: install only if absent, never overwrite the user's.
keep_or_offer() { local f="$1"; [ -f "$B/$f" ] || return 0
  if [ -f "$CLAUDE_DIR/$f" ]; then warn "Kept your existing $f."
  else cp "$B/$f" "$CLAUDE_DIR/$f"; ok "Installed $f."; fi; }
keep_or_offer settings.json
keep_or_offer CLAUDE.md
keep_or_offer MEMORY.md
[ -f "$HOME_DIR/todo.md" ] || printf '# To-do\n\n' > "$HOME_DIR/todo.md"

sort -u "$NEWOWNED" > "$OWNED"; rm -f "$NEWOWNED"
printf '%s\n' "$VERSION" > "$MARKER"
n=$(wc -l < "$OWNED" | tr -d ' ')
if   [ -z "$PREV_VER" ];               then ok "Concierge v$VERSION installed ($n items)."
elif [ "$PREV_VER" = "$VERSION" ];     then ok "Concierge v$VERSION re-flushed — clean and up to date ($n items)."
else ok "Updated Concierge v$PREV_VER → v$VERSION ($n items)."; fi
[ "$kept" -gt 0 ] && info "$kept of your own skills were kept untouched."

# --- 5. verify ---------------------------------------------------------------
step "Verifying"
SKILL_COUNT="$(ls -1 "$CLAUDE_DIR/skills" 2>/dev/null | wc -l | tr -d ' ')"
ok "$SKILL_COUNT skills present."
if command -v claude >/dev/null 2>&1; then
  ok "Claude Code is on your PATH."
else
  warn "Claude not on PATH yet — open a new terminal, or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- 6. guided onboarding ----------------------------------------------------
step "Last steps — these need you (one minute)"
cat <<EOF
    ${C_B}1. Open a NEW Terminal window${C_0}
       Close this one and open a fresh Terminal (so it sees Claude). Or run:
       ${C_D}source ~/.zshrc${C_0}

    ${C_B}2. Sign in${C_0}
       Type ${C_B}claude${C_0} and press Enter, then sign in with your Claude account.

    ${C_B}3. Authorize Gmail + Calendar${C_0}  (one time, in your browser)
       Claude Code can't run Google's sign-in itself, so you authorize once at
       ${C_D}https://claude.ai/settings/connectors${C_0} (switch on Gmail + Calendar).
       After that, ${C_B}/morning-brief${C_0} and ${C_B}/email-digest${C_0} use them right here in
       Claude Code — you never go back to the browser. (Claude Pro or Max plan.)
EOF
if [ "${CONCIERGE_NONINTERACTIVE:-0}" != "1" ] && [ -e /dev/tty ]; then
  reply="$(ask "    Open the connectors page in your browser now? [Y/n] ")"
  case "$reply" in
    n|N|no|NO) info "No problem — open it whenever you're ready." ;;
    *) command -v open >/dev/null 2>&1 && open "https://claude.ai/settings/connectors" 2>/dev/null && ok "Opened in your browser." ;;
  esac
fi

# --- done --------------------------------------------------------------------
printf '\n%s%s Concierge is ready.%s\n' "$C_G" "✓" "$C_0"
cat <<EOF

    Try it now (in a new Terminal window):
       ${C_B}claude${C_0}        then type   ${C_B}/oracle${C_0}   (it routes you to the right tool)
                          or       ${C_B}/email-digest${C_0}   (after step 3 above)

    What you've got: morning brief · email digest · oracle · brainstorm ·
    deep research (feynman) · humanizer · person & company research ·
    market sizing · mac health · a personal biographer agent.

    Re-run this installer any time to update. Enjoy.
EOF
