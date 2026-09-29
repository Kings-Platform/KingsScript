#!/bin/bash
# Installs KingsScript on this machine. Safe to run again (after moving the repo, for example).
#
#   - $KINGS_HOME (~/.kingsScripts): config.env, logs/, git-hooks/, cache and layer registry
#   - the `kings` executable in $KINGS_HOME/bin, a real file rather than a shell function, so
#     non-interactive shells (git hooks, AI agents) can call it by its absolute path
#   - a marked block in ~/.zshrc: bin/ on the PATH and the background checkup
#   - global git hook stubs (core.hooksPath), which hand every hook over to the layers

export KINGS_CMD="install"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/Scripts/Core/cache.sh"
. "$ROOT/Scripts/Core/print.sh"

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
HOOKS_DIR="$KINGS_HOME/git-hooks"
BIN_DIR="$KINGS_HOME/bin"
GIT_HOOKS="pre-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push post-rewrite"
MARK_BEGIN="# >>> kings >>>"
MARK_END="# <<< kings <<<"

print_title "Installing KingsScript"

mkdir -p "$KINGS_HOME/logs" "$KINGS_HOME/backup" "$HOOKS_DIR" "$BIN_DIR"
if [ ! -f "$KINGS_HOME/config.env" ]; then
  cp "$ROOT/install/config.example.env" "$KINGS_HOME/config.env"
  print_info "Config created: $KINGS_HOME/config.env"
fi

find "$ROOT/Scripts" -name '*.sh' -exec chmod +x {} +

cat > "$BIN_DIR/kings" <<WRAPPER
#!/bin/bash
export KINGS_HOME="$KINGS_HOME"
exec "$ROOT/Scripts/main.sh" "\$@"
WRAPPER
chmod +x "$BIN_DIR/kings"
print_info "Command: $BIN_DIR/kings"

for hook in $GIT_HOOKS; do
  cat > "$HOOKS_DIR/$hook" <<STUB
#!/bin/bash
exec "$BIN_DIR/kings" hooks run $hook "\$@"
STUB
  chmod +x "$HOOKS_DIR/$hook"
done

current_hooks="$(git config --global core.hooksPath)"
if [ "$current_hooks" != "$HOOKS_DIR" ]; then
  if [ -n "$current_hooks" ]; then
    cache_set install.previous-hookspath "$current_hooks"
    print_warn "core.hooksPath was $current_hooks; replaced (uninstall restores it)"
  fi
  git config --global core.hooksPath "$HOOKS_DIR"
fi
print_info "Git hooks: $HOOKS_DIR"

block="$MARK_BEGIN
export PATH=\"$BIN_DIR:\$PATH\"
( kings checkup > /dev/null 2>&1 & )
$MARK_END"

[ -f "$ZSHRC" ] && cp "$ZSHRC" "$KINGS_HOME/backup/zshrc.$(date +%Y-%m-%d_%H-%M-%S)"
tmp="$(mktemp)"
BLOCK="$block" awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
  $0 == b { print ENVIRON["BLOCK"]; skip = 1; done = 1; next }
  $0 == e { skip = 0; next }
  !skip { print }
  END { if (!done) printf "\n%s\n", ENVIRON["BLOCK"] }
' "${ZSHRC}" 2> /dev/null > "$tmp" || printf '%s\n' "$block" > "$tmp"
cat "$tmp" > "$ZSHRC"
rm -f "$tmp"
print_info "Shell: $ZSHRC"

print_success "Done. Open a new terminal (or run: source $ZSHRC) and try: kings help"
