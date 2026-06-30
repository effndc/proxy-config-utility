# System environment (`/etc/environment`) proxy integration

`bin/proxy-env` writes/removes the proxy variables in `/etc/environment` so they're
available **system-wide** — including under `sudo` and in non-shell login sessions (PAM's
`pam_env` reads `/etc/environment` at login). **Linux-only** — macOS doesn't use this file,
so `proxy-env` isn't even installed there.

| File | Affects | Privilege | Applies |
|---|---|---|---|
| `/etc/environment` (managed block) | every user's login + `sudo` sessions | **root** | **new** login/sudo sessions (not already-open shells) |

## Usage

```sh
proxy-env on      # add the proxy vars to /etc/environment (self-elevates)
proxy-env off     # remove them
```

It maintains a clearly marked block so your other `/etc/environment` entries are untouched:

```
# >>> proxy-config-utility >>>
http_proxy=…    HTTP_PROXY=…    https_proxy=…   HTTPS_PROXY=…
no_proxy=…      NO_PROXY=…      socks_proxy=…   all_proxy=…   ALL_PROXY=…
# <<< proxy-config-utility <<<
```

Both lower- and UPPER-case (plus `all_proxy`/`ALL_PROXY`), values from
`~/.config/proxy-config/config`. Self-elevates with a notice; no restart needed.

## Notes

- **System-wide:** this affects **all users** on the host — unlike the per-user shell env
  the prompt/`on-change` hook manages. Use it when you specifically want `sudo` and
  system services to inherit the proxy.
- **Takes effect on the NEXT login/sudo session**, not your current shell. Re-login (or open
  a new session) to pick it up.
- **Remember to `proxy-env off`** when you leave the network — your *shell* env clears
  itself, but `/etc/environment` persists until you toggle it (or wire the optional
  passwordless-sudo automation, like apt/snap).
- Test override: `ENV_FILE` (point at a scratch file); `PROXY_CONFIG` overrides the config.
