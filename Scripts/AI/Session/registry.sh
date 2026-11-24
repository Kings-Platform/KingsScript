#!/bin/bash
# Sessions started by `kings ai-session`, so `kings ai-resume` can bring them back:
# $KINGS_HOME/ai-sessions.tsv, one "tmux-name<TAB>title<TAB>folder<TAB>session-id" per line.
#
# KINGS_AI_SESSION_SOURCE (config.env) names a command that keeps the record somewhere else, e.g. a
# table a layer reads. Then it is the record and the local file is its copy for when it can't be
# reached. The command answers:
#
#   <source> list                         one "title<TAB>folder<TAB>id" per session to bring back;
#                                         an empty id means a session still to be started
#   <source> set <title> <folder> <id>    creates or updates the session
#   <source> forget <title>               stops bringing it back
#   <source> result <title> <status>      resumed, running, busy or failed, after each ai-resume
#
#   registry_set <title> <dir> <id>   creates or replaces the session of that title
#   registry_forget <title>           drops it
#   registry_result <title> <status>  reports to the source, when there is one
#   registry_list                     prints every session, in the local file's format

AI_SESSIONS_FILE="$KINGS_HOME/ai-sessions.tsv"

# tmux names can't hold dots or colons; the Remote Control title keeps the name as typed.
tmux_name_of() {
  printf '%s\n' "$1" | tr ' .:' '---'
}

# Calls the source command with the given arguments; fails when there is none.
registry_source() {
  [ -n "$KINGS_AI_SESSION_SOURCE" ] || return 1
  /bin/bash -c "$KINGS_AI_SESSION_SOURCE \"\$@\"" _ "$@"
}

local_unset() {
  [ -f "$AI_SESSIONS_FILE" ] || return 0
  local tmp="$AI_SESSIONS_FILE.tmp"
  awk -F '\t' -v k="$1" '$1 != k' "$AI_SESSIONS_FILE" > "$tmp" && mv "$tmp" "$AI_SESSIONS_FILE"
}

registry_set() {
  local tmux_name
  tmux_name="$(tmux_name_of "$1")"
  local_unset "$tmux_name"
  mkdir -p "$KINGS_HOME"
  printf '%s\t%s\t%s\t%s\n' "$tmux_name" "$1" "$2" "$3" >> "$AI_SESSIONS_FILE"
  [ -z "$KINGS_AI_SESSION_SOURCE" ] || registry_source set "$1" "$2" "$3" \
    || print_warn "$1: recorded locally only — the session source failed"
}

registry_forget() {
  local_unset "$(tmux_name_of "$1")"
  [ -z "$KINGS_AI_SESSION_SOURCE" ] || registry_source forget "$1"
}

registry_result() {
  [ -z "$KINGS_AI_SESSION_SOURCE" ] || registry_source result "$1" "$2" > /dev/null 2>&1 || true
}

# From the source when it answers, refreshing the local copy; from the local copy otherwise.
registry_list() {
  local from_source
  if [ -n "$KINGS_AI_SESSION_SOURCE" ]; then
    if from_source="$(registry_source list)"; then
      mkdir -p "$KINGS_HOME"
      printf '%s\n' "$from_source" | awk -F '\t' 'NF >= 2 && $1 != "" {
        name = $1; gsub(/[ .:]/, "-", name); print name "\t" $1 "\t" $2 "\t" $3 }' > "$AI_SESSIONS_FILE"
    else
      print_warn "Session source unreachable — using the local copy"
    fi
  fi
  [ -f "$AI_SESSIONS_FILE" ] && cat "$AI_SESSIONS_FILE"
  return 0
}
