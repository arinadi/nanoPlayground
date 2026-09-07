#!/usr/bin/env bash
# desktop-install — install the headless VNC desktop stack on demand.
#
# The VNC stack (Xvfb, xauth, x11vnc, Openbox, xterm) is intentionally NOT
# baked into the image: X11 libraries cost roughly 50-120MB. Run once per
# container when you need a GUI; afterwards start it with `start-desktop.sh`.
#
#   desktop-install
#
# Idempotent: skips packages already installed. Uses sudo when not root
# (the image's `admin` user has NOPASSWD sudo). Targets the container —
# refuses clearly where apt-get does not exist (e.g. proot hosts).
set -euo pipefail

PKGS=(xvfb xauth x11vnc openbox xterm)

missing=()
for p in "${PKGS[@]}"; do
    if dpkg -l 2>/dev/null | grep -q "^ii  $p "; then
        echo "[desktop-install] $p: already installed"
    else
        missing+=("$p")
    fi
done

if [ "${#missing[@]}" -eq 0 ]; then
    echo "[desktop-install] desktop stack present; next: start-desktop.sh"
    exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "[desktop-install] ERROR: apt-get not found — run this inside the container, not on the host." >&2
    exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

echo "[desktop-install] installing missing: ${missing[*]}"
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends "${missing[@]}"
$SUDO apt-get clean
$SUDO rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/apt/

for b in Xvfb x11vnc openbox xterm; do
    command -v "$b" >/dev/null 2>&1 || { echo "[desktop-install] verification failed: $b" >&2; exit 1; }
done
echo "[desktop-install] ready; next: start-desktop.sh"
