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
  `pip install` outside a virtual environment (PEP 668). Create a venv in the
  project (`python3 -m venv .venv`, then `.venv/bin/pip install …`) so it is kept
  with the workspace; don't use `--break-system-packages`. There is no C compiler,
  so packages without a prebuilt wheel can't be built.
- When a task needs a tool that isn't installed, don't look for ways around the
  missing root access. Tell the user which Debian package it needs and that it can
  be added with `EXTRA_APT_PACKAGES` in their `.env` and a rebuild
  (`docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build`),
  or, for Python, by switching to the `python` image variant.
- `claude-status` shows the login, Remote Control and the sessions running in the
  container.
