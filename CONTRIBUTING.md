# Contributing

How scripts are written in KingsScript — core and layers follow the same rules.

#### Index

- [Adding a command](#adding-a-command)
- [Script structure](#script-structure)
- [Rules](#rules)
- [Testing](#testing)
- [Git](#git)

## Adding a command

1. Create the script in a folder per subject: `Scripts/<Area>/<Subject>/<name>.sh`
   (e.g. `Scripts/Design/Figma/`, `Scripts/Installers/Tabby/`)
2. Make it executable: `chmod +x`
3. Add one line to the `case` in `main.sh` — the core's, or the layer's
4. Add its line to `help` — `Kings/Help/help.sh` in the core, the `help)` branch in a layer

A folder can also hold a `.md` when the subject needs its own explanation.

Command names follow `<area>-<action>`: `git-prreview`, `fig-parse`, `xcode-simulator`.

## Script structure

Every step is a function with an action name and a one-line comment. The end of the file calls
them in order, so it reads as a script of what happens:

```bash
#!/bin/bash
# `kings xcode-simulator [device]`: opens the Simulator, booting the device if needed.

. "$KINGS_CORE/print.sh"

DEVICE="${1:-iPhone 17}"

# Boots the device unless it's already running.
boot_device() {
  xcrun simctl boot "$DEVICE" 2> /dev/null
  print_info "Device: $DEVICE"
}

open_simulator() {
  open -a Simulator
}

boot_device
open_simulator
print_success "Simulator ready"
```

A script with subcommands ends in a `case` that calls one function per subcommand
(see [`Scripts/Kings/Secret/secret.sh`](Scripts/Kings/Secret/secret.sh)).

## Rules

| Topic | Rule |
|---|---|
| Shell | `#!/bin/bash`, compatible with **bash 3.2** — no `declare -A`, `mapfile`, `${var,,}`, `local -n` |
| Comments | One line above what isn't obvious — the why, not the what. No long docstrings |
| Input | Arguments only, never prompts — a command that must prompt says so in its `help` line |
| Output | Result on stdout with `printf`; messages through `print_*` (stderr and log) |
| Exit codes | `0` success, `1` failure — `127` is reserved for "not mine" in a layer's `main.sh` |
| Printing | `printf`, not `echo -e` |
| Secrets | `secret_get <NAME>` — never in a file, never printed |
| State | Only in `$KINGS_HOME` (`cache_*` or files there), never inside the repo |
| Paths | No fixed machine paths — use `config.env` with a sensible default |
| Language | Code, comments and docs in English |
| Content | Nothing that names a company, client or person — that belongs in a private layer |

## Testing

Always against a throwaway home, so the real `~/.zshrc`, `~/.gitconfig` and `~/.kingsScripts`
stay untouched:

```bash
# Throwaway home for this terminal only
export HOME="$(mktemp -d)"
unset KINGS_HOME

# Install there and use the command it wrote
/bin/bash install/install.sh
~/.kingsScripts/bin/kings help

# Syntax check with the shell the hooks use
for f in $(find Scripts install -name '*.sh'); do /bin/bash -n "$f"; done
```

## Git

- **Trunk-based**: short branch from `main` (`feature/...`, `fix/...`), merged through a PR
- Commit messages short and direct, in English — a description only when needed, as bullets
