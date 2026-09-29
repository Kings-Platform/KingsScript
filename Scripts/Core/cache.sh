#!/bin/bash
# Machine state shared by every command: $KINGS_HOME/cache.txt, one "key=value" per line.
#
#   cache_get <key>           prints the value (empty if missing)
#   cache_set <key> <value>   creates or replaces the entry
#   cache_unset <key>         removes the entry

. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

KINGS_CACHE_FILE="$KINGS_HOME/cache.txt"

cache_get() {
  [ -f "$KINGS_CACHE_FILE" ] || return 0
  # First line starting with "key="; plain text match, so dots in keys are literal.
  awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$KINGS_CACHE_FILE"
}

cache_unset() {
  [ -f "$KINGS_CACHE_FILE" ] || return 0
  # Rewrites the file without the key's line.
  local tmp="$KINGS_CACHE_FILE.tmp"
  awk -v k="$1=" 'index($0, k) != 1' "$KINGS_CACHE_FILE" > "$tmp" && mv "$tmp" "$KINGS_CACHE_FILE"
}

cache_set() {
  cache_unset "$1"
  mkdir -p "$KINGS_HOME"
  printf '%s=%s\n' "$1" "$2" >> "$KINGS_CACHE_FILE"
}
