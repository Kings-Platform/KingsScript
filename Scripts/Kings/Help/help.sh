#!/bin/bash
# `kings help`: core commands, then each layer's own list (its `main.sh help`).

. "$(dirname "${BASH_SOURCE[0]}")/../../Core/layers.sh"

# One aligned "command   description" line.
row() {
  printf '  %-34s %s\n' "$1" "$2"
}

print_core_commands() {
  printf 'Usage: kings <command> [args...]\n\nKings:\n'
  row "help" "Show this help"
  row "layer list|add|remove|create" "Manage layers"
  row "hooks on|off|status" "Toggle every layer's git hooks"
  row "checkup [--force]" "Run periodic maintenance tasks now"
  row "secret set|delete|status <NAME>" "Manage secrets in the Keychain (set prompts)"

  printf '\nGit:\n'
  row "git-swiftformatstaged" "Format the staged .swift files"
  row "git-prreview <PR>" "PR review comments as a markdown table"
  row "git-deletebranch [branch]" "Delete a local branch (current by default)"
}

# Each layer lists its own commands, under its name.
print_layer_commands() {
  local layer
  layers_list | while IFS= read -r layer; do
    printf '\n%s (%s):\n' "$(layer_name "$layer")" "$layer"
    if [ ! -d "$layer" ]; then
      row "(missing)" "Folder not found; see 'kings layer remove'"
    elif [ -x "$layer/main.sh" ]; then
      "$layer/main.sh" help < /dev/null
    else
      row "(no commands)" ""
    fi
  done
}

print_core_commands
print_layer_commands
