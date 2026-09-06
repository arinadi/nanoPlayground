---
name: playground-manage
description: >
  Manage the nanoPlayground runtime itself — the Agent of Empires (aoe) session
  manager, the headless VNC desktop (Xvfb/awesome/x11vnc), and the
  proot-distro lifecycle on the host. Use when starting/stopping agent sessions,
  the aoe daemon/web dashboard, the remote desktop, or when a container must be
  reinstalled/upgraded. Complements ubuntu-manage (packages/services), which is
  the right skill for apt/systemd. Triggers: aoe, start-desktop, stop-desktop,
  VNC, x11vnc, Xvfb, proot-distro, pd login, playground, session.
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  os: ubuntu-26.04
---

# playground-manage

Manage the nanoPlayground stack, not the OS. Ubuntu itself (apt/systemd) is
handled by the sibling `ubuntu-manage` skill. This skill owns everything above
the OS: the **aoe** session manager, the helper CLIs (`npg`, `rtk`), the
headless **VNC desktop** stack we ship, and the **proot-distro** lifecycle.

## Detect where we are first (shared with ubuntu-manage)

```bash
ps -p 1 -o comm=                      # PID 1: systemd? entrypoint.sh?
[ -f /.dockerenv ] && echo docker
grep -q proot /proc/version && echo proot
systemctl is-system-running 2>/dev/null || echo "no systemd bus"
```

- **Booted VM** (PID 1 = `systemd`): full systemctl + real daemons.
- **Docker/podman run** and **Termux proot-distro** (PID 1 = `entrypoint.sh`):
  no systemd bus. Run daemons foreground; aoe/npg/desktop work fine.
- Under **proot**: kernel reports `proot@termux`, `/proc` & `/sys` are stubs,
  no `CAP_SYS_ADMIN`. Package/process management is fine; anything needing
  real kernel features is not.

## Top of the stack: `aoe` (Agent of Empires)

`aoe` is a tmux-based session manager that runs Claude Code / OpenCode agents.
It IS the playground. Everything else serves it.

**Start policy:** on `docker run` / `proot-distro`, ONLY the interactive `aoe`
TUI auto-starts. The web dashboard and the VNC desktop never auto-start —
they are opt-in / on-demand (below).

- `aoe` (no args) → interactive TUI dashboard. Don't run a TUI when not a TTY.
- Start the daemon + web dashboard: `aoe serve` (entrypoint tries it when
  `AOE_WEB=1`). Then `aoe url` prints the dashboard address.
- Sessions: `aoe add` create, `aoe session start|stop|restart|attach`,
  `aoe send "msg"` message a running agent, `aoe ps` / `aoe status` monitor,
  `aoe killall` stop everything (destructive).
- `aoe list`, `aoe logs`, `aoe log-level`, `aoe mcp`, `aoe skill`, `aoe profile`,
  `aoe settings`, `aoe update`, `aoe uninstall`.
- Sandbox (docker-in-docker) is **off** by default (`config/aoe-config.toml`).
  Only turn it on for a real docker host, never under proot.

## Helper CLIs (token-saving, accurate)

- `npg` — one-command OS/desktop ops. `npg commands` to discover; `npg sys info`
  for a single-line health check; `npg skills sync|list` to install the built-in
  skills into every agent home (`~/.agents`, `~/.claude`, `~/.codex`,
  `~/.config/opencode`). Skill source: `/usr/share/nanoplayground/skills`.
- `rtk` — shell-output compression so the LLM reads less. `rtk init -g
  --auto-patch` (Claude) and `rtk init -g --opencode --auto-patch` (OpenCode)
  register hooks; `rtk gain` reports savings. Prefer plain shell commands; the
  hook rewrites them.

## Desktop / VNC stack (this repo now ships it)

`bin/start-desktop.sh` wires Xvfb → awesome → x11vnc. Connect with a native
VNC client app (bVNC, RealVNC Viewer). Stop with `bin/stop-desktop.sh`.

- **Never auto-starts.** Start it explicitly when you need a GUI:
  `start-desktop.sh` (defaults `:1`, 800x1280 portrait, VNC 127.0.0.1:5900,
  no password). Stop: `stop-desktop.sh` (idempotent, safe when stopped).
- Access: `127.0.0.1:5900` from a VNC app on the device (no password).
  bVNC offers a simulated-touchpad input mode. From a remote machine use
  Termux `adb reverse tcp:5900 tcp:5900` (or a port-forward).
- Tune via env: `DISPLAY_NUM`, `RESOLUTION`, `VNC_PORT`.
- Headless browser automation (crawl4ai/playwright/firefox) needs no desktop;
  launch headed under the VNC display to watch it.

See `references/desktop.md` for runnable examples and debugging.

## Termux proot-distro lifecycle (the host, NOT inside the container)

Reinstalling / upgrading the playground is a HOST action. From a Termux shell
(never from inside this container):

```bash
proot-distro list                    # find "npg"
pd backup npg -o npg.tar.xz          # safety first
pd install ghcr.io/arinadi/nanoplayground -n npg
pd login npg --user admin            # shell / debug  (never root)
```

Read the reference before touching sessions: `references/proot-lifecycle.md`.
The push-to-main CI rebuilds the GHCR image; to pick it up, reinstall the
proot container (remove + install).

## Playbook

1. Health check: `npg sys info` (1 call: OS/PID1/tool versions).
2. Agent trouble → `aoe ps`, `aoe logs`, `aoe session show`; restart with
   `aoe session restart <name>` or `aoe killall`.
3. Desktop trouble → `references/desktop.md`; check ports/PID1 first.
4. Need the new image → push to main (CI), then reinstall on host Termux.

Read the matching reference on demand; don't dump them all into context.