#!/bin/bash
# Installs KingsScript on this machine. Safe to run again, e.g. after moving the repo.

export KINGS_CMD="install"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/Scripts/Core/cache.sh"
. "$ROOT/Scripts/Core/print.sh"
. "$ROOT/install/zshrc.sh"

BIN_DIR="$KINGS_HOME/bin"
HOOKS_DIR="$KINGS_HOME/git-hooks"
GIT_HOOKS="pre-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push post-rewrite"

# ~/.kingsScripts and its config, created only on the first install.
create_home() {
  mkdir -p "$KINGS_HOME/logs" "$KINGS_HOME/backup" "$BIN_DIR" "$HOOKS_DIR"
  if [ ! -f "$KINGS_HOME/config.env" ]; then
    cp "$ROOT/install/config.example.env" "$KINGS_HOME/config.env"
    print_info "Config created: $KINGS_HOME/config.env"
  fi
}

# The `kings` command: a small file that remembers where the repo is and forwards to it.
# A real file, not a shell function, so git hooks and AI agents can call it too.
write_command() {
  find "$ROOT/Scripts" -name '*.sh' -exec chmod +x {} +

  printf '#!/bin/bash\nexport KINGS_HOME="%s"\nexec "%s" "$@"\n' \
    "$KINGS_HOME" "$ROOT/Scripts/main.sh" > "$BIN_DIR/kings"
  chmod +x "$BIN_DIR/kings"
  print_info "Command: $BIN_DIR/kings"
}

# One file per git hook, each just calling `kings hooks run <hook>`.
write_git_hooks() {
  local hook
  for hook in $GIT_HOOKS; do
    printf '#!/bin/bash\nexec "%s" hooks run %s "$@"\n' "$BIN_DIR/kings" "$hook" > "$HOOKS_DIR/$hook"
    chmod +x "$HOOKS_DIR/$hook"
  done
}

# Points git to those hooks for every repo, remembering any previous setting for uninstall.
set_git_hooks_path() {
  local current
  current="$(git config --global core.hooksPath)"
  [ "$current" = "$HOOKS_DIR" ] && return

  if [ -n "$current" ]; then
    cache_set install.previous-hookspath "$current"
    print_warn "core.hooksPath was $current; replaced (uninstall restores it)"
  fi
  git config --global core.hooksPath "$HOOKS_DIR"
  print_info "Git hooks: $HOOKS_DIR"
}

# Puts `kings` on the PATH and starts the checkup in the background on every new shell.
update_zshrc() {
  [ -f "$ZSHRC" ] && cp "$ZSHRC" "$KINGS_HOME/backup/zshrc.$(date +%Y-%m-%d_%H-%M-%S)"
  zshrc_set_block "export PATH=\"$BIN_DIR:\$PATH\"
( kings checkup > /dev/null 2>&1 & )"
  print_info "Shell: $ZSHRC"
}

print_title "Installing KingsScript"
create_home
write_command
write_git_hooks
set_git_hooks_path
update_zshrc
print_success "Done. Open a new terminal (or run: source $ZSHRC) and try: kings help"
