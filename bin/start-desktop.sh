#!/usr/bin/env bash
# start-desktop.sh — headless desktop via noVNC for nanoPlayground.
#   Runs Xvfb + awesome WM, shares it with x11vnc, then bridges VNC -> browser
#   with websockify + the bundled noVNC client.
#
#   Usage:
#     start-desktop.sh                       # defaults (6080/5900, :1, 1440x900)
#     DISPLAY_NUM=:2 VNC_PORT=5901 WEB_PORT=6081 start-desktop.sh
#
#   Access: http://<host>:<WEB_PORT>/vnc.html
set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-:1}"
RESOLUTION="${RESOLUTION:-1440x900x24}"
VNC_PORT="${VNC_PORT:-5900}"
WEB_PORT="${WEB_PORT:-6080}"
NOVNC_DIR="${NOVNC_DIR:-/opt/novnc}"
AUTH="${HOME}/.Xauthority"

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

echo "[desktop] starting Xvfb ${DISPLAY_NUM} (${RESOLUTION})"
Xvfb "${DISPLAY_NUM}" -screen 0 "${RESOLUTION}" -auth "${AUTH}" &
echo $! > /tmp/xvfb.pid
sleep 1

export DISPLAY="${DISPLAY_NUM}"
echo "[desktop] starting awesome wm"
awesome &
echo $! > /tmp/awesome.pid
sleep 2

echo "[desktop] starting x11vnc on :${VNC_PORT}"
x11vnc -display "${DISPLAY}" -rfbport "${VNC_PORT}" \
    -forever -shared -noxdamage -nopw -quiet &
echo $! > /tmp/x11vnc.pid
sleep 1

echo "[desktop] starting websockify ${WEB_PORT} -> :${VNC_PORT} (web: ${NOVNC_DIR})"
websockify --web="${NOVNC_DIR}" "${WEB_PORT}" "localhost:${VNC_PORT}" &
echo $! > /tmp/websockify.pid
sleep 2

echo "[desktop] READY: http://<host>:${WEB_PORT}/vnc.html"
echo "[desktop] VNC port :${VNC_PORT}, web port :${WEB_PORT}"
wait