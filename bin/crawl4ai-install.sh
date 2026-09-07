#!/usr/bin/env bash
# crawl4ai-install — fetch playwright + crawl4ai pip packages on demand.
#
# These are intentionally NOT baked into the image: together they pull a huge
# transitive tree (playwright lib, lxml, html parsers, async stack, pydantic)
# worth hundreds of MB. Run this once at runtime when you need browser
# automation; afterwards run `playwright-install` once for the Firefox binary.
#
#   crawl4ai-install              # pip install playwright + crawl4ai, retried
#
# Idempotent: skips packages whose import already works. Uses --no-cache-dir
# so no pip cache lands in the container layer. Needs network + the image's
# build tools (gcc/python3-dev) for any dep without a wheel.
set -euo pipefail

need_pkg() {
    python3 -c "import ${1}" 2>/dev/null
}

install_pkgs() {
    pip3 install --no-cache-dir --no-compile playwright crawl4ai \
        && find /usr/lib/python* /usr/local/lib/python* -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true \
        && rm -rf "${HOME}/.cache/pip" /tmp/* /var/tmp/* 2>/dev/null || true
}

missing=()
for mod in playwright crawl4ai; do
    if need_pkg "$mod"; then
        echo "[crawl4ai-install] $mod: already installed"
    else
        missing+=("$mod")
    fi
done

if [ "${#missing[@]}" -eq 0 ]; then
    echo "[crawl4ai-install] everything present; next: playwright-install (firefox binary)"
    exit 0
fi

echo "[crawl4ai-install] installing missing: ${missing[*]}"
attempts="${CRAWL4AI_INSTALL_ATTEMPTS:-3}"
for i in $(seq 1 "$attempts"); do
    if install_pkgs; then
        if need_pkg playwright && need_pkg crawl4ai; then
            echo "[crawl4ai-install] ready; next: playwright-install (firefox binary)"
            exit 0
        fi
        echo "[crawl4ai-install] install ran but imports still fail" >&2
        exit 1
    fi
    echo "[crawl4ai-install] attempt ${i}/${attempts} failed; retrying in $((i*10))s..." >&2
    sleep "$((i * 10))"
done

echo "[crawl4ai-install] failed after ${attempts} attempts" >&2
exit 1
