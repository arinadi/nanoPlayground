# aoe session manager (references/aoe.md)

`aoe` (Agent of Empires) is a tmux-based session manager that launches and
supervises AI coding agents (Claude Code, OpenCode). Read on demand; the
top-level commands live in the skill front-matter.

## Two run modes

| Mode | Command | When |
|---|---|---|
| Interactive TUI | `aoe` (no args) | real terminal / TTY |
| Daemon + web dashboard | `aoe serve` (+ `AOE_WEB=1`), then `aoe url` | headless / remote |

The entrypoint starts a web dashboard only when `AOE_WEB=1`; it tries
`aoe serve`, then `aoe session serve`, then `aoe web` and uses the first that
supports `--help`. Port: `AOE_WEB_PORT` (default 4200). If none match (new aoe
version), check `aoe --help` and adjust `entrypoint.sh`.

## Sessions

```bash
aoe add                                  # create a new session
aoe session start <name>                 # start tmux process
aoe session stop <name>                  # stop
aoe session restart <name>               # restart one
aoe session restart --all                # restart every session
aoe session attach <name>                # attach interactively
aoe session show <name>                  # details
aoe session current                      # auto-detect current session
aoe session capture <name>               # dump pane output (non-interactive)
aoe send <name> "do the thing"           # message a running agent
aoe session archive|unarchive <name>     # tidy without full delete
aoe session snooze|unsnooze <name>       # pause / wake
```

## Monitor

```bash
aoe ps                                   # in-flight sessions, one row each
aoe status                               # session status summary
aoe list                                 # all sessions
aoe logs                                 # pretty log viewer
aoe log-level debug                      # raise logging (ephemeral)
```

## Stop everything

`aoe killall` force-stops the serve daemon, all agent workers, and all aoe
tmux sessions. Destructive + unprompted — prefer targeted stop/restart first.

## Config, profile & sandbox

- Per-repo defaults come from `.agent-of-empires/config.toml`. The image
  default disables the docker-in-docker sandbox:
  ```toml
  [sandbox]
  enabled_by_default = false
  [session]
  yolo_mode_default = false
  ```
- Profiles separate workspaces: `-p <profile>` / `AGENT_OF_EMPIRES_PROFILE`.
- Never enable the sandbox under proot — there is no Docker/Podman daemon.

## Misc

`aoe agents` (install status), `aoe skill` (agent skills), `aoe mcp`
(MCP provenance/conflicts), `aoe profile`, `aoe theme`, `aoe settings`,
`aoe update`, `aoe uninstall`, `aoe completion`.

## If aoe misbehaves after an upgrade

Check `aoe --help` for renamed subcommands, then fix `entrypoint.sh` if the
web-dashboard candidate list is stale.