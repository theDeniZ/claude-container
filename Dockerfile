# syntax=docker/dockerfile:1.7
# Base image is pinned by digest; Dependabot opens PRs when it changes.
# Debian (glibc) keeps the Claude CLI and anything it runs fully compatible.

# uv (Python package and version manager), installed only with WITH_UV=true
# (the python variant). Pinned; .github/workflows/update-deps.yml bumps it.
ARG UV_VERSION=0.12.23
ARG WITH_UV=false

# --- Install Claude Code (curl and the installer stay out of the final image) ---
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS claude

# Claude Code version baked into the image. Pinned so every release is
# reproducible; .github/workflows/update-deps.yml opens a PR to bump it.
ARG CLAUDE_VERSION=2.1.286

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --uid 1000 --create-home claude

USER claude
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
 && /home/claude/.local/bin/claude --version

# uv from its GitHub release, checked against the release's SHA-256. /opt/uv
# stays empty without WITH_UV, so the slim image gets nothing.
ARG UV_VERSION
ARG WITH_UV
USER root
RUN mkdir -p /opt/uv \
 && if [ "$WITH_UV" = true ]; then \
      url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-$(uname -m)-unknown-linux-gnu.tar.gz" \
      && curl -fsSLo /tmp/uv.tar.gz "$url" \
      && echo "$(curl -fsSL "$url.sha256" | cut -d' ' -f1)  /tmp/uv.tar.gz" | sha256sum -c - \
      && tar -xzf /tmp/uv.tar.gz -C /opt/uv --strip-components=1 \
      && rm /tmp/uv.tar.gz \
      && /opt/uv/uv --version; \
    fi

# --- Runtime image ---
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# Optional Debian packages, e.g. "git gh openssh-client tmux" (space separated).
ARG EXTRA_APT_PACKAGES=""
ARG WITH_UV

LABEL org.opencontainers.image.title="claude-container" \
      org.opencontainers.image.description="Claude Code CLI in a container with a mounted workspace, persistent auth and optional Remote Control" \
      org.opencontainers.image.source="https://github.com/theDeniZ/claude-container"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates gosu jq procps tini ${EXTRA_APT_PACKAGES} \
 && rm -rf /var/lib/apt/lists/*

# Unprivileged user; UID/GID are remapped at startup from PUID/PGID.
RUN groupadd --gid 1000 claude \
 && useradd --uid 1000 --gid claude --create-home --shell /bin/bash claude \
 && mkdir -p /workspace /home/claude/.claude \
 && mkdir -m 0700 /run/claude \
 && chown claude:claude /workspace /home/claude/.claude /run/claude

# Owned by the runtime user so `claude update` (CLAUDE_AUTO_UPDATE) works in place.
COPY --from=claude --chown=claude:claude /home/claude/.local /home/claude/.local
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/
COPY --from=claude /opt/uv/ /usr/local/bin/

# Managed CLAUDE.md describing the container to Claude, with this build's extra
# packages filled in. Kept apart from the user's ~/.claude/CLAUDE.md and the
# project's /workspace/CLAUDE.md, which the image never touches.
COPY rootfs/etc/claude-code/ /etc/claude-code/
RUN tools="${EXTRA_APT_PACKAGES}" && if [ "$WITH_UV" = true ]; then tools="$tools uv"; fi \
 && packages="$(for p in $tools; do printf '`%s`, ' "$p"; done)" \
 && sed -i "s|{{EXTRA_APT_PACKAGES}}|${packages%, }|; s|: \.$|: none.|" /etc/claude-code/CLAUDE.md

# XDG_RUNTIME_DIR: private runtime dir for the claude user. Without it Claude
#   keeps its messaging sockets in a shared /tmp/cc-socks owned by whoever made it first.
# GIT_CONFIG_*: the workspace is bind-mounted with the host owner; if git is
#   installed, don't let it refuse the repo (env config needs no git at build time).
# UV_*: if uv is installed, keep the Pythons it downloads in the config volume so
#   venvs in /workspace that use them still work after the container is
#   recreated, and copy rather than hardlink (cache and workspace are on
#   different filesystems).
ENV PATH=/usr/local/bin:/home/claude/.local/bin:$PATH \
    CLAUDE_CONFIG_DIR=/home/claude/.claude \
    CLAUDE_BIN=/home/claude/.local/bin/claude \
    XDG_RUNTIME_DIR=/run/claude \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory \
    GIT_CONFIG_VALUE_0=* \
    UV_PYTHON_INSTALL_DIR=/home/claude/.claude/uv/python \
    UV_LINK_MODE=copy

WORKDIR /workspace
VOLUME ["/home/claude/.claude"]

HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
CMD []
