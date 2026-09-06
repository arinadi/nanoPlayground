# syntax=docker/dockerfile:1
#
# nanoPlayground — image siap pakai untuk Claude Code + OpenCode
# via Agent of Empires (aoe), TUI langsung nyala saat `docker run`.
# Jalan sebagai non-root user `admin`, bukan root.
#
# Base: Ubuntu 26.04 LTS "Resolute Raccoon" (glibc jauh di atas floor 2.28
# yang dibutuhkan binary aoe). Void Linux glibc-full juga bisa dipakai —
# lihat Dockerfile.void di folder yang sama untuk versinya.

FROM ubuntu:26.04

LABEL org.opencontainers.image.title="nanoPlayground" \
      org.opencontainers.image.description="TUI Agent of Empires + Claude Code + OpenCode, docker run langsung jalan" \
      org.opencontainers.image.source="https://github.com/arinadi/nanoPlayground"

ARG USERNAME=admin
# Samakan dengan UID/GID user host kamu supaya file yang dibuat lewat
# bind-mount /workspace tidak jadi milik UID asing:
#   docker build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) ...
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

# --- Dependensi dasar (masih sebagai root) ----------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        tmux \
        git \
        curl \
        wget \
        ca-certificates \
        gnupg \
        ripgrep \
        fzf \
        openssh-client \
        build-essential \
        less \
        nano \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# --- Node.js (dibutuhkan Claude Code & OpenCode via npm) --------------------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# --- Buat user non-root `admin` ---------------------------------------------
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# --- Entrypoint (di-copy sebagai root, executable untuk semua user) --------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- Workspace, kepemilikan diserahkan ke admin -----------------------------
RUN mkdir -p /workspace && chown -R "${USERNAME}:${USERNAME}" /workspace

# --- Pindah ke user non-root untuk sisa instalasi ---------------------------
USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.npm-global/bin:${PATH}" \
    NPM_CONFIG_PREFIX="/home/${USERNAME}/.npm-global"

RUN mkdir -p "${NPM_CONFIG_PREFIX}" && npm config set prefix "${NPM_CONFIG_PREFIX}"

# aoe — TUI/CLI session manager. Sandbox Docker tidak akan pernah aktif
# kecuali diminta eksplisit (lihat config/aoe-config.toml di bawah):
# enabled_by_default = false.
RUN curl -fsSL \
      https://raw.githubusercontent.com/agent-of-empires/agent-of-empires/main/scripts/install.sh \
      | bash

# Coding agent
RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g opencode-ai@latest

# Config default aoe + dir persist agar `docker run` tanpa -v tetap jalan
RUN mkdir -p /home/${USERNAME}/.agent-of-empires /home/${USERNAME}/.claude /home/${USERNAME}/.config/opencode
COPY --chown=${USERNAME}:${USERNAME} config/aoe-config.toml /home/${USERNAME}/.agent-of-empires/config.toml

WORKDIR /workspace

# Tanpa VOLUME: container jalan dengan filesystem internal secara default.
# User yang mau persist tinggal tambah -v sendiri (lihat README).

# Verifikasi cepat saat build (gagal build kalau salah satu binary hilang)
RUN aoe --version && claude --version && opencode --version

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
