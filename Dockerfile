# syntax=docker/dockerfile:1.7
# Base image is pinned by digest; Dependabot opens PRs when it changes.
# Debian (glibc) keeps the Claude CLI and anything it runs fully compatible.

# --- Install Claude Code (curl and the installer stay out of the final image) ---
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS claude

# Claude Code version baked into the image. Pinned so every release is
# reproducible; .github/workflows/update-claude-cli.yml opens a PR to bump it.
ARG CLAUDE_VERSION=2.1.283

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --uid 1000 --create-home claude

USER claude
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
 && /home/claude/.local/bin/claude --version

# --- Runtime image ---
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# Optional Debian packages, e.g. "git gh openssh-client tmux" (space separated).
ARG EXTRA_APT_PACKAGES=""

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

# XDG_RUNTIME_DIR: private runtime dir for the claude user. Without it Claude
#   keeps its messaging sockets in a shared /tmp/cc-socks owned by whoever made it first.
# GIT_CONFIG_*: the workspace is bind-mounted with the host owner; if git is
#   installed, don't let it refuse the repo (env config needs no git at build time).
ENV PATH=/usr/local/bin:/home/claude/.local/bin:$PATH \
    CLAUDE_CONFIG_DIR=/home/claude/.claude \
    CLAUDE_BIN=/home/claude/.local/bin/claude \
    XDG_RUNTIME_DIR=/run/claude \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory \
    GIT_CONFIG_VALUE_0=*

WORKDIR /workspace
VOLUME ["/home/claude/.claude"]

HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
CMD []
