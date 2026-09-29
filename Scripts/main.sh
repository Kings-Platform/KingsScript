#!/bin/bash
# Entry point for `kings <command> [args...]`. Core commands resolve here; anything else is
# offered to each registered layer, in order. A layer exits 127 for a command it doesn't own
# (the shell's "command not found"), so any other code, including a failure, ends the search.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPTS_DIR/Core/layers.sh"

# Core commands: exec replaces this process, so it only returns when $cmd isn't one of them.
run_core_command() {
  case "$cmd" in
    help | -h | --help) exec "$SCRIPTS_DIR/Kings/Help/help.sh" "$@" ;;
    layer) exec "$SCRIPTS_DIR/Kings/Layer/layer.sh" "$@" ;;
    hooks) exec "$SCRIPTS_DIR/Kings/Hooks/hooks.sh" "$@" ;;
    checkup) exec "$SCRIPTS_DIR/Kings/Checkup/checkup.sh" "$@" ;;
    secret) exec "$SCRIPTS_DIR/Kings/Secret/secret.sh" "$@" ;;
    git-swiftformatstaged) exec "$SCRIPTS_DIR/Git/SwiftFormatStaged/swiftformat-staged.sh" "$@" ;;
    git-prreview) exec "$SCRIPTS_DIR/Git/PRReview/pr-review.sh" "$@" ;;
    git-deletebranch) exec "$SCRIPTS_DIR/Git/DeleteBranch/delete-branch.sh" "$@" ;;
    xcode-simulator) exec "$SCRIPTS_DIR/Xcode/Simulator/simulator.sh" "$@" ;;
    xcode-deeplink) exec "$SCRIPTS_DIR/Xcode/Deeplink/deeplink.sh" "$@" ;;
    slack-test) exec "$SCRIPTS_DIR/Slack/Test/slack-test.sh" "$@" ;;
    install-tabby) exec "$SCRIPTS_DIR/Installers/Tabby/install-tabby.sh" "$@" ;;
    install-gem) exec "$SCRIPTS_DIR/Installers/Gem/install-gem.sh" "$@" ;;
    graph) exec python3 "$SCRIPTS_DIR/AI/Graph/graph.py" "$@" ;;
    docs-check) exec python3 "$SCRIPTS_DIR/AI/DocsCheck/docs-check.py" "$@" ;;
    ai-update) exec "$SCRIPTS_DIR/AI/Update/ai-update.sh" "$@" ;;
    fig-parse) exec node --max-old-space-size=8192 "$SCRIPTS_DIR/Design/Figma/parse-fig.js" "$@" ;;
    fig-check) exec node --max-old-space-size=8192 "$SCRIPTS_DIR/Design/Figma/check.js" "$@" ;;
  esac
}

# Offers the command to each layer; 127 means "not mine", anything else is the answer.
run_layer_command() {
  # Layer list read up front, so a command reading stdin can't consume it.
  local layers=() layer status
  while IFS= read -r layer; do
    layers+=("$layer")
  done < <(layers_list)

  for layer in "${layers[@]}"; do
    [ -x "$layer/main.sh" ] || continue
    KINGS_CMD="$(layer_name "$layer"):$cmd" "$layer/main.sh" "$cmd" "$@"
    status=$?
    [ "$status" -ne 127 ] && exit "$status"
  done
}

# No layer owns the command.
fail_unknown_command() {
  . "$SCRIPTS_DIR/Core/print.sh"
  print_error "Unknown command: $cmd (see 'kings help')"
  exit 127
}

# No command shows the help; the rest of the arguments go to the command.
cmd="${1:-help}"
[ $# -gt 0 ] && shift
export KINGS_CMD="$cmd"

run_core_command "$@"
run_layer_command "$@"
fail_unknown_command
