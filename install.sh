#!/usr/bin/env bash
# proxy-config-utility — guided installer.
#
# Interactive, OS/tool-aware, idempotent. Installs only the commands that apply to
# this host (e.g. no proxy-snap on macOS), asks for your proxy settings, wires up
# your shell(s), and optionally sets up automatic detection, SSH routing, and the
# on-change hook. Backs up anything it changes. Run it from the repo:  ./install.sh
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$REPO/lib/proxy-common.sh" 2>/dev/null || { echo "install: cannot load lib/proxy-common.sh — run from the repo." >&2; exit 1; }
OS="$(uname -s)"
CFG_DIR="$HOME/.config/proxy-config"; CFG="$CFG_DIR/config"; BIN="$HOME/bin"

say(){ printf '%s\n' "$*" >&2; }
hr(){  printf -- '------------------------------------------------------------\n' >&2; }
backup(){ [ -e "$1" ] && cp "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" && say "  backed up $1"; }
ensure_line(){ local f="$1" line="$2"; [ -e "$f" ] || : > "$f"
  if grep -qF -- "$line" "$f" 2>/dev/null; then say "  = already wired: $(basename "$f")"
  else printf '\n# proxy-config-utility\n%s\n' "$line" >> "$f"; say "  + wired $(basename "$f")"; fi; }

say "== proxy-config-utility installer =="
say "repo: $REPO    os: $OS"
hr

# 1) commands (OS/tool-aware: only what applies to this host)
say "Installing commands into $BIN (only those whose tool is present):"
__pcu_link_bins "$REPO" "$BIN"
case ":$PATH:" in *":$BIN:"*) :;; *) say "note: $BIN isn't on PATH yet — the shell snippet adds it for new shells.";; esac
hr

# 2) config
if [ -e "$CFG" ]; then
  if __pcu_yesno "Config $CFG exists — re-enter values?" "n"; then backup "$CFG"; __pcu_interview "$CFG"; say "wrote $CFG"
  else say "kept existing $CFG"; fi
else
  say "Proxy settings (press Enter to accept the [default]):"
  __pcu_interview "$CFG"; say "wrote $CFG"
fi
hr

# 3) shell integration
say "Shell integration:"
__pcu_yesno "  Wire up bash (~/.bashrc)?" "$( [ -e "$HOME/.bashrc" ] && echo y || echo n )" && ensure_line "$HOME/.bashrc" "source \"$REPO/shell/bash.sh\""
__pcu_yesno "  Wire up zsh (~/.zshrc)?"   "$( [ -e "$HOME/.zshrc" ]  && echo y || echo n )" && ensure_line "$HOME/.zshrc"  "source \"$REPO/shell/zsh.sh\""
if command -v fish >/dev/null 2>&1; then
  __pcu_yesno "  Wire up fish (conf.d)?" "y" && { mkdir -p "$HOME/.config/fish/conf.d"; ln -sf "$REPO/shell/proxy.fish" "$HOME/.config/fish/conf.d/proxy.fish"; say "  + linked fish conf.d/proxy.fish"; }
fi
[ "$OS" = Darwin ] && [ -e "$HOME/.bash_profile" ] && say "note: macOS bash login shells read ~/.bash_profile — make sure it sources ~/.bashrc."
hr

# 4) automatic detection
say "Automatic detection:"
if [ "$OS" = Darwin ]; then
  if __pcu_yesno "  Install macOS launchd agent (login + every 5 min + on net change)?" "y"; then
    PLIST="$HOME/Library/LaunchAgents/local.proxy-detect.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.cache/proxy"
    sed -e "s#/ABSOLUTE/PATH/TO/bin/proxy-detect#$BIN/proxy-detect#" \
        -e "s#/ABSOLUTE/PATH/TO/.cache/proxy/launchd.log#$HOME/.cache/proxy/launchd.log#g" \
        "$REPO/macos/local.proxy-detect.plist" > "$PLIST"
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null && launchctl kickstart -k "gui/$(id -u)/local.proxy-detect" 2>/dev/null && say "  + launchd agent loaded" || say "  ! launchd load failed — load it manually (see macos/ comments)"
  fi
elif command -v systemctl >/dev/null 2>&1 && systemctl --user list-units >/dev/null 2>&1; then
  if __pcu_yesno "  Install systemd --user timer (every 5 min)?" "y"; then
    mkdir -p "$HOME/.config/systemd/user"
    cp "$REPO/linux/proxy-detect.service" "$REPO/linux/proxy-detect.timer" "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable --now proxy-detect.timer 2>/dev/null && say "  + systemd timer enabled" || say "  ! timer enable failed"
  fi
else
  say "  no user scheduler available — manual mode (run 'proxy-refresh' after network changes)"
fi
hr

# 5) SSH routing
if __pcu_yesno "Set up SSH routing (SOCKS only when behind proxy AND host not directly reachable)?" "n"; then
  __pcu_load_config
  DEF_SOCKS="${SOCKS_PROXY_URL#socks5://}"; DEF_SOCKS="${DEF_SOCKS:-${PROXY_PROBE_HOST:-proxy.example.com}:1080}"
  SSH_SOCKS="$(__pcu_ask "  SOCKS host:port for ssh ProxyCommand" "$DEF_SOCKS")"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh" 2>/dev/null || true
  if grep -q 'proxy-reachable' "$HOME/.ssh/config" 2>/dev/null; then say "  = ~/.ssh/config already has the proxy Match"
  else
    backup "$HOME/.ssh/config"; tmp="$(mktemp)"
    cat > "$tmp" <<EOF
# proxy-config-utility: SOCKS only when behind the proxy AND target not directly reachable.
Match exec "grep -q '^PROXY_STATUS=proxy_yes' ~/.cache/proxy/state.env && ! ~/bin/proxy-reachable %h %p"
    ProxyCommand nc -X 5 -x $SSH_SOCKS %h %p

EOF
    [ -e "$HOME/.ssh/config" ] && cat "$HOME/.ssh/config" >> "$tmp"
    mv "$tmp" "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
    say "  + prepended SSH Match (SOCKS $SSH_SOCKS)"
  fi
fi
hr

# 6) on-change hook (auto git + Docker-client proxy; no editing)
if __pcu_yesno "Install on-change hook (auto git + Docker-client proxy on each detection)?" "y"; then
  cp "$REPO/config/on-change.example" "$CFG_DIR/on-change"; chmod +x "$CFG_DIR/on-change"
  say "  + installed $CFG_DIR/on-change (delegates to proxy-git + proxy-docker; no editing)"
fi
hr

# 7) prime + verify
say "Priming detection..."
"$BIN/proxy-detect" 2>&1 | sed 's/^/  /' || true
say "Current state:"; sed 's/^/  /' "$HOME/.cache/proxy/state.env" 2>/dev/null
hr
say "Done. Open a NEW shell (or re-source your rc) for the colored prompt + proxy-* commands."
say "Try:  proxy-help        # current state + every command"
say "      proxy-refresh      # re-detect now      proxy-setup   # change settings"
say "Per-tool proxies (root-only ones self-elevate and show what they'll run):"
say "      proxy-git on | proxy-docker on | proxy-apt on | proxy-snap on   (and 'off')"
