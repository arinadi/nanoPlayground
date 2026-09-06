---
name: ubuntu-manage
description: >
  REQUIRED when managing Ubuntu 26.04 LTS (apt packages, systemd services,
  users) inside nanoPlayground or any Ubuntu glibc container/VM. Use when
  installing packages, updating the system, enabling services, or when the
  agent is tempted to use xbps/apk/dnf/systemctl-only tricks — use apt and
  systemd correctly. Triggers: Ubuntu, apt, apt-get, systemctl, dpkg, /etc/apt.
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  os: ubuntu-26.04
---

# ubuntu-manage

Manage Ubuntu 26.04 LTS accurately. Ubuntu is a fixed-release Debian-derived
distro, uses **apt/dpkg** (not xbps/apk/dnf) and **systemd** (not runit).
Base image here is `ubuntu:26.04` (glibc, required by the `aoe` binary which
needs glibc >= 2.28).

## Environment awareness — proot vs docker/podman vs VM (CHECK FIRST)

nanoPlayground runs in three very different places. Detect before acting —
do NOT assume systemd or a normal process tree:

```bash
ps -p 1 -o comm=           # PID 1 name
[ -f /.dockerenv ] && echo docker
cat /proc/1/cgroup 2>/dev/null | head -1      # "docker"/"podman"/"libpod" => container
grep -q proot /proc/version && echo proot     # proot@termux marker
systemctl is-system-running 2>/dev/null || echo "no systemd bus"
```

Interpretation:

| Where | PID 1 | systemd bus | What works |
|---|---|---|---|
| Booted Ubuntu VM / host | `systemd` | yes | `systemctl enable/start`, real services |
| Docker / podman run | `entrypoint.sh` | no | `systemctl` fails — run daemons foreground |
| Termux **proot-distro** | `entrypoint.sh` | no | `systemctl` fails — run daemons foreground |

Rules that follow:
- In **docker/podman** AND **proot**, PID 1 is `entrypoint.sh`, NOT systemd, so
  `systemctl start|enable|stop` fail cleanly ("Failed to connect to bus").
  That is expected — never fight it. Enablement is baked at build time or the
  daemon is run in the foreground (see `references/services.md`).
- Under **proot** expect extra quirks: a fake `proot@termux` kernel version,
  bind-mounted `/proc`/`/sys` (pid/loadavg/etc. are stubs), and no real
  `CAP_SYS_ADMIN`/device nodes. Package install works, but anything needing
  kernel features (namespaces, real mounts, systemd) will not. If a command
  "should work" but silently fails, suspect proot limits first.
- Only ever touch `systemctl` when PID 1 is literally `systemd`.

## Prefer `npg` wrappers (hemat token)

Image ini punya CLI `npg` — SATU panggilan menggantikan banyak shell:

- `npg commands [--json]` — discover every command (start here)
- `npg sys info` — OS, PID1, versi tools, jumlah service (1 panggilan)
- `npg pkg update | add <p..> | search <pola> | rm <p> | clean`
- `npg svc status|enable|disable|run` — systemd + deteksi container otomatis
- `npg skills sync|list` — pasang skill ke semua harness agent

`npg` refuses to run on non-Ubuntu (guarded by `apt`), so the wrong host
stays safe.

`rtk` (Rust Token Killer) is also preinstalled and pre-registered
(`rtk init` for Claude Code + OpenCode): shell output the agent reads is
auto-compressed. Prefer plain shell commands (`rg`, `cat`, `git status`) so
the hook can rewrite them; check savings with `rtk gain`.

## Hard rules (when `npg` is unavailable)

- NEVER use `xbps`, `apk`, `dnf`, `pacman`, `yum`. Only `apt-get`, `apt`,
  `dpkg`, `systemctl`.
- Package update before installs:
  `sudo apt-get update && sudo apt-get install -y <pkg>`.
- Full system update: `sudo apt-get update && sudo apt-get upgrade -y`
  (and `sudo apt-get dist-upgrade -y` for major kernel/transition upgrades).
- `systemctl enable/start` only works when systemd is PID 1 (real VM). Inside
  the nanoPlayground container PID 1 is `entrypoint.sh`, so `systemctl start`
  fails cleanly — that is expected. Bake enablement with symlinks, run
  daemons foreground, or use `npg svc run <name>`.
- `useradd`/`groupadd` are from `passwd`/`adduser` packages (already present);
  sudo via `/etc/sudoers.d/<user>` (mode 0440), never hand-edit `/etc/sudoers`.

## Topic guides

Read the matching file on demand, don't dump all into context:

- Package ops (install/search/remove/cache/hold): `references/packages.md`
- Services (systemd enable/start/conf, container limits): `references/services.md`

## Validate after every change

- Packages: `dpkg -l <pkg>` (installed?) / `apt list --installed | grep <pkg>`
- Services on VM: `systemctl is-active <svc>`; in container: run the daemon
  foreground (e.g. `sshd -D`) instead of waiting for `systemctl`.
- Syntax/unit files you touched: re-read the file, `visudo -c` for sudoers.

## Decision order

1. `npg <grup> <aksi>` beats raw `apt-*`/`systemctl` (idempoten, batch,
   terverifikasi).
2. Stock command (`apt-get install`, `systemctl`, `ln -s /etc/systemd/...`)
   beats config edit.
3. Config edit beats hook/script. Never edit `/lib/systemd/system/<svc>`
   in place — it is overwritten on update; drop an override in
   `/etc/systemd/system/<svc>.d/` instead.
4. Keep user state in `$HOME` / `/workspace`; system defaults stay read-only.