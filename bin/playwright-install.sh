#!/usr/bin/env bash
# playwright-install — fetch playwright's Firefox (with system deps) + symlink.
#
# The browser is intentionally NOT baked into the image: cdn.playwright.dev is
# flaky in CI (ECONNRESET / HTTP 400 / self-signed), so the build skips it.
# Run this once at runtime to make firefox available for crawl4ai/playwright
# and for the noVNC desktop. Idempotent and retried.
#
#   playwright-install            # install with system deps + retries
set -euo pipefail

export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/ms-playwright}"
mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"

install_one() {
    playwright install --with-deps firefox
}

attempts="${PLAYWRIGHT_INSTALL_ATTEMPTS:-5}"
for i in $(seq 1 "$attempts"); do
    if install_one; then
        bin="$(find "${PLAYWRIGHT_BROWSERS_PATH}" -maxdepth 2 -type f -name firefox 2>/dev/null | head -1)"
        if [ -n "$bin" ]; then
            ln -sf "$bin" /usr/local/bin/firefox
            echo "[playwright-install] firefox ready: $(readlink /usr/local/bin/firefox)"
        else
            echo "[playwright-install] installed but firefox binary not found under ${PLAYWRIGHT_BROWSERS_PATH}" >&2
        fi
        exit 0
    fi
    echo "[playwright-install] attempt ${i}/${attempts} failed; retrying in $((i*10))s..." >&2
    sleep "$((i * 10))"
done

echo "[playwright-install] failed after ${attempts} attempts" >&2
exit 1