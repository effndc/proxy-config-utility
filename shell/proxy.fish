# proxy-config-utility — fish integration.
#
# Install (fish auto-loads conf.d):
#     cp /path/to/proxy-config-utility/shell/proxy.fish ~/.config/fish/conf.d/proxy.fish
#
# Reads the fish cache written by proxy-detect (~/.cache/proxy/state.fish); sets
# the *_proxy env and colors the prompt. Contains NO proxy values (those live in
# ~/.config/proxy-config/config).
#
# Commands provided:
#   proxy-sync     adopt the latest cached state in THIS shell (no network)
#   proxy-refresh  run proxy-detect now, then adopt the result

set -g PROXY_STATE "$HOME/.cache/proxy/state.fish"
set -q PROXY_DETECT; or set -g PROXY_DETECT "$HOME/bin/proxy-detect"

function __proxy_sync --description 'adopt cached proxy state'
    test -r "$PROXY_STATE"; and source "$PROXY_STATE"
    set -q PROXY_COLOR;  or set -gx PROXY_COLOR '38;5;51'
    set -q PROXY_STATUS; or set -gx PROXY_STATUS no_proxy
end

function proxy-sync --description 'adopt latest cached proxy state'
    __proxy_sync
    echo "proxy_status=$PROXY_STATUS (color $PROXY_COLOR)"
end

function proxy-refresh --description 'run proxy-detect now, then adopt'
    eval "$PROXY_DETECT"
    proxy-sync
end

__proxy_sync   # warm at load

# fish runs fish_prompt every prompt, so syncing here keeps env + color live and
# propagates a `proxy-refresh` from another shell. The color is emitted as the raw
# 256-color escape (theme-independent), matching the bash/zsh versions.
#
# If you ALREADY have a custom fish_prompt, do NOT use the definition below;
# instead add, at the top of your prompt:   __proxy_sync; printf '\033[%sm' $PROXY_COLOR
# and at the very end:                       printf '\033[m'
function fish_prompt
    __proxy_sync
    printf '\033[%sm' $PROXY_COLOR
    echo -n '['(whoami)'@'(prompt_hostname)' '(prompt_pwd)']> '
    printf '\033[m'
end
