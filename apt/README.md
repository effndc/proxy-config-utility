# APT proxy integration

`bin/proxy-apt` writes or removes APT's proxy config to match the detected proxy
state, so `apt update` / `apt install` traverse the corporate proxy when you're
behind it and go direct when you're not — without hand-editing config each time.

| File | Affects | Privilege | Restart |
|---|---|---|---|
| `/etc/apt/apt.conf.d/95proxy` (`Acquire::http::Proxy` / `Acquire::https::Proxy`) | all `apt` / `apt-get` HTTP(S) fetches | **root** | none — apt reads it each run |

`on` writes the file (proxy URLs get a trailing slash, as apt expects; HTTPS defaults
to the HTTP proxy via CONNECT). `off` removes the file. Values come from
`~/.config/proxy-config/config` (`HTTP_PROXY_URL` / `HTTPS_PROXY_URL`); under `sudo`
the invoking user's config is read via `$SUDO_USER`. Linux/Debian-family only.

## Usage

```sh
sudo proxy-apt on      # arriving on the proxied network
sudo proxy-apt off     # leaving it (apt goes direct)
```

It needs `sudo` because the file is under `/etc`. There's no daemon to restart.

## Automating it (optional)

Because `/etc` needs root, the unprivileged `on-change` hook does **not** toggle apt by
default. To make it follow detection automatically, add a narrow passwordless-sudo entry
and call it from `~/.config/proxy-config/on-change`:

```sh
# /etc/sudoers.d/proxy-apt   (run: sudo visudo -f /etc/sudoers.d/proxy-apt)
youruser ALL=(root) NOPASSWD: /home/youruser/bin/proxy-apt on, /home/youruser/bin/proxy-apt off
```
```sh
# in ~/.config/proxy-config/on-change
case "$status" in
  proxy_yes) sudo -n proxy-apt on  >/dev/null 2>&1 || true ;;
  *)         sudo -n proxy-apt off >/dev/null 2>&1 || true ;;
esac
```
apt has no daemon to bounce, so (unlike the Docker daemon) automating it is low-risk.

## Notes

- **Internal apt mirrors:** this sets a single global proxy. If you have an internal
  mirror that must be reached **directly**, add a per-host override yourself, e.g.
  `Acquire::http::Proxy::mirror.internal "DIRECT";` in its own
  `/etc/apt/apt.conf.d/` file (proxy-apt won't touch it).
- Test/override the path with `APT_PROXY_FILE` (and `PROXY_CONFIG`).
