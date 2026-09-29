# KingsScript

Personal productivity scripts behind a single command: `kings <command> [args...]`.

The core is generic and reusable anywhere. Everything tied to a company or project lives in a
**layer**: a separate repository that plugs its own commands, git hooks and periodic tasks into
`kings`, and uses the core library (logs, prints, secrets, cache) instead of reinventing it.

Built to be used by people and by AI agents alike: every command runs without a terminal,
keeps results on stdout and messages on stderr, and has predictable exit codes.

## Install

Requirements: macOS and `git`. Clone anywhere; the repository stays where it is and the
installer only records its path.

```bash
cd ~/Documents/GitHub   # any folder
git clone https://github.com/Kings-Platform/KingsScript.git
./KingsScript/install/install.sh
source ~/.zshrc
kings help
```

Then register the layers this machine uses:

```bash
kings layer add /path/to/some-layer
kings help   # the layer's commands now show up
```

What the installer does:

- creates `~/.kingsScripts/`, the machine state (see below);
- writes the `kings` executable to `~/.kingsScripts/bin/`;
- adds a marked block to `~/.zshrc`: that folder on the `PATH`, plus the background checkup;
- points the global `core.hooksPath` to `~/.kingsScripts/git-hooks/`, saving any previous value.

Run it again after moving the repository. To remove it:

```bash
./KingsScript/install/uninstall.sh           # keeps ~/.kingsScripts (logs, config, layers)
./KingsScript/install/uninstall.sh --purge   # removes it too
```

## Machine state: `~/.kingsScripts/`

| Path | Content |
|---|---|
| `config.env` | Machine settings, sourced (and exported) by every command |
| `layers` | Registered layers, one path per line, in lookup order |
| `cache.txt` | `key=value` state shared by every command |
| `logs/YYYY-MM-DD.log` | One log per day; past months are zipped into `logs/YYYY-MM.zip` |
| `bin/kings` | The command itself |
| `git-hooks/` | Global git hook stubs |
| `backup/` | `.zshrc` copies taken by the installer |

Override the location with `KINGS_HOME`.

## Core commands

| Command | Does |
|---|---|
| `help` | Core commands, then each layer's commands |
| `layer list \| add <path> \| remove <name\|path> \| create <path> [name]` | Manage layers |
| `hooks on \| off \| status` | Toggle every layer's git hooks without touching `core.hooksPath` |
| `checkup [--force]` | Run periodic tasks now (normally automatic, see below) |
| `secret set \| delete \| status <NAME>` | Manage secrets in the Keychain; values are never printed. `set` prompts, so it needs a terminal |

Exit codes: `0` success, `1` error or wrong usage, `127` unknown command.

## For AI agents

- `kings help` lists every command available on the machine, core and layers. Prefer an
  existing command over writing a one-off script.
- Shells that don't load `~/.zshrc` may not have `kings` on the `PATH`; call
  `~/.kingsScripts/bin/kings` instead.
- The result of a command is on stdout; progress and errors are on stderr, without colors when
  not on a terminal.
- To debug a run, read today's log, `~/.kingsScripts/logs/$(date +%Y-%m-%d).log`, and filter by
  the command label (e.g. `[acme:deploy`).
- Ask the user before running anything that changes the machine setup: `install/*.sh`,
  `layer add|remove`, `secret set|delete`.

Snippet for an agent's global instructions (`~/.claude/CLAUDE.md`, `AGENTS.md`):

```markdown
## KingsScript
Personal scripts run through `kings <command>` (or `~/.kingsScripts/bin/kings` when not on
the PATH). Run `kings help` to see what exists before writing a new script; new personal
scripts become `kings` commands. Logs: `~/.kingsScripts/logs/<date>.log`.
Docs: https://github.com/Kings-Platform/KingsScript
```

## Layers

```
my-layer/
  layer.env      # LAYER_NAME="my-layer"
  main.sh        # the layer's commands
  hooks/         # optional: <git-hook>.sh
  checkup.sh     # optional: periodic tasks
  Scripts/       # the actual scripts
```

`kings layer create <path>` scaffolds one from [templates/layer/](templates/layer/);
`kings layer add <path>` registers it.

**Commands.** `kings <cmd>` first tries the core, then each layer's `main.sh <cmd> [args]`, in
registration order. A layer's `main.sh` is a `case` that must:

- print its commands for `help`, one line each;
- exit **127** for a command it doesn't own. That's the shell's "command not found" code, so
  the dispatcher can tell "not mine, try the next layer" apart from "mine, and it failed".

```bash
case "$cmd" in
  help)  printf '  %-34s %s\n' "deploy <env>" "Deploy the app" ;;
  deploy) exec "$LAYER_DIR/Scripts/Deploy/deploy.sh" "$@" ;;
  *)     exit 127 ;;
esac
```

Every command, so that people and agents can use it the same way:

- takes its input as arguments and never prompts; a command that must prompt says so in its
  `help` line;
- prints its result to stdout and messages through `print_*`;
- exits `0` on success and `1` on failure (`127` is reserved for "not mine").

**Environment.** Layer scripts receive `KINGS_CORE` (core library), `KINGS_ROOT`,
`KINGS_HOME`, `KINGS_CMD` (`<layer>:<command>`, used as the log label) and every variable from
`config.env`.

**Git hooks.** Every git hook of every repository goes through `kings hooks run <hook>`, which:

1. runs the repository's own `.git/hooks/<hook>`, which git would otherwise skip because of
   the global `core.hooksPath`, and stops if it fails;
2. runs each layer's `hooks/<hook>.sh` with git's arguments and stdin, unless `kings hooks off`.

Hooks run for all repositories, so a project-specific hook checks
`git config --get remote.origin.url` first and exits 0 elsewhere.

**Checkup.** Every new shell runs `kings checkup` in the background. `checkup.sh` registers
tasks:

```bash
checkup_task cleanup weekly "$LAYER_DIR/Scripts/Cleanup/cleanup.sh"
```

Periods are `daily`, `weekly` and `monthly`. A task runs at most once per period, only
counting successful runs, and task ids get the layer name as prefix. Once all tasks are done
for the day, later shells exit right away. The core registers `log-archive` (monthly).

## Core library

Source from `$KINGS_CORE`, e.g. `. "$KINGS_CORE/print.sh"`.

| Module | Functions |
|---|---|
| `print.sh` | `print_info`, `print_title`, `print_success`, `print_warn`, `print_error`: stderr (colored on a terminal) plus the log. A command's own output goes to stdout with `printf` |
| `log.sh` | `log <message>`, `log_run <cmd> [args...]` (runs a command, its output goes to the log only), `log_file` |
| `secrets.sh` | `secret_get <NAME>`: an environment variable with that name, otherwise the Keychain. Also `secret_set`, `secret_delete`, `secret_source` |
| `cache.sh` | `cache_get <key>`, `cache_set <key> <value>`, `cache_unset <key>` |
| `notify.sh` | `notify_banner`, `notify_alert`, `notify_dialog` `<title> <message>` |
| `timer.sh` | `timer_elapsed`: script run time as `HH:MM:SS` |
| `layers.sh` | `layers_list`, `layer_name <path>`, `layer_is_valid <path>` |

Log line format:

```
[2026-09-29 14:03:12] [acme:deploy #48213] Deploying to staging
```
