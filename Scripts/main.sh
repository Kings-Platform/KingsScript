#!/bin/bash
# Entry point for `kings <command> [args...]`. Core commands resolve here; anything else is
# offered to each registered layer, in order. A layer exits 127 for a command it doesn't own
# (the shell's "command not found"), so any other code, including a failure, ends the search.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPTS_DIR/Core/layers.sh"

# No command shows the help; the rest of the arguments go to the command.
cmd="${1:-help}"
[ $# -gt 0 ] && shift
export KINGS_CMD="$cmd"

# Core commands: exec replaces this process with the command's script.
case "$cmd" in
  help | -h | --help)
    exec "$SCRIPTS_DIR/Kings/Help/help.sh" "$@"
    ;;
  layer)
    exec "$SCRIPTS_DIR/Kings/Layer/layer.sh" "$@"
    ;;
  hooks)
    exec "$SCRIPTS_DIR/Kings/Hooks/hooks.sh" "$@"
    ;;
  checkup)
    exec "$SCRIPTS_DIR/Kings/Checkup/checkup.sh" "$@"
    ;;
  secret)
    exec "$SCRIPTS_DIR/Kings/Secret/secret.sh" "$@"
    ;;
esac

# Layer list read up front, so a command reading stdin can't consume it.
layers=()
while IFS= read -r layer; do
  layers+=("$layer")
done < <(layers_list)

# Offers the command to each layer; 127 means "not mine", anything else is the answer.
for layer in "${layers[@]}"; do
  [ -x "$layer/main.sh" ] || continue
  KINGS_CMD="$(layer_name "$layer"):$cmd" "$layer/main.sh" "$cmd" "$@"
  status=$?
  [ "$status" -ne 127 ] && exit "$status"
done

# No layer owns it.
. "$SCRIPTS_DIR/Core/print.sh"
print_error "Unknown command: $cmd (see 'kings help')"
exit 127
