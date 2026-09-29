#!/bin/bash
# One log file per day: $KINGS_HOME/logs/YYYY-MM-DD.log. Every line carries the command
# and the PID, since concurrent runs interleave in the same file.
#
#   log <message>            appends a line
#   log_run <cmd> [args...]  runs a command, sending its output to the log only

. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

KINGS_LOG_DIR="$KINGS_HOME/logs"

_log_prefix() {
  printf '[%s] [%s #%s]' "$(date '+%Y-%m-%d %H:%M:%S')" "${KINGS_CMD:-kings}" "$$"
}

log_file() {
  printf '%s/%s.log' "$KINGS_LOG_DIR" "$(date +%Y-%m-%d)"
}

log() {
  [ -d "$KINGS_LOG_DIR" ] || mkdir -p "$KINGS_LOG_DIR"
  printf '%s %s\n' "$(_log_prefix)" "$*" >> "$(log_file)"
}

log_run() {
  log "\$ $*"
  local prefix
  prefix="$(_log_prefix)"
  "$@" 2>&1 | awk -v p="$prefix" '{ print p "   " $0 }' >> "$(log_file)"
  return "${PIPESTATUS[0]}"
}
