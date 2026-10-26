#!/bin/bash
# `kings ai-session <name> [--dir DIR] [--resume SESSION_ID]`: starts a Claude Code session in a
# detached tmux session with Remote Control on, so it can be driven from claude.ai or the phone.
# The tmux session and the Remote Control title share the name. --resume reopens an existing
# conversation instead of starting a new one.

. "$KINGS_CORE/print.sh"

NAME=""
DIR="$PWD"
RESUME=""

usage() {
  print_error "Usage: kings ai-session <name> [--dir DIR] [--resume SESSION_ID]"
  exit 1
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) DIR="$2"; shift 2 ;;
      --resume) RESUME="$2"; shift 2 ;;
      -*) usage ;;
      *) [ -z "$NAME" ] && NAME="$1" || usage; shift ;;
    esac
  done
  [ -n "$NAME" ] || usage
}

require_tools() {
  command -v tmux > /dev/null || { print_error "tmux not found"; exit 1; }
  command -v claude > /dev/null || { print_error "Claude Code not found (the claude command)"; exit 1; }
  [ -d "$DIR" ] || { print_error "Folder not found: $DIR"; exit 1; }
}

# tmux names can't hold dots or colons; the Remote Control title keeps the name as typed.
session_id() {
  printf '%s\n' "$NAME" | tr ' .:' '---'
}

# A second session with the same name would hide the first one behind `tmux attach`.
refuse_existing() {
  tmux has-session -t "=$(session_id)" 2> /dev/null || return 0
  print_error "A tmux session named '$(session_id)' already exists — attach with: tmux attach -t $(session_id)"
  exit 1
}

start_session() {
  # Long-lived sessions never update themselves: a running session that sees a newer version reinstalls the
  # binary in place on every check, which breaks scheduled jobs running at that moment. `claude-update` updates
  # once a day instead.
  local cmd="env DISABLE_AUTOUPDATER=1 claude --remote-control \"$NAME\""
  [ -n "$RESUME" ] && cmd="env DISABLE_AUTOUPDATER=1 claude --resume \"$RESUME\" --remote-control \"$NAME\""
  tmux new-session -d -s "$(session_id)" -c "$DIR" "$cmd"
}

# Claude exits right away on a bad flag or session id; the tmux session dies with it.
confirm_running() {
  sleep 2
  tmux has-session -t "=$(session_id)" 2> /dev/null && return
  print_error "The session stopped right after starting — run the command by hand in $DIR to see why"
  exit 1
}

parse_args "$@"
require_tools
refuse_existing
start_session
confirm_running
print_success "Session '$NAME' running in $DIR"
printf 'tmux attach -t %s\n' "$(session_id)"
