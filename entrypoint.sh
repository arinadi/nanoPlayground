#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# nanoPlayground entrypoint
#
# Perilaku default (docker run -it image):
#   -> langsung buka TUI `aoe`, tidak ada Docker sandbox yang dibuat
#      (lihat /root/.agent-of-empires/config.toml -> enabled_by_default=false)
#
# Web dashboard (AoE menyebutnya "experimental"):
#   AoE punya web dashboard, tapi nama sub-command persisnya berubah-ubah
#   antar rilis (pernah `aoe serve`, ada juga build yang expose via
#   `aoe session serve` / daemon terpisah). Supaya image ini tidak
#   hardcode command yang mungkin sudah usang, entrypoint ini MENCOBA
#   beberapa kandidat command dan pakai yang pertama valid.
#
#   Set AOE_WEB=1 saat docker run untuk mengaktifkan percobaan ini.
#   Kalau tidak ada satupun yang cocok, entrypoint akan bilang jelas
#   dan menyarankan cek `aoe --help` manual di dalam container.
#
# Zero-params: `docker run ghcr.io/<owner>/nanoplayground` langsung jalan
# tanpa -v / -e. Config dir dibuat otomatis, API key yang hilang hanya
# warning (bukan gagal).
# ----------------------------------------------------------------------------

# --- Defaults agar jalan tanpa -v / -e --------------------------------------
mkdir -p "${HOME}/.claude" "${HOME}/.config/opencode" \
    "${HOME}/.agent-of-empires" /workspace 2>/dev/null || true

# Sync skill bawaan ke home user (idempoten, murah). Penting bila home
# di-mount dari host sehingga symlink saat build tidak terbawa.
if command -v npg >/dev/null 2>&1; then
    npg skills sync >/dev/null 2>&1 || true
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "[nanoPlayground] ANTHROPIC_API_KEY kosong — Claude Code akan minta login/API key di dalam TUI."
fi

WEB_PORT="${AOE_WEB_PORT:-4200}"

try_start_web() {
    local candidates=(
        "aoe serve --host 0.0.0.0 --port ${WEB_PORT}"
        "aoe session serve --host 0.0.0.0 --port ${WEB_PORT}"
        "aoe web --host 0.0.0.0 --port ${WEB_PORT}"
    )
    for cmd in "${candidates[@]}"; do
        # cek subcommand-nya beneran ada (help-nya sukses) sebelum dieksekusi
        # shellcheck disable=SC2086
        if $cmd --help >/dev/null 2>&1; then
            echo "[nanoPlayground] Menjalankan web dashboard: ${cmd} &"
            # shellcheck disable=SC2086
            $cmd &
            return 0
        fi
    done
    echo "[nanoPlayground] Tidak menemukan sub-command web dashboard yang cocok."
    echo "[nanoPlayground] Cek manual di dalam container dengan: aoe --help"
    return 1
}

if [ "${AOE_WEB:-0}" = "1" ]; then
    try_start_web || true
fi

# Kalau user override CMD (misal: docker run image bash, atau image claude),
# jalankan itu apa adanya. Kalau tidak ada argumen sama sekali -> buka TUI.
# Tanpa TTY (misal docker run tanpa -it di CI), jangan force TUI yang akan
# hang — tampilkan versi + cara pakai lalu exit 0.
if [ "$#" -eq 0 ]; then
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[nanoPlayground] jalan tanpa TTY — lewati TUI."
        echo "Gunakan: docker run -it --rm <image>  untuk TUI interaktif."
        aoe --version 2>/dev/null || true
        claude --version 2>/dev/null || true
        opencode --version 2>/dev/null || true
        exit 0
    fi
    exec aoe
else
    exec "$@"
fi
