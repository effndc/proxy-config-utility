# proxy-config-utility

A tiny, dependency-light utility that gives your shell a **visual cue** when you're
behind a corporate proxy/VPN and **manages your `*_proxy` environment** to match —
without slowing down shell startup or fighting itself when many shells start at once.

- **Prompt color** changes based on proxy state (e.g. blue = behind proxy, cyan = direct).
- **`http_proxy` / `https_proxy` / `socks_proxy` / `no_proxy`** are set or unset automatically.
- **Detection is decoupled from shell startup**: one detector writes a small cache file;
  every shell just reads it (instant, lock-free). Detection runs on a schedule (macOS
  launchd / Linux systemd) or **manually** via `proxy-refresh`.
- Works in **bash, zsh, and fish**, on **macOS and Linux** (WSL2 untested — see below).
- Optional **SSH integration** routes connections through a SOCKS proxy only when needed.

## How it works

```
proxy-detect  (scheduled, or run manually via `proxy-refresh`)
   │  probes PROXY_PROBE_HOST:PORT  → proxy_yes / no_proxy
   │  (optional) runs your on-change hook (e.g. set git http.proxy)
   │  atomically writes:
   ├──> ~/.cache/proxy/state.env    (POSIX: bash & zsh source this)
   └──> ~/.cache/proxy/state.fish   (fish sources this)
                 │  read once at startup, and re-read each prompt
                 ▼
   prompt color + *_proxy env follow the cache; a single refresh
   propagates to every open shell on its next prompt
```

The detector is safe to run concurrently (atomic `mkdir` lock + atomic cache writes),
so multiple shells or a scheduler can never corrupt the cache or collide on the hook.

### Why the prompt color is a 256-color value

Colors are written as **256-color-cube** SGR params (e.g. `38;5;33`), not the 16 base
ANSI indices. The base 16 are remapped by terminal themes (so "blue" and "cyan" can
render identically in iTerm2/Ghostty); the 16–255 cube is a fixed table that themes
don't remap, so the cue stays distinct everywhere. The prompt also embeds the color via
a **command substitution inside a fixed prompt string**, so shell integrations (iTerm2,
VS Code) that cache the prompt don't freeze the color.

## Install

1. **Get the detector on your PATH.** Symlink (or copy) `bin/proxy-detect` to `~/bin`:
   ```sh
   mkdir -p ~/bin
   ln -s "$PWD/bin/proxy-detect" ~/bin/proxy-detect   # ensure ~/bin is on your PATH
   ```
   (Or point the shell snippet at it with `export PROXY_DETECT=/path/to/bin/proxy-detect`.)

2. **Create your config** (this is the only file you must edit):
   ```sh
   mkdir -p ~/.config/proxy-config
   cp config/config.example ~/.config/proxy-config/config
   $EDITOR ~/.config/proxy-config/config
   ```

3. **Add the shell integration** for your shell:
   ```sh
   # bash
   echo 'source "$HOME/path/to/proxy-config-utility/shell/bash.sh"' >> ~/.bashrc
   # zsh
   echo 'source "$HOME/path/to/proxy-config-utility/shell/zsh.sh"'  >> ~/.zshrc
   # fish
   cp shell/proxy.fish ~/.config/fish/conf.d/proxy.fish
   ```
   (Prefer `source` over copy/paste so you get updates when you `git pull`.)

4. **Prime the cache** in a new shell:
   ```sh
   proxy-refresh
   ```
   Your prompt should now reflect the current proxy state.

5. **(Optional) automatic detection** so you don't have to run `proxy-refresh`:
   - **macOS:** customize and install `macos/local.proxy-detect.plist` (see comments in it).
   - **Linux:** see [`linux/README.md`](linux/README.md) (systemd user timer + optional
     NetworkManager trigger).
   - **WSL2:** manual `proxy-refresh` is recommended (untested; see caveat below).

6. **(Optional) SSH integration** — route SSH through a SOCKS proxy only when behind it.
   Customize `ssh/proxy.sshconfig` and either paste its two lines at the top of
   `~/.ssh/config` or `Include` it there (see comments in that file). No `Host *`
   wrapper is needed — `Match` is its own top-level block, so it works even in an
   empty `~/.ssh/config`. Place it near the top, since ssh uses the first matching
   `ProxyCommand`.

7. **(Optional) on-change hook** — e.g. configure git-over-HTTPS to use the proxy:
   ```sh
   cp config/on-change.example ~/.config/proxy-config/on-change
   chmod +x ~/.config/proxy-config/on-change
   $EDITOR ~/.config/proxy-config/on-change
   ```

   > **About `dt` / "devtool":** the author's macOS setup runs an internal corporate
   > tool, `dt` (aka *devtool*), to manage GitHub configuration — including the git
   > proxy. `dt` is internal and is **not included in this repo**. The `on-change`
   > hook above is the generic, self-contained replacement: it sets git's HTTP/HTTPS
   > proxy directly, so you don't need `dt` or any equivalent.

## What you must customize

| Item | File | Example → set to your values |
|---|---|---|
| Reachability probe host:port | `~/.config/proxy-config/config` | `proxy.effndc.com` / `8080` |
| HTTP / HTTPS / SOCKS proxy URLs | `~/.config/proxy-config/config` | `http://proxy.effndc.com:8080`, `socks5://…:1080` |
| `NO_PROXY_LIST` | `~/.config/proxy-config/config` | add your internal domains + CIDRs |
| Prompt colors (optional) | `~/.config/proxy-config/config` | `38;5;33` (on) / `38;5;51` (off) |
| SSH SOCKS host:port (optional) | `ssh/proxy.sshconfig` | `SOCKS_PROXY_HOST:SOCKS_PROXY_PORT` |
| git-proxy / other side effects (optional) | `~/.config/proxy-config/on-change` | your script |

The shell snippets contain **no** site-specific values and don't need editing.

## Commands

- **`proxy-refresh`** — run detection now and adopt the result in this shell.
- **`proxy-sync`** — adopt the latest cached state in this shell without re-detecting
  (no network); useful to immediately pick up a refresh done elsewhere.

## Manual vs automatic detection

Detection only *runs* when something invokes `proxy-detect` — a scheduler or you via
`proxy-refresh`. Everything else (prompt color, env, propagation to open shells) is the
cheap cache-read path that always works. Manual mode is a fine, low-complexity default;
add a scheduler when you want hands-off updates.

## Platform / shell support

| | Status |
|---|---|
| macOS | Tested (launchd auto-detect + manual) |
| Linux (Ubuntu) | Detector portable; systemd units provided as a lightly-tested proposal |
| WSL2 | **Untested** — use manual `proxy-refresh` (systemd is opt-in; NAT'd networking) |
| bash / zsh / fish | Supported |
| Terminal.app / iTerm2 / Ghostty | Color cue verified |

## Troubleshooting

- **See current state:** `cat ~/.cache/proxy/state.env`
- **Prompt color doesn't change between states:** your terminal theme is probably
  remapping ANSI colors — this tool already uses theme-independent 256-color values, so
  make sure you're on the latest snippet and that you didn't substitute base ANSI codes.
- **Prompt color frozen on one value:** a shell integration is caching your prompt — keep
  `PS1`/`PROMPT` as the provided *fixed* string with the `$(__proxy_color)` substitution
  (don't reassign the whole prompt each render).
- **Env not updating in an already-open shell:** press Enter (the per-prompt sync re-reads
  the cache) or run `proxy-sync`.
- **Probe always says proxy_yes/no:** confirm `PROXY_PROBE_HOST:PORT` is reachable *only*
  when behind the proxy; an always-on tunnel/VPN can keep it reachable.

## Roadmap / future ideas

Possible additions, mostly extending the `on-change` hook so more tools follow the
detected proxy state automatically:

- **Ubuntu `apt` proxy** — write/remove `/etc/apt/apt.conf.d/95proxy`
  (`Acquire::http::Proxy` / `Acquire::https::Proxy`) on state change (needs sudo).
- **git HTTPS proxy without `dt`** — promote the `on-change` git-proxy snippet into a
  first-class, documented option (set/unset `http.proxy`/`https.proxy`), so corporate
  users get the `dt` behavior with nothing internal required.
- **Docker image pulls through the proxy** — manage the Docker client proxy
  (`~/.docker/config.json` `proxies` block) and/or the daemon's
  `Service.Proxy`/systemd drop-in so `docker pull` works behind the proxy.
- **Podman image pulls through the proxy** — manage Podman's proxy env
  (`containers.conf` `[engine] env`, or `~/.config/environment.d`) so `podman pull`
  works behind the proxy.

Each of these is naturally a small, opt-in module invoked from `on-change` (and gated
on `proxy_yes`/`no_proxy`), keeping the core detector minimal.

## License

See [LICENSE](LICENSE).
