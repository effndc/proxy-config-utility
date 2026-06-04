# Linux automatic detection (proposal)

On Linux you can either run detection **manually** (just use the `proxy-refresh`
shell command whenever your network changes — the simplest, most portable option)
or wire up **automatic** detection with a systemd user timer and, optionally, an
instant network-change trigger.

> **Status:** the manual workflow is the recommended baseline. The systemd units
> below are a reasonable starting point but are **lightly tested**. They have
> **not been tested on WSL2** (see the caveat at the end) — there, prefer manual.

## Option A — manual (recommended baseline)

Nothing to install beyond the shell snippet. Run `proxy-refresh` when you connect
to / disconnect from the corporate network. It updates the cache; all open shells
pick it up on their next prompt.

## Option B — systemd user timer (periodic)

Refreshes every 5 minutes and shortly after boot/login.

```sh
mkdir -p ~/.config/systemd/user
cp linux/proxy-detect.service linux/proxy-detect.timer ~/.config/systemd/user/
# ensure ~/bin/proxy-detect exists (or edit ExecStart in the .service)
systemctl --user daemon-reload
systemctl --user enable --now proxy-detect.timer

# check it:
systemctl --user list-timers proxy-detect.timer
journalctl --user -u proxy-detect.service -n 20
```

Uninstall: `systemctl --user disable --now proxy-detect.timer`.

## Option C — instant on network change (optional, needs root)

A periodic timer can lag a network change by up to its interval. For instant
updates, trigger `proxy-detect` from NetworkManager's dispatcher:

```sh
sudo tee /etc/NetworkManager/dispatcher.d/90-proxy-detect >/dev/null <<'EOF'
#!/bin/sh
# $1 = interface, $2 = action (up/down/connectivity-change)
case "$2" in
  up|down|connectivity-change|vpn-up|vpn-down)
    su - YOUR_USERNAME -c '~/bin/proxy-detect' ;;
esac
EOF
sudo chmod +x /etc/NetworkManager/dispatcher.d/90-proxy-detect
```

(Replace `YOUR_USERNAME`. systemd-networkd users can use `networkd-dispatcher`
instead. A systemd `.path` unit watching `/etc/resolv.conf` is another option.)

## WSL2 caveat (untested)

This has **not been tested on WSL2**. Notes for if you try it:

- systemd in WSL2 is **opt-in** — set `[boot]\nsystemd=true` in `/etc/wsl.conf`
  and `wsl --shutdown` to restart. Without it, Options B/C don't apply; use
  **manual** (`proxy-refresh`).
- WSL2 networking is NAT'd behind Windows with an auto-generated `/etc/resolv.conf`,
  so the reachability probe reflects the Windows host's network, and your
  `NO_PROXY_LIST` may need WSL-specific values.
- There is no NetworkManager in a default WSL2 image, so Option C does not apply.
