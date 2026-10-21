#!/bin/bash
# `kings schedule add|list|run|check|logs|enable|disable|remove`: jobs that run at a fixed time of day
# through launchd, so they fire with every terminal closed. A job is either a shell command
# (`--script`) or a headless Claude Code prompt (`--ai`).
#
# A job lives in $KINGS_HOME/schedules/<name>.env (outside the repo) and has a launchd agent
# generated from it in ~/Library/LaunchAgents. The agent only calls `kings schedule run <name>`,
# so a job always runs with the same environment, logs and failure notification.
#
# macOS (TCC) blocks launchd jobs from reading ~/Documents, ~/Desktop and ~/Downloads unless
# /bin/bash has Full Disk Access. `add` warns when the scripts live there and `check` proves the
# job starts under launchd; granting the access is a manual step in System Settings.
#
# KINGS_LAUNCH_AGENTS overrides the agents folder and KINGS_SCHEDULE_NO_LOAD=1 skips launchctl:
# both exist so the command can be tested without touching the real login session.

SCHEDULE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCHEDULE_SCRIPT_DIR/../../Core/print.sh"
. "$SCHEDULE_SCRIPT_DIR/../../Core/notify.sh"

SCHEDULE_DIR="$KINGS_HOME/schedules"
AGENTS_DIR="${KINGS_LAUNCH_AGENTS:-$HOME/Library/LaunchAgents}"
LABEL_PREFIX="com.kings.schedule"
MAIN_SH="$KINGS_ROOT/Scripts/main.sh"
KEEP_LOGS=30

usage() {
  print_error "Usage: kings schedule add <name> --at HH:MM [--days daily|weekdays|mon,wed,...] (--script <command> | --ai <prompt|@file>) [--model M] [--permission-mode P] [--claude-args '...'] [--workdir DIR] [--timeout SECONDS] [--notify <command>] [--replace]"
  print_error "       kings schedule list | run <name> | check <name> | logs <name> [--list] | enable <name> | disable <name> | remove <name>"
  exit 1
}

# Job names are file and launchd label parts, so they stay simple.
require_valid_name() {
  case "$1" in
    "" | -* | *[!a-z0-9-]*)
      print_error "Invalid job name '$1' (lowercase letters, digits and dashes)"
      exit 1
      ;;
  esac
}

require_job() {
  require_valid_name "$1"
  [ -f "$(job_file "$1")" ] && return
  print_error "No job named '$1' (see 'kings schedule list')"
  exit 1
}

job_file() { printf '%s/%s.env' "$SCHEDULE_DIR" "$1"; }
last_file() { printf '%s/%s.last' "$SCHEDULE_DIR" "$1"; }
lock_dir() { printf '%s/%s.lock' "$SCHEDULE_DIR" "$1"; }
log_dir() { printf '%s/logs/%s' "$SCHEDULE_DIR" "$1"; }
job_label() { printf '%s.%s' "$LABEL_PREFIX" "$1"; }
plist_file() { printf '%s/%s.plist' "$AGENTS_DIR" "$(job_label "$1")"; }

# Sets HOUR and MINUTE from "H:MM" / "HH:MM"; anything else is an error.
parse_time() {
  case "$1" in
    [0-9]:[0-5][0-9] | [0-1][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9])
      HOUR=$((10#${1%%:*}))
      MINUTE=$((10#${1##*:}))
      ;;
    *)
      print_error "Invalid time '$1' (use 24h HH:MM)"
      exit 1
      ;;
  esac
}

# Prints launchd weekday numbers (Monday=1 ... Sunday=7), one per line; nothing means every day.
weekday_numbers() {
  local day
  case "$1" in
    daily | "") return 0 ;;
    weekdays) printf '%s\n' 1 2 3 4 5 ;;
    *)
      for day in $(printf '%s' "$1" | tr ',' ' '); do
        case "$day" in
          mon) printf '1\n' ;;
          tue) printf '2\n' ;;
          wed) printf '3\n' ;;
          thu) printf '4\n' ;;
          fri) printf '5\n' ;;
          sat) printf '6\n' ;;
          sun) printf '7\n' ;;
          *)
            print_error "Invalid day '$day' (daily, weekdays or mon,tue,wed,thu,fri,sat,sun)"
            exit 1
            ;;
        esac
      done
      ;;
  esac
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Loads a job's settings into the JOB_* variables.
load_job() {
  JOB_KIND="" JOB_TIME="" JOB_DAYS="" JOB_COMMAND="" JOB_PROMPT="" JOB_MODEL="" JOB_PERMISSION=""
  JOB_CLAUDE_ARGS="" JOB_WORKDIR="" JOB_TIMEOUT="" JOB_PATH="" JOB_ENABLED="" JOB_NOTIFY=""
  . "$(job_file "$1")"
}

# Writes the settings with %q, so any text round-trips through `.`.
write_job() {
  local file
  file="$(job_file "$1")"
  mkdir -p "$SCHEDULE_DIR"
  {
    printf 'JOB_KIND=%q\n' "$JOB_KIND"
    printf 'JOB_TIME=%q\n' "$JOB_TIME"
    printf 'JOB_DAYS=%q\n' "$JOB_DAYS"
    printf 'JOB_COMMAND=%q\n' "$JOB_COMMAND"
    printf 'JOB_PROMPT=%q\n' "$JOB_PROMPT"
    printf 'JOB_MODEL=%q\n' "$JOB_MODEL"
    printf 'JOB_PERMISSION=%q\n' "$JOB_PERMISSION"
    printf 'JOB_CLAUDE_ARGS=%q\n' "$JOB_CLAUDE_ARGS"
    printf 'JOB_WORKDIR=%q\n' "$JOB_WORKDIR"
    printf 'JOB_TIMEOUT=%q\n' "$JOB_TIMEOUT"
    printf 'JOB_PATH=%q\n' "$JOB_PATH"
    printf 'JOB_ENABLED=%q\n' "$JOB_ENABLED"
    printf 'JOB_NOTIFY=%q\n' "$JOB_NOTIFY"
  } > "$file"
}

# One <dict> of the calendar trigger; the weekday key only when the job isn't daily.
calendar_entry() {
  printf '    <dict>\n'
  [ -n "$1" ] && printf '      <key>Weekday</key><integer>%s</integer>\n' "$1"
  printf '      <key>Hour</key><integer>%s</integer>\n' "$HOUR"
  printf '      <key>Minute</key><integer>%s</integer>\n' "$MINUTE"
  printf '    </dict>\n'
}

# Generates the launchd agent: a calendar trigger that calls `kings schedule run <name>`.
write_plist() {
  local name="$1" plist weekdays day
  plist="$(plist_file "$name")"
  parse_time "$JOB_TIME"
  weekdays="$(weekday_numbers "$JOB_DAYS")" || exit 1
  mkdir -p "$AGENTS_DIR" "$(log_dir "$name")"
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0">\n<dict>\n'
    printf '  <key>Label</key><string>%s</string>\n' "$(job_label "$name")"
    printf '  <key>ProgramArguments</key>\n  <array>\n'
    printf '    <string>/bin/bash</string>\n    <string>%s</string>\n' "$(xml_escape "$MAIN_SH")"
    printf '    <string>schedule</string>\n    <string>run</string>\n    <string>%s</string>\n    <string>--scheduled</string>\n' "$name"
    printf '  </array>\n'
    printf '  <key>EnvironmentVariables</key>\n  <dict>\n'
    printf '    <key>HOME</key><string>%s</string>\n' "$(xml_escape "$HOME")"
    printf '    <key>KINGS_HOME</key><string>%s</string>\n' "$(xml_escape "$KINGS_HOME")"
    printf '    <key>PATH</key><string>%s</string>\n' "$(xml_escape "$JOB_PATH")"
    printf '  </dict>\n'
    printf '  <key>StartCalendarInterval</key>\n  <array>\n'
    if [ -z "$weekdays" ]; then
      calendar_entry ""
    else
      for day in $weekdays; do calendar_entry "$day"; done
    fi
    printf '  </array>\n'
    printf '  <key>StandardOutPath</key><string>%s/launchd.log</string>\n' "$(xml_escape "$(log_dir "$name")")"
    printf '  <key>StandardErrorPath</key><string>%s/launchd.log</string>\n' "$(xml_escape "$(log_dir "$name")")"
    printf '</dict>\n</plist>\n'
  } > "$plist"
  plutil -lint "$plist" > /dev/null || {
    print_error "Generated an invalid plist: $plist"
    exit 1
  }
}

# Registers / unregisters the agent in the login session (a no-op while testing).
launch_load() {
  [ "${KINGS_SCHEDULE_NO_LOAD:-0}" = "1" ] && return 0
  launch_unload "$1"
  launchctl bootstrap "gui/$(id -u)" "$(plist_file "$1")"
}

launch_unload() {
  [ "${KINGS_SCHEDULE_NO_LOAD:-0}" = "1" ] && return 0
  launchctl bootout "gui/$(id -u)/$(job_label "$1")" > /dev/null 2>&1
  return 0
}

is_loaded() {
  [ "${KINGS_SCHEDULE_NO_LOAD:-0}" = "1" ] && return 1
  launchctl print "gui/$(id -u)/$(job_label "$1")" > /dev/null 2>&1
}

# launchd's own "last exit code" for the job: empty if it never ran, 126 when macOS blocked it.
launchd_exit_code() {
  launchctl print "gui/$(id -u)/$(job_label "$1")" 2> /dev/null | sed -n 's/^[[:space:]]*last exit code = //p' | grep -v 'never exited' | head -1
}

# True when the scripts launchd must read are in a folder macOS protects.
scripts_in_protected_folder() {
  case "$MAIN_SH" in
    /Users/*/Documents/* | /Users/*/Desktop/* | /Users/*/Downloads/*) return 0 ;;
  esac
  return 1
}

# A successful `check` leaves this marker: the access is granted, so `add` stops warning.
ACCESS_MARKER="$SCHEDULE_DIR/.launchd-access-ok"

warn_if_protected() {
  scripts_in_protected_folder || return 0
  [ -f "$ACCESS_MARKER" ] && return 0
  print_warn "KingsScript lives in a folder macOS protects, so launchd can't run it until /bin/bash has Full Disk Access"
  print_warn "System Settings > Privacy & Security > Full Disk Access > add /bin/bash, then: kings schedule check $1"
}

# Human-readable "14:00 daily" / "09:00 mon,fri".
describe_when() {
  printf '%02d:%02d %s' "$((10#${JOB_TIME%%:*}))" "$((10#${JOB_TIME##*:}))" "${JOB_DAYS:-daily}"
}

# Parses `add`'s options into the JOB_* variables; NAME is the first argument.
parse_add_args() {
  JOB_KIND="" JOB_TIME="" JOB_DAYS="daily" JOB_COMMAND="" JOB_PROMPT="" JOB_MODEL="sonnet"
  JOB_PERMISSION="" JOB_CLAUDE_ARGS="" JOB_WORKDIR="$HOME" JOB_TIMEOUT="" JOB_PATH="$PATH" JOB_ENABLED=1 JOB_NOTIFY=""
  REPLACE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --at) JOB_TIME="$2"; shift 2 ;;
      --days) JOB_DAYS="$2"; shift 2 ;;
      --script) JOB_KIND=script; JOB_COMMAND="$2"; shift 2 ;;
      --ai) JOB_KIND=ai; JOB_PROMPT="$2"; shift 2 ;;
      --model) JOB_MODEL="$2"; shift 2 ;;
      --permission-mode) JOB_PERMISSION="$2"; shift 2 ;;
      --claude-args) JOB_CLAUDE_ARGS="$2"; shift 2 ;;
      --workdir) JOB_WORKDIR="$2"; shift 2 ;;
      --timeout) JOB_TIMEOUT="$2"; shift 2 ;;
      --notify) JOB_NOTIFY="$2"; shift 2 ;;
      --replace) REPLACE=1; shift ;;
      *) usage ;;
    esac
  done
  [ -n "$JOB_TIME" ] && [ -n "$JOB_KIND" ] || usage
  [ -n "$JOB_TIMEOUT" ] || { [ "$JOB_KIND" = ai ] && JOB_TIMEOUT=3600 || JOB_TIMEOUT=0; }
  case "$JOB_TIMEOUT" in
    *[!0-9]*) print_error "--timeout takes seconds"; exit 1 ;;
  esac
  [ -d "$JOB_WORKDIR" ] || { print_error "--workdir does not exist: $JOB_WORKDIR"; exit 1; }
}

schedule_command_add() {
  local name="$1"
  [ $# -ge 1 ] || usage
  shift
  require_valid_name "$name"
  parse_add_args "$@"
  parse_time "$JOB_TIME"
  weekday_numbers "$JOB_DAYS" > /dev/null || exit 1
  if [ -f "$(job_file "$name")" ] && [ "$REPLACE" -ne 1 ]; then
    print_error "Job '$name' already exists (use --replace to overwrite)"
    exit 1
  fi
  write_job "$name"
  write_plist "$name"
  launch_load "$name"
  warn_if_protected "$name"
  print_success "Scheduled '$name' at $(describe_when) ($JOB_KIND)"
  print_info "If the Mac is asleep then, launchd runs it as soon as it wakes. Test it now: kings schedule run $name"
}

schedule_command_list() {
  local file name last_status last_at state
  printf '%-22s %-16s %-7s %-6s %s\n' NAME WHEN KIND STATE LAST
  for file in "$SCHEDULE_DIR"/*.env; do
    [ -f "$file" ] || continue
    name="$(basename "$file" .env)"
    load_job "$name"
    if [ "$JOB_ENABLED" = 1 ] && { is_loaded "$name" || [ "${KINGS_SCHEDULE_NO_LOAD:-0}" = "1" ]; }; then
      state=on
    else
      state=off
    fi
    last_status="never"
    if [ -f "$(last_file "$name")" ]; then
      last_status="$(sed -n 's/^STATUS=//p' "$(last_file "$name")") $(sed -n 's/^AT=//p' "$(last_file "$name")")"
    elif [ "$(launchd_exit_code "$name")" = "126" ]; then
      last_status="blocked by macOS (kings schedule check $name)"
    fi
    printf '%-22s %-16s %-7s %-6s %s\n' "$name" "$(describe_when)" "$JOB_KIND" "$state" "$last_status"
  done
}

# Only one run of a job at a time; a lock whose process is gone is left over from a crash.
acquire_job_lock() {
  local lock pid
  lock="$(lock_dir "$1")"
  if ! mkdir "$lock" 2> /dev/null; then
    pid="$(cat "$lock/pid" 2> /dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null; then
      print_warn "Job '$1' is already running (pid $pid)"
      exit 0
    fi
    rm -rf "$lock"
    mkdir "$lock" || exit 1
  fi
  printf '%s' "$$" > "$lock/pid"
  trap 'rm -rf "$(lock_dir "$JOB_NAME")"' EXIT
}

# Runs the command in the background and kills it when the timeout passes (exit 124).
run_with_timeout() {
  local seconds="$1" pid watchdog status
  shift
  if [ "$seconds" -eq 0 ]; then
    "$@"
    return
  fi
  "$@" &
  pid=$!
  (
    sleep "$seconds"
    pkill -TERM -P "$pid" 2> /dev/null
    kill -TERM "$pid" 2> /dev/null
  ) &
  watchdog=$!
  wait "$pid"
  status=$?
  kill "$watchdog" 2> /dev/null
  wait "$watchdog" 2> /dev/null
  # 143 = killed by the watchdog's TERM
  [ "$status" -eq 143 ] && status=124
  return "$status"
}

# The job's work, with the PATH it was scheduled with (launchd's own is minimal).
run_job_body() {
  local prompt
  cd "$JOB_WORKDIR" || return 1
  export PATH="$JOB_PATH"
  if [ "$JOB_KIND" = script ]; then
    /bin/bash -c "$JOB_COMMAND"
    return
  fi
  prompt="$JOB_PROMPT"
  case "$prompt" in
    @*) prompt="$(cat "${prompt#@}")" || return 1 ;;
  esac
  local args=(-p "$prompt" --model "$JOB_MODEL")
  [ -n "$JOB_PERMISSION" ] && args+=(--permission-mode "$JOB_PERMISSION")
  if [ -n "$JOB_CLAUDE_ARGS" ]; then
    # Word splitting on purpose, without globbing
    set -f
    args+=($JOB_CLAUDE_ARGS)
    set +f
  fi
  claude "${args[@]}"
}

# After a scheduled run that succeeded, shows the last line the job's --notify command prints as a banner.
# The banner comes from here, not from the job: a headless Claude session can't reach Notification Center.
notify_job_result() {
  local message
  [ "$scheduled" -eq 1 ] && [ -n "$JOB_NOTIFY" ] || return 0
  message="$(cd "$JOB_WORKDIR" && PATH="$JOB_PATH" /bin/bash -c "$JOB_NOTIFY" 2> /dev/null | tail -n 1)"
  [ -n "$message" ] && notify_banner "$JOB_NAME" "$message"
  return 0
}

# Keeps the newest $KEEP_LOGS run logs of a job.
prune_logs() {
  ls -1t "$(log_dir "$1")"/run-*.log 2> /dev/null | tail -n +$((KEEP_LOGS + 1)) | while IFS= read -r old; do
    rm -f "$old"
  done
}

schedule_command_run() {
  local scheduled=0 logfile started status
  JOB_NAME="$1"
  [ "$2" = "--scheduled" ] && scheduled=1
  require_job "$JOB_NAME"
  load_job "$JOB_NAME"
  if [ "$scheduled" -eq 1 ] && [ "$JOB_ENABLED" != 1 ]; then
    log "schedule $JOB_NAME: disabled, skipped"
    exit 0
  fi
  acquire_job_lock "$JOB_NAME"
  mkdir -p "$(log_dir "$JOB_NAME")"
  logfile="$(log_dir "$JOB_NAME")/run-$(date +%Y%m%d-%H%M%S).log"
  started="$(date +%s)"
  print_info "Running '$JOB_NAME' ($JOB_KIND); log: $logfile"
  {
    printf '== %s %s\n' "$JOB_NAME" "$(date '+%Y-%m-%d %H:%M:%S')"
    run_with_timeout "${JOB_TIMEOUT:-0}" run_job_body
  } > "$logfile" 2>&1
  status=$?
  record_result "$status" "$started" "$logfile"
  prune_logs "$JOB_NAME"
  if [ "$status" -ne 0 ]; then
    print_error "'$JOB_NAME' failed (exit $status); see 'kings schedule logs $JOB_NAME'"
    [ "$scheduled" -eq 1 ] && notify_banner "Kings schedule" "$JOB_NAME failed (exit $status). kings schedule logs $JOB_NAME"
    exit 1
  fi
  notify_job_result
  print_success "'$JOB_NAME' finished"
}

# Stores the outcome of the last run, shown by `list`.
record_result() {
  {
    printf 'STATUS=%s\n' "$([ "$1" -eq 0 ] && printf ok || printf failed)"
    printf 'AT=%s\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'EXIT=%s\n' "$1"
    printf 'SECONDS=%s\n' "$(($(date +%s) - $2))"
    printf 'LOG=%s\n' "$3"
  } > "$(last_file "$JOB_NAME")"
}

schedule_command_logs() {
  local latest
  require_job "$1"
  if [ "$2" = "--list" ]; then
    ls -1t "$(log_dir "$1")"/run-*.log 2> /dev/null
    return 0
  fi
  latest="$(ls -1t "$(log_dir "$1")"/run-*.log 2> /dev/null | head -1)"
  if [ -z "$latest" ]; then
    print_warn "'$1' has not run yet"
    return 0
  fi
  printf '# %s\n' "$latest"
  cat "$latest"
}

# Starts the job through launchd, exactly as the schedule would, to prove it can run there.
schedule_command_check() {
  local code waited=0
  require_job "$1"
  if ! is_loaded "$1"; then
    print_error "'$1' is not loaded in launchd (disabled, or testing mode)"
    exit 1
  fi
  launchctl kickstart -k "gui/$(id -u)/$(job_label "$1")" || exit 1
  # A blocked start fails within a second; a started job keeps running or finishes with its own code.
  while [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
    code="$(launchd_exit_code "$1")"
    launchctl print "gui/$(id -u)/$(job_label "$1")" 2> /dev/null | grep -q 'state = running' && continue
    [ -n "$code" ] && break
  done
  case "$code" in
    0)
      touch "$ACCESS_MARKER"
      print_success "'$1' ran under launchd (see 'kings schedule logs $1')"
      ;;
    126)
      rm -f "$ACCESS_MARKER"
      print_error "macOS blocked launchd from running the scripts (Operation not permitted)"
      warn_if_protected "$1"
      exit 1
      ;;
    "") print_success "'$1' started under launchd and is still running (see 'kings schedule logs $1')" ;;
    *)
      print_warn "'$1' started under launchd but exited with $code (see 'kings schedule logs $1')"
      exit 1
      ;;
  esac
}

schedule_command_enable() {
  require_job "$1"
  load_job "$1"
  JOB_ENABLED=1
  write_job "$1"
  write_plist "$1"
  launch_load "$1"
  print_success "Enabled '$1'"
}

schedule_command_disable() {
  require_job "$1"
  load_job "$1"
  JOB_ENABLED=0
  write_job "$1"
  launch_unload "$1"
  print_success "Disabled '$1' (kings schedule enable $1 turns it back on)"
}

schedule_command_remove() {
  require_job "$1"
  launch_unload "$1"
  rm -f "$(job_file "$1")" "$(last_file "$1")" "$(plist_file "$1")"
  rm -rf "$(log_dir "$1")" "$(lock_dir "$1")"
  print_success "Removed '$1'"
}

case "$1" in
  add) shift; schedule_command_add "$@" ;;
  list) schedule_command_list ;;
  run) [ -n "$2" ] || usage; shift; schedule_command_run "$@" ;;
  logs) [ -n "$2" ] || usage; shift; schedule_command_logs "$@" ;;
  check) [ -n "$2" ] || usage; schedule_command_check "$2" ;;
  enable) [ -n "$2" ] || usage; schedule_command_enable "$2" ;;
  disable) [ -n "$2" ] || usage; schedule_command_disable "$2" ;;
  remove) [ -n "$2" ] || usage; schedule_command_remove "$2" ;;
  *) usage ;;
esac
