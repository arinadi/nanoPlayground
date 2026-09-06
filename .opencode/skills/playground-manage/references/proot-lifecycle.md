# Termux proot-distro lifecycle (references/proot-lifecycle.md)

nanoPlayground is most often deployed via **proot-distro on Termux**, not real
Docker. This reference covers the HOST-side operations you run from a Termux
shell. You cannot run these from inside the container.

## Host vs container

| Where | Command | Purpose |
|---|---|---|
| Host Termux shell | `proot-distro list` | list installed distros |
| Host Termux shell | `pd install ghcr.io/arinadi/nanoplayground -n npg` | install/reinstall image as container `npg` |
| Host Termux shell | `pd login npg --user admin` | interactive shell (use `--user admin`, never root) |
| Host Termux shell | `pd backup npg -o npg.tar.xz` | snapshot before experiments |
| Host Termux shell | `pd remove npg` | remove container |
| Host Termux shell | `pd clear-cache` | free disk after pulls |

> `pd` is an alias for `proot-distro`. Inside the container only `npg`
> (the helper) exists — `proot-distro`/`pd` are host-only.

## Why reinstall after a repo push

`pd install ...` pulls the published **GHCR image**
(`ghcr.io/arinadi/nanoplayground`), which is rebuilt by CI whenever you push
to `main` (see `.github/workflows/docker-publish.yml`). The live container is
a snapshot of an older image — pushing does NOT change a running container.

### Getting the new image

```bash
# 1. On the HOST, from the repo dir: push main (triggers CI build+push)
git push origin main
# 2. Watch CI to completion (in the repo, host or container):
gh run watch
# 3. On the HOST Termux: swap the container
pd backup npg -o npg.tar.xz
pd remove npg
pd install ghcr.io/arinadi/nanoplayground -n npg
pd login npg --user admin
```

## proot specifics to expect

- PID 1 inside = `entrypoint.sh` (not systemd) → no systemd bus; run daemons
  foreground.
- `/proc/version` shows a synthetic `proot@termux` kernel; `/proc` & `/sys`
  are bind-mounted stubs (loadavg, stat, uptime, version, ...).
- No `CAP_SYS_ADMIN` / real namespaces → no nested containers, no `mount`
  of real filesystems, no systemd. Docker-in-Docker must stay disabled.
- Ports opened inside bind to the device's network namespace — reachable on
  device `localhost`; forward from a remote host as needed.
- Storage is limited on phones: `pd clear-cache` after pulls; pulls are gzip
  layers (~500MB) — prefer Wi-Fi.

## Safety

Always `pd backup npg` before reinstalling or heavy experiments. Keep
`TERM=xterm-256color`; never `--detach` an interactive TUI session.