# nanoPlayground

> `docker run -it --rm ghcr.io/arinadi/nanoplayground` — langsung masuk TUI,
> tanpa `-v` / `-e` wajib.

Docker image siap pakai: begitu `docker run`, langsung masuk TUI [Agent of
Empires (aoe)](https://www.agent-of-empires.com/) dengan **Claude Code** dan
**OpenCode** sudah terpasang. Skill, MCP, dan provider dikelola lewat menu
`aoe` sendiri (tekan `m` untuk MCP, lihat dokumentasi per-agent untuk
skill/provider), jadi tidak perlu edit file config manual lagi.

Container jalan sebagai **user non-root `admin`**, bukan root. Docker
sandbox (fitur `aoe` yang membuat container *di dalam* container) juga
**dimatikan secara default** lewat `config/aoe-config.toml` — cocok untuk
dijalankan di proot, di mana biasanya tidak ada Docker/Podman daemon sama
sekali.

## Pakai dari GHCR (tanpa build)

```bash
docker run -it --rm ghcr.io/arinadi/nanoplayground
```

Tanpa params pun jalan: config dir dibuat otomatis, `ANTHROPIC_API_KEY`
yang kosong cuma warning. Tanpa `-it` (misal di CI), container cetak versi
lalu exit 0 alih-alih hang di TUI.

Persistensi opsional — tambah kalau perlu:

```bash
docker run -it --rm \
  -v "$PWD:/workspace" \
  -v nano-claude:/home/admin/.claude \
  -v nano-opencode:/home/admin/.config/opencode \
  -v nano-aoe:/home/admin/.agent-of-empires \
  -e ANTHROPIC_API_KEY \
  ghcr.io/arinadi/nanoplayground
```

> Image GHCR selalu lowercase: `ghcr.io/arinadi/nanoplayground`.

## Build

Base tunggal: **Void Linux glibc-full** (rolling, kecil, `glibc` agar binary
`aoe` yang butuh glibc >= 2.28 jalan).

Samakan `USER_UID`/`USER_GID` dengan user host kamu (`id -u` / `id -g`)
supaya file yang dibuat lewat bind-mount `/workspace` tidak jadi milik UID
asing yang cuma bisa diutak-atik lewat `sudo`:

```bash
docker build \
  --build-arg USER_UID=$(id -u) \
  --build-arg USER_GID=$(id -g) \
  -t nanoplayground .
```

Kalau `id -u` kamu di host adalah `0` (misal proot yang selalu bertindak
sebagai root), tetap boleh pakai default `USER_UID=1000` — container-nya
tetap non-root, cuma UID di /workspace jadi 1000 dan kamu akses lewat host
sebagai root biasa.

## Run

```bash
docker run -it --rm \
  -v "$PWD:/workspace" \
  -v "$HOME/.claude:/home/admin/.claude" \
  -v "$HOME/.config/opencode:/home/admin/.config/opencode" \
  -v "$HOME/.agent-of-empires:/home/admin/.agent-of-empires" \
  -e ANTHROPIC_API_KEY \
  nanoplayground
```

Penjelasan mount:

| Host path                     | Guna                                                |
| ------------------------------ | ---------------------------------------------------- |
| `$PWD` -> `/workspace`         | Project yang mau dikerjakan agent                    |
| `~/.claude`                    | Kredensial & history Claude Code, persist antar run   |
| `~/.config/opencode`           | Config & provider OpenCode, persist antar run         |
| `~/.agent-of-empires`          | Config `aoe` (sessions, profiles), persist antar run  |

Tanpa mount config di atas, tiap `docker run` = login/setup provider dari
nol lagi. Sekali mount, kamu edit config lewat menu TUI `aoe` / `claude` /
`opencode` seperti biasa, dan itu otomatis nempel di host.

> Kalau direktori host (`~/.claude` dll.) belum ada / masih kosong dan
> dimiliki root dari percobaan sebelumnya, jalankan
> `sudo chown -R $(id -u):$(id -g) ~/.claude ~/.config/opencode ~/.agent-of-empires`
> di host dulu supaya user `admin` di dalam container bisa menulis ke situ.

### Auto-run TUI

Default `CMD` kosong -> entrypoint langsung `exec aoe`, jadi begitu
container start kamu langsung di layar TUI. Tidak perlu attach/exec manual.

### Butuh package tambahan saat runtime?

User `admin` sudah masuk `sudoers` tanpa password, jadi kalau sebuah agent
perlu install dependency baru di tengah sesi:

```bash
sudo xbps-install -Sy <paket>
```

Kalau kamu tidak mau container punya akses sudo sama sekali, hapus baris
`sudoers.d` di Dockerfile.

### Web dashboard (opsional, experimental)

```bash
docker run -it --rm \
  -p 4200:4200 \
  -e AOE_WEB=1 \
  ... \
  nanoplayground
```

Entrypoint akan **mencoba** beberapa kandidat sub-command (`aoe serve`,
`aoe session serve`, `aoe web`) dan pakai yang valid di versi `aoe` yang
ter-install saat image di-build. Kalau tidak ada satupun yang cocok
(sub-command berubah lagi di rilis baru), pesan error akan menyarankan cek
`aoe --help` manual — jalankan:

```bash
docker exec -it <container_id> aoe --help
```

untuk lihat nama sub-command web dashboard yang benar di versi tersebut,
lalu sesuaikan `entrypoint.sh` kalau perlu.

### Jalan di proot

Karena `[sandbox] enabled_by_default = false`, `aoe` tidak akan pernah
mencoba bicara ke Docker socket kecuali kamu eksplisit pakai flag
`--sandbox` / `--sandbox-image`. Jalan di proot (tanpa Docker daemon di
dalam) aman.

## Catatan versi

- Binary `aoe` butuh **glibc >= 2.28** (floor dari `manylinux_2_28`).
  Void glibc-full jauh di atas itu.
- Kalau butuh tool tambahan (Python, Rust, dll — mirip "dev sandbox" resmi
  AoE), tinggal tambah `RUN xbps-install ...`
  di Dockerfile, sebelum baris `USER ${USERNAME}`.
