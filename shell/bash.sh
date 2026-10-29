# proxy-config-utility — bash integration.
#
# Add to your ~/.bashrc (or ~/.bash_profile) one of:
#     source /path/to/proxy-config-utility/shell/bash.sh
#   or copy its contents:
#     cat /path/to/proxy-config-utility/shell/bash.sh >> ~/.bashrc
#
# Reads the cache written by proxy-detect; sets the *_proxy env and colors the
# prompt. Contains NO proxy values (those live in ~/.config/proxy-config/config).
#
# Commands provided:
#   proxy-sync     adopt the latest cached state in THIS shell (no network)
#   proxy-refresh  run proxy-detect now, then adopt the result

PROXY_STATE="$HOME/.cache/proxy/state.env"
PROXY_DETECT="${PROXY_DETECT:-$HOME/bin/proxy-detect}"
# make the proxy-* commands runnable by name (they live in ~/bin)
case ":$PATH:" in *":$HOME/bin:"*) ;; *) PATH="$HOME/bin:$PATH" ;; esac

[ -r "$PROXY_STATE" ] && . "$PROXY_STATE"
: "${PROXY_COLOR:=38;5;51}"                      # default cyan until cache is warm
export proxy_status="${PROXY_STATUS:-no_proxy}"

# Color is emitted via a command substitution INSIDE a fixed PS1 string, so PS1
# itself never changes — terminal shell-integrations (iTerm2, VS Code) capture it
# once and keep re-rendering the live color instead of freezing it. The 256-color
# value is theme-independent (see config.example). The hostname gets its own fixed
# color and the path a third (dark green / lavender; override with PROXY_HOST_COLOR /
# PROXY_PATH_COLOR before sourcing) so both stand out from the state color. If you
# already have a custom PS1, embed
# \[$(__proxy_color)\] ... \[\033[m\]  rather than replacing it.
: "${PROXY_HOST_COLOR:=38;5;28}"
: "${PROXY_PATH_COLOR:=38;5;141}"
__proxy_color()     { printf '\033[%sm' "${PROXY_COLOR:-38;5;51}"; }
__proxy_hostcolor() { printf '\033[%sm' "$PROXY_HOST_COLOR"; }
__proxy_pathcolor() { printf '\033[%sm' "$PROXY_PATH_COLOR"; }
PS1='\[$(__proxy_color)\][\u@\[$(__proxy_hostcolor)\]\h\[$(__proxy_color)\] \[$(__proxy_pathcolor)\]\W\[$(__proxy_color)\]]\$ \[\033[m\]'   # MUST stay single-quoted

__proxy_sync() {   # re-read cache each prompt: updates env + PROXY_COLOR (not PS1)
  [ -r "$PROXY_STATE" ] && . "$PROXY_STATE"
  export proxy_status="${PROXY_STATUS:-no_proxy}"
  : "${PROXY_COLOR:=38;5;51}"
}
case ";$PROMPT_COMMAND;" in *";__proxy_sync;"*) ;; *) PROMPT_COMMAND="__proxy_sync;${PROMPT_COMMAND}";; esac

proxy-sync()    { __proxy_sync; echo "proxy_status=$proxy_status (color ${PROXY_COLOR:-38;5;51})"; }
proxy-refresh() { "$PROXY_DETECT"; proxy-sync; }
