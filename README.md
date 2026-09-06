# nanoPlayground

> **Instant, Fun & Agentic Playground for AI coding agents.**
> The disposable playground for the age of agents — spin it up, vibe through
> every task, throw it away.
>
> `docker run -it --rm ghcr.io/arinadi/nanoplayground` — straight into the
> TUI, no `-v` / `-e` required.

A ready-to-run Docker image: one `docker run` drops you into the
[Agent of Empires (aoe)](https://www.agent-of-empires.com/) TUI with
**Claude Code** and **OpenCode** preinstalled. Skills, MCPs, and providers
are managed through `aoe` itself (press `m` for MCP, see each agent's docs
for skills/providers) — no manual config-file editing needed.

The container runs as the **non-root user `admin`**, not root. Docker
sandboxing (the `aoe` feature that spawns containers *inside* the container)
is **disabled by default** via `config/aoe-config.toml` — ideal for proot
environments, where there is usually no Docker/Podman daemon at all.

## Use from GHCR (no build)

```bash
docker run -it --rm ghcr.io/arinadi/nanoplayground
```

It runs with zero params: config dirs are created automatically, a missing
`ANTHROPIC_API_KEY` is just a warning. Without `-it` (e.g. in CI), the
container prints versions and exits 0 instead of hanging in the TUI.

Optional persistence — add when you need it:

```bash
docker run -it --rm \
  -v "$PWD:/workspace" \
  -v nano-claude:/home/admin/.claude \
  -v nano-opencode:/home/admin/.config/opencode \
  -v nano-aoe:/home/admin/.agent-of-empires \
  -e ANTHROPIC_API_KEY \
  ghcr.io/arinadi/nanoplayground
```

> GHCR images are always lowercase: `ghcr.io/arinadi/nanoplayground`.

## Build

Single base: **Void Linux glibc-full** (rolling, small, `glibc` so the `aoe`
binary with its glibc >= 2.28 requirement runs).

Match `USER_UID`/`USER_GID` to your host user (`id -u` / `id -g`) so files
created through the `/workspace` bind-mount aren't owned by a foreign UID
you can only touch via `sudo`:

```bash
docker build \
  --build-arg USER_UID=$(id -u) \
  --build-arg USER_GID=$(id -g) \
  -t nanoplayground .
```

If your host `id -u` is `0` (e.g. proot, which always acts as root), keeping
the default `USER_UID=1000` is fine — the container stays non-root, only the
UID on /workspace is 1000, which you access from the host as root anyway.

## Run

```bash
docker run -it --rm \
  -v "$PWD:/workspace" \
  -v "$HOME/.claude:/home/admin/.claude" \
  -v "$HOME/.config/opencode:/home/admin/.config/opencode" \
  -v "$HOME/.agent-of-empires:/home/admin/.agent-of-empires" \
  -e ANTHROPIC_API_KEY \
  nanoplayground
```

Mounts explained:

| Host path                     | Purpose                                           |
| ------------------------------ | ------------------------------------------------- |
| `$PWD` -> `/workspace`         | Project the agent works on                        |
| `~/.claude`                    | Claude Code credentials & history, persists       |
| `~/.config/opencode`           | OpenCode config & providers, persists             |
| `~/.agent-of-empires`          | `aoe` config (sessions, profiles), persists       |

Without the config mounts above, every `docker run` means logging in /
setting up providers from scratch. Mount once, then edit config through the
`aoe` / `claude` / `opencode` TUI menus as usual — it sticks on the host.

> If the host dirs (`~/.claude` etc.) don't exist yet / are empty and owned
> by root from an earlier attempt, run
> `sudo chown -R $(id -u):$(id -g) ~/.claude ~/.config/opencode ~/.agent-of-empires`
> on the host first so the `admin` user inside the container can write there.

### Auto-run TUI

Empty default `CMD` -> the entrypoint `exec`s `aoe` directly, so you land in
the TUI as soon as the container starts. No manual attach/exec needed.

### Helper CLI `npg` (token-saving, accurate)

Neither you nor the agent needs to memorize `xbps`/`sv`. One API:

```bash
npg commands --json   # discover every command
npg sys info          # OS, PID1, tool versions, services — 1 call
npg pkg search htop
npg pkg add htop ripgrep   # idempotent batch, 1 transaction
npg pkg update             # correct two-phase full update
npg svc status
npg svc enable sshd
npg skills sync            # install skills into every agent harness
```

`npg` refuses to run on non-Void systems so the agent can't misfire on the
host.

### Agent toolbox (baked in)

Beyond `rg`/`fzf`/`git`, every container ships proven agent tools:

| Tool | Why | Invoke |
|---|---|---|
| `rtk` | Compresses shell output before the LLM reads it (up to 90% less bash output); pre-registered for Claude Code + OpenCode | `rtk gain`, or just run commands — the hook rewrites them |
| `ast-grep` | Structural code search (`function $NAME($$$)`), 25+ langs | `ast-grep -p 'pattern' --lang ts` |
| `gh` | PRs/issues/checks without scraping the web UI (needs `GH_TOKEN`) | `gh pr view 42`, `gh issue list` |
| `jq` / `yq` | Slice JSON/YAML instead of catting whole files | `jq '.items[:5]'`, `yq -y . file.yaml` |
| `fd` / `bat` / `eza` / `delta` | Cleaner `find`/`cat`/`ls`/`diff` = fewer tokens | `fd`, `bat file`, `eza`, `git config --global core.pager delta` |
| `just` | Discoverable tasks via `just -l`, no README grep | `just -l` |
| `ctags` | Zero-daemon symbol index | `ctags -R` |
| `trafilatura` | Web page → clean text, keyless | `trafilatura -u <URL>` |
| `sqlite3` | Local data work | `sqlite3 db.sqlite` |

Deliberately **not** baked (heavy or key-gated, use on demand): `crawl4ai`
+ Chromium, `pandoc`, full Playwright browsers, `repomix`
(`npx -y repomix --compress`), Tavily/Firecrawl (API keys via env, never in
the image).

### Built-in agent skills

The `void-manage` skill is baked into `/usr/share/nanoplayground/skills/`
and auto-synced on every container start into `~/.agents/skills/`,
`~/.claude/skills/`, `~/.codex/skills/`, `~/.config/opencode/skills/`
(Omarchy-style symlink pattern). In this repo the source lives in
`.opencode/skills/` — add a new skill there, no installer code changes
needed.

### Extra packages at runtime?

User `admin` is in sudoers with no password:

```bash
npg pkg add <package>        # preferred way (idempotent + verified)
# or raw:
sudo xbps-install -Sy <package>
```

If you don't want the container to have sudo access at all, remove the
`sudoers.d` line from the Dockerfile.

### Web dashboard (optional, experimental)

```bash
docker run -it --rm \
  -p 4200:4200 \
  -e AOE_WEB=1 \
  ... \
  nanoplayground
```

The entrypoint **tries** several candidate sub-commands (`aoe serve`,
`aoe session serve`, `aoe web`) and uses the first valid one for the `aoe`
version installed at build time. If none match (sub-command renamed again in
a new release), the error tells you to check `aoe --help` manually — run:

```bash
docker exec -it <container_id> aoe --help
```

to see the correct web dashboard sub-command for that version, then adjust
`entrypoint.sh` if needed.

### Running under proot

Since `[sandbox] enabled_by_default = false`, `aoe` never touches the Docker
socket unless you explicitly pass `--sandbox` / `--sandbox-image`. Running
under proot (no Docker daemon inside) is safe.

### Termux proot-distro

```bash
pd install ghcr.io/arinadi/nanoplayground -n npg
pd run npg --user admin     # main TUI (needs an interactive Termux session)
pd login npg --user admin   # shell / debugging
```

Notes from the proot trenches:

- `pd login` defaults to **root** and ignores the image `USER` — always pass
  `--user admin` so `HOME`, skills, `rtk` state, and npm bins resolve to
  `/home/admin`.
- Keep `TERM=xterm-256color` from Termux; never `--detach` a TUI session.
  If `tmux` breaks after heavy shell work, open a fresh Termux session.
- Storage hygiene on phones: `pd backup npg -o npg.tar.xz` before
  experiments, `pd clear-cache` after pulls. Pulls are gzip layers
  (~500MB) — prefer Wi-Fi.

## Version notes

- The `aoe` binary needs **glibc >= 2.28** (floor of `manylinux_2_28`).
  Void glibc-full is far above that.
- Need extra tools (Python, Rust, etc. — like the official AoE "dev
  sandbox")? Just add `RUN xbps-install ...`
  to the Dockerfile, before the `USER ${USERNAME}` line.
