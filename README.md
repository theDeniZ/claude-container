# claude-container

Run [Claude Code](https://docs.claude.com/en/docs/claude-code) in a container with:

- your project mounted at `/workspace`
- a pinned, up-to-date Claude Code CLI (a bot opens a bump PR for every new CLI release)
- login, settings and sessions kept in a volume or a folder you choose
- an optional background **Remote Control** server, so you can drive Claude from
  [claude.ai/code](https://claude.ai/code) or the Claude mobile app
- a built-in health check
- files written with your own UID/GID, not root

Image: `ghcr.io/thedeniz/claude-container` (linux/amd64, linux/arm64), in a slim
and a [Python](#image-variants) variant. See [Versions and releases](#versions-and-releases).

## Quick start

```bash
git clone https://github.com/theDeniZ/claude-container.git && cd claude-container
cp .env.example .env
# edit .env: set WORKSPACE_PATH to your project, PUID/PGID to `id -u` / `id -g`
docker compose up -d
```

Or skip the clone: download [`docker-compose.yml`](docker-compose.yml) (and
optionally [`.env.example`](.env.example) as `.env`) into any folder and run
`docker compose up -d` there.

### Log in (once)

```bash
docker compose exec -u claude claude claude auth login
```

Open the URL it prints, sign in, and paste the code back. The login is saved in the
config volume and survives restarts, rebuilds and image updates.

### Use Claude

```bash
docker compose exec -u claude claude claude      # interactive session in /workspace
docker compose exec -u claude claude bash        # shell as the claude user
```

`docker compose exec claude claude …` (without `-u claude`) works too: the
`claude` command switches from root to the `claude` user on its own.

## Remote Control

Set in `.env`:

```dotenv
CLAUDE_REMOTE_CONTROL=true
CLAUDE_RC_NAME=my-project             # name shown in the Claude apps
CLAUDE_RC_MODE=session                # or server, see below
CLAUDE_PERMISSION_MODE=default        # or acceptEdits | auto | plan | dontAsk | bypassPermissions
```

Then run `docker compose up -d`. Remote Control starts in `/workspace` in the background
and is restarted if it exits. Open the **Code** tab in the Claude app or
[claude.ai/code](https://claude.ai/code). What you find there depends on the mode:

- **`session` (default):** runs `claude --remote-control <name>`. One session named
  `CLAUDE_RC_NAME` starts with the container and is ready in the app straight away.
  After a restart you get a new session.
- **`server`:** runs `claude remote-control --name <name>`. It registers an
  environment and creates sessions when you start them from the app
  (`CLAUDE_RC_SPAWN_MODE`, `CLAUDE_RC_CAPACITY`).

Several stacks can share one config folder (one login) as long as each has its own
`CLAUDE_RC_NAME`.

- It needs a one-time setup. Until it's done, nothing is started: the container
  prints the steps in `docker compose logs` and reports **unhealthy**.
  1. Log in with a claude.ai account: `docker compose exec -u claude claude claude auth login`.
     API keys and `CLAUDE_CODE_OAUTH_TOKEN` can't be used for Remote Control.
  2. Start Remote Control once, answer **y** to "Enable Remote Control?", then press Ctrl+C:
     `docker compose exec -u claude claude claude remote-control`.
  3. Restart the container: `docker compose restart claude`.

  Both are saved in the config volume, so this is needed only once.
- Its terminal output (URL, errors) is in `/tmp/remote-control.log`:
  `docker compose exec claude cat /tmp/remote-control.log`.
- `CLAUDE_PERMISSION_MODE=bypassPermissions` lets Claude act without asking. The
  container is the sandbox, but Claude can still do anything your mounted workspace,
  tokens and network allow.

## Image variants

Every release is published in these variants, built from the same commit and
updated together:

| Variant | Tags | Extra packages |
|---|---|---|
| slim | `latest`, `X.Y.Z`, `X.Y`, `X` | none |
| python | `python`, `X.Y.Z-python`, `X.Y-python`, `X-python` | `python3`, `python3-venv`, `python3-pip`, `python-is-python3`, `curl`, `git`, `openssh-client`, [uv](https://docs.astral.sh/uv/) |

Pick one in `.env`:

```dotenv
CLAUDE_IMAGE=ghcr.io/thedeniz/claude-container:python
```

The Python variant has Debian's Python (`python` and `python3`), `pip` and `venv`,
[uv](https://docs.astral.sh/uv/), `git` (with `openssh-client` for SSH remotes) and
`curl`. Debian's Python is externally managed, so packages go into a virtual
environment in your project, which also keeps them across restarts:

- `uv venv` and `uv pip install …`, or `uv add …` in a uv project (fast, and the
  managed `CLAUDE.md` tells Claude to prefer it), or `python3 -m venv .venv`.
- Need another Python version? `uv venv --python 3.12` downloads it. uv keeps the
  Pythons it downloads in the config volume (`UV_PYTHON_INSTALL_DIR`), so venvs that
  use them still work after the container is recreated.

There is no compiler: packages without a prebuilt wheel need a
[local build](#optional-tools) with `build-essential python3-dev` added. A local build
can also add uv with `WITH_UV=true`.

## Configuration

Every setting is an environment variable. See [`.env.example`](.env.example) for all of them.

| Variable | Default | Description |
|---|---|---|
| `WORKSPACE_PATH` | `./workspace` | Host folder mounted at `/workspace` |
| `CLAUDE_CONFIG_PATH` | `claude-config` | Docker volume name **or** host path for login/settings (`/home/claude/.claude`) |
| `PUID` / `PGID` | `1000` | UID/GID Claude runs as. Match your host user so workspace files stay yours |
| `CLAUDE_REMOTE_CONTROL` | `false` | Start the Remote Control server on container start |
| `CLAUDE_RC_NAME` | `claude-container` | Remote Control name (also the container hostname); unique per stack |
| `CLAUDE_RC_MODE` | `session` | `session`: one named session at start; `server`: sessions on demand from the apps |
| `CLAUDE_RC_SPAWN_MODE` | `same-dir` | Server mode: `same-dir`, `worktree` or `session` |
| `CLAUDE_RC_CAPACITY` | | Server mode: max concurrent sessions |
| `CLAUDE_RC_EXTRA_ARGS` | | Extra flags for the Remote Control command |
| `CLAUDE_PERMISSION_MODE` | `default` | Permission mode for Remote Control sessions |
| `CLAUDE_AUTO_UPDATE` | `false` | `true`: run `claude update` on start and allow the built-in auto-updater |
| `CLAUDE_TRUST_WORKSPACE` | `true` | Pre-accept the trust prompt for `/workspace` |
| `ANTHROPIC_API_KEY` | | Optional API-key auth for normal sessions |
| `CLAUDE_CODE_OAUTH_TOKEN` | | Optional long-lived token (`claude setup-token`) for normal sessions |
| `GH_TOKEN` | | Token for `gh`, if you add it (see [Optional tools](#optional-tools)) |
| `TZ` | `UTC` | Time zone (other than UTC needs `tzdata` added) |

### Persistent config

`CLAUDE_CONFIG_DIR` is set to the mounted folder, so it holds **everything** Claude
keeps: credentials, `settings.json`, `.claude.json` (project trust, onboarding), session
history, agents, skills and plugins. To keep it in a normal folder, for example to
back it up or share it between hosts:

```dotenv
CLAUDE_CONFIG_PATH=./claude-config
```

### CLAUDE.md files

Claude reads three instruction files, and each has its own place:

| File | Who owns it | Kept |
|---|---|---|
| `/etc/claude-code/CLAUDE.md` | the image: describes the container (paths, what persists, installed tools) | replaced with each image update |
| `~/.claude/CLAUDE.md` | you: personal instructions for every project | in the config volume |
| `/workspace/CLAUDE.md` | your project | in your project, never touched by the image |

The managed file lists the extra packages the image was built with, so Claude knows
whether it has `git` and other tools. You can't edit it, and you don't need to: your
own files add to it.

### Updates

- **Image (default):** each release pins one Claude Code CLI version. Upgrade by
  pulling a newer tag (`docker compose pull && docker compose up -d` when you follow
  `latest` or a major/minor tag).
- **In place:** `CLAUDE_AUTO_UPDATE=true` runs `claude update` on every start and lets
  the CLI update itself while it runs.

## Status

```console
$ docker compose exec claude claude-status
Claude Code      2.1.283
Login            claude.ai, you@example.com
Remote Control   running for 2h 5m as "claude-container" (server, spawn: same-dir, permissions: default)
Remote sessions  2
  cse_01ABC…                     up 41m      /workspace
                                 https://claude.ai/code/session_01ABC…
  cse_02DEF…                     up 3m       /workspace
                                 https://claude.ai/code/session_02DEF…
Local sessions   1
```

**Remote sessions** are the background sessions a Remote Control server started for
the Claude apps. In session mode the Remote Control line shows that session's link
instead. **Local sessions** are the ones opened with `docker compose exec … claude`. Add
`--json` for machine-readable output.

## Health check

`healthcheck` runs every 30 s (`docker compose ps` shows the result). The container
is healthy when:

1. the Claude CLI runs,
2. the config dir is writable, and
3. with `CLAUDE_REMOTE_CONTROL=true`, the Remote Control server is running.

Its message includes the number of remote sessions, e.g.
`OK: Remote Control running, 2 remote session(s)`
(`docker inspect --format '{{json .State.Health}}' claude`).

## Building locally

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```

Build args: `CLAUDE_VERSION` (defaults to the version pinned in the `Dockerfile`; also
`latest`, `stable` or `X.Y.Z`) and `EXTRA_APT_PACKAGES` (see below, also settable in
`.env`).

### Optional tools

The published image is kept slim: it has only what Claude Code itself needs. Add
Debian packages at build time:

```dotenv
# .env
EXTRA_APT_PACKAGES="git gh openssh-client tmux"
```

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```

Without `git`, Claude still reads, edits and runs code, but has no git context
(branch, status, diffs), can't commit and can't use worktrees
(`CLAUDE_RC_SPAWN_MODE=worktree`). For most coding work you'll want at least `git`.
Other common additions: `openssh-client` (git over SSH), `gh` (GitHub CLI),
`python3`, `nodejs npm` (many MCP servers), `tzdata`, `less`.

### Possible expansions

Ideas for making tools easier to get without giving up updatable images.

- **Choose a feature set up front (preferred).** Decide which tools you need when you
  set the container up, commit to that choice, and switch deliberately later. The
  options below should support that, not replace it.
- **Several published images.** Started with the [`python`](#image-variants)
  variant. More can be added the same way (a matrix entry in
  [`docker.yml`](.github/workflows/docker.yml)), e.g. `-git` (git, openssh-client,
  gh) or `-node` (nodejs, npm). Changing the feature set then means changing the
  image tag, with no local build, and every variant keeps getting updates.
- **Remember and reinstall (last resort, not built).** Record the packages installed at runtime
  in the config volume and reinstall them on every start, before Remote Control
  starts. This makes tools survive image updates, but at a cost: every start gets
  slower and needs network access, root is needed at runtime, and the tool set can
  drift away from what the image was tested with.

## Versions and releases

The image has one version, `X.Y.Z`, set by
[semantic-release](https://semantic-release.gitbook.io/) from
[conventional commits](https://www.conventionalcommits.org/) on `main`. A published
`X.Y.Z` image is never rebuilt or overwritten.

| Commit type | Release |
|---|---|
| `fix:`, `perf:`, e.g. `fix(deps): bump Claude Code CLI …` | patch |
| `feat:` | minor |
| `feat!:` or a `BREAKING CHANGE:` footer | major |
| `chore:`, `ci:`, `docs:`, `refactor:`, `test:`, `build:` | none |

Dependencies are pinned and bumped through pull requests:

- **Claude Code CLI** (`ARG CLAUDE_VERSION`) and **uv** (`ARG UV_VERSION`) in the
  `Dockerfile`: [`update-deps.yml`](.github/workflows/update-deps.yml) checks npm and
  PyPI every night and opens or updates one `fix(deps):` PR per tool
  (`feat(deps)!:` for a new major version, or a new minor version of a 0.x tool).
  Reword its commit to `feat`/`feat!` if the new version changes behaviour users
  rely on.
- **Base image** (pinned by digest) and **GitHub Actions**: Dependabot, as `fix(deps):`
  and `chore(deps):` respectively.

Flow: bump PR → CI builds and smoke-tests → rebase-merge → semantic-release tags
`vX.Y.Z` and writes the GitHub release → the image is built and pushed.

### Image tags

| Tag | Moves? |
|---|---|
| `X.Y.Z` | never |
| `X.Y`, `X` | to the newest matching release |
| `latest` | to the newest release |

The [Python variant](#image-variants) has the same tags with a `-python` suffix,
and `python` instead of `latest`.

The Claude Code version inside is in the image label `dev.claude-code.version` and in the
GitHub release notes; the variant is in `dev.claude-container.variant`.

### Repository setup

- Merge PRs with **rebase**. Every commit lands on `main` as-is and semantic-release
  reads each one, so every commit must be a conventional commit. The
  "Commit messages" check lints all of a PR's commits
  ([`.commitlintrc.json`](.commitlintrc.json)).
- Settings → Actions → General: allow GitHub Actions to create pull requests (for the
  CLI bump PRs).
- Optional: a `BOT_TOKEN` secret (fine-grained PAT or GitHub App token with contents and
  pull-requests write) so CI also runs on the CLI bump PRs. PRs opened with the
  default token don't trigger workflows.
- After the first release, make the GHCR package public if others should pull it.

## What's inside

`debian:trixie-slim` (glibc, about 30 MB to download) plus `ca-certificates`, `jq`,
`procps`, `gosu` and `tini`, and the Claude Code CLI (about 240 MB, most of the image),
installed with the official native installer in a separate build stage so the installer
and `curl` stay out of the image. Claude Code ships its own ripgrep.
