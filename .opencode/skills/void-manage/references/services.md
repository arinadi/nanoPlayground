# runit services (references/services.md)

Void uses **runit**, not systemd. There is no `systemctl`.

```sh
ls /etc/sv/                      # available services
ls -l /var/service/              # enabled (= symlinks)
sv status <svc>                  # or: sv status /var/service/*
sv up|down|restart|once|check <svc>

# Enable + start (booted Void VM)
sudo ln -s /etc/sv/<svc> /var/service/
# Disable + stop
sudo rm /var/service/<svc>
# Enable at image-build time (offline, no running runsvdir)
sudo ln -s /etc/sv/<svc> /etc/runit/runsvdir/default/
# Keep enabled but don't auto-start
sudo touch /etc/sv/<svc>/down
```

Service config lives in `/etc/sv/<svc>/conf` (`OPTS=...`). Never edit
`/etc/sv/<svc>/run` in place — package updates overwrite it.

## Container limit (nanoPlayground)

PID 1 here is `entrypoint.sh`, NOT runit, so `runsvdir` isn't supervising
and `sv up/down/status` fails. That is expected. Instead:

- Bake enablement for real-VM boots via the `default/` symlink above.
- Run daemons foreground in-container: `sshd -D`, `/etc/sv/<svc>/run`,
  or the daemon binary directly. Don't wait for `sv`.

Check: `ps -p 1 -o comm=` (expect `entrypoint.sh`, not `runit`).

Docs: `https://docs.voidlinux.org/config/services/index.html`
