# syntax=docker/dockerfile:1.7
# Base image is pinned by digest; Dependabot opens PRs when it changes.
# Debian (glibc) keeps the Claude CLI and anything it runs fully compatible.

# Optional tools, each off by default (the slim image gets none of them).
# Versions are pinned; .github/workflows/update-deps.yml bumps uv, rustup and Node.js.
#   WITH_UV           uv (Python package and version manager)
#   WITH_RUST         rustup; the toolchain itself is installed into the config
#                     volume on first start (RUST_TOOLCHAIN, default stable)
#   WITH_NODE         Node.js LTS with npm and npx
#   WITH_ONNXRUNTIME  ONNX Runtime shared library (libonnxruntime.so), for crates
#                     that load it at runtime through ORT_DYLIB_PATH
ARG UV_VERSION=0.12.23
ARG RUSTUP_VERSION=1.29.1
ARG NODE_VERSION=24.21.0
# ONNX Runtime is not auto-bumped: the version must match what the `ort` crate
# of the projects using it expects. Microsoft publishes no checksum files, so
# the SHA-256 of each release tarball is pinned here.
ARG ONNXRUNTIME_VERSION=1.30.0
ARG ONNXRUNTIME_SHA256_X64=a5ed5a3cac51fbb2e90da632ae43d19212faaa20e76484e62bcb7c23ddb3b3fd
ARG ONNXRUNTIME_SHA256_AARCH64=e16a27a8ed330bbc698df7330b0cf56e722f354e3bcc92118682c74ef3c3e3da
ARG WITH_UV=false
ARG WITH_RUST=false
ARG WITH_NODE=false
ARG WITH_ONNXRUNTIME=false

# --- Install Claude Code (curl and the installer stay out of the final image) ---
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS claude

# Claude Code version baked into the image. Pinned so every release is
# reproducible; .github/workflows/update-deps.yml opens a PR to bump it.
ARG CLAUDE_VERSION=2.1.296

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --uid 1000 --create-home claude

USER claude
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
 && /home/claude/.local/bin/claude --version

# --- Optional tools, laid out like /usr/local and copied there ---
# Every download is checked against a SHA-256 before it is unpacked. /opt/extras
# stays empty when nothing is asked for.
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS extras

ARG UV_VERSION
ARG RUSTUP_VERSION
ARG NODE_VERSION
ARG ONNXRUNTIME_VERSION
ARG ONNXRUNTIME_SHA256_X64
ARG ONNXRUNTIME_SHA256_AARCH64
ARG WITH_UV
ARG WITH_RUST
ARG WITH_NODE
ARG WITH_ONNXRUNTIME

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
WORKDIR /tmp/dl
RUN mkdir -p /opt/extras/bin /opt/extras/lib \
 && arch="$(uname -m)" \
 && case "$arch" in \
      x86_64)  node_arch=x64;   ort_arch=x64;     ort_sha="$ONNXRUNTIME_SHA256_X64" ;; \
      aarch64) node_arch=arm64; ort_arch=aarch64; ort_sha="$ONNXRUNTIME_SHA256_AARCH64" ;; \
      *) echo "unsupported architecture: $arch"; exit 1 ;; \
    esac \
 # uv: GitHub release, checked against the release's .sha256
 && if [[ "$WITH_UV" == true ]]; then \
      url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${arch}-unknown-linux-gnu.tar.gz"; \
      curl -fsSLo uv.tar.gz "$url"; \
      echo "$(curl -fsSL "$url.sha256" | cut -d' ' -f1)  uv.tar.gz" | sha256sum -c -; \
      tar --no-same-owner -xzf uv.tar.gz -C /opt/extras/bin --strip-components=1; \
      /opt/extras/bin/uv --version; \
    fi \
 # rustup: the official rustup-init binary. Named rustup it acts as rustup; the
 # cargo, rustc, ... links make it act as a proxy for the active toolchain.
 && if [[ "$WITH_RUST" == true ]]; then \
      url="https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${arch}-unknown-linux-gnu/rustup-init"; \
      curl -fsSLo rustup-init "$url"; \
      echo "$(curl -fsSL "$url.sha256" | cut -d' ' -f1)  rustup-init" | sha256sum -c -; \
      install -m 0755 rustup-init /opt/extras/bin/rustup; \
      for p in cargo cargo-clippy cargo-fmt cargo-miri clippy-driver rls rust-analyzer \
               rust-gdb rust-gdbgui rust-lldb rustc rustdoc rustfmt; do \
        ln -s rustup "/opt/extras/bin/$p"; \
      done; \
      /opt/extras/bin/rustup --version; \
    fi \
 # Node.js: official binary tarball, checked against the release's SHASUMS256.txt
 && if [[ "$WITH_NODE" == true ]]; then \
      file="node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
      curl -fsSLo "$file" "https://nodejs.org/dist/v${NODE_VERSION}/${file}"; \
      curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${file}\$" | sha256sum -c -; \
      tar --no-same-owner -xJf "$file" -C /opt/extras --strip-components=1 --wildcards '*/bin' '*/include' '*/lib' '*/share/man'; \
      /opt/extras/bin/node --version; \
    fi \
 # ONNX Runtime: Microsoft's CPU build, only its shared libraries
 && if [[ "$WITH_ONNXRUNTIME" == true ]]; then \
      file="onnxruntime-linux-${ort_arch}-${ONNXRUNTIME_VERSION}.tgz"; \
      curl -fsSLo "$file" "https://github.com/microsoft/onnxruntime/releases/download/v${ONNXRUNTIME_VERSION}/${file}"; \
      echo "${ort_sha}  ${file}" | sha256sum -c -; \
      tar --no-same-owner -xzf "$file" -C /opt/extras/lib --strip-components=2 --wildcards '*/lib/libonnxruntime*.so*'; \
      ls -l /opt/extras/lib/libonnxruntime*; \
    fi \
 && rm -rf /tmp/dl/*

# --- Runtime image ---
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# Optional Debian packages, e.g. "git gh openssh-client tmux" (space separated).
ARG EXTRA_APT_PACKAGES=""
ARG WITH_UV
ARG WITH_RUST
ARG WITH_NODE
ARG WITH_ONNXRUNTIME

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
COPY --from=extras /opt/extras/ /usr/local/
RUN ldconfig

# Managed CLAUDE.md describing the container to Claude, with this build's extra
# packages filled in. Kept apart from the user's ~/.claude/CLAUDE.md and the
# project's /workspace/CLAUDE.md, which the image never touches.
COPY rootfs/etc/claude-code/ /etc/claude-code/
RUN tools="${EXTRA_APT_PACKAGES}" \
 && if [ "$WITH_UV" = true ]; then tools="$tools uv"; fi \
 && if [ "$WITH_RUST" = true ]; then tools="$tools rustup"; fi \
 && if [ "$WITH_NODE" = true ]; then tools="$tools node npm"; fi \
 && if [ "$WITH_ONNXRUNTIME" = true ]; then tools="$tools onnxruntime"; fi \
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
# RUSTUP_HOME/CARGO_HOME: if rustup is installed, keep the toolchain, the crate
#   cache and `cargo install`ed tools in the config volume, so they survive
#   rebuilds and image updates.
# NPM_CONFIG_PREFIX: if Node.js is installed, `npm install -g` goes to the config
#   volume (writable by the claude user, kept across image updates).
# ORT_DYLIB_PATH: if ONNX Runtime is installed, where `ort` loads it from.
ENV PATH=/usr/local/bin:/home/claude/.local/bin:/home/claude/.claude/cargo/bin:/home/claude/.claude/npm-global/bin:$PATH \
    CLAUDE_CONFIG_DIR=/home/claude/.claude \
    CLAUDE_BIN=/home/claude/.local/bin/claude \
    XDG_RUNTIME_DIR=/run/claude \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory \
    GIT_CONFIG_VALUE_0=* \
    UV_PYTHON_INSTALL_DIR=/home/claude/.claude/uv/python \
    UV_LINK_MODE=copy \
    RUSTUP_HOME=/home/claude/.claude/rustup \
    CARGO_HOME=/home/claude/.claude/cargo \
    NPM_CONFIG_PREFIX=/home/claude/.claude/npm-global \
    ORT_DYLIB_PATH=/usr/local/lib/libonnxruntime.so

WORKDIR /workspace
VOLUME ["/home/claude/.claude"]

HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
CMD []
