# just command runner (references/just.md)

`just` (casey/just) is a mature, fast command runner written in Rust — the
"make for humans" / one-shot task runner. It is NOT in the Ubuntu archive, so
nanoPlayground installs a static musl binary at `/usr/local/bin/just` (works
identically on Ubuntu and under proot — no kernel features needed).

## Recipes file: `justfile`

A `justfile` at the repo root defines named recipes. No install script / no
shell history needed to rerun tasks. Ideal for the agent to expose discoverable
tasks instead of forcing README greps.

```make
# ~/workspace/justfile
set shell := ["bash", "-cu"]

update:   # update system packages
    sudo apt-get update && sudo apt-get upgrade -y

lint:
    just --list

fmt py:
    python3 -m ruff format {{py}}

build: (deps compile)   # dependencies
    ./scripts/build.sh

deps:
    echo "installing deps"
```

## Core usage

```bash
just -l / just --list       # list recipes (the discoverable index)
just                          # run the default recipe (first one)
just update                  # run a named recipe
just fmt src/                # recipe with positional arg
just build                   # recipe with dependencies (runs `deps` first)
just --dry-run update        # print what it would run, don't execute
just --evaluate              # show variable values
```

## Notes for Ubuntu / proot

- Runs as a plain static binary — same behavior on Ubuntu, docker, and proot.
- Recipes are shell-agnostic; `just` executes each line with the shell set in
  `set shell` (default `sh`; use bash for bashisms).
- Keep user recipes in `$HOME`/`/workspace` (per the playground skill, user
  state stays in those dirs, system defaults stay read-only).
- For one-liners where `just` is overkill, `npg` still beats a full justfile;
  use `just` when the project has an actual set of repeatable tasks.