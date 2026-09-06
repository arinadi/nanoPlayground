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
    TERM=xterm-256color \
    RTK_TELEMETRY_DISABLED=1

# --- Base deps (still as root) ------------------------------------------------
# Must-bake (verified in void-packages): ast-grep, github-cli (gh), jq, yq,
# fd, just, ctags (universal-ctags), python3 + pip (for trafilatura).
# Worth-baking: bat, delta, eza, sqlite (sqlite3 shell).
RUN xbps-install -Suy xbps && \
    xbps-install -Suy && \
    xbps-install -y \
        bash \
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
        ast-grep \
        github-cli \
        jq \
        yq \
        fd \
        just \
        ctags \
        bat \
        delta \
        eza \
        sqlite \
        python3 \
        python3-pip \
    && xbps-remove -Oo -y

# --- rtk (Rust Token Killer, https://github.com/rtk-ai/rtk) ---------------------
# Single static binary -> runs on Void glibc too. Installed system-wide
# (NOT via install.sh, which targets ~/.local/bin, and NEVER via
# `cargo install rtk` — that is a different crate).
# TARGETARCH-aware (amd64/arm64) for multi-arch builds.
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
        amd64) RTK_TRIPLE="x86_64-unknown-linux-musl" ;; \
        arm64) RTK_TRIPLE="aarch64-unknown-linux-gnu" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && RTK_VER="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/rtk-ai/rtk/releases/latest | sed 's#.*/##')" \
    && curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/${RTK_VER}/rtk-${RTK_TRIPLE}.tar.gz" \
        | tar -xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/rtk && rtk --version

# --- trafilatura (https://trafilatura.readthedocs.io) --------------------------
# Best-in-class HTML -> text/Markdown extractor. CLI: `trafilatura -u <URL>`.
RUN pip3 install --no-cache-dir trafilatura && trafilatura --help >/dev/null

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

# rtk setup for BOTH agents — verbose on purpose so the build log proves
# registration. `rtk init --show` fails the build if hooks are missing.
RUN rtk init -g --auto-patch && rtk init -g --opencode --auto-patch && rtk init --show

# Cleaner diffs for agents: delta pager (git auto-disables it when not a TTY).
RUN git config --global core.pager delta

WORKDIR /workspace

# No VOLUME: the container runs on its internal filesystem by default.
# Users who want persistence add -v themselves (see README).

RUN aoe --version && claude --version && opencode --version && npg commands >/dev/null \
    && rtk --version && ast-grep --version && gh --version && trafilatura --help >/dev/null

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
