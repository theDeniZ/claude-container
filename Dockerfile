# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim

# Claude Code version to install: "latest", "stable" or an exact version (e.g. 2.1.283).
ARG CLAUDE_VERSION=latest
# Extra Debian packages to bake into the image (space separated).
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
      bash ca-certificates curl git gnupg gosu jq less openssh-client procps \
      ripgrep tini tmux unzip nano ${EXTRA_APT_PACKAGES} \
 # GitHub CLI
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/* \
 # Workspace is bind-mounted with the host owner; don't let git refuse it.
 && git config --system --add safe.directory '*'

# Unprivileged user; UID/GID are remapped at startup from PUID/PGID.
RUN groupadd --gid 1000 claude \
 && useradd --uid 1000 --gid claude --create-home --shell /bin/bash claude \
 && mkdir -p /workspace /home/claude/.claude \
 && chown claude:claude /workspace /home/claude/.claude

# Install Claude Code with the official native installer, owned by the runtime
# user so `claude update` (and CLAUDE_AUTO_UPDATE) can replace it in place.
USER claude
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
 && /home/claude/.local/bin/claude --version
USER root

COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/

ENV PATH=/usr/local/bin:/home/claude/.local/bin:$PATH \
    CLAUDE_CONFIG_DIR=/home/claude/.claude \
    CLAUDE_BIN=/home/claude/.local/bin/claude

WORKDIR /workspace
VOLUME ["/home/claude/.claude"]

HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
CMD []
