#!/bin/bash
# Undoes install.sh: removes the ~/.zshrc block, the kings executable and the git hook stubs,
# and restores the previous core.hooksPath. $KINGS_HOME (logs, config, layer registry) is kept
# unless --purge.

export KINGS_CMD="uninstall"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/Scripts/Core/cache.sh"
. "$ROOT/Scripts/Core/print.sh"

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
HOOKS_DIR="$KINGS_HOME/git-hooks"

if [ -f "$ZSHRC" ]; then
  tmp="$(mktemp)"
  awk -v b="# >>> kings >>>" -v e="# <<< kings <<<" '
    $0 == b { if (blanks > 0) blanks--; skip = 1; next }
    $0 == e { skip = 0; next }
    skip { next }
    $0 == "" { blanks++; next }
    { while (blanks > 0) { print ""; blanks-- } print }
    END { while (blanks > 0) { print ""; blanks-- } }
  ' "$ZSHRC" > "$tmp" && cat "$tmp" > "$ZSHRC"
  rm -f "$tmp"
  print_info "Removed the kings block from $ZSHRC"
fi

if [ "$(git config --global core.hooksPath)" = "$HOOKS_DIR" ]; then
  previous="$(cache_get install.previous-hookspath)"
  if [ -n "$previous" ]; then
    git config --global core.hooksPath "$previous"
    cache_unset install.previous-hookspath
    print_info "core.hooksPath restored to $previous"
  else
    git config --global --unset core.hooksPath
    print_info "core.hooksPath unset"
  fi
fi
rm -rf "$HOOKS_DIR" "$KINGS_HOME/bin"

if [ "$1" = "--purge" ]; then
  rm -rf "$KINGS_HOME"
  printf 'Removed %s\n' "$KINGS_HOME"
else
  print_info "Kept $KINGS_HOME (use --purge to remove it)"
fi
printf 'KingsScript uninstalled. Open a new terminal to refresh the PATH.\n'
