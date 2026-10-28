# KingsScript

![Language](https://img.shields.io/badge/language-Bash-blue?logo=gnubash)
![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)
[![License](https://img.shields.io/badge/license-GPL--3.0-brightgreen)](./LICENSE)

</br>

Personal scripts behind a single command, `kings`: a generic core, plus one **layer** per company
or project.

- Improve reuse: logs, prints, secrets and cache live in the core, and every layer uses them.
- Improve portability: company-specific scripts stay in their own repo, plugged in when needed.

#### Index

- [Requirements](#requirements)
- [Install](#install)
- [Structure](#structure)
- [Commands](#commands)
- [Layers](#layers)
  - [Git hooks](#git-hooks)
  - [Checkup](#checkup)
  - [Schedule](#schedule)
- [Core library](#core-library)
- [For AI agents](#for-ai-agents)
- [Contributing](#contributing)
- [Author](#author)

## Requirements

| Tool | Version |
|---|---|
| ![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white) | Any recent |
| ![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white) | 3.2, the system `/bin/bash` |
| ![Git](https://img.shields.io/badge/Git-F05032?logo=git&logoColor=white) | Any |

Some commands need more — each one says so when it's missing:

| Tool | Used by |
|---|---|
| `gh` (logged in) | `git-prreview` |
| `swiftformat` | `git-swiftformatstaged` |
| Xcode | `xcode-*` |
| `jq` | `slack-test` |
| Python 3 | `graph`, `docs-check`, `site-icon`, `mail` (plus a Google Cloud OAuth client, see [its README](Scripts/Mail/Gmail/)) |
| Graphify | `graph` |
| Node 20+ and `npm install --prefix Scripts/Design/Figma` | `fig-*` |
| ImageMagick, plus Chrome or `rsvg-convert` for SVG icons | `site-icon` |

## Install

```bash
# Clone anywhere — the repo stays there, the installer only records its path
git clone https://github.com/Kings-Platform/KingsScript.git

# Install: ~/.kingsScripts, the kings command, git hooks and a block in ~/.zshrc
./KingsScript/install/install.sh

# Load it in the current terminal and check
source ~/.zshrc
kings help

# Register the layers this machine uses
kings layer add /path/to/some-layer
```

> [!NOTE]
> Run the install again after moving the repo. To remove it: `./KingsScript/install/uninstall.sh`
> (add `--purge` to also delete `~/.kingsScripts`).

## Structure

**Repo:**

| Folder | What it is |
|---|---|
| [`Scripts/main.sh`](Scripts/main.sh) | Dispatcher — core commands first, then each layer |
| [`Scripts/Core/`](Scripts/Core/) | Shared library (see [Core library](#core-library)) |
| [`Scripts/Kings/`](Scripts/Kings/) | Commands that manage `kings` itself |
| `Scripts/<Area>/<Subject>/` | Every other command, one folder per subject — with a `README.md` when it needs one |
| [`install/`](install/) | Install and uninstall |
| [`templates/layer/`](templates/layer/) | Starting point for a new layer |

**Machine** (`~/.kingsScripts/`, never committed):

| Path | What it is |
|---|---|
| `bin/kings` | The command |
| `config.env` | Machine settings, loaded by every command — see [`config.example.env`](install/config.example.env) |
| `layers` | Registered layers, one path per line |
| `cache.txt` | `key=value` state shared by every command |
| `logs/` | One `YYYY-MM-DD.log` per day — past months zipped as `YYYY-MM.zip` |
| `git-hooks/` | Global git hooks, all forwarding to the layers |
| `backup/` | `.zshrc` copies taken by the installer |

## Commands

**Kings:**

| Command | What it does |
|---|---|
| `kings help` | Lists every command: core first, then each layer |
| `kings layer list \| add \| remove \| create` | Manages the layers of this machine |
| `kings hooks on \| off \| status` | Turns every layer's git hooks on or off |
| `kings checkup [--force]` | Runs the periodic tasks now |
| `kings secret set \| delete \| status <NAME>` | Keeps secrets in the Keychain — `set` asks for the value |
| `kings schedule add \| list \| run \| check \| logs \| enable \| disable \| remove` | Runs a script or a Claude prompt at a fixed time of day, through launchd |

**Tools:**

| Area | Command | What it does |
|---|---|---|
| [Git](Scripts/Git/) | `git-swiftformatstaged` | Formats the staged `.swift` files and stages them again — partially staged files are skipped |
| | `git-prreview <PR>` | PR review comments as a markdown table |
| | `git-deletebranch [branch]` | Deletes a local branch, the current one by default |
| [Xcode](Scripts/Xcode/) | `xcode-simulator [device]` | Opens the Simulator, booting the device if given |
| | `xcode-deeplink <url>` | Opens a URL in the booted simulator |
| [Slack](Scripts/Slack/Test/) | `slack-test [channel]` | Reads and posts in a channel to check a Slack app |
| [Installers](Scripts/Installers/) | `install-tabby` | Installs Tabby without admin rights |
| | `install-gem <gem> [version]` | Installs a Ruby gem without admin rights |
| [AI](Scripts/AI/) | [`graph`](Scripts/AI/Graph/) | Queries the repo's Graphify dependency graph |
| | [`docs-check`](Scripts/AI/DocsCheck/) | Finds broken links, anchors and orphan pages in docs |
| | [`ai-update [--auto]`](Scripts/AI/Update/ai-update.sh) | Updates the installed Claude Code plugins — pulls marketplaces that are local clones first |
| | [`ai-session <name> [--dir DIR] [--resume ID]`](Scripts/AI/Session/ai-session.sh) | Starts a Claude Code session in a detached tmux session with Remote Control on (new, or `--resume` an existing one); refuses a name already in use. Auto-update is off in these sessions (`DISABLE_AUTOUPDATER=1`): a long-lived session reinstalls the binary on every check, which breaks scheduled jobs; update once a day instead |
| [Design](Scripts/Design/Figma/) | `fig-parse <file.fig>` | Extracts layout, colors and text from a Figma file |
| | `fig-check [file.fig]` | Regression check of `fig-parse` |
| | [`site-icon <url>`](Scripts/Design/SiteIcon/site-icon.sh) | Saves the icon a site shows in the browser tab as a transparent PNG (`--size`, `--out`, `--name`; `--list` shows the candidates, `--source` picks one) |
| [Mail](Scripts/Mail/Gmail/) | `mail send \| attachments \| auth \| status` | Sends Gmail messages with attachments (or leaves a draft) and downloads attachments, as the account in `config.env` — setup in its README |

Exit codes: `0` success · `1` error · `127` unknown command.

## Layers

A layer is a separate repo (or folder) with its own commands, git hooks and periodic tasks.
`kings layer create <path>` scaffolds one.

| File | Role |
|---|---|
| `layer.env` | `LAYER_NAME`, shown in `kings help` and in the logs |
| `main.sh` | The layer's commands |
| `hooks/<hook>.sh` | Git hooks (optional) |
| `checkup.sh` | Periodic tasks (optional) |
| `Scripts/` | The scripts themselves |

`main.sh` is a `case` over the command name:

```bash
case "$cmd" in
  help)   printf '  %-34s %s\n' "deploy <env>" "Deploys the app" ;;   # one line per command
  deploy) exec "$LAYER_DIR/Scripts/Deploy/deploy.sh" "$@" ;;
  *)      exit 127 ;;                                                  # not mine: next layer
esac
```

Every command:

- takes input as arguments and never prompts — if it must, its `help` line says so
- prints the result to stdout and messages through `print_*`
- exits `0` or `1` — `127` only means "not mine"

### Git hooks

Every hook of every repo goes through `kings hooks run <hook>`, which:

1. Runs the repo's own `.git/hooks/<hook>` — git skips it when `core.hooksPath` is global
2. Runs each layer's `hooks/<hook>.sh`, unless `kings hooks off`

Hooks run in all repos, so a project-specific one checks `git config --get remote.origin.url`
first and exits `0` elsewhere.

### Checkup

Each new terminal runs `kings checkup` in the background. `checkup.sh` registers the tasks:

```bash
checkup_task cleanup weekly "$LAYER_DIR/Scripts/Cleanup/cleanup.sh"   # daily | weekly | monthly
```

A task runs at most once per period, counting only successful runs. The core has two:

| Task | Period | What it does |
|---|---|---|
| `log-archive` | Monthly | Zips last month's logs |
| `ai-update` | Daily | `kings ai-update --auto` — skips a marketplace clone that isn't clean and on its default branch, and notifies when a plugin was updated |

### Schedule

`kings checkup` runs when a terminal opens; `kings schedule` runs a job at a fixed time of day with every terminal closed, through a launchd agent per job.

```bash
kings schedule add backup --at 14:00 --script "kings some-command"                  # a shell command, no AI
kings schedule add digest --at 15:00 --days weekdays --ai @/path/prompt.md          # a headless Claude Code prompt
kings schedule list                    # name, time, kind, on/off, result of the last run
kings schedule run digest              # run it now (log in $KINGS_HOME/schedules/logs/digest/)
kings schedule check digest            # start it through launchd, as the schedule would
```

| Option | Meaning |
|---|---|
| `--at HH:MM` | 24h time, required |
| `--days` | `daily` (default), `weekdays` or a list such as `mon,wed,fri` |
| `--script <command>` / `--ai <prompt or @file>` | What runs. A prompt starting with `@` is read from that file on every run |
| `--model`, `--permission-mode`, `--claude-args` | For `--ai`: model (default `sonnet`), Claude Code permission mode and extra flags (e.g. `--allowedTools ...`) |
| `--workdir`, `--timeout` | Where it runs, and the limit in seconds (AI jobs default to 3600; exit 124 when hit) |
| `--notify` | A command run after a scheduled run that succeeded; the last line it prints becomes a Notification Center banner titled with the job's name. Use it instead of asking an `--ai` job to notify: a headless Claude session can't reach Notification Center |
| `--on-start`, `--on-finish` | Commands run before and after every run (scheduled or `run`), e.g. to open and close a report page. They get `KINGS_JOB_NAME`, `KINGS_JOB_STATUS` (`running`, then `ok` or `failed`), `KINGS_JOB_EXIT` and `KINGS_JOB_LOG`. The start hook's last output line reaches the job itself and the finish hook as `KINGS_JOB_REF`. A failing hook is logged and never fails the job |
| `--replace` | Overwrite a job with the same name |

- Jobs live in `$KINGS_HOME/schedules/`, never in the repo, so a layer's private jobs stay private.
- The agent calls `kings schedule run <name> --scheduled` with the `PATH` the job was added with. A failure shows a macOS notification; the last 30 logs per job are kept.
- `--ai` jobs run the installed `claude` with auto-update off (`DISABLE_AUTOUPDATER=1`): a run whose executable is replaced mid-way loses its macOS file permissions. Never a copy of the binary: macOS ties the `~/Documents` permission to the executable's path, so a copy at a new path stops on a permission prompt.
- `--ai` jobs use the interactive login, the only one that reaches the claude.ai connectors (Gmail, Calendar, Notion). Its OAuth session can expire while nobody is at the machine; the run then fails at start and is retried once with the secret `CLAUDE_CODE_OAUTH_TOKEN` when it is set (`claude setup-token`, then `kings secret set CLAUDE_CODE_OAUTH_TOKEN`), which signs in but has no connectors.
- If the Mac sleeps at the scheduled time, launchd runs the job when it wakes. It can't wake the Mac: that takes `sudo pmset repeat wakeorpoweron ...`.
- macOS blocks launchd from reading `~/Documents`, `~/Desktop` and `~/Downloads` unless `/bin/bash` has Full Disk Access (System Settings › Privacy & Security). `add` warns when KingsScript lives there; `check` proves the job starts.
- `KINGS_LAUNCH_AGENTS` (agents folder) and `KINGS_SCHEDULE_NO_LOAD=1` (skip launchctl) exist for testing.

## Core library

Loaded with `. "$KINGS_CORE/<module>.sh"`.

| Module | Functions |
|---|---|
| `print.sh` | `print_info`, `print_title`, `print_success`, `print_warn`, `print_error` — stderr and log |
| `log.sh` | `log <message>`, `log_run <cmd>` (output to the log only), `log_file` |
| `secrets.sh` | `secret_get <NAME>` — env var first, then Keychain; `secret_set`, `secret_delete`, `secret_source` |
| `cache.sh` | `cache_get`, `cache_set`, `cache_unset` |
| `notify.sh` | `notify_banner`, `notify_alert`, `notify_dialog` |
| `zshrc.sh` | `zshrc_set_block <name> <content>`, `zshrc_remove_block`, `zshrc_has_block` — named blocks in `~/.zshrc` |
| `timer.sh` | `timer_elapsed` — `HH:MM:SS` since the script started |
| `layers.sh` | `layers_list`, `layer_name`, `layer_is_valid` |

Layer scripts also get `KINGS_CORE`, `KINGS_ROOT`, `KINGS_HOME`, `KINGS_CMD` and everything in
`config.env`. Log lines look like:

```
[2026-09-29 14:03:12] [acme:deploy #48213] Deploying to staging
```

## For AI agents

- `kings help` lists what exists — prefer a command over a one-off script
- Not on the `PATH`? Call `~/.kingsScripts/bin/kings`
- Result on stdout, messages on stderr, no colors outside a terminal
- Debug with today's log, filtering by the command label (`[acme:deploy`)
- Ask before `install/*.sh`, `layer add | remove` and `secret set | delete`

Snippet for the agent's global instructions (`~/.claude/CLAUDE.md`, `AGENTS.md`):

```markdown
## KingsScript
Personal scripts run through `kings <command>` (or `~/.kingsScripts/bin/kings`). Run
`kings help` before writing a new script; new personal scripts become `kings` commands.
Logs: `~/.kingsScripts/logs/<date>.log`. Docs: https://github.com/Kings-Platform/KingsScript
```

## Contributing

Script structure, rules and how to test: [CONTRIBUTING.md](CONTRIBUTING.md).

</br>

---

## Author

<table>
    <tr>
        <td align="center">
            <a href="https://github.com/Gui25Reis">
                <img src="https://avatars1.githubusercontent.com/u/48360732" width="100px;" alt="Gui Reis's profile picture at GitHub"/><br>
                <sub>
                    <b>Gui Reis</b>
                </sub>
            </a>
        </td>
    </tr>
</table>
