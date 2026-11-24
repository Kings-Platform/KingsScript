#!/bin/bash
# Sessions started by `kings ai-session`, so `kings ai-resume` can bring them back:
# $KINGS_HOME/ai-sessions.tsv, one "tmux-name<TAB>title<TAB>folder<TAB>session-id" per line.
#
#   registry_set <tmux> <title> <dir> <id>   creates or replaces the line of that tmux name
#   registry_unset <tmux>                    removes it
#   registry_list                            prints every line

AI_SESSIONS_FILE="$KINGS_HOME/ai-sessions.tsv"

registry_unset() {
  [ -f "$AI_SESSIONS_FILE" ] || return 0
  local tmp="$AI_SESSIONS_FILE.tmp"
  awk -F '\t' -v k="$1" '$1 != k' "$AI_SESSIONS_FILE" > "$tmp" && mv "$tmp" "$AI_SESSIONS_FILE"
}

registry_set() {
  registry_unset "$1"
  mkdir -p "$KINGS_HOME"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$AI_SESSIONS_FILE"
}

registry_list() {
  [ -f "$AI_SESSIONS_FILE" ] && cat "$AI_SESSIONS_FILE"
  return 0
}
