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

## Bootstrapping behind a proxy

Chicken-and-egg: a fresh machine behind a corporate proxy can't reach GitHub until a proxy
is configured — but this repo is what configures it. Fetch it with a **one-off** proxy
(replace `proxy.example.com:8080` with your HTTP proxy). Both work for a public repo with no
SSH key:

```sh
# git over HTTPS (anonymous)
https_proxy=http://proxy.example.com:8080 \
  git clone https://github.com/effndc/proxy-config-utility.git

# or, no git needed — download the tarball through the proxy
https_proxy=http://proxy.example.com:8080 \
  curl -L https://github.com/effndc/proxy-config-utility/archive/refs/heads/main.tar.gz | tar xz
```

Then run the installer (below); it sets up the *persistent* proxy config so subsequent
git/network operations work without the one-off `https_proxy=` prefix. (If you must use SSH —
e.g. a private mirror — clone with `GIT_SSH_COMMAND='ssh -o ProxyCommand="nc -X 5 -x
SOCKS_HOST:1080 %h %p"' git clone git@…`.)

## Install

### Quick start (guided)

```sh
./install.sh
```

The interactive installer asks for your proxy settings (probe host/port, HTTP/HTTPS/SOCKS
URLs, `no_proxy`, prompt colors), then installs the scripts, wires up your shell(s), offers
automatic detection (macOS launchd / Linux systemd timer), optional SSH routing, and an
optional git-proxy hook. It's safe to re-run and backs up anything it changes. Prefer the
manual steps below if you'd rather see exactly what gets written.

### Manual

1. **Get the scripts on your PATH.** Symlink (or copy) `bin/proxy-detect` to `~/bin`
   (and `bin/proxy-reachable` too if you'll use the SSH integration):
   ```sh
   mkdir -p ~/bin
   ln -s "$PWD/bin/proxy-detect"    ~/bin/proxy-detect      # ensure ~/bin is on your PATH
   ln -s "$PWD/bin/proxy-reachable" ~/bin/proxy-reachable   # only needed for SSH integration
   ```
   (Or point the shell snippet at the detector with `export PROXY_DETECT=/path/to/bin/proxy-detect`.)

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
   `ProxyCommand`. Requires `bin/proxy-reachable` on your PATH (step 1) — it does the
   OS-correct `nc` connect-timeout so the config is portable between macOS and Linux.

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
| Linux (Ubuntu) | Detector + SSH helper verified on Ubuntu (OpenBSD netcat, bash 5.2, dash `/bin/sh`): `nc` flags, connect-timeout, `stat -c`, `date -u`, `mktemp`, mkdir-lock all confirmed. systemd units remain a proposal. |
| WSL2 | **Untested** — use manual `proxy-refresh` (systemd is opt-in; NAT'd networking) |
| bash / zsh / fish | Supported |
| Terminal.app / iTerm2 / Ghostty | Color cue verified |
| Docker proxy (`proxy-docker`) | **Linux / Docker Engine** — verified on Ubuntu; macOS Docker Desktop uses its own proxy settings (client config.json still applies) |
| APT proxy (`proxy-apt`) | **Debian/Ubuntu** — writes `/etc/apt/apt.conf.d/95proxy` (sudo; no restart) |
| Snap proxy (`proxy-snap`) | **Ubuntu/snapd** — `snap set system proxy.http/https` (sudo; no restart) |

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

## Docker

`bin/proxy-docker` syncs Docker's proxy config with the detected state — client scope
(`~/.docker/config.json`, for build/run container env; no sudo) automatically via the
`on-change` hook, and daemon scope (`/etc/docker/daemon.json`, for `docker pull`; needs
root + a Docker restart) on demand:

```sh
proxy-docker on|off                 # client (auto via on-change hook)
sudo proxy-docker --daemon on|off   # daemon (deliberate; restarts dockerd)
```

**Scope — Linux (Docker Engine) only.** This targets a native **Docker Engine**, as on
Ubuntu, and is **verified live** there (the daemon proxy made `docker pull` succeed behind
the corporate proxy). macOS has **no native Docker Engine** — Docker Desktop runs the daemon
inside a VM and you set its proxy in *Settings → Resources → Proxies*, so the
`/etc/docker/daemon.json` + systemd-restart parts don't apply on macOS. The **client**
(`~/.docker/config.json`) part is portable and still works on macOS for build/run container
env. See [`docker/README.md`](docker/README.md) for details and optional daemon-side automation.

## APT (Debian/Ubuntu)

`bin/proxy-apt` writes/removes APT's proxy config so `apt update` / `apt install` go
through the proxy when you're behind it and direct when you're not — no hand-editing:

```sh
sudo proxy-apt on|off    # writes/removes /etc/apt/apt.conf.d/95proxy (no restart)
```

Needs `sudo` (the file is under `/etc`); there's no daemon to restart. Not wired into the
unprivileged `on-change` hook by default — run it deliberately, or see
[`apt/README.md`](apt/README.md) for a narrow passwordless-sudo recipe to automate it
(low-risk, since apt has no daemon to bounce). Debian-family only.

## Snap (snapd)

snapd ignores `http_proxy`/apt config and uses its own setting, so `bin/proxy-snap` wraps it:

```sh
sudo proxy-snap on|off    # snap set/unset system proxy.http + proxy.https (applies live)
```

Needs `sudo` (snapd system config is root-only); no restart. Not in the unprivileged hook
by default — see [`snap/README.md`](snap/README.md) for usage and an optional
passwordless-sudo recipe. Ubuntu/snapd only (no-ops if `snap` isn't installed).

## Roadmap / future ideas

More opt-in modules that extend the `on-change` hook so additional tools follow the
detected proxy state (each gated on `proxy_yes`/`no_proxy`, keeping the core minimal):

- **git HTTPS proxy without `dt`** — promote the `on-change` git-proxy snippet into a
  first-class, documented option (set/unset `http.proxy`/`https.proxy`), so corporate
  users get the `dt` behavior with nothing internal required.
- **Podman image pulls through the proxy** — manage Podman's proxy env
  (`containers.conf` `[engine] env`, or `~/.config/environment.d`) so `podman pull`
  works behind the proxy.

## License

See [LICENSE](LICENSE).
