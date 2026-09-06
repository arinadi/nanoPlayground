---
name: void-manage
description: >
  REQUIRED when managing Void Linux (xbps packages, runit services, users)
  inside nanoPlayground or any Void glibc container/VM. Use when installing
  packages, updating the system, enabling services, or when the agent is
  tempted to use apt/dnf/apk/systemctl — those are wrong on Void.
  Triggers: Void, xbps-install, xbps-query, runit, sv, /etc/sv.
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  os: void-linux
---

# void-manage

Manage Void Linux accurately. Void is rolling-release, uses **XBPS** (not
apt/dnf/apk) and **runit** (not systemd). Base image here is
`void-glibc-full` (glibc, required by the `aoe` binary which needs
glibc >= 2.28) — never suggest `musl`-only tricks.

## Prefer `npg` wrappers (hemat token)

Image ini punya CLI `npg` — SATU panggilan menggantikan banyak shell:

- `npg commands [--json]` — discover every command (start here)
- `npg sys info` — OS, PID1, versi tools, jumlah service (1 panggilan)
- `npg pkg update | add <p..> | search <pola> | rm <p> | clean`
- `npg svc status|enable|disable|run` — runit + deteksi container otomatis
- `npg skills sync|list` — pasang skill ke semua harness agent

`npg` refuses to run on non-Void (guarded by `xbps`), so the wrong host stays safe.

`rtk` (Rust Token Killer) is also preinstalled and pre-registered
(`rtk init` for Claude Code + OpenCode): shell output the agent reads is
auto-compressed. Prefer plain shell commands (`rg`, `cat`, `git status`) so
the hook can rewrite them; check savings with `rtk gain`.

## Hard rules (when `npg` is unavailable)

- NEVER use `apt`, `apt-get`, `dnf`, `apk`, `pacman`, `systemctl`, `service`.
  Only `xbps-install`, `xbps-query`, `xbps-remove`, `xbps-reconfigure`, `sv`.
- System update is ALWAYS two-phase (`xbps` itself first):
  `sudo xbps-install -Suy xbps && sudo xbps-install -Suy`
- `sv up/down/status` only works when runit is PID 1 (real VM). Inside the
  nanoPlayground container PID 1 is `entrypoint.sh`, so `sv` fails cleanly —
  that is expected. Bake enablement with symlinks, run daemons foreground.
- `useradd`/`groupadd` need the `shadow` package; sudo via
  `/etc/sudoers.d/<user>` (mode 0440), never hand-edit `/etc/sudoers`.

## Topic guides

Read the matching file on demand, don't dump all into context:

- Package ops (install/search/remove/hold/cache): `references/packages.md`
- Services (runit enable/start/conf, container limits): `references/services.md`

## Validate after every change

- Packages: `xbps-query -S <pkg>` (installed?) / `xbps-query -l | grep <pkg>`
- Services on VM: `sv check <svc>`; in container: run the daemon foreground
  (e.g. `sshd -D`) instead of waiting for `sv`.
- Syntax/unit files you touched: re-read the file, `visudo -c` for sudoers.

## Decision order (copy of omarchy pattern)

1. `npg <grup> <aksi>` beats raw `xbps-*`/`sv` (idempoten, batch, terverifikasi).
2. Stock command (`xbps-install`, `sv`, `ln -s /etc/sv/...`) beats config edit.
2. Config edit beats hook/script. Never edit `/etc/sv/<svc>/run` in place —
   it is overwritten on update; copy/overlay instead.
3. Keep user state in `$HOME` / `/workspace`; system defaults stay read-only.
