# syntax=docker/dockerfile:1.7
#
# nanoPlayground — Instant, Fun & Agentic Playground for AI coding agents.
# SPIKE: Debian 13 (trixie-slim) base + Openbox. Runs as non-root user `admin`, not root.
#
# Build:  docker build \
#           --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) \
#           -t nanoplayground .

FROM debian:13

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
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1

# --- Base deps in ONE layer (still as root) --------------------------------------
# Cache mounts keep /var/cache/apt and /var/lib/apt out of the final layer for
# faster rebuilds without growing size.
# Debian trixie-slim ships `main` by default and all packages below live in
# `main`, so no extra component setup is needed (unlike Ubuntu `universe`).
# Must-have (to verify on trixie): jq, fd (fd-find), ctags (universal-ctags),
# bat (binary `batcat`), git-delta (binary `delta`), eza, sqlite3, python3 + pip.
# yq / ast-grep / just / gh (github-cli) are NOT apt packages on Debian either —
# they come from static binaries in the next step.
# Nice-to-have: bat, git-delta, eza, sqlite3.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
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
        npm \
        nano \
        sudo \
        uidmap \
        ncurses-base \
        tzdata \
        jq \
        fd-find \
        universal-ctags \
        bat \
        git-delta \
        eza \
        sqlite3 \
        python3 \
        python3-pip \
        python3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/apt/

# --- Agent tools missing from the Debian archive ----------------------------------
# yq & ast-grep have no apt package on Debian, and just & github-cli
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
    && chmod +x /usr/local/bin/gh && gh --version \
    && rm -rf /tmp/* /var/tmp/*

# --- rtk (Rust Token Killer, https://github.com/rtk-ai/rtk) ---------------------
# Single static binary -> runs on Ubuntu. Installed system-wide
# (NOT via install.sh, which targets ~/.local/bin, and NEVER via
# `cargo install rtk` — that is a different crate).
# TARGETARCH-aware (amd64/arm64) for multi-arch builds.
# NOTE: ARG TARGETARCH declared once above is reused here (no re-declare needed).
RUN case "${TARGETARCH}" in \
        amd64) RTK_TRIPLE="x86_64-unknown-linux-musl" ;; \
        arm64) RTK_TRIPLE="aarch64-unknown-linux-gnu" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && RTK_VER="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/rtk-ai/rtk/releases/latest | sed 's#.*/##')" \
    && curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/${RTK_VER}/rtk-${RTK_TRIPLE}.tar.gz" \
        | tar -xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/rtk && rtk --version \
    && rm -rf /tmp/* /var/tmp/* /root/.cache

# --- trafilatura (https://trafilatura.readthedocs.io) --------------------------
# Best-in-class HTML -> text/Markdown extractor. CLI: `trafilatura -u <URL>`.
RUN pip3 install --no-cache-dir --no-compile trafilatura \
    && find /usr/lib/python* -type d -name '__pycache__' -prune -exec rm -rf {} + \
    && rm -rf /root/.cache /tmp/* /var/tmp/* && trafilatura --help >/dev/null

# --- Remote desktop / VNC stack: ON DEMAND, not baked -----------------------------
# X11 libraries cost roughly 50-120MB, so the VNC stack (xvfb, xauth, x11vnc,
# openbox, xterm) ships as a runtime script instead of an image layer.
# At runtime: `desktop-install` (apt packages) then `start-desktop.sh`
# (Xvfb → openbox → x11vnc).
# SPIKE: Openbox (mouse-driven stacking WM) instead of awesome (tiling).

# --- Browser automation: ON DEMAND, not baked --------------------------------------
# playwright + crawl4ai pull hundreds of MB of Python deps, so they ship as a
# runtime script instead of an image layer. At runtime: `crawl4ai-install`
# (pip packages) then `playwright-install` (firefox binary + symlink).
# Playwright's CDN is flaky in CI (ECONNRESET/400/self-signed), hence runtime.

# --- Create non-root user `admin` --------------------------------------------
# debian:13-slim ships no UID 1000 user by default (unlike Ubuntu minimal), so
# we normally create `admin` fresh; the repurpose branch stays for compat.
# Keeps UID/GID 1000 for host mount compat; otherwise create admin normally.
RUN set -eux; \
    if id "${USERNAME}" >/dev/null 2>&1; then \
        :; \
    elif getent passwd "${USER_UID}" >/dev/null 2>&1; then \
        _old="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
        usermod -l "${USERNAME}" -s /bin/bash -m -d "/home/${USERNAME}" "${_old}"; \
    else \
        groupadd --gid "${USER_GID}" "${USERNAME}" 2>/dev/null || true; \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}"; \
    fi; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}; \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Stable first: workspace dir owned by admin (rarely changes, keep high for cache).
RUN mkdir -p /workspace && chown -R "${USER_UID}:${USER_GID}" /workspace

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.npm-global/bin:${PATH}" \
    NPM_CONFIG_PREFIX="/home/${USERNAME}/.npm-global"

# --- Heavy stable layers as admin (keep above volatile COPYs for cache reuse) ---
RUN curl -fsSL \
      https://raw.githubusercontent.com/agent-of-empires/agent-of-empires/main/scripts/install.sh \
      | bash \
    && rm -rf /tmp/* /var/tmp/*

# One transaction + cache purge: npm's _cacache (~200MB) must die in the SAME
# layer or it still ships. Sourcemap (*.map) removal only affects debugging.
# mkdir + npm config merged here to save one extra layer.
# NOTE: claude-code is intentionally NOT baked (saves ~100-200MB); install it
# on demand at runtime when needed.
RUN mkdir -p "${NPM_CONFIG_PREFIX}" && npm config set prefix "${NPM_CONFIG_PREFIX}" \
    && npm install -g --no-fund --no-audit --no-update-notifier \
        opencode-ai@latest pnpm \
    && npm cache clean --force \
    && find "${NPM_CONFIG_PREFIX}/lib/node_modules" -name '*.map' -delete \
    && rm -rf /tmp/* /var/tmp/*

# Stable admin dirs (empty dirs must exist for mounts; keep before volatile COPY).
RUN mkdir -p /home/${USERNAME}/.agent-of-empires /home/${USERNAME}/.claude /home/${USERNAME}/.config/opencode

# --- Volatile root COPYs LAST (as root) so bin/skills edits do NOT invalidate ---
# --- the heavy npm/aoe layers above. COPY --chmod saves the extra chmod RUN. ---
USER root
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 bin/npg /usr/local/bin/npg
COPY --chmod=0755 bin/start-desktop.sh /usr/local/bin/start-desktop.sh
COPY --chmod=0755 bin/stop-desktop.sh /usr/local/bin/stop-desktop.sh
COPY --chmod=0755 bin/desktop-install.sh /usr/local/bin/desktop-install
COPY --chmod=0755 bin/playwright-install.sh /usr/local/bin/playwright-install
COPY --chmod=0755 bin/crawl4ai-install.sh /usr/local/bin/crawl4ai-install

# Built-in skills (read-only defaults, omarchy-style /usr/share/nanoplayground).
# Installed into the user home via `npg skills sync` (build + every start).
COPY .opencode/skills /usr/share/nanoplayground/skills
COPY --chown=${USER_UID}:${USER_GID} config/aoe-config.toml /home/${USERNAME}/.agent-of-empires/config.toml

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Install skills + CLI helper for the default user (the entrypoint re-syncs
# on every start so even mounted homes keep the skills).
RUN npg skills sync && npg commands >/dev/null

# rtk setup for BOTH agents — verbose on purpose so the build log proves
# registration. `rtk init --show` fails the build if hooks are missing.
# Merged with git pager config to save one layer.
RUN rtk init -g --auto-patch && rtk init -g --opencode --auto-patch && rtk init --show \
    && git config --global core.pager delta

WORKDIR /workspace

# No VOLUME: the container runs on its internal filesystem by default.
# Users who want persistence add -v themselves (see README).

RUN aoe --version && opencode --version && npg commands >/dev/null \
    && rtk --version && ast-grep --version && yq --version && just --version \
    && gh --version && trafilatura --help >/dev/null \
    && pnpm --version \
    && command -v playwright-install \
    && command -v crawl4ai-install \
    && command -v desktop-install

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
