#!/bin/bash
# User-facing messages: stderr (colored on a terminal) and the daily log.
# A command's actual output (tables, lists) goes to stdout with printf instead.

. "$(dirname "${BASH_SOURCE[0]}")/log.sh"

_print() {
  local color="$1" level="$2"
  shift 2
  log "$level$*"
  if [ -t 2 ]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

print_info()    { _print 0 '' "$@"; }
print_title()   { _print 35 '' "$@"; }
print_success() { _print 32 '' "$@"; }
print_warn()    { _print 33 'WARN: ' "$@"; }
print_error()   { _print 31 'ERROR: ' "$@"; }
