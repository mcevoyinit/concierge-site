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

VERSION="${CONCIERGE_VERSION:-0.1.0}"
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
# Make sure the install dir is on PATH for this and future shells.
if [ -d "$HOME_DIR/.local/bin" ] && ! echo ":$PATH:" | grep -q ":$HOME_DIR/.local/bin:"; then
  export PATH="$HOME_DIR/.local/bin:$PATH"
  for prof in "$HOME_DIR/.zshrc" "$HOME_DIR/.bash_profile"; do
    [ -f "$prof" ] && ! grep -q '.local/bin' "$prof" 2>/dev/null \
      && printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$prof"
  done
  ok "Added ~/.local/bin to your PATH."
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

# --- 4. back up, then merge into ~/.claude (never clobber personal files) -----
step "Installing into ~/.claude"
mkdir -p "$CLAUDE_DIR"
if [ -n "$(ls -A "$CLAUDE_DIR" 2>/dev/null || true)" ]; then
  BAK="$CLAUDE_DIR.bak-$(date +%Y%m%d-%H%M%S)"
  cp -R "$CLAUDE_DIR" "$BAK"
  ok "Backed up your existing setup to $(basename "$BAK")."
fi

B="$WORK/bundle"
# Our content — safe to overwrite (skills/commands/agents/statusline/banner).
for d in skills commands agents concierge; do
  [ -d "$B/$d" ] && { mkdir -p "$CLAUDE_DIR/$d"; cp -R "$B/$d/." "$CLAUDE_DIR/$d/"; }
done
[ -f "$B/statusline.sh" ] && { cp "$B/statusline.sh" "$CLAUDE_DIR/statusline.sh"; chmod +x "$CLAUDE_DIR/statusline.sh"; }

# Personal-config files — install only if absent; otherwise leave a *.concierge copy.
keep_or_offer() { # $1 = filename in bundle root
  local f="$1"
  [ -f "$B/$f" ] || return 0
  if [ -f "$CLAUDE_DIR/$f" ]; then
    cp "$B/$f" "$CLAUDE_DIR/$f.concierge"
    warn "Kept your existing $f (new version saved as $f.concierge)."
  else
    cp "$B/$f" "$CLAUDE_DIR/$f"
    ok "Installed $f."
  fi
}
keep_or_offer settings.json
keep_or_offer CLAUDE.md
keep_or_offer MEMORY.md
ok "Skills, commands, and branding installed."

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
    ${C_B}1. Sign in${C_0}
       Run ${C_B}claude${C_0} in your terminal and sign in with your Claude account.

    ${C_B}2. Connect Gmail + Calendar${C_0}  (powers ${C_B}/email-digest${C_0})
       Open  ${C_D}https://claude.ai/settings/connectors${C_0}
       and turn on the Google Gmail and Google Calendar connectors.
       (Requires a Claude Pro or Max plan.)
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

    Try it now:
       ${C_B}claude${C_0}        then type   ${C_B}/oracle${C_0}   (it routes you to the right tool)
                          or       ${C_B}/email-digest${C_0}   (after step 2 above)

    What you've got: brainstorm · oracle · deep research (feynman) ·
    humanizer · person & company research · market sizing · email digest ·
    mac health · a personal biographer agent.

    Re-run this installer any time to update. Enjoy.
EOF
