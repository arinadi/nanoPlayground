# syntax=docker/dockerfile:1
#
# nanoPlayground — Instant, Fun & Agentic Playground for AI coding agents.
# Void Linux glibc-full base. Runs as non-root user `admin`, not root.
#
# Build:  docker build \
#           --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) \
#           -t nanoplayground .

FROM ghcr.io/void-linux/void-glibc-full:latest

LABEL org.opencontainers.image.title="nanoPlayground" \
      org.opencontainers.image.description="Instant, fun & agentic playground: aoe TUI + Claude Code + OpenCode, runs with plain docker run" \
      org.opencontainers.image.source="https://github.com/arinadi/nanoPlayground"

ARG USERNAME=admin
ARG USER_UID=1000
ARG USER_GID=1000

ENV LANG=C.UTF-8 \
    TERM=xterm-256color

# xbps-install -Su twice: first update xbps itself (the officially
# recommended Void pattern), then the whole system.
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

# --- Create non-root user `admin` --------------------------------------------
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY bin/npg /usr/local/bin/npg
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/npg

# Built-in skills (read-only defaults, omarchy-style /usr/share/omarchy).
# Installed into the user home via `npg skills sync` (build + every start).
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

# Install skills + CLI helper for the default user (the entrypoint re-syncs
# on every start so even mounted homes keep the skills).
RUN npg skills sync && npg commands >/dev/null

WORKDIR /workspace

# No VOLUME: the container runs on its internal filesystem by default.
# Users who want persistence add -v themselves (see README).

RUN aoe --version && claude --version && opencode --version && npg commands >/dev/null

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
