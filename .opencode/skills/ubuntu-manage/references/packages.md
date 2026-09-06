# apt packages (references/packages.md)

Ubuntu uses **apt/dpkg**. This is the go-to reference for package operations.

## Safe full update

```bash
sudo apt-get update
sudo apt-get upgrade -y          # normal package upgrades
sudo apt-get dist-upgrade -y     # kernel / major transitions (rarely needed)
```

## Install / search / remove

```bash
sudo apt-get install -y <pkg>            # install
apt-cache search <pattern>               # search repo packages
apt-cache policy <pkg>                   # repo version vs installed
dpkg -l <pkg>                            # installed? ("ii" first col)
apt list --installed | grep <pkg>        # confirm installed
sudo apt-get remove -y <pkg>             # remove (keep config)
sudo apt-get purge -y <pkg>              # remove + config
sudo apt-get autoremove -y               # drop unused deps
```

## Hold / unhold (pin a version)

```bash
sudo apt-mark hold <pkg>
sudo apt-mark unhold <pkg>
```

## Cache & logs

- Lists: `/var/lib/apt/lists/`; cache: `/var/cache/apt/archives/`.
- Never remove the whole `/var/lib/apt/lists` in a running system — it is
  rebuilt by `apt-get update`.

## Docs

- https://manpages.ubuntu.com/manpages/noble/en/man8/apt.8.html
- https://help.ubuntu.com/community/AptGet/Howto