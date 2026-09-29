#!/bin/bash
# `kings layer list|add|remove|create`: manages the layer registry ($KINGS_HOME/layers).

. "$(dirname "${BASH_SOURCE[0]}")/../../Core/layers.sh"
. "$KINGS_CORE/print.sh"

TEMPLATE_DIR="$KINGS_ROOT/templates/layer"

usage() {
  print_error "Usage: kings layer list | add <path> | remove <name|path> | create <path> [name]"
  exit 1
}

layer_list() {
  local found=0 layer
  while IFS= read -r layer; do
    found=1
    if [ -d "$layer" ]; then
      printf '%-16s %s\n' "$(layer_name "$layer")" "$layer"
    else
      printf '%-16s %s (missing)\n' "?" "$layer"
    fi
  done < <(layers_list)
  [ "$found" -eq 1 ] || print_info "No layers registered. Add one with 'kings layer add <path>'."
}

layer_add() {
  [ -n "$1" ] || usage
  local path name layer
  path="$(cd "$1" 2> /dev/null && pwd)" || { print_error "Folder not found: $1"; exit 1; }
  layer_is_valid "$path" || { print_error "Not a layer (no layer.env): $path"; exit 1; }
  name="$(layer_name "$path")"

  while IFS= read -r layer; do
    if [ "$layer" = "$path" ]; then
      print_warn "Already registered: $name"
      exit 0
    fi
    if [ -d "$layer" ] && [ "$(layer_name "$layer")" = "$name" ]; then
      print_error "A layer named '$name' is already registered: $layer"
      exit 1
    fi
  done < <(layers_list)

  mkdir -p "$KINGS_HOME"
  printf '%s\n' "$path" >> "$KINGS_LAYERS_FILE"
  print_success "Layer added: $name ($path)"
}

layer_remove() {
  [ -n "$1" ] || usage
  local layer kept="" removed=""
  while IFS= read -r layer; do
    if [ "$layer" = "$1" ] || [ "$(layer_name "$layer")" = "$1" ]; then
      removed="$layer"
    else
      kept="$kept$layer"$'\n'
    fi
  done < <(layers_list)

  [ -n "$removed" ] || { print_error "No layer matches: $1"; exit 1; }
  printf '%s' "$kept" > "$KINGS_LAYERS_FILE"
  print_success "Layer removed: $removed"
}

layer_create() {
  [ -n "$1" ] || usage
  local path="$1" name="${2:-$(basename "$1")}"
  if [ -e "$path" ] && [ -n "$(ls -A "$path")" ]; then
    print_error "Folder exists and is not empty: $path"
    exit 1
  fi
  mkdir -p "$path"
  cp -R "$TEMPLATE_DIR/." "$path/"
  printf 'LAYER_NAME="%s"\n' "$name" > "$path/layer.env"
  print_success "Layer '$name' created at $path"
  print_info "Register it with: kings layer add $path"
}

action="${1:-list}"
[ $# -gt 0 ] && shift
case "$action" in
  list) layer_list ;;
  add) layer_add "$@" ;;
  remove) layer_remove "$@" ;;
  create) layer_create "$@" ;;
  *) usage ;;
esac
