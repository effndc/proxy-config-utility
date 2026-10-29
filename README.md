# proxy-config-utility

A tiny, dependency-light utility that gives your shell a **visual cue** when you're
behind a corporate proxy/VPN and **manages your `*_proxy` environment** to match —
without slowing down shell startup or fighting itself when many shells start at once.

- **Prompt color** changes based on proxy state (e.g. blue = behind proxy, cyan = direct).
  The hostname (dark green) and path (lavender) get their own fixed colors so they're easy
  to spot (override with `PROXY_HOST_COLOR="38;5;<n>"` / `PROXY_PATH_COLOR="38;5;<n>"`
  before sourcing the shell snippet).
- **`http_proxy` / `https_proxy` / `no_proxy`** (and their **UPPER-CASE** twins, plus
  `socks_proxy` and `all_proxy`/`ALL_PROXY` for SOCKS) are set or unset automatically — both
  cases, since tools disagree on which they read.
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
is configured — but this tool is what configures it. So give the **first** download a
**one-off** proxy on the command line (replace `proxy.example.com:8080` with your HTTP
proxy); the installer then writes the *persistent* config and you never need the prefix again.

**Requirements:** `bash`, `tar`, and either `curl` or `wget` — **`git` and `gh` are *not*
required** (without `git` the installer unpacks the release tarball instead of cloning; with
`git` you get a clone). Everything below works for a public repo with no GitHub account or
SSH key.

**One-liner (recommended)** — proxy the download *and* the installer's own fetch. Exporting
the variables once covers curl, wget and git (lower-case is what they read):

```sh
export http_proxy=http://proxy.example.com:8080 https_proxy=http://proxy.example.com:8080
curl -fsSL https://raw.githubusercontent.com/effndc/proxy-config-utility/main/install.sh | bash
```

Or per-command, without exporting anything (the proxy has to be given to *both* sides of the
pipe — `curl` for the script, `bash` so the installer's own download inherits it):

```sh
curl -x http://proxy.example.com:8080 -fsSL \
  https://raw.githubusercontent.com/effndc/proxy-config-utility/main/install.sh \
  | https_proxy=http://proxy.example.com:8080 bash
```

Variations:

```sh
# no curl? wget works too (wget reads https_proxy / http_proxy from the environment)
export https_proxy=http://proxy.example.com:8080
wget -qO- https://raw.githubusercontent.com/effndc/proxy-config-utility/main/install.sh | bash

# SOCKS5 proxy instead of HTTP (curl/git only — wget has no SOCKS support; 'socks5h' lets the proxy resolve DNS)
curl --proxy socks5h://proxy.example.com:1080 -fsSL <URL-above> | ALL_PROXY=socks5h://proxy.example.com:1080 bash

# proxy that needs credentials (note: these land in your shell history)
export https_proxy=http://USER:PASSWORD@proxy.example.com:8080

# TLS-intercepting proxy with a corporate CA: point curl/git/wget at the CA bundle
export CURL_CA_BUNDLE=/path/to/corp-ca.pem GIT_SSL_CAINFO=/path/to/corp-ca.pem SSL_CERT_FILE=/path/to/corp-ca.pem
```

Prefer to read it before running it? Download first, inspect, then run:

```sh
curl -x http://proxy.example.com:8080 -fsSLo install.sh \
  https://raw.githubusercontent.com/effndc/proxy-config-utility/main/install.sh
less install.sh && https_proxy=http://proxy.example.com:8080 bash install.sh
```

Other ways to fetch it, if you'd rather not pipe to a shell (each then runs `./install.sh`,
which installs/updates the standard copy described below):

```sh
# git over HTTPS (anonymous), one-off proxy
https_proxy=http://proxy.example.com:8080 \
  git clone https://github.com/effndc/proxy-config-utility.git

# no git: tarball through the proxy
https_proxy=http://proxy.example.com:8080 \
  curl -fsSL https://github.com/effndc/proxy-config-utility/archive/main.tar.gz | tar xz
cd proxy-config-utility-main && https_proxy=http://proxy.example.com:8080 ./install.sh
```

(If you must use SSH — e.g. a private mirror — clone with
`GIT_SSH_COMMAND='ssh -o ProxyCommand="nc -X 5 -x SOCKS_HOST:1080 %h %p"' git clone git@…`
and set `PROXY_REPO_URL` for the installer.)

**Fully offline / can't reach GitHub at all?** Copy the tarball over by other means, unpack
it, and install in place: `tar xz --strip-components=1 -f main.tar.gz && ./install.sh --here`.

## Install

### Quick start (guided)

```sh
curl -fsSL https://raw.githubusercontent.com/effndc/proxy-config-utility/main/install.sh | bash
```

(Behind a proxy? Add the proxy first — see [Bootstrapping behind a proxy](#bootstrapping-behind-a-proxy).
Prefer not to pipe to a shell? Download `install.sh`, read it, and run `bash install.sh`.)

It installs the tool to **`~/.local/share/proxy-config-utility`** — a git clone if `git` is
available, otherwise the unpacked release tarball. That is the *installed copy*: shell
snippets are sourced from it, `~/bin/proxy-*` link into it, and [`proxy-update`](#updating)
keeps it current. Config lives in `~/.config/proxy-config/` and state in `~/.cache/proxy/`.
Override the location with `PROXY_INSTALL_DIR=...` (`XDG_DATA_HOME` is honored), the clone
source with `PROXY_REPO_URL`, the tarball with `PROXY_TARBALL_URL`, and the branch/tag with
`PROXY_REF` (e.g. `curl ... | PROXY_REF=v1.2 bash`).

The interactive installer then asks for your proxy settings (probe host/port, HTTP/HTTPS/SOCKS
URLs, `no_proxy`, prompt colors), installs the scripts, wires up your shell(s), offers
automatic detection (macOS launchd / Linux systemd timer), optional SSH routing, and the
optional on-change hook (auto git + Docker-client proxy). It's safe to re-run and backs up
anything it changes. With no terminal attached (CI, `ssh host 'curl ... | bash'` without
`-t`) the prompts take their defaults — re-run `proxy-setup` afterwards to enter real values.
Prefer the manual steps below if you'd rather see exactly what gets written.

Running `./install.sh` from a clone or tarball you already have does the same thing: it
installs/updates the standard copy above rather than linking into wherever you ran it, so what
you test is what an end user gets. **Developers:** `./install.sh --here` installs in place
from your working checkout instead (and `bin/proxy-update` run from a checkout relinks
`~/bin` to *that* checkout).

### Manual

1. **Get the code and put the scripts on your PATH.** Fetch the repo to the standard
   location (use the `https_proxy=...` prefix from the bootstrapping section if needed),
   then symlink `bin/` into `~/bin` (the on-change hook and `proxy-help` expect
   `proxy-git`/`proxy-docker`/etc. to be findable):
   ```sh
   D=~/.local/share/proxy-config-utility
   git clone https://github.com/effndc/proxy-config-utility.git "$D"
   # no git? mkdir -p "$D" && curl -fsSL https://github.com/effndc/proxy-config-utility/archive/main.tar.gz | tar xz --strip-components=1 -C "$D"
   cd "$D"
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
   echo 'source "$HOME/.local/share/proxy-config-utility/shell/bash.sh"' >> ~/.bashrc
   # zsh
   echo 'source "$HOME/.local/share/proxy-config-utility/shell/zsh.sh"'  >> ~/.zshrc
   # fish
   ln -sf "$PWD/shell/proxy.fish" ~/.config/fish/conf.d/proxy.fish
   ```
   (Prefer `source` over copy/paste so you get updates from `proxy-update`.)

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
- **`proxy-setup`** — (re)enter your proxy settings interactively and re-detect.
- **`proxy-update`** — pull the latest repo and relink commands (see [Updating](#updating)).

> All commands work by name once your shell is configured (the snippet adds `~/bin` to `PATH`).
> The root-only helpers (`proxy-apt`, `proxy-snap`, `proxy-docker --daemon`) **self-elevate** —
> just run `proxy-apt on`; they print exactly what they'll do, then prompt for `sudo`.

## Updating

Because the shell snippets are `source`d from the installed copy
(`~/.local/share/proxy-config-utility`) and the `~/bin/proxy-*` commands are **symlinks into
it**, an update is mostly just "refresh that copy." `proxy-update` does that and relinks any
newly added commands:

```sh
proxy-update      # git pull (or tarball refresh) + re-symlink bin/* into ~/bin
```

- New shells are current immediately; in an already-open shell run `proxy-sync` (or
  `proxy-refresh` to also re-detect).
- **With `git`:** it's a `git pull --ff-only`. **Without `git`** (or if the install was made
  from the tarball): it re-downloads the release tarball over the install (needs `curl` or
  `wget` + `tar`; files deleted upstream are left behind, harmless). Behind a proxy, once
  configured, both just work; before that, prefix `https_proxy=...` as in
  [Bootstrapping behind a proxy](#bootstrapping-behind-a-proxy).
- Your `~/.config/proxy-config/config`, the `on-change` hook, scheduler, and SSH config are
  untouched — only the installed code/commands refresh.
- Run it as `proxy-update` (the `~/bin` link into the installed copy). Running a *development
  checkout's* `bin/proxy-update` relinks `~/bin` to that checkout instead.

Typical flow: `git push` from your dev machine → `proxy-update` on each box.

### Moving an older install to the standard location

Earlier installs ran from wherever you cloned or extracted the repo (a git clone, or an
extracted tarball that couldn't `git pull`). To move to `~/.local/share/proxy-config-utility`,
just re-run the installer — it fetches the standard copy and relinks `~/bin` to it:

```sh
curl -fsSL https://raw.githubusercontent.com/effndc/proxy-config-utility/main/install.sh | bash
```

Your config, the `on-change` hook, scheduler, and SSH settings live outside the repo and are
kept (the installer asks before re-entering values or wiring shells, and backs up what it edits). If your `~/.bashrc`/`~/.zshrc` still `source` the
old path, or your own rc file carries an **inline copy** of the prompt code, replace it with
`source "$HOME/.local/share/proxy-config-utility/shell/bash.sh"` (or `zsh.sh`) — `proxy-update`
only refreshes the repo, so an inline copy never changes. You can then delete the old
checkout.

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
| System env (`proxy-env`) | **Linux only** — managed block in `/etc/environment` (sudo; system-wide; new sessions) |

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
proxy-docker on|off            # client (auto via on-change hook)
proxy-docker --daemon on|off   # daemon (self-elevates; restarts dockerd)
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
proxy-apt on|off    # self-elevates; writes/removes /etc/apt/apt.conf.d/95proxy (no restart)
```

Self-elevates (the file is under `/etc`); no daemon to restart. Not wired into the
unprivileged `on-change` hook by default — run it deliberately, or see
[`apt/README.md`](apt/README.md) for a narrow passwordless-sudo recipe to automate it
(low-risk, since apt has no daemon to bounce). Debian-family only.

## Snap (snapd)

snapd ignores `http_proxy`/apt config and uses its own setting, so `bin/proxy-snap` wraps it:

```sh
proxy-snap on|off    # self-elevates; snap set/unset system proxy.http + proxy.https (applies live)
```

Self-elevates (snapd system config is root-only); no restart. Not in the unprivileged hook
by default — see [`snap/README.md`](snap/README.md) for usage and an optional
passwordless-sudo recipe. Ubuntu/snapd only (no-ops if `snap` isn't installed).

## System environment (`/etc/environment`, Linux)

`bin/proxy-env` puts the proxy vars in `/etc/environment` so they're inherited **system-wide
— including under `sudo`** (and other PAM login sessions), which the per-user shell env
doesn't cover:

```sh
proxy-env on|off    # self-elevates; maintains a managed block in /etc/environment
```

**Linux-only** (macOS doesn't use `/etc/environment`, so it isn't installed there). It's
*system-wide* (all users) and applies to **new** login/sudo sessions, not already-open
shells — so remember `proxy-env off` when you leave the network. See [`env/README.md`](env/README.md).

## Roadmap / future ideas

More opt-in modules that extend the `on-change` hook so additional tools follow the
detected proxy state (each gated on `proxy_yes`/`no_proxy`, keeping the core minimal):

- **Podman image pulls through the proxy** — manage Podman's proxy env
  (`containers.conf` `[engine] env`, or `~/.config/environment.d`) so `podman pull`
  works behind the proxy.

## License

See [LICENSE](LICENSE).
