# syntax=docker/dockerfile:1
#
# nanoPlayground — Instant, Fun & Agentic Playground for AI coding agents.
# Ubuntu 26.04 LTS base. Runs as non-root user `admin`, not root.
#
# Build:  docker build \
#           --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) \
#           -t nanoplayground .

FROM ubuntu:26.04

LABEL org.opencontainers.image.title="nanoPlayground" \
      org.opencontainers.image.description="Instant, fun & agentic playground: aoe TUI + Claude Code + OpenCode, runs with plain docker run" \
      org.opencontainers.image.source="https://github.com/arinadi/nanoPlayground"

ARG USERNAME=admin
ARG USER_UID=1000
ARG USER_GID=1000

ENV LANG=C.UTF-8 \
    TERM=xterm-256color \
    RTK_TELEMETRY_DISABLED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PIP_BREAK_SYSTEM_PACKAGES=1

# --- Enable universe ------------------------------------------------------------
# The minimal ubuntu:26.04 container image ships only `main`. The desktop and
# automation stack (xvfb, x11vnc, awesome, xterm, and friends) lives in
# `universe`, so enable it across all sources before the first install.
RUN sed -i 's/^Components: main$/Components: main universe/g' \
        /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && rm -rf /var/lib/apt/lists/*

# --- Base deps (still as root) ------------------------------------------------
# Must-have (verified for Ubuntu 26.04): jq, fd, ctags (universal-ctags), bat,
# delta, eza, sqlite3, python3 + pip. yq / ast-grep / just / gh (github-cli)
# are NOT apt packages on Ubuntu (snap-only / unpackaged) — they come from
# static binaries in the next step.
# Nice-to-have: bat, delta, eza, sqlite3.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        tmux \
        git \
        curl \
        wget \
        ca-certificates \
        ripgrep \
        fzf \
        openssh-client \
        build-essential \
        pkg-config \
        nodejs \
        nano \
        sudo \
        uidmap \
        ncurses-base \
        tzdata \
        jq \
        fd-find \
        universal-ctags \
        bat \
        delta \
        eza \
        sqlite3 \
        python3 \
        python3-pip \
        python3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/apt/

# --- Agent tools missing from the Ubuntu archive --------------------------------
# yq & ast-grep are snap-only on Ubuntu (no apt package), and just & github-cli
# are unpackaged there, so `apt-get install` for them fails the build (exit 100).
# Pull static binaries instead. TARGETARCH-aware.
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
        amd64) YQ_ASSET="yq_linux_amd64"; JUST_T="x86_64-unknown-linux-musl"; SG_T="x86_64-unknown-linux-gnu"; GH_T="amd64" ;; \
        arm64) YQ_ASSET="yq_linux_arm64"; JUST_T="aarch64-unknown-linux-musl"; SG_T="aarch64-unknown-linux-gnu"; GH_T="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/${YQ_ASSET}" \
    && chmod +x /usr/local/bin/yq && yq --version \
    && JUST_VER="$(curl -fsSL https://api.github.com/repos/casey/just/releases/latest \
        | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -1)" \
    && curl -fsSL "https://github.com/casey/just/releases/latest/download/just-${JUST_VER}-${JUST_T}.tar.gz" \
        | tar -xz -C /usr/local/bin just \
    && chmod +x /usr/local/bin/just && just --version \
    && curl -fsSL "https://github.com/ast-grep/ast-grep/releases/latest/download/app-${SG_T}.zip" \
        -o /tmp/sg.zip \
    && python3 -m zipfile -e /tmp/sg.zip /usr/local/bin \
    && rm -f /tmp/sg.zip \
    && chmod +x /usr/local/bin/ast-grep && ast-grep --version \
    && GH_VER="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
        | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' | head -1)" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_${GH_T}.tar.gz" \
        | tar -xz -C /tmp \
    && mv "/tmp/gh_${GH_VER}_linux_${GH_T}/bin/gh" /usr/local/bin/gh \
    && chmod +x /usr/local/bin/gh && gh --version

# --- rtk (Rust Token Killer, https://github.com/rtk-ai/rtk) ---------------------
# Single static binary -> runs on Ubuntu. Installed system-wide
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
RUN pip3 install --no-cache-dir --no-compile trafilatura \
    && find /usr/lib/python* -type d -name '__pycache__' -prune -exec rm -rf {} + \
    && rm -rf /root/.cache && trafilatura --help >/dev/null

# --- Remote desktop / noVNC stack ----------------------------------------------
# Headless X + a window manager, shared over VNC, bridged to the browser via
# noVNC + websockify. `start-desktop.sh` wires it all together at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        xauth \
        x11vnc \
        awesome \
        xterm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/apt/

# --- noVNC + websockify ----------------------------------------------------------
RUN pip3 install --no-cache-dir websockify \
    && curl -fsSL -o /tmp/novnc.tar.gz \
        https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz \
    && mkdir -p /opt/novnc \
    && tar -xzf /tmp/novnc.tar.gz -C /opt/novnc --strip-components=1 \
    && rm -f /tmp/novnc.tar.gz \
    && test -f /opt/novnc/vnc.html

# --- Firefox (from playwright; snap-free for containers) -------------------------
# Ubuntu's `firefox` apt package is a snap transition stub that won't run in a
# container, and download.mozilla.org has no aarch64 Linux tarball. Playwright
# ships a full, arch-agnostic Firefox build we already pull below — we just
# expose it as /usr/local/bin/firefox for convenience.

# --- crawl4ai + playwright (browser automation) -----------------------------------
# Installed to a shared /ms-playwright so both root (build) and the `admin`
# runtime user find the same browser binaries. `--with-deps` lets playwright
# pull every system library firefox needs (via apt) so it also runs headed in
# the noVNC desktop.
RUN pip3 install --no-cache-dir playwright crawl4ai \
    && playwright install --with-deps firefox \
    && ln -sf "$(find /ms-playwright -maxdepth 2 -type f -name firefox | head -1)" \
        /usr/local/bin/firefox \
    && rm -rf /root/.cache /tmp/*

# --- Create non-root user `admin` --------------------------------------------
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY bin/npg /usr/local/bin/npg
COPY bin/start-desktop.sh /usr/local/bin/start-desktop.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/npg /usr/local/bin/start-desktop.sh

# Built-in skills (read-only defaults, omarchy-style /usr/share/nanoplayground).
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

# One transaction + cache purge: npm's _cacache (~200MB) must die in the SAME
# layer or it still ships. Sourcemap (*.map) removal only affects debugging.
RUN npm install -g --no-fund --no-audit --no-update-notifier \
        @anthropic-ai/claude-code opencode-ai@latest pnpm \
    && npm cache clean --force \
    && find "${NPM_CONFIG_PREFIX}/lib/node_modules" -name '*.map' -delete \
    && rm -rf /tmp/* /var/tmp/*

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
    && rtk --version && ast-grep --version && yq --version && just --version \
    && gh --version && trafilatura --help >/dev/null \
    && pnpm --version && test -x /usr/local/bin/firefox && awesome --version \
    && command -v websockify \
    && python3 -c "import playwright, crawl4ai"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
