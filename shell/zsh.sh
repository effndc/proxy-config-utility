# proxy-config-utility — zsh integration.
#
# Add to your ~/.zshrc one of:
#     source /path/to/proxy-config-utility/shell/zsh.sh
#   or copy its contents:
#     cat /path/to/proxy-config-utility/shell/zsh.sh >> ~/.zshrc
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

__proxy_color() { printf '\033[%sm' "${PROXY_COLOR:-38;5;51}"; }

# PROMPT_SUBST makes $(...) re-evaluate every render; %{...%} marks the bytes as
# non-printing so line editing stays correct. The color is theme-independent
# 256-color. If you already have a custom PROMPT, wrap your body with
# %{$(__proxy_color)%} ... %{$(printf "\033[m")%} instead of replacing it.
setopt PROMPT_SUBST
PROMPT='%{$(__proxy_color)%}[%n@%m %1~]%# %{$(printf "\033[m")%}'

__proxy_sync() {   # re-read cache each prompt: updates env + PROXY_COLOR
  [ -r "$PROXY_STATE" ] && . "$PROXY_STATE"
  export proxy_status="${PROXY_STATUS:-no_proxy}"
  : "${PROXY_COLOR:=38;5;51}"
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd __proxy_sync

proxy-sync()    { __proxy_sync; print "proxy_status=$proxy_status (color ${PROXY_COLOR:-38;5;51})"; }
proxy-refresh() { "$PROXY_DETECT"; proxy-sync; }
