#!/bin/bash
# Registered layers: $KINGS_HOME/layers, one absolute path per line, in lookup order.
# A folder is a layer when it has a layer.env (LAYER_NAME="...").

. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

KINGS_LAYERS_FILE="$KINGS_HOME/layers"

# Registered layer paths, skipping blank lines.
layers_list() {
  [ -f "$KINGS_LAYERS_FILE" ] && grep -v '^[[:space:]]*$' "$KINGS_LAYERS_FILE"
  return 0
}

layer_is_valid() {
  [ -f "$1/layer.env" ]
}

# Reads LAYER_NAME in a subshell, so the layer.env can't change this script's variables.
layer_name() {
  (
    LAYER_NAME=""
    . "$1/layer.env" 2> /dev/null
    printf '%s\n' "${LAYER_NAME:-$(basename "$1")}"
  )
}
