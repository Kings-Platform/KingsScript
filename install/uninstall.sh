#!/bin/bash
# Undoes install.sh. Logs, config and layers in ~/.kingsScripts are kept unless --purge.

export KINGS_CMD="uninstall"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/Scripts/Core/cache.sh"
. "$ROOT/Scripts/Core/print.sh"
. "$ROOT/Scripts/Core/zshrc.sh"

HOOKS_DIR="$KINGS_HOME/git-hooks"

update_zshrc() {
  zshrc_remove_block kings
  print_info "Removed the kings block from $ZSHRC"
}

# Gives git back the hooks setting it had before the install, if any.
restore_git_hooks_path() {
  [ "$(git config --global core.hooksPath)" = "$HOOKS_DIR" ] || return

  local previous
  previous="$(cache_get install.previous-hookspath)"
  if [ -n "$previous" ]; then
    git config --global core.hooksPath "$previous"
    cache_unset install.previous-hookspath
    print_info "core.hooksPath restored to $previous"
  else
    git config --global --unset core.hooksPath
    print_info "core.hooksPath unset"
  fi
}

remove_command_and_hooks() {
  rm -rf "$HOOKS_DIR" "$KINGS_HOME/bin"
}

# Printed with printf after deleting, since print_* would recreate the log folder.
remove_home_if_purge() {
  if [ "$1" = "--purge" ]; then
    rm -rf "$KINGS_HOME"
    printf 'Removed %s\n' "$KINGS_HOME"
  else
    print_info "Kept $KINGS_HOME (use --purge to remove it)"
  fi
}

update_zshrc
restore_git_hooks_path
remove_command_and_hooks
remove_home_if_purge "$1"
printf 'KingsScript uninstalled. Open a new terminal to refresh the PATH.\n'
