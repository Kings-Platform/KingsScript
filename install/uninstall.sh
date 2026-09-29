#!/bin/bash
# Undoes install.sh. Logs, config and layers in ~/.kingsScripts are kept unless --purge.

export KINGS_CMD="uninstall"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/Scripts/Core/cache.sh"
. "$ROOT/Scripts/Core/print.sh"
. "$ROOT/install/zshrc.sh"

HOOKS_DIR="$KINGS_HOME/git-hooks"

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

zshrc_remove_block
print_info "Removed the kings block from $ZSHRC"

restore_git_hooks_path
rm -rf "$HOOKS_DIR" "$KINGS_HOME/bin"

# Printed with printf, since print_* would recreate the log folder being deleted.
if [ "$1" = "--purge" ]; then
  rm -rf "$KINGS_HOME"
  printf 'Removed %s\n' "$KINGS_HOME"
else
  print_info "Kept $KINGS_HOME (use --purge to remove it)"
fi
printf 'KingsScript uninstalled. Open a new terminal to refresh the PATH.\n'
