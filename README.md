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
- [Core library](#core-library)
- [For AI agents](#for-ai-agents)
- [Author](#author)

## Requirements

| Tool | Version |
|---|---|
| ![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white) | Any recent |
| ![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white) | 3.2, the system `/bin/bash` |
| ![Git](https://img.shields.io/badge/Git-F05032?logo=git&logoColor=white) | Any |

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
| [`Scripts/Kings/`](Scripts/Kings/) | The core commands |
| [`install/`](install/) | Install and uninstall |
| [`templates/layer/`](templates/layer/) | Starting point for a new layer |

**Machine** (`~/.kingsScripts/`, never committed):

| Path | What it is |
|---|---|
| `bin/kings` | The command |
| `config.env` | Machine settings, loaded by every command |
| `layers` | Registered layers, one path per line |
| `cache.txt` | `key=value` state shared by every command |
| `logs/` | One `YYYY-MM-DD.log` per day — past months zipped as `YYYY-MM.zip` |
| `git-hooks/` | Global git hooks, all forwarding to the layers |
| `backup/` | `.zshrc` copies taken by the installer |

## Commands

| Command | What it does |
|---|---|
| `kings help` | Lists every command: core first, then each layer |
| `kings layer list \| add \| remove \| create` | Manages the layers of this machine |
| `kings hooks on \| off \| status` | Turns every layer's git hooks on or off |
| `kings checkup [--force]` | Runs the periodic tasks now |
| `kings secret set \| delete \| status <NAME>` | Keeps secrets in the Keychain — `set` asks for the value |

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

A task runs at most once per period, counting only successful runs. The core has one:
`log-archive` (monthly).

## Core library

Loaded with `. "$KINGS_CORE/<module>.sh"`.

| Module | Functions |
|---|---|
| `print.sh` | `print_info`, `print_title`, `print_success`, `print_warn`, `print_error` — stderr and log |
| `log.sh` | `log <message>`, `log_run <cmd>` (output to the log only), `log_file` |
| `secrets.sh` | `secret_get <NAME>` — env var first, then Keychain; `secret_set`, `secret_delete`, `secret_source` |
| `cache.sh` | `cache_get`, `cache_set`, `cache_unset` |
| `notify.sh` | `notify_banner`, `notify_alert`, `notify_dialog` |
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
