# proxy-config-utility

A tiny, dependency-light utility that gives your shell a **visual cue** when you're
behind a corporate proxy/VPN and **manages your `*_proxy` environment** to match —
without slowing down shell startup or fighting itself when many shells start at once.

- **Prompt color** changes based on proxy state (e.g. blue = behind proxy, cyan = direct).
- **`http_proxy` / `https_proxy` / `socks_proxy` / `no_proxy`** are set or unset automatically.
- **Per-tool proxy** for **git, Docker, APT, and Snap** follows the same state — git and the
  Docker client toggle automatically via the on-change hook; APT, Snap, and the Docker daemon
  are one-command `sudo` helpers (they touch root-owned config).
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
automatic detection (macOS launchd / Linux systemd timer), optional SSH routing, and the
optional on-change hook (auto git + Docker-client proxy). It's safe to re-run and backs up
anything it changes. Prefer the
manual steps below if you'd rather see exactly what gets written.

### Manual

1. **Get the scripts on your PATH.** Symlink all of `bin/` into `~/bin` (the on-change hook
   and `proxy-help` expect `proxy-git`/`proxy-docker`/etc. to be findable):
   ```sh
   mkdir -p ~/bin
   ln -s "$PWD"/bin/proxy-* ~/bin/   # detect, reachable, git, docker, apt, snap, help
   ```
   Ensure `~/bin` is on your `PATH`. (At minimum you need `proxy-detect`; `proxy-reachable`
   is used by the SSH integration, and `proxy-git`/`proxy-docker` by the on-change hook.)

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

7. **(Optional) on-change hook** — auto-apply the no-sudo proxies (git + Docker client) on
   every detection. Just install it (no editing — it reads your config via the modules):
   ```sh
   cp config/on-change.example ~/.config/proxy-config/on-change
   chmod +x ~/.config/proxy-config/on-change
   ```
   It calls `proxy-git` and `proxy-docker` for you; the root-only tools (APT, Snap, Docker
   daemon) stay as deliberate `sudo` commands (the hook documents them).

   > **About `dt` / "devtool":** the author's macOS setup runs an internal corporate tool,
   > `dt` (aka *devtool*), to manage GitHub config — including the git proxy. `dt` is internal
   > and **not included here**; `proxy-git` (invoked by this hook) is the generic, self-contained
   > replacement, so you don't need `dt` or any equivalent.

## What you must customize

| Item | File | Example → set to your values |
|---|---|---|
| Reachability probe host:port | `~/.config/proxy-config/config` | `proxy.effndc.com` / `8080` |
| HTTP / HTTPS / SOCKS proxy URLs | `~/.config/proxy-config/config` | `http://proxy.effndc.com:8080`, `socks5://…:1080` |
| `NO_PROXY_LIST` | `~/.config/proxy-config/config` | add your internal domains + CIDRs |
| Prompt colors (optional) | `~/.config/proxy-config/config` | `38;5;33` (on) / `38;5;51` (off) |
| SSH SOCKS host:port (optional) | `ssh/proxy.sshconfig` | `SOCKS_PROXY_HOST:SOCKS_PROXY_PORT` |

The shell snippets and the `on-change` hook contain **no** site-specific values and don't need
editing — the git/Docker/APT/Snap helpers all read the proxy URLs from the config above.

## Commands

- **`proxy-help`** — show current state, your config (and its values), and every command
  per tool — adapting to what's installed and which scheduler is active. Start here if you
  forget the rest.
- **`proxy-refresh`** — run detection now and adopt the result in this shell.
- **`proxy-sync`** — adopt the latest cached state in this shell without re-detecting
  (no network); useful to immediately pick up a refresh done elsewhere.
- **`proxy-git` / `proxy-docker` / `proxy-apt` / `proxy-snap`** — per-tool proxy toggles (see their sections).

## Manual vs automatic detection

Detection only *runs* when something invokes `proxy-detect` — a scheduler or you via
`proxy-refresh`. Everything else (prompt color, env, propagation to open shells) is the
cheap cache-read path that always works. Manual mode is a fine, low-complexity default;
add a scheduler when you want hands-off updates.

## Platform / shell support

| | Status |
|---|---|
| macOS | Tested (launchd auto-detect + manual) |
| Linux (Ubuntu) | Verified on Ubuntu: detector, SSH helper/routing, the `systemd --user` timer (enabled + recurring), and the git/Docker/APT/Snap helpers. (`nc` flags, connect-timeout, `stat -c`, `date -u`, `mktemp`, mkdir-lock all confirmed.) |
| WSL2 | **Untested** — use manual `proxy-refresh` (systemd is opt-in; NAT'd networking) |
| bash / zsh / fish | Supported |
| Terminal.app / iTerm2 / Ghostty | Color cue verified |
| git proxy (`proxy-git`) | **macOS + Linux** — `git config --global http.proxy/https.proxy` (no sudo) |
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

## git (HTTPS)

`bin/proxy-git` sets/clears git's global HTTP(S) proxy (`~/.gitconfig`) so `git` over HTTPS
works behind the proxy and direct otherwise — the generic replacement for an internal tool
like `dt`/devtool:

```sh
proxy-git on|off    # git config --global http.proxy/https.proxy   [auto via on-change hook]
```

No sudo; cross-platform; invoked automatically by the `on-change` hook (single-writer, so no
`.gitconfig.lock` races). git over **SSH** is handled separately by the SSH integration. See
[`git/README.md`](git/README.md).

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

- **Podman image pulls through the proxy** — manage Podman's proxy env
  (`containers.conf` `[engine] env`, or `~/.config/environment.d`) so `podman pull`
  works behind the proxy.

## License

See [LICENSE](LICENSE).
