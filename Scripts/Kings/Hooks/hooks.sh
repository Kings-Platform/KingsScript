#!/bin/bash
# `kings hooks on|off|status`: toggles every layer's git hooks at once, without touching
# core.hooksPath. `kings hooks run <hook> [args...]` is what the global git hook stubs call.

. "$(dirname "${BASH_SOURCE[0]}")/../../Core/layers.sh"
. "$KINGS_CORE/cache.sh"
. "$KINGS_CORE/print.sh"

HOOKS_DIR="$KINGS_HOME/git-hooks"

hooks_status() {
  local state="on" path
  [ "$(cache_get hooks)" = "off" ] && state="off"
  path="$(git config --global core.hooksPath)"
  printf 'Layer hooks: %s\n' "$state"
  if [ "$path" = "$HOOKS_DIR" ]; then
    printf 'core.hooksPath: %s\n' "$path"
  else
    printf 'core.hooksPath: %s (expected %s; run install/install.sh)\n' "${path:-unset}" "$HOOKS_DIR"
  fi
}

# stdin is read once and replayed, since some hooks (pre-push, post-rewrite) receive data
# there and more than one script may need it.
hooks_run() {
  local name="$1"
  [ -n "$name" ] || { print_error "Usage: kings hooks run <hook> [args...]"; exit 1; }
  shift

  local input="" status=0 git_dir layer script
  [ -t 0 ] || input="$(cat)"

  feed() {
    if [ -n "$input" ]; then
      printf '%s\n' "$input" | "$@"
    else
      "$@" < /dev/null
    fi
  }

  # A global core.hooksPath makes git skip the repo's own .git/hooks, so they run from here.
  git_dir="$(git rev-parse --git-common-dir 2> /dev/null)"
  if [ -n "$git_dir" ] && [ -x "$git_dir/hooks/$name" ]; then
    feed "$git_dir/hooks/$name" "$@" || exit $?
  fi

  [ "$(cache_get hooks)" = "off" ] && exit 0

  while IFS= read -r layer; do
    script="$layer/hooks/$name.sh"
    [ -x "$script" ] || continue
    KINGS_CMD="$(layer_name "$layer"):hook:$name" feed "$script" "$@" || status=$?
  done < <(layers_list)
  exit "$status"
}

action="${1:-status}"
[ $# -gt 0 ] && shift
case "$action" in
  on)
    cache_unset hooks
    print_success "Layer hooks: on"
    ;;
  off)
    cache_set hooks off
    print_success "Layer hooks: off"
    ;;
  status) hooks_status ;;
  run) hooks_run "$@" ;;
  *)
    print_error "Usage: kings hooks on|off|status"
    exit 1
    ;;
esac
