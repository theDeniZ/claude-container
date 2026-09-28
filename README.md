# claude-container

Run [Claude Code](https://docs.claude.com/en/docs/claude-code) in a container with:

- your project mounted at `/workspace`
- a pinned, up-to-date Claude Code CLI (a bot opens a bump PR for every new CLI release)
- login, settings and sessions kept in a volume or a folder you choose
- an optional background **Remote Control** server, so you can drive Claude from
  [claude.ai/code](https://claude.ai/code) or the Claude mobile app
- a built-in health check
- files written with your own UID/GID, not root

Image: `ghcr.io/thedeniz/claude-container` (linux/amd64, linux/arm64). See [Versions and releases](#versions-and-releases).

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
CLAUDE_RC_NAME=my-server              # name shown in the Claude apps
CLAUDE_PERMISSION_MODE=default        # or acceptEdits | auto | plan | dontAsk | bypassPermissions
```

Then run `docker compose up -d`. A `claude remote-control` server starts in the
background in `/workspace` and is restarted if it exits. Open the **Code** tab in the
Claude app or [claude.ai/code](https://claude.ai/code) and pick the environment.

- It needs a claude.ai login made with `claude auth login` (see above). API keys and
  `CLAUDE_CODE_OAUTH_TOKEN` can't be used for Remote Control. Until you log in, the
  container waits, says so in `docker compose logs`, and reports **unhealthy**.
- The server runs in a tmux session. To see it (e.g. its URL or a first-run prompt):
  `docker compose exec -u claude claude tmux attach -t remote-control` (detach with
  `Ctrl-b d`). Its output is also written to `/tmp/remote-control.log`.
- `CLAUDE_PERMISSION_MODE=bypassPermissions` lets Claude act without asking. The
  container is the sandbox, but Claude can still do anything your mounted workspace,
  tokens and network allow.

## Configuration

Every setting is an environment variable. See [`.env.example`](.env.example) for all of them.

| Variable | Default | Description |
|---|---|---|
| `WORKSPACE_PATH` | `./workspace` | Host folder mounted at `/workspace` |
| `CLAUDE_CONFIG_PATH` | `claude-config` | Docker volume name **or** host path for login/settings (`/home/claude/.claude`) |
| `PUID` / `PGID` | `1000` | UID/GID Claude runs as. Match your host user so workspace files stay yours |
| `CLAUDE_REMOTE_CONTROL` | `false` | Start the Remote Control server on container start |
| `CLAUDE_RC_NAME` | `claude-container` | Remote Control name (also the container hostname) |
| `CLAUDE_RC_SPAWN_MODE` | `same-dir` | `same-dir`, `worktree` or `session` |
| `CLAUDE_RC_CAPACITY` | | Max concurrent remote sessions |
| `CLAUDE_RC_EXTRA_ARGS` | | Extra flags for `claude remote-control` |
| `CLAUDE_PERMISSION_MODE` | `default` | Permission mode for Remote Control sessions |
| `CLAUDE_AUTO_UPDATE` | `false` | `true`: run `claude update` on start and allow the built-in auto-updater |
| `CLAUDE_TRUST_WORKSPACE` | `true` | Pre-accept the trust prompt for `/workspace` |
| `ANTHROPIC_API_KEY` | | Optional API-key auth for normal sessions |
| `CLAUDE_CODE_OAUTH_TOKEN` | | Optional long-lived token (`claude setup-token`) for normal sessions |
| `GH_TOKEN` | | Token for the bundled GitHub CLI |
| `TZ` | `UTC` | Time zone |

### Persistent config

`CLAUDE_CONFIG_DIR` is set to the mounted folder, so it holds **everything** Claude
keeps: credentials, `settings.json`, `.claude.json` (project trust, onboarding), session
history, agents, skills and plugins. To keep it in a normal folder, for example to
back it up or share it between hosts:

```dotenv
CLAUDE_CONFIG_PATH=./claude-config
```

### Updates

- **Image (default):** each release pins one Claude Code CLI version. Upgrade by
  pulling a newer tag (`docker compose pull && docker compose up -d` when you follow
  `latest` or a major/minor tag).
- **In place:** `CLAUDE_AUTO_UPDATE=true` runs `claude update` on every start and lets
  the CLI update itself while it runs.

## Health check

`healthcheck` runs every 30 s (`docker compose ps` shows the result). The container
is healthy when:

1. the Claude CLI runs,
2. the config dir is writable, and
3. with `CLAUDE_REMOTE_CONTROL=true`, the Remote Control server is running.

## Building locally

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```

Build args: `CLAUDE_VERSION` (defaults to the version pinned in the `Dockerfile`; also
`latest`, `stable` or `X.Y.Z`) and `EXTRA_APT_PACKAGES` (e.g. `"python3 nodejs"`, also
settable in `.env`).

## Versions and releases

The image has one version, `X.Y.Z`, set by
[semantic-release](https://semantic-release.gitbook.io/) from
[conventional commits](https://www.conventionalcommits.org/) on `main`. A published
`X.Y.Z` image is never rebuilt or overwritten.

| Commit type (squash-merged PR title) | Release |
|---|---|
| `fix:`, `perf:`, e.g. `fix(deps): bump Claude Code CLI …` | patch |
| `feat:` | minor |
| `feat!:` or a `BREAKING CHANGE:` footer | major |
| `chore:`, `ci:`, `docs:`, `refactor:`, `test:`, `build:` | none |

Dependencies are pinned and bumped through pull requests:

- **Claude Code CLI:** `ARG CLAUDE_VERSION` in the `Dockerfile`.
  [`update-claude-cli.yml`](.github/workflows/update-claude-cli.yml) checks npm every
  night and opens or updates a `fix(deps):` PR (`feat(deps)!:` for a new CLI major).
  Retitle it `feat`/`feat!` if the new CLI changes behaviour users rely on.
- **Base image** (pinned by digest) and **GitHub Actions**: Dependabot, as `fix(deps):`
  and `chore(deps):` respectively.

Flow: bump PR → CI builds and smoke-tests → squash-merge → semantic-release tags
`vX.Y.Z` and writes the GitHub release → the image is built and pushed.

### Image tags

| Tag | Moves? |
|---|---|
| `X.Y.Z` | never |
| `X.Y`, `X` | to the newest matching release |
| `latest` | to the newest release |

The Claude Code version inside is in the image label `dev.claude-code.version` and in the
GitHub release notes.

### Repository setup

- Merge PRs with **squash** and use the PR title as the commit message (a check makes
  sure PR titles are conventional commits).
- Settings → Actions → General: allow GitHub Actions to create pull requests (for the
  CLI bump PRs).
- Optional: a `BOT_TOKEN` secret (fine-grained PAT or GitHub App token with contents and
  pull-requests write) so CI also runs on the CLI bump PRs. PRs opened with the
  default token don't trigger workflows.
- After the first release, make the GHCR package public if others should pull it.

## What's inside

Debian bookworm-slim plus `git`, `gh`, `curl`, `jq`, `ripgrep`, `tmux`,
`openssh-client`, `less`, `nano`, `procps`, `unzip`, `tini` and `gosu`. Claude Code is
installed with the official native installer.
