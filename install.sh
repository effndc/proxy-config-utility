#!/usr/bin/env bash
# proxy-config-utility — guided installer.
#
# Interactive, OS/tool-aware, idempotent. Installs only the commands that apply to
# this host (e.g. no proxy-snap on macOS), asks for your proxy settings, wires up
# your shell(s), and optionally sets up automatic detection, SSH routing, and the
# on-change hook. Backs up anything it changes.
#
#   curl -fsSL https://raw.githubusercontent.com/effndc/proxy-config-utility/main/install.sh | bash
#   ./install.sh            # from any checkout: installs/updates the standard copy below
#   ./install.sh --here     # developers: install in place from THIS checkout instead
#
# The installed copy lives at ~/.local/share/proxy-config-utility (override
# with PROXY_INSTALL_DIR; XDG_DATA_HOME is honored). Shell snippets are sourced from it
# and ~/bin/proxy-* link into it, so 'proxy-update' keeps it current. git is optional:
# without it the release tarball is used (curl or wget + tar). Other overrides:
# PROXY_REPO_URL (clone source), PROXY_TARBALL_URL, PROXY_REF (branch/tag, first fetch).
set -u

PCU_INSTALL_DIR="${PROXY_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/proxy-config-utility}"
PCU_REPO_URL="${PROXY_REPO_URL:-https://github.com/effndc/proxy-config-utility.git}"
PCU_REF="${PROXY_REF:-main}"
PCU_TARBALL_URL="${PROXY_TARBALL_URL:-https://github.com/effndc/proxy-config-utility/archive/${PCU_REF}.tar.gz}"

# Runs first. If we are not already the installed copy (or --here), fetch/update that copy
# and re-exec its installer. Needs only bash + (git OR curl/wget) + tar — never gh. With git
# it makes a clone; without, it unpacks the release tarball (proxy-update refreshes either).
# One function, so a truncated 'curl | bash' download is a syntax error rather than a
# half-run script; the exec happens before the rest of the file is read.
__pcu_bootstrap() {
  local src="${BASH_SOURCE[0]:-}" here="" want="$PCU_INSTALL_DIR" in_place=0 a have_git=0
  for a in "$@"; do [ "$a" = --here ] && in_place=1; done
  command -v git >/dev/null 2>&1 && have_git=1
  [ -f "$src" ] && here="$(cd "$(dirname "$src")" && pwd -P)"
  if [ -n "$here" ] && [ -f "$here/lib/proxy-common.sh" ]; then
    [ "$in_place" = 1 ] && return 0
    [ -d "$want" ] && [ "$here" = "$(cd "$want" && pwd -P)" ] && return 0
  fi
  __pcu_dl() {  # tarball -> $want (strip the top-level dir); curl or wget, plus tar
    mkdir -p "$want" || return 1
    ( set -o pipefail
      if command -v curl >/dev/null 2>&1; then curl -fsSL "$PCU_TARBALL_URL"
      elif command -v wget >/dev/null 2>&1; then wget -qO- "$PCU_TARBALL_URL"
      else echo "install: need git, curl or wget to download." >&2; exit 1; fi | tar -xz --strip-components=1 -C "$want" )
  }
  local fail="install: download failed (behind a proxy? see README 'Bootstrapping behind a proxy')."
  if [ -d "$want/.git" ] && [ "$have_git" = 1 ]; then
    echo "install: updating $want" >&2
    git -C "$want" pull --ff-only >&2 || echo "install: git pull failed — continuing with the existing copy." >&2
  elif [ -f "$want/lib/proxy-common.sh" ]; then
    echo "install: refreshing $want from the tarball" >&2
    __pcu_dl || echo "install: refresh failed — continuing with the existing copy." >&2
  elif [ -e "$want" ] && [ -n "$(ls -A "$want" 2>/dev/null)" ]; then
    echo "install: $want exists and is not a proxy-config-utility install — move it aside and re-run." >&2; exit 1
  elif [ "$have_git" = 1 ]; then
    echo "install: cloning $PCU_REPO_URL ($PCU_REF) -> $want" >&2
    mkdir -p "$(dirname "$want")"
    git clone --branch "$PCU_REF" "$PCU_REPO_URL" "$want" >&2 || { echo "$fail" >&2; exit 1; }
  else
    echo "install: git not found — downloading the tarball -> $want" >&2
    __pcu_dl || { rmdir "$want" 2>/dev/null; echo "$fail" >&2; exit 1; }
  fi
  # the prompts must read the keyboard, not the pipe carrying this script; with no
  # terminal at all they get EOF and fall back to their defaults
  if [ -t 0 ]; then exec bash "$want/install.sh" "$@"
  elif { : </dev/tty; } 2>/dev/null; then exec bash "$want/install.sh" "$@" </dev/tty
  else echo "install: no terminal — accepting all defaults." >&2; exec bash "$want/install.sh" "$@" </dev/null
  fi
}
__pcu_bootstrap "$@"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$REPO/lib/proxy-common.sh" 2>/dev/null || { echo "install: cannot load lib/proxy-common.sh — run from the repo." >&2; exit 1; }
OS="$(uname -s)"
CFG_DIR="$HOME/.config/proxy-config"; CFG="$CFG_DIR/config"; BIN="$HOME/bin"

say(){ printf '%s\n' "$*" >&2; }
hr(){  printf -- '------------------------------------------------------------\n' >&2; }
backup(){ [ -e "$1" ] && cp "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" && say "  backed up $1"; }
ensure_line(){ local f="$1" line="$2" match="${3:-$2}"; [ -e "$f" ] || : > "$f"
  # already wired if the current path appears (absolute, or with a literal $HOME)
  if grep -qF -- "$match" "$f" 2>/dev/null || grep -qF -- "${match/#$HOME/\$HOME}" "$f" 2>/dev/null; then say "  = already wired: $(basename "$f")"
  else printf '\n# proxy-config-utility\n%s\n' "$line" >> "$f"; say "  + wired $(basename "$f")"; fi; }

# Earlier installs sourced the snippet from wherever the repo was cloned. Point any such
# plain 'source <old>/shell/<name>' line at the current copy (backed up; a duplicate of an
# already-correct line is dropped). Returns 0 if it changed the file.
__stale_pat(){ printf '%s' "^[[:space:]]*(source|\\.)[[:space:]]+[\"']?[^\"' ]*/shell/${1//./\\.}[\"']?[[:space:]]*(#.*)?\$"; }
__src_path(){  # the path a matched source line points at, with $HOME / ~ expanded
  local p; p="$(printf '%s' "$1" | sed -E "s/^[[:space:]]*(source|\\.)[[:space:]]+[\"']?//; s/[\"']?[[:space:]]*(#.*)?\$//")"
  p="${p//\$\{HOME\}/$HOME}"; p="${p//\$HOME/$HOME}"; printf '%s' "${p/#\~/$HOME}"; }
fix_stale_source(){ local f="$1" name="$2" pat cur="$REPO/shell/$2" line have=0 changed=0 tmp
  [ -f "$f" ] || return 1; pat="$(__stale_pat "$name")"; grep -qE "$pat" "$f" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" | grep -qE "$pat" && [ "$(__src_path "$line")" = "$cur" ] && have=1
  done < "$f"
  tmp="$(mktemp)" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if printf '%s\n' "$line" | grep -qE "$pat" && [ "$(__src_path "$line")" != "$cur" ]; then
      changed=1; [ "$have" = 1 ] || { printf 'source "%s"\n' "$cur"; have=1; }
    else printf '%s\n' "$line"; fi
  done < "$f" > "$tmp"
  if [ "$changed" = 1 ]; then backup "$f"; cat "$tmp" > "$f"; say "  ~ updated old source line in $f"; fi
  rm -f "$tmp"; [ "$changed" = 1 ]; }
# An inline copy of the prompt code (instead of sourcing the snippet) never updates; just flag it.
warn_inline(){ [ -f "$1" ] && grep -qE '^__proxy_color\(\)' "$1" && ! grep -qF "/shell/$2" "$1" \
  && say "  ! $1 has an inline copy of the prompt code — replace it with: source \"$REPO/shell/$2\""; true; }

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
for f in .bashrc .bash_profile .profile; do fix_stale_source "$HOME/$f" bash.sh; warn_inline "$HOME/$f" bash.sh; done
for f in .zshrc .zprofile; do fix_stale_source "$HOME/$f" zsh.sh; warn_inline "$HOME/$f" zsh.sh; done
__pcu_yesno "  Wire up bash (~/.bashrc)?" "$( [ -e "$HOME/.bashrc" ] && echo y || echo n )" && ensure_line "$HOME/.bashrc" "source \"$REPO/shell/bash.sh\"" "$REPO/shell/bash.sh"
__pcu_yesno "  Wire up zsh (~/.zshrc)?"   "$( [ -e "$HOME/.zshrc" ]  && echo y || echo n )" && ensure_line "$HOME/.zshrc"  "source \"$REPO/shell/zsh.sh\""  "$REPO/shell/zsh.sh"
if command -v fish >/dev/null 2>&1; then
  __pcu_yesno "  Wire up fish (conf.d)?" "y" && { FISHF="$HOME/.config/fish/conf.d/proxy.fish"; mkdir -p "$HOME/.config/fish/conf.d"
    [ -e "$FISHF" ] && [ ! -L "$FISHF" ] && backup "$FISHF"   # an old copied file, not a link
    ln -sf "$REPO/shell/proxy.fish" "$FISHF"; say "  + linked fish conf.d/proxy.fish -> $REPO"; }
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
