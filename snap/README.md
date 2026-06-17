# Snap (snapd) proxy integration

`bin/proxy-snap` points the Snap Store at the proxy when you're behind it and clears it
when you're not. snapd is special: it **ignores `http_proxy`/`https_proxy` env and apt
config** and uses its own system setting.

| Mechanism | Affects | Privilege | Restart |
|---|---|---|---|
| `snap set system proxy.http` / `proxy.https` | `snap install` / `snap refresh` (Snap Store) | **root** | none — applies live |

## Usage

```sh
proxy-snap on      # snap set system proxy.http/https from your config
proxy-snap off     # snap unset system proxy.http/https
```

Inspect manually: `snap get system proxy`. Values come from
`~/.config/proxy-config/config` (`HTTP_PROXY_URL`; `HTTPS_PROXY_URL` defaults to it);
under `sudo` the invoking user's config is read via `$SUDO_USER`. Self-elevates (snapd
system config is root-only); there's no daemon restart.

## Automating it (optional)

Like apt and the Docker daemon, the unprivileged `on-change` hook doesn't toggle snap by
default. To make it follow detection automatically, add a narrow passwordless-sudo entry
and call it from `~/.config/proxy-config/on-change`:

```sh
# /etc/sudoers.d/proxy-snap   (run: sudo visudo -f /etc/sudoers.d/proxy-snap)
youruser ALL=(root) NOPASSWD: /home/youruser/bin/proxy-snap on, /home/youruser/bin/proxy-snap off
```
```sh
# in ~/.config/proxy-config/on-change
case "$status" in
  proxy_yes) proxy-snap on  >/dev/null 2>&1 || true ;;
  *)         proxy-snap off >/dev/null 2>&1 || true ;;
esac
```
Low-risk (applies live, no daemon bounce).

## Notes

- Ubuntu/snapd only. `proxy-snap` no-ops with a message if `snap` isn't installed.
- Override the command for testing with `SNAP_CMD` (e.g. a mock); `PROXY_CONFIG` overrides
  the config path.
