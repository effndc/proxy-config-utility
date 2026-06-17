# git proxy integration

`bin/proxy-git` sets or clears git's **global** HTTP(S) proxy to match the detected
proxy state, so `git clone`/`fetch`/`push` over HTTPS work behind the corporate proxy
and go direct when you're off it. This is the generic, self-contained replacement for
an internal "configure my git proxy" tool such as `dt`/devtool (not included here).

| File | Affects | Privilege | Restart |
|---|---|---|---|
| `~/.gitconfig` (`http.proxy` / `https.proxy`) | git over HTTPS | your user (no sudo) | none |

(git over **SSH** is handled separately by `ssh/proxy.sshconfig`, not here.)

## Usage

```sh
proxy-git on      # git config --global http.proxy/https.proxy from your config
proxy-git off     # git config --global --unset http.proxy/https.proxy
```

Run as your user (no sudo). Values come from `~/.config/proxy-config/config`
(`HTTP_PROXY_URL`; `HTTPS_PROXY_URL` defaults to it).

## Automatic

`proxy-git` is invoked by the `on-change` hook on every detection, so once that hook is
installed your git proxy follows the network automatically — no manual step. Because the
hook runs from `proxy-detect` (single-instance `mkdir` lock), only one writer ever edits
`~/.gitconfig`, which avoids the `.gitconfig.lock` contention that plagued running
`git config` from many shells at once.

## Notes

- Cross-platform (macOS + Linux); needs `git` on `PATH`.
- Override the global config path for testing with `GIT_CONFIG_GLOBAL`; `PROXY_CONFIG`
  overrides the config path.
