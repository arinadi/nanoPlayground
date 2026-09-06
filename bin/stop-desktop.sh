#!/usr/bin/env bash
# stop-desktop.sh — stop the headless VNC desktop started by start-desktop.sh.
#   Kills Xvfb + awesome (+ dbus-run-session wrapper) + x11vnc
#   via their /tmp PID files. Safe to run when already stopped.
#
#   Usage:
#     stop-desktop.sh
set -euo pipefail

stopped=0
for f in x11vnc awesome xvfb; do
    pidfile="/tmp/${f}.pid"
    if [ ! -f "${pidfile}" ]; then
        echo "[desktop] ${f}: not running (no pid file)"
        continue
    fi
    pid="$(cat "${pidfile}")"
    if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
        # Wait up to ~5s for it to exit.
        for _ in $(seq 1 10); do
            kill -0 "${pid}" 2>/dev/null || break
            sleep 0.5
        done
        if kill -0 "${pid}" 2>/dev/null; then
            echo "[desktop] ${f} (${pid}): still alive, sending KILL"
            kill -9 "${pid}" 2>/dev/null || true
        else
            echo "[desktop] ${f} (${pid}): stopped"
        fi
        stopped=1
    else
        echo "[desktop] ${f} (${pid}): already dead, cleaning pid file"
    fi
    rm -f "${pidfile}"
done

if [ "${stopped}" = "0" ]; then
    echo "[desktop] nothing was running"
else
    echo "[desktop] all stopped"
fi
