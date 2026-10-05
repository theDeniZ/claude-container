# Container environment

This file is managed by the claude-container image and is replaced whenever the
image is updated. Personal instructions belong in `~/.claude/CLAUDE.md` (kept in the
config volume, applies to every project); project instructions belong in the
project's own `CLAUDE.md`.

## Where you are

- You run inside a Docker container as the unprivileged user `claude`. There is no
  root access and no `sudo`, so you can't install system packages.
- `/workspace` is the user's project, bind-mounted from the host. Changes there are
  real and permanent.
- `~/.claude` (`$CLAUDE_CONFIG_DIR`) is a persistent volume with the login, settings,
  session history and the user's own `CLAUDE.md`.
- Everything else, including anything installed outside these two folders and `/tmp`,
  is lost when the container is recreated or the image is updated.

## Tools

The image is deliberately slim: bash, coreutils, `jq`, `ps` and CA certificates,
plus Claude Code's built-in ripgrep for searching.

Extra packages in this image: {{EXTRA_APT_PACKAGES}}.

- If `git` isn't listed, there is no git: no status, diffs, commits or worktrees.
  Work on the files directly and say so when git would have been needed.
- If `python3` is listed, it is Debian's system Python, which refuses
  `pip install` outside a virtual environment (PEP 668). Keep environments in the
  project so they survive restarts, and don't use `--break-system-packages`.
  Unless `build-essential` is listed, there is no C compiler, so packages
  without a prebuilt wheel can't be built.
- If `uv` is listed, use it for Python work: `uv venv`, `uv pip install …`, or
  `uv add …` / `uv run …` in uv projects. For a Python version other than the
  system one, use `uv venv --python 3.12` (or `uv python install`); uv keeps the
  Pythons it downloads in the config volume, so those venvs keep working after
  the container is recreated. Without uv, use `python3 -m venv .venv` and
  `.venv/bin/pip install …`.
- If `rustup` is listed, Rust is managed by rustup: `cargo`, `rustc`, `clippy`
  and `rustfmt` are on the PATH. The toolchain (`$RUSTUP_HOME`), the crate cache
  and `cargo install`ed tools (`$CARGO_HOME`) live in the config volume and
  survive restarts. `rustup toolchain install …` and `rustup update` work; don't
  try to update rustup itself, it belongs to the image.
- If `node` is listed, Node.js LTS with `npm` and `npx` is installed. `npm install -g`
  goes to the config volume (`$NPM_CONFIG_PREFIX`), so global tools persist; for
  project dependencies prefer a local `npm install`.
- If `onnxruntime` is listed, the ONNX Runtime shared library is at
  `$ORT_DYLIB_PATH` (`/usr/local/lib/libonnxruntime.so`) for programs that load
  it at runtime, such as the Rust `ort` crate with `load-dynamic`.
- When a task needs a tool that isn't installed, don't look for ways around the
  missing root access. Tell the user which Debian package it needs and that it can
  be added with `EXTRA_APT_PACKAGES` in their `.env` and a rebuild
  (`docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build`),
  or by switching to the `python` or `full` image variant.
- `claude-status` shows the login, Remote Control and the sessions running in the
  container.
