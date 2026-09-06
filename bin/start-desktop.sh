#!/usr/bin/env bash
# start-desktop.sh — headless desktop via noVNC for nanoPlayground.
#   Runs Xvfb + awesome WM, shares it with x11vnc, then bridges VNC -> browser
#   with websockify + the bundled noVNC client.
#
#   Proot-optimized: no systemd/D-Bus here, non-root uid, tight memory, so:
#   local-only listeners, private D-Bus session when available, light default
#   resolution, and readiness waits instead of fixed sleeps.
#
#   Usage:
#     start-desktop.sh                       # defaults (6080/5900, :1, 800x1280 portrait)
#     DISPLAY_NUM=:2 VNC_PORT=5901 WEB_PORT=6081 start-desktop.sh
#     RESOLUTION=1280x800x16 start-desktop.sh  # landscape
#     RESOLUTION=1440x900x24 start-desktop.sh  # old large landscape
#
#   Access: http://<host>:<WEB_PORT>/vnc.html
set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-:1}"
RESOLUTION="${RESOLUTION:-800x1280x16}"
VNC_PORT="${VNC_PORT:-5900}"
WEB_PORT="${WEB_PORT:-6080}"
NOVNC_DIR="${NOVNC_DIR:-/opt/novnc}"
AUTH="${HOME}/.Xauthority"
DISP_NUM="${DISPLAY_NUM#:}"   # ":1" -> "1" for /tmp/.X11-unix/X1

cleanup() {
    echo "[desktop] shutdown..."
    for f in xvfb awesome x11vnc websockify; do
        if [ -f "/tmp/${f}.pid" ]; then
            kill "$(cat "/tmp/${f}.pid")" 2>/dev/null || true
            rm -f "/tmp/${f}.pid"
        fi
    done
}
trap cleanup EXIT INT TERM

# --- preflight (proot: no systemd, non-root uid) ---
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true
touch "${AUTH}"
# Drop dead PID files from a previous run.
for f in xvfb awesome x11vnc websockify; do
    if [ -f "/tmp/${f}.pid" ] && ! kill -0 "$(cat "/tmp/${f}.pid")" 2>/dev/null; then
        rm -f "/tmp/${f}.pid"
    fi
done
# Fail fast if the ports are already taken (e.g. old instance still up).
for p in "${VNC_PORT}" "${WEB_PORT}"; do
    if python3 -c "import socket,sys; s=socket.create_connection(('127.0.0.1',int(sys.argv[1])),timeout=2); s.close()" "$p" 2>/dev/null; then
        echo "[desktop] ERROR: port $p already in use — stop the old instance first." >&2
        exit 1
    fi
done

# --- D-Bus: none under proot, give awesome a private session bus if possible ---
if command -v dbus-run-session >/dev/null 2>&1; then
    WM_CMD="dbus-run-session -- awesome"
else
    unset DBUS_SESSION_BUS_ADDRESS || true
    WM_CMD="awesome"
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
echo "[desktop] starting awesome wm (${WM_CMD})"
${WM_CMD} &
echo $! > /tmp/awesome.pid
sleep 2

echo "[desktop] starting x11vnc on 127.0.0.1:${VNC_PORT}"
x11vnc -display "${DISPLAY}" -rfbport "${VNC_PORT}" \
    -localhost -forever -shared -threads -noxdamage -ncache 0 -nopw -quiet &
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

echo "[desktop] starting websockify 127.0.0.1:${WEB_PORT} -> 127.0.0.1:${VNC_PORT} (web: ${NOVNC_DIR})"
websockify --heartbeat 30 --web="${NOVNC_DIR}" "127.0.0.1:${WEB_PORT}" "127.0.0.1:${VNC_PORT}" &
echo $! > /tmp/websockify.pid
# Readiness wait: HTTP 200 instead of a fixed sleep.
for _ in $(seq 1 30); do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${WEB_PORT}/vnc.html" 2>/dev/null || true)"
    [ "${CODE}" = "200" ] && break
    sleep 0.5
done
[ "${CODE}" = "200" ] || { echo "[desktop] ERROR: websockify not serving :${WEB_PORT}" >&2; exit 1; }

echo "[desktop] READY: http://<host>:${WEB_PORT}/vnc.html"
echo "[desktop] VNC port :${VNC_PORT} (loopback only), web port :${WEB_PORT} (loopback)"
wait
