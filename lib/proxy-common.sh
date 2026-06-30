# proxy-config-utility — shared library (sourced by the proxy-* scripts; not executable).
# Centralizes path/config/SUDO_USER resolution, placeholder detection, transparent
# self-elevation, and the OS/tool-aware install logic so the per-tool scripts stay tiny
# and there's a single source of truth. All functions are `set -u`-safe.

# Resolve a path through any symlink chain to an absolute real path.
__pcu_realpath() {
  local s="${1:-}" t
  while [ -L "$s" ]; do
    t="$(readlink "$s")"
    case "$t" in /*) s="$t" ;; *) s="$(cd "$(dirname "$s")" && pwd)/$t" ;; esac
  done
  printf '%s' "$(cd "$(dirname "$s")" && pwd)/$(basename "$s")"
}

# Call once per script:  __pcu_init "${BASH_SOURCE[0]:-$0}"
# Sets PCU_SELF (abs real path), PCU_PROG (basename), PCU_REPO (repo root).
__pcu_init() {
  PCU_SELF="$(__pcu_realpath "${1:-$0}")"
  PCU_PROG="$(basename "$PCU_SELF")"
  PCU_REPO="$(cd "$(dirname "$PCU_SELF")/.." && pwd)"
}

# Invoking user's home (resolves the real user under sudo).
__pcu_user_home() {
  if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ]; then eval echo "~$SUDO_USER"; else printf '%s' "$HOME"; fi
}

# Load the config into HTTP_PROXY_URL/etc (with sane defaults). Sets PCU_CONFIG.
__pcu_load_config() {
  PCU_CONFIG="${PROXY_CONFIG:-$(__pcu_user_home)/.config/proxy-config/config}"
  PROXY_PROBE_HOST=""; PROXY_PROBE_PORT=""
  HTTP_PROXY_URL=""; HTTPS_PROXY_URL=""; SOCKS_PROXY_URL=""; NO_PROXY_LIST=""
  PROXY_COLOR_ON=""; PROXY_COLOR_OFF=""
  # shellcheck disable=SC1090
  [ -r "$PCU_CONFIG" ] && . "$PCU_CONFIG"
  : "${HTTPS_PROXY_URL:=$HTTP_PROXY_URL}"
}

# True (0) if the config is unset or still the shipped example placeholder.
__pcu_is_placeholder() {
  case "${PROXY_PROBE_HOST:-}|${HTTP_PROXY_URL:-}" in
    "|") return 0 ;;            # nothing set
    *example.com*) return 0 ;;  # shipped placeholder domain
    *) return 1 ;;
  esac
}

# Print a one-line warning (to stderr) if the config is placeholder/unset.
__pcu_warn_placeholder() {
  __pcu_is_placeholder || return 0
  printf '%s: proxy config is unset or still the example placeholder (%s).\n' "${PCU_PROG:-proxy}" "${PCU_CONFIG:-?}" >&2
  printf "   set real values with 'proxy-setup' (or edit it, then run 'proxy-refresh').\n" >&2
}

# Re-exec self as root with a TRANSPARENT notice. $1 = human description; rest = original args.
__pcu_need_root() {
  local what="$1"; shift
  [ "$(id -u)" -eq 0 ] && return 0
  local sudo="${PCU_SUDO:-sudo}"
  if ! command -v "$sudo" >/dev/null 2>&1; then
    printf '%s: needs root (%s) but %s is not available — re-run as root.\n' "$PCU_PROG" "$what" "$sudo" >&2
    exit 1
  fi
  printf '%s: this requires root.\n' "$PCU_PROG" >&2
  printf '   action : %s\n' "$what" >&2
  printf '   running: %s %s %s\n' "$sudo" "$PCU_SELF" "$*" >&2
  exec "$sudo" -- "$PCU_SELF" "$@"
}

# OS/tool-aware: should command <name> be installed on this host?
# Core commands always; per-tool ones only when their tool is present.
__pcu_should_link() {
  case "$1" in
    proxy-git)    command -v git     >/dev/null 2>&1 ;;
    proxy-docker) command -v docker  >/dev/null 2>&1 ;;
    proxy-apt)    command -v apt-get >/dev/null 2>&1 ;;
    proxy-snap)   command -v snap    >/dev/null 2>&1 ;;
    proxy-env)    [ "$(uname -s)" = Linux ] ;;   # /etc/environment is Linux-only
    proxy-*)      return 0 ;;     # core (detect/reachable/help/update/setup)
    *)            return 1 ;;     # not a command (e.g. a stray file)
  esac
}

# Symlink the relevant bin/* from <repo> into <bindir>, OS/tool-aware. Logs to stderr.
__pcu_link_bins() {
  local repo="$1" bindir="$2" f b
  mkdir -p "$bindir"
  for f in "$repo"/bin/*; do
    b="$(basename "$f")"
    if __pcu_should_link "$b"; then ln -sf "$f" "$bindir/$b"; printf '  + %s\n' "$b" >&2
    else printf '  - %s (skipped — its tool is not installed here)\n' "$b" >&2; fi
  done
}

# --- interactive interview (used by install.sh and proxy-setup) ---
__pcu_ask() {  # __pcu_ask "prompt" "default" -> echoes answer (prompt -> stderr)
  local p="$1" d="${2:-}" in
  if [ -n "$d" ]; then printf '%s [%s]: ' "$p" "$d" >&2; else printf '%s: ' "$p" >&2; fi
  IFS= read -r in || true
  printf '%s' "${in:-$d}"
}
__pcu_yesno() {  # __pcu_yesno "prompt" "y|n" -> 0 for yes
  local in; in="$(__pcu_ask "$1" "$2")"
  case "$(printf '%s' "$in" | tr 'A-Z' 'a-z')" in y|yes) return 0 ;; *) return 1 ;; esac
}

# Interview for proxy settings, writing <cfg>. Pre-fills defaults from any current config.
__pcu_interview() {
  local cfg="$1" ph pp hu hs su np co cf
  __pcu_load_config >/dev/null 2>&1 || true   # pre-fill from existing values if present
  ph="$(__pcu_ask '  Probe host (reachable ONLY when behind the proxy)' "${PROXY_PROBE_HOST:-proxy.example.com}")"
  pp="$(__pcu_ask '  Probe port' "${PROXY_PROBE_PORT:-8080}")"
  hu="$(__pcu_ask '  HTTP proxy URL' "${HTTP_PROXY_URL:-http://$ph:$pp}")"
  hs="$(__pcu_ask '  HTTPS proxy URL' "${HTTPS_PROXY_URL:-$hu}")"
  su="$(__pcu_ask '  SOCKS5 proxy URL (blank to skip)' "${SOCKS_PROXY_URL:-socks5://$ph:1080}")"
  np="$(__pcu_ask '  no_proxy list' "${NO_PROXY_LIST:-127.0.0.1,localhost,.example.com,.internal,.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}")"
  co="$(__pcu_ask '  Prompt color BEHIND proxy (256-color SGR)' "${PROXY_COLOR_ON:-38;5;33}")"
  cf="$(__pcu_ask '  Prompt color when DIRECT (256-color SGR)' "${PROXY_COLOR_OFF:-38;5;51}")"
  mkdir -p "$(dirname "$cfg")"
  cat > "$cfg" <<EOF
# proxy-config-utility config — $(date -u +%Y-%m-%dT%H:%M:%SZ)
PROXY_PROBE_HOST="$ph"
PROXY_PROBE_PORT="$pp"
HTTP_PROXY_URL="$hu"
HTTPS_PROXY_URL="$hs"
SOCKS_PROXY_URL="$su"
NO_PROXY_LIST="$np"
PROXY_COLOR_ON="$co"
PROXY_COLOR_OFF="$cf"
EOF
}
