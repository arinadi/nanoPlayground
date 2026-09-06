# syntax=docker/dockerfile:1
#
# nanoPlayground — Void Linux glibc-full. Jalan sebagai
# non-root user `admin`, bukan root.
#
# Build:  docker build \
#           --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) \
#           -t nanoplayground .

FROM ghcr.io/void-linux/void-glibc-full:latest

LABEL org.opencontainers.image.title="nanoPlayground" \
      org.opencontainers.image.description="TUI Agent of Empires + Claude Code + OpenCode, docker run langsung jalan" \
      org.opencontainers.image.source="https://github.com/arinadi/nanoPlayground"

ARG USERNAME=admin
ARG USER_UID=1000
ARG USER_GID=1000

ENV LANG=C.UTF-8 \
    TERM=xterm-256color

# xbps-install -Su dua kali: pertama update xbps itu sendiri (pola resmi
# yang direkomendasikan Void), lalu update seluruh sistem.
RUN xbps-install -Suy xbps && \
    xbps-install -Suy && \
    xbps-install -y \
        tmux \
        git \
        curl \
        wget \
        ca-certificates \
        ripgrep \
        fzf \
        openssh \
        base-devel \
        nodejs \
        nano \
        sudo \
        shadow \
    && xbps-remove -Oo -y

# --- Buat user non-root `admin` ---------------------------------------------
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY bin/npg /usr/local/bin/npg
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/npg

# Skills bawaan (read-only defaults ala omarchy /usr/share/omarchy).
# Dipasang ke home user via `npg skills sync` (build + tiap start).
COPY .opencode/skills /usr/share/nanoplayground/skills

RUN mkdir -p /workspace && chown -R "${USERNAME}:${USERNAME}" /workspace

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.npm-global/bin:${PATH}" \
    NPM_CONFIG_PREFIX="/home/${USERNAME}/.npm-global"

RUN mkdir -p "${NPM_CONFIG_PREFIX}" && npm config set prefix "${NPM_CONFIG_PREFIX}"

RUN curl -fsSL \
      https://raw.githubusercontent.com/agent-of-empires/agent-of-empires/main/scripts/install.sh \
      | bash

RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g opencode-ai@latest

RUN mkdir -p /home/${USERNAME}/.agent-of-empires /home/${USERNAME}/.claude /home/${USERNAME}/.config/opencode
COPY --chown=${USERNAME}:${USERNAME} config/aoe-config.toml /home/${USERNAME}/.agent-of-empires/config.toml

# Pasang skills + CLI helper untuk user default (entrypoint sync ulang tiap start
# agar home hasil mount pun tetap dapat skill).
RUN npg skills sync && npg commands >/dev/null

WORKDIR /workspace

# Tanpa VOLUME: container jalan dengan filesystem internal secara default.
# User yang mau persist tinggal tambah -v sendiri (lihat README).

RUN aoe --version && claude --version && opencode --version && npg commands >/dev/null

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
