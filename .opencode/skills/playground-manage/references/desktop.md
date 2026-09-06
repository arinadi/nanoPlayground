# Headless VNC desktop (references/desktop.md)

The image ships a headless X desktop for native VNC client apps:
**Xvfb → awesome → x11vnc** (loopback-only, no password).

- Shared playwright browsers: `/ms-playwright`.
- Firefox: `playwright-install` (installs playwright's firefox + creates the
  `/usr/local/bin/firefox` symlink). It is NOT baked at build — `cdn.playwright.dev`
  is flaky in CI — so run `playwright-install` once before first headed use.

## Start / stop

```bash
start-desktop.sh                 # defaults: :1, 800x1280x16 portrait, VNC 127.0.0.1:5900
stop-desktop.sh                  # idempotent, safe when already stopped
```

Connect a VNC client app (bVNC, RealVNC Viewer) to `127.0.0.1:5900`,
no password. bVNC offers a simulated-touchpad input mode.

## Tuning via env

```bash
DISPLAY_NUM=:2 RESOLUTION=1280x800x16 VNC_PORT=5901 start-desktop.sh
```

## Architecture / data flow

```
VNC app --(RFB 127.0.0.1:5900)--> x11vnc --> Xvfb :1 <-- awesome
```

Each component writes a PID file (`/tmp/{xvfb,awesome,x11vnc}.pid`)
and the helper's `cleanup()` traps EXIT/INT/TERM to stop them all.

## Headless browser automation (no desktop needed)

crawl4ai / playwright drive firefox **headless** and need no X. First make sure
the browser is present: `playwright-install` (retries the flaky CDN).

```bash
python3 - <<'PY'
import asyncio
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b = await p.firefox.launch()
        pg = await b.new_page(); await pg.goto("https://example.com")
        print(await pg.title()); await b.close()
asyncio.run(main())
PY
```

To *watch* an automation run headed, launch it on the VNC display:
`DISPLAY=:1 python3 ...` (with `headless=False` / crawl4ai `headless=False`).

## Troubleshooting

- **VNC app won't connect**: confirm `x11vnc` is up
  (`ps aux | rg x11vnc`), port 5900 free before start, exact host
  `127.0.0.1` + port `5900`, no password.
- **Black screen**: `awesome` didn't start on the display, or
  `x11vnc` lost the Xvfb auth. Restart `start-desktop.sh` with a fresh
  `RESOLUTION`/display.
- **"Failed to connect to bus"**: normal under proot/docker (no systemd PID1).
  Ignore; these are foreground daemons, not systemd services.
- **Port reachability from outside an Android host**: proot shares the device
  network namespace, so ports are reachable on device `localhost`. From a
  remote machine use Termux `adb reverse tcp:5900 tcp:5900` (or a port-forward).
- **Missing X auth**: helper points Xvfb at `${HOME}/.Xauthority`; ensure it
  exists or Xvfb starts with `-auth`. If `awesome` can't connect to the
  display, `export DISPLAY` matches `DISPLAY_NUM`.
