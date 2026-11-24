#!/bin/bash
# `kings ai-resume [--restart] [name...]`: brings back the sessions `kings ai-session` recorded,
# each in its tmux session, conversation and Remote Control title. Without names, all of them.
# Running sessions get their recorded id refreshed: /clear and resuming from a summary move a
# session to a new id.
# --restart also restarts the ones still running but idle — a session that lost its sign-in
# stays alive with Remote Control off until it restarts. `--forget <name>` drops one for good.

. "$KINGS_CORE/print.sh"
. "$(dirname "${BASH_SOURCE[0]}")/registry.sh"

AI_SESSION="$(dirname "${BASH_SOURCE[0]}")/ai-session.sh"
CLAUDE_SESSIONS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
RESTART=0
FORGET=""
NAMES=()

usage() {
  print_error "Usage: kings ai-resume [--restart] [name...] | --forget <name>"
  exit 1
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --restart) RESTART=1; shift ;;
      --forget) [ -n "$2" ] || usage; FORGET="$2"; shift 2 ;;
      -*) usage ;;
      *) NAMES+=("$1"); shift ;;
    esac
  done
}

require_tools() {
  command -v tmux > /dev/null || { print_error "tmux not found"; exit 1; }
}

forget_session() {
  registry_list | awk -F '\t' -v n="$FORGET" '$1 == n || $2 == n { found = 1 } END { exit !found }' \
    || { print_error "No recorded session named '$FORGET'"; exit 1; }
  local tmux_name
  tmux_name="$(registry_list | awk -F '\t' -v n="$FORGET" '$1 == n || $2 == n { print $1; exit }')"
  registry_unset "$tmux_name"
  print_success "Forgot '$FORGET'"
}

# A name given on the command line matches the tmux name or the Remote Control title.
is_selected() {
  [ ${#NAMES[@]} -eq 0 ] && return 0
  local n
  for n in "${NAMES[@]}"; do
    [ "$n" = "$1" ] || [ "$n" = "$2" ] && return 0
  done
  return 1
}

# Claude keeps a <pid>.json per running process; the pane runs claude itself, or a shell with
# claude as a child when someone restarted it by hand.
claude_session_file() {
  local pane_pid pid
  pane_pid="$(tmux list-panes -t "=$1:" -F '#{pane_pid}' 2> /dev/null | head -1)"
  [ -n "$pane_pid" ] || return 1
  for pid in "$pane_pid" $(pgrep -P "$pane_pid" 2> /dev/null); do
    [ -f "$CLAUDE_SESSIONS_DIR/$pid.json" ] && { printf '%s\n' "$CLAUDE_SESSIONS_DIR/$pid.json"; return 0; }
  done
  return 1
}

# Pattern match instead of a JSON parser: Claude rewrites the file in place, and a shorter write
# can leave stray characters at the end that make it invalid JSON.
json_field() {
  sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" "$1" | head -1
}

resume_one() {
  local tmux_name="$1" title="$2" dir="$3" id="$4" file live_id
  if tmux has-session -t "=$tmux_name" 2> /dev/null; then
    # A running session can be on a newer id than the recorded one; keep the record current.
    file="$(claude_session_file "$tmux_name")"
    live_id="$([ -n "$file" ] && json_field "$file" sessionId)"
    if [ -n "$live_id" ] && [ "$live_id" != "$id" ]; then
      id="$live_id"
      registry_set "$tmux_name" "$title" "$dir" "$id"
    fi
    [ "$RESTART" -eq 1 ] || { print_info "$title: already running"; return 0; }
    if [ -z "$file" ] || [ "$(json_field "$file" status)" != "idle" ]; then
      print_warn "$title: busy or not a Claude session — left running"
      return 0
    fi
    tmux kill-session -t "=$tmux_name"
  fi
  "$AI_SESSION" "$title" --dir "$dir" --resume "$id" > /dev/null
}

resume_all() {
  # Lines read up front: ai-session rewrites the registry while the loop runs.
  local lines=() line tmux_name title dir id
  while IFS= read -r line; do
    lines+=("$line")
  done < <(registry_list)
  [ ${#lines[@]} -gt 0 ] || { print_warn "No recorded sessions — start one with kings ai-session"; return 0; }

  for line in "${lines[@]}"; do
    IFS=$'\t' read -r tmux_name title dir id <<< "$line"
    is_selected "$tmux_name" "$title" || continue
    resume_one "$tmux_name" "$title" "$dir" "$id"
  done
}

parse_args "$@"
require_tools
if [ -n "$FORGET" ]; then
  forget_session
else
  resume_all
fi
