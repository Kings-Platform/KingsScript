#!/bin/bash
# `kings checkup [--force]`: periodic maintenance, run in the background on every shell start.
#
# Tasks are registered with `checkup_task <id> <daily|weekly|monthly> <script>` by the core
# (tasks.sh) and by each layer's checkup.sh (ids get the layer name as prefix). A task runs at
# most once per period: the period it last succeeded in is kept in the cache as
# `checkup.<id>`. Once everything is done for the day, later shells exit right away.

. "$(dirname "${BASH_SOURCE[0]}")/../../Core/layers.sh"
. "$KINGS_CORE/cache.sh"
. "$KINGS_CORE/print.sh"

CHECKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --force ignores what already ran in the current period.
force=0
case "$1" in
  --force) force=1 ;;
  "") ;;
  *)
    print_error "Usage: kings checkup [--force]"
    exit 1
    ;;
esac

# Everything already done today: nothing to do.
today="$(date +%Y-%m-%d)"
[ "$force" -eq 0 ] && [ "$(cache_get checkup.last)" = "$today" ] && exit 0

# Several terminals opening at once must not run the tasks twice. A lock older than
# 10 minutes is left over from a crashed run.
lock="$KINGS_HOME/checkup.lock"
mkdir -p "$KINGS_HOME"
find "$lock" -maxdepth 0 -mmin +10 -exec rmdir {} \; 2> /dev/null
mkdir "$lock" 2> /dev/null || exit 0
trap 'rmdir "$lock"' EXIT

# Identifies the current period: a task runs again when this value changes.
period_stamp() {
  case "$1" in
    daily) date +%Y-%m-%d ;;
    weekly) date +%G-W%V ;;
    monthly) date +%Y-%m ;;
    *) return 1 ;;
  esac
}

failures=0
task_prefix=""

# Runs a task if it hasn't succeeded yet in the current period.
checkup_task() {
  local id="$task_prefix$1" period="$2" script="$3" stamp
  if ! stamp="$(period_stamp "$period")"; then
    print_error "Checkup task $id: invalid period '$period'"
    failures=$((failures + 1))
    return
  fi
  [ "$force" -eq 0 ] && [ "$(cache_get "checkup.$id")" = "$stamp" ] && return

  if KINGS_CMD="checkup:$id" "$script" < /dev/null; then
    cache_set "checkup.$id" "$stamp"
    log "Task $id done"
  else
    print_error "Checkup task $id failed"
    failures=$((failures + 1))
  fi
}

# Core tasks first, then each layer's.
. "$CHECKUP_DIR/tasks.sh"

while IFS= read -r layer; do
  [ -f "$layer/checkup.sh" ] || continue
  task_prefix="$(layer_name "$layer"):"
  LAYER_DIR="$layer"
  . "$layer/checkup.sh"
done < <(layers_list)

# Only a fully successful run skips the rest of the day; failures retry on the next shell.
[ "$failures" -eq 0 ] && cache_set checkup.last "$today"
exit "$failures"
