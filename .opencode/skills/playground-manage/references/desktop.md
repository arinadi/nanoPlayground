# Headless noVNC desktop (references/desktop.md)

The image ships a headless X desktop you can reach from a browser:
**Xvfb → awesome → x11vnc → websockify → noVNC**.

- noVNC client + static files: `/opt/novnc` (`vnc.html`).
- Shared playwright browsers: `/ms-playwright`.
- System firefox: `/usr/local/bin/firefox` (symlink → `/opt/firefox/firefox`).
- Helper: `/usr/local/bin/start-desktop.sh` (source in `bin/`).

## Start

```bash
start-desktop.sh                 # defaults: :1, 1440x900x24, VNC 5900, web 6080
```

Then open `http://<host>:6080/vnc.html` and click Connect.

## Tuning via env

```bash
DISPLAY_NUM=:2 RESOLUTION=1280x800x24 VNC_PORT=5901 WEB_PORT=6081 \
NOVNC_DIR=/opt/novnc start-desktop.sh
```

## Architecture / data flow

```
Browser --(WS :6080)--> websockify --> :5900 x11vnc --> Xvfb :1 <-- awesome
```

Each component writes a PID file (`/tmp/{xvfb,awesome,x11vnc,websockify}.pid`)
and the helper's `cleanup()` traps EXIT/INT/TERM to stop them all.

## Headless browser automation (no desktop needed)

crawl4ai / playwright drive firefox **headless** and need no X:

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

- **Web page won't load / connect**: confirm `websockify` & `x11vnc` are up
  (`ps aux | rg 'x11vnc|websockify'`), ports free, then check the exact
  `:WEB_PORT/vnc.html` URL.
- **Black screen in noVNC**: `awesome` didn't start on the display, or
  `x11vnc` lost the Xvfb auth. Restart `start-desktop.sh` with a fresh
  `RESOLUTION`/display.
- **"Failed to connect to bus"**: normal under proot/docker (no systemd PID1).
  Ignore; these are foreground daemons, not systemd services.
- **Port reachability from outside an Android host**: proot shares the device
  network namespace, so ports are reachable on device `localhost`. From a
  remote machine use Termux `adb reverse tcp:6080 tcp:6080` (or a port-forward).
- **Missing X auth**: helper points Xvfb at `${HOME}/.Xauthority`; ensure it
  exists or Xvfb starts with `-auth`. If `awesome` can't connect to the
  display, `export DISPLAY` matches `DISPLAY_NUM`.