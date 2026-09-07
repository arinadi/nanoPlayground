#!/usr/bin/env bash
# start-desktop.sh — headless desktop via native VNC for nanoPlayground.
#   Runs Xvfb + Openbox WM, shared over VNC with x11vnc. Connect with any
#   VNC client app (bVNC, RealVNC Viewer): host 127.0.0.1, port 5900,
#   no password.
#
#   Proot-optimized: no systemd/D-Bus here, non-root uid, tight memory, so:
#   loopback-only listener, private D-Bus session when available, light
#   default resolution, and readiness waits instead of fixed sleeps.
#
#   Usage:
#     start-desktop.sh                       # defaults (:1, 800x1280 portrait, VNC 5900)
#     DISPLAY_NUM=:2 VNC_PORT=5901 start-desktop.sh
#     RESOLUTION=1280x800x16 start-desktop.sh  # landscape
#
#   Access: 127.0.0.1:<VNC_PORT> with a VNC client (no password).
set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-:1}"
RESOLUTION="${RESOLUTION:-800x1280x16}"
VNC_PORT="${VNC_PORT:-5900}"
AUTH="${HOME}/.Xauthority"
DISP_NUM="${DISPLAY_NUM#:}"   # ":1" -> "1" for /tmp/.X11-unix/X1

cleanup() {
    echo "[desktop] shutdown..."
    for f in xvfb openbox x11vnc; do
        if [ -f "/tmp/${f}.pid" ]; then
            kill "$(cat "/tmp/${f}.pid")" 2>/dev/null || true
            rm -f "/tmp/${f}.pid"
        fi
    done
}
trap cleanup EXIT INT TERM

# --- preflight: desktop stack installed? (on-demand via desktop-install) ---
for b in Xvfb x11vnc openbox; do
    if ! command -v "$b" >/dev/null 2>&1; then
        echo "[desktop] ERROR: $b not found — run desktop-install first." >&2
        exit 1
    fi
done

# --- preflight (proot: no systemd, non-root uid) ---
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true
touch "${AUTH}"
# Drop dead PID files from a previous run.
for f in xvfb openbox x11vnc; do
    if [ -f "/tmp/${f}.pid" ] && ! kill -0 "$(cat "/tmp/${f}.pid")" 2>/dev/null; then
        rm -f "/tmp/${f}.pid"
    fi
done
# Fail fast if the port is already taken (e.g. old instance still up).
if python3 -c "import socket,sys; s=socket.create_connection(('127.0.0.1',int(sys.argv[1])),timeout=2); s.close()" "${VNC_PORT}" 2>/dev/null; then
    echo "[desktop] ERROR: port ${VNC_PORT} already in use — run stop-desktop.sh first." >&2
    exit 1
fi

# --- D-Bus: none under proot, give openbox a private session bus if possible ---
if command -v dbus-run-session >/dev/null 2>&1; then
    WM_CMD="dbus-run-session -- openbox"
else
    unset DBUS_SESSION_BUS_ADDRESS || true
    WM_CMD="openbox"
fi

echo "[desktop] starting Xvfb ${DISPLAY_NUM} (${RESOLUTION})"
Xvfb "${DISPLAY_NUM}" -screen 0 "${RESOLUTION}" -auth "${AUTH}" -nolisten tcp &
echo $! > /tmp/xvfb.pid
# Readiness wait: X socket instead of a fixed sleep.
for _ in $(seq 1 20); do
    [ -S "/tmp/.X11-unix/X${DISP_NUM}" ] && break
    sleep 0.5
done
[ -S "/tmp/.X11-unix/X${DISP_NUM}" ] || { echo "[desktop] ERROR: Xvfb socket missing" >&2; exit 1; }

export DISPLAY="${DISPLAY_NUM}"
echo "[desktop] starting openbox wm (${WM_CMD})"
${WM_CMD} &
echo $! > /tmp/openbox.pid
sleep 2

echo "[desktop] starting x11vnc on 127.0.0.1:${VNC_PORT}"
# -defer/-wait lowered from 20ms defaults: loopback link to AVNC is free,
# so trade a little CPU for snappier pointer response.
x11vnc -display "${DISPLAY}" -rfbport "${VNC_PORT}" \
    -localhost -forever -shared -threads -noxdamage -ncache 0 -nopw -quiet \
    -defer 10 -wait 10 &
echo $! > /tmp/x11vnc.pid
# Readiness wait: RFB banner instead of a fixed sleep.
BANNER=""
for _ in $(seq 1 30); do
    BANNER="$(python3 -c "import socket; s=socket.create_connection(('127.0.0.1',${VNC_PORT}),timeout=2); s.settimeout(2); print(repr(s.recv(32)))" 2>/dev/null || true)"
    [ -n "${BANNER}" ] && break
    sleep 0.5
done
[ -n "${BANNER}" ] || { echo "[desktop] ERROR: no RFB banner on :${VNC_PORT}" >&2; exit 1; }
echo "[desktop] VNC banner: ${BANNER}"

echo "[desktop] READY: 127.0.0.1:${VNC_PORT} (VNC client, no password)"
wait
