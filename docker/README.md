# Docker proxy integration

`bin/proxy-docker` keeps Docker's proxy settings in sync with the detected proxy
state. Docker splits proxy config into two independent layers, so the tool does too:

| Scope | File | Affects | Privilege | Restart |
|---|---|---|---|---|
| **client** | `~/.docker/config.json` (`proxies.default.httpProxy`…) | proxy env **injected into containers** at `docker build` / `docker run` | your user | none |
| **daemon** | `/etc/docker/daemon.json` (`proxies.http-proxy`…) | the proxy **dockerd** uses for `docker pull` | **root** | `systemctl restart docker` |

(The two use different key casing — `httpProxy` vs `http-proxy` — which `proxy-docker`
handles for you. It merges into existing JSON, so other keys like `auths` or
`log-driver` are preserved, and writes atomically.)

## Usage

```sh
proxy-docker on                 # client scope: write ~/.docker/config.json proxies
proxy-docker off                # client scope: remove them

sudo proxy-docker --daemon on   # daemon scope: write /etc/docker/daemon.json + restart docker
sudo proxy-docker --daemon off  # daemon scope: remove + restart
sudo proxy-docker --daemon --no-restart on   # write only; restart later yourself

proxy-docker on --all           # client + daemon (daemon part still needs root)
```

Values come from `~/.config/proxy-config/config` (`HTTP_PROXY_URL` / `HTTPS_PROXY_URL`
/ `NO_PROXY_LIST`). Under `sudo`, the invoking user's config is read via `$SUDO_USER`.

## Recommended wiring (auto client, manual daemon)

The **client** side is safe to automate — no sudo, no restart. The included
`config/on-change.example` already calls `proxy-docker on|off` when `proxy-docker` is on
your `PATH`, so installing that hook keeps container build/run proxy env in sync
automatically as you move on/off the network.

The **daemon** side restarts dockerd (killing running containers), so run it
deliberately when you actually need `docker pull` to traverse the proxy:

```sh
sudo proxy-docker --daemon on     # arriving on the proxied network
sudo proxy-docker --daemon off    # leaving it
```

## Fully automating the daemon side (optional, advanced)

If you want the daemon layer to follow detection automatically too, add a narrowly
scoped passwordless sudoers entry and call it from the hook — accepting that dockerd
will restart on network changes:

```sh
# /etc/sudoers.d/proxy-docker   (run: sudo visudo -f /etc/sudoers.d/proxy-docker)
youruser ALL=(root) NOPASSWD: /home/youruser/bin/proxy-docker --daemon on, /home/youruser/bin/proxy-docker --daemon off
```
Then in `~/.config/proxy-config/on-change`:
```sh
case "$status" in
  proxy_yes) sudo -n proxy-docker --daemon on  >/dev/null 2>&1 || true ;;
  *)         sudo -n proxy-docker --daemon off >/dev/null 2>&1 || true ;;
esac
```
This is intentionally **not** the default — auto-restarting Docker is disruptive.

## Notes

- Requires `python3` (present by default on Ubuntu) for safe JSON merging.
- **The daemon side is Linux / Docker Engine only.** macOS has no native Docker Engine —
  Docker Desktop runs the daemon in a VM, and you set its proxy in *Settings → Resources →
  Proxies* (the `/etc/docker/daemon.json` + systemd-restart steps don't apply there). The
  **client** `~/.docker/config.json` part is portable and still works on macOS.
- Verified live on Ubuntu: with the daemon proxy set, `docker run hello-world` pulled and
  ran behind the corporate proxy (it failed beforehand).
- Test/override paths via `DOCKER_CLIENT_JSON`, `DOCKER_DAEMON_JSON`, `PROXY_CONFIG`.
