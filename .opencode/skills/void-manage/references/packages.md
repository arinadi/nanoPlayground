# XBPS packages (references/packages.md)

All commands as `admin` (NOPASSWD sudo) unless noted.

```sh
# Safe full update — xbps itself first (official Void pattern)
sudo xbps-install -Suy xbps && sudo xbps-install -Suy

# Install + verify
sudo xbps-install -Sy <pkg> && xbps-query -S <pkg>

# Search (repos need a prior -S sync)
xbps-query -Rs <pattern> | head -20
xbps-query -s <pattern>          # installed only
xbps-query -RS <pkg>             # repo metadata (version/desc/deps)
xbps-query -f <pkg>              # files owned by pkg
xbps-query -l | grep <pkg>       # confirm installed

# Reinstall / reconfigure
sudo xbps-install -f <pkg>
sudo xbps-reconfigure -fa

# Remove + slim (image builds)
sudo xbps-remove <pkg>
sudo xbps-remove -R <pkg>        # + unused deps
sudo xbps-remove -Oo -y          # orphans + cache (used in Dockerfile)

# Hold / unhold
sudo xbps-pkgdb -m hold <pkg>
sudo xbps-pkgdb -m unhold <pkg>
```

Extras: `xtools` provides `xpkg`, `xlocate`, `xcheckrestart`, `xdowngrade`.
XBPS never restarts services on update — restart manually
(`sudo xbps-install -y xtools && xcheckrestart`).

Repos: `/usr/share/xbps.d/*.conf`; `nonfree`/`restricted` are opt-in.
Cache `/var/cache/xbps/`, DB `/var/db/xbps/`.
Docs: `https://docs.voidlinux.org/xbps/index.html`
