#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# nanoPlayground entrypoint
#
# START POLICY (only the TUI auto-starts):
#   * On `docker run` / `proot-distro` the ONLY thing that auto-starts is the
#     interactive `aoe` TUI (see below).
#   * The aoe WEB dashboard does NOT auto-start; it is opt-in via AOE_WEB=1.
#   * The VNC desktop (Xvfb/awesome/x11vnc) is NEVER auto-started;
#     run `start-desktop.sh` manually when you want it, then connect a
#     VNC client app to 127.0.0.1:5900 (no password).
#
# Default behavior (docker run -it image):
#   -> open the `aoe` TUI right away, no Docker sandbox is created
#      (see /root/.agent-of-empires/config.toml -> enabled_by_default=false)
#
# Web dashboard (AoE calls it "experimental"):
#   AoE ships a web dashboard, but the exact sub-command name changes
#   between releases (seen `aoe serve`, also builds exposing it via
#   `aoe session serve` / a separate daemon). So this image doesn't
#   hardcode a command that may already be outdated — the entrypoint TRIES
#   several candidate commands and uses the first valid one.
#
#   Set AOE_WEB=1 on docker run to enable this attempt.
#   If none match, the entrypoint says so clearly
#   and suggests checking `aoe --help` manually inside the container.
#
# Zero-params: `docker run ghcr.io/arinadi/nanoplayground` just works
# without -v / -e. Config dirs are created automatically, a missing API key
# is only a warning (not a failure).
# ----------------------------------------------------------------------------

# --- Defaults so it runs without -v / -e -------------------------------------
mkdir -p "${HOME}/.claude" "${HOME}/.config/opencode" \
    "${HOME}/.agent-of-empires" /workspace 2>/dev/null || true

# Sync built-in skills into the user home (idempotent, cheap). Matters when
# home is mounted from the host so build-time symlinks don't carry over.
if command -v npg >/dev/null 2>&1; then
    npg skills sync >/dev/null 2>&1 || true
fi

# Register rtk shell-output compression for this home (idempotent,
# non-interactive). Matters when home is mounted from the host.
if command -v rtk >/dev/null 2>&1; then
    rtk init -g --auto-patch >/dev/null 2>&1 || true
    rtk init -g --opencode --auto-patch >/dev/null 2>&1 || true
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "[nanoPlayground] ANTHROPIC_API_KEY is empty — Claude Code will ask for login/API key inside the TUI."
fi

if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "[nanoPlayground] GH_TOKEN is empty — 'gh' works for public repos only (authenticated calls need it)."
fi

WEB_PORT="${AOE_WEB_PORT:-4200}"

try_start_web() {
    local candidates=(
        "aoe serve --host 0.0.0.0 --port ${WEB_PORT}"
        "aoe session serve --host 0.0.0.0 --port ${WEB_PORT}"
        "aoe web --host 0.0.0.0 --port ${WEB_PORT}"
    )
    for cmd in "${candidates[@]}"; do
        # only proceed if the subcommand really exists (its help succeeds)
        # shellcheck disable=SC2086
        if $cmd --help >/dev/null 2>&1; then
            echo "[nanoPlayground] Starting web dashboard: ${cmd} &"
            # shellcheck disable=SC2086
            $cmd &
            return 0
        fi
    done
    echo "[nanoPlayground] No matching web dashboard sub-command found."
    echo "[nanoPlayground] Check manually inside the container with: aoe --help"
    return 1
}

if [ "${AOE_WEB:-0}" = "1" ]; then
    try_start_web || true
fi

# If the user overrides CMD (e.g. docker run image bash, or image claude),
# run it as-is. With no arguments at all -> open the TUI.
# Without a TTY (e.g. docker run without -it in CI), don't force a TUI that
# would hang — print versions + usage, then exit 0.
if [ "$#" -eq 0 ]; then
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[nanoPlayground] running without a TTY — skipping TUI."
        echo "Use: docker run -it --rm <image>  for the interactive TUI."
        aoe --version 2>/dev/null || true
        claude --version 2>/dev/null || true
        opencode --version 2>/dev/null || true
        exit 0
    fi
    exec aoe
else
    exec "$@"
fi
