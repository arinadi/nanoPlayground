# systemd services (references/services.md)

Ubuntu uses **systemd**, not runit. There is no `sv`.

## Enable + start (booted Ubuntu VM)

```bash
sudo systemctl enable --now <svc>   # enable + start in one shot
sudo systemctl status <svc>
sudo systemctl restart <svc>
sudo systemctl disable <svc>
```

## Container / proot caveat

PID 1 here is `entrypoint.sh`, NOT systemd, so `systemctl start` / `enable`
fail cleanly ("Failed to connect to bus"). That is expected inside
nanoPlayground. Options:

- Bake enablement by dropping a symlink/unit and let the host start it.
- Run the daemon foreground: `npg svc run <svc>` or the binary directly
  (e.g. `sshd -D`, `nginx -g 'daemon off;'`).
- Overrides go in `/etc/systemd/system/<svc>.d/override.conf`, never edit
  `/lib/systemd/system/<svc>` in place.

Check PID 1: `ps -p 1 -o comm=` (expect `entrypoint.sh`, not `systemd`).