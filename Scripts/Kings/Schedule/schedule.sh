#!/bin/bash
# `kings schedule add|list|run|check|logs|enable|disable|remove|sync|export`: jobs that run at a fixed time
# of day (or every N minutes) through launchd, so they fire with every terminal closed. A job is either a
# shell command (`--script`) or a headless Claude Code prompt (`--ai`).
#
# A job lives in $KINGS_HOME/schedules/<name>.env (outside the repo) and has a launchd agent
# generated from it in ~/Library/LaunchAgents. The agent only calls `kings schedule run <name>`,
# so a job always runs with the same environment, logs and failure notification.
#
# macOS (TCC) blocks launchd jobs from reading ~/Documents, ~/Desktop and ~/Downloads unless
# /bin/bash has Full Disk Access. `add` warns when the scripts live there and `check` proves the
# job starts under launchd; granting the access is a manual step in System Settings.
#
# KINGS_SCHEDULE_SOURCE (config.env) names a command that keeps the jobs somewhere else, e.g. a table a
# layer reads; `sync` makes the local jobs match it (see schedule_command_sync for its contract).
#
# KINGS_LAUNCH_AGENTS overrides the agents folder and KINGS_SCHEDULE_NO_LOAD=1 skips launchctl:
# both exist so the command can be tested without touching the real login session.

SCHEDULE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCHEDULE_SCRIPT_DIR/../../Core/print.sh"
. "$SCHEDULE_SCRIPT_DIR/../../Core/notify.sh"
. "$SCHEDULE_SCRIPT_DIR/../../Core/secrets.sh"

SCHEDULE_DIR="$KINGS_HOME/schedules"
AGENTS_DIR="${KINGS_LAUNCH_AGENTS:-$HOME/Library/LaunchAgents}"
LABEL_PREFIX="com.kings.schedule"
MAIN_SH="$KINGS_ROOT/Scripts/main.sh"
KEEP_LOGS=30
RETRY_DELAY="${KINGS_SCHEDULE_RETRY_DELAY:-300}"

usage() {
  print_error "Usage: kings schedule add <name> (--at HH:MM [--days daily|weekdays|mon,wed,...] | --every MINUTES) (--script <command> | --ai <prompt|@file>) [--model M] [--permission-mode P] [--claude-args '...'] [--workdir DIR] [--timeout SECONDS] [--notify <command>] [--on-start <command>] [--on-finish <command>] [--replace]"
  print_error "       kings schedule list | run <name> | check <name> | logs <name> [--list] | enable <name> | disable <name> | remove <name>"
  print_error "       kings schedule sync [--dry-run] | export"
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
  clear_job
  . "$(job_file "$1")"
}

clear_job() {
  JOB_KIND="" JOB_TIME="" JOB_EVERY="" JOB_DAYS="" JOB_COMMAND="" JOB_PROMPT="" JOB_MODEL="" JOB_PERMISSION=""
  JOB_CLAUDE_ARGS="" JOB_WORKDIR="" JOB_TIMEOUT="" JOB_PATH="" JOB_ENABLED="" JOB_NOTIFY="" JOB_ON_START="" JOB_ON_FINISH=""
  JOB_MANAGED=""
}

# Writes the settings with %q, so any text round-trips through `.`.
write_job() {
  local file
  file="$(job_file "$1")"
  mkdir -p "$SCHEDULE_DIR"
  {
    printf 'JOB_KIND=%q\n' "$JOB_KIND"
    printf 'JOB_TIME=%q\n' "$JOB_TIME"
    printf 'JOB_EVERY=%q\n' "$JOB_EVERY"
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
    printf 'JOB_ON_START=%q\n' "$JOB_ON_START"
    printf 'JOB_ON_FINISH=%q\n' "$JOB_ON_FINISH"
    printf 'JOB_MANAGED=%q\n' "$JOB_MANAGED"
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

# Generates the launchd agent: a calendar (or interval) trigger that calls `kings schedule run <name>`.
write_plist() {
  local name="$1" plist weekdays day
  plist="$(plist_file "$name")"
  if [ -z "$JOB_EVERY" ]; then
    parse_time "$JOB_TIME"
    weekdays="$(weekday_numbers "$JOB_DAYS")" || exit 1
  fi
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
    if [ -n "$JOB_EVERY" ]; then
      printf '  <key>StartInterval</key><integer>%s</integer>\n' "$((JOB_EVERY * 60))"
    else
      printf '  <key>StartCalendarInterval</key>\n  <array>\n'
      if [ -z "$weekdays" ]; then
        calendar_entry ""
      else
        for day in $weekdays; do calendar_entry "$day"; done
      fi
      printf '  </array>\n'
    fi
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

# Human-readable "14:00 daily" / "09:00 mon,fri" / "every 15m".
describe_when() {
  [ -n "$JOB_EVERY" ] && { printf 'every %sm' "$JOB_EVERY"; return; }
  printf '%02d:%02d %s' "$((10#${JOB_TIME%%:*}))" "$((10#${JOB_TIME##*:}))" "${JOB_DAYS:-daily}"
}

# Parses `add`'s options into the JOB_* variables; NAME is the first argument.
parse_add_args() {
  clear_job
  JOB_DAYS="daily" JOB_MODEL="sonnet" JOB_WORKDIR="$HOME" JOB_PATH="$PATH" JOB_ENABLED=1
  REPLACE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --at) JOB_TIME="$2"; shift 2 ;;
      --every) JOB_EVERY="$2"; shift 2 ;;
      --days) JOB_DAYS="$2"; shift 2 ;;
      --script) JOB_KIND=script; JOB_COMMAND="$2"; shift 2 ;;
      --ai) JOB_KIND=ai; JOB_PROMPT="$2"; shift 2 ;;
      --model) JOB_MODEL="$2"; shift 2 ;;
      --permission-mode) JOB_PERMISSION="$2"; shift 2 ;;
      --claude-args) JOB_CLAUDE_ARGS="$2"; shift 2 ;;
      --workdir) JOB_WORKDIR="$2"; shift 2 ;;
      --timeout) JOB_TIMEOUT="$2"; shift 2 ;;
      --notify) JOB_NOTIFY="$2"; shift 2 ;;
      --on-start) JOB_ON_START="$2"; shift 2 ;;
      --on-finish) JOB_ON_FINISH="$2"; shift 2 ;;
      --replace) REPLACE=1; shift ;;
      *) usage ;;
    esac
  done
  [ -n "$JOB_KIND" ] || usage
  # Exactly one of --at and --every
  { [ -n "$JOB_TIME" ] || [ -n "$JOB_EVERY" ]; } && { [ -z "$JOB_TIME" ] || [ -z "$JOB_EVERY" ]; } || usage
  case "$JOB_EVERY" in
    "") ;;
    *[!0-9]* | 0) print_error "--every takes minutes"; exit 1 ;;
    *) JOB_DAYS="" ;;
  esac
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
  if [ -z "$JOB_EVERY" ]; then
    parse_time "$JOB_TIME"
    weekday_numbers "$JOB_DAYS" > /dev/null || exit 1
  fi
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
  # Headless Claude stops background agents 10 minutes after its last turn; 0 waits for them, and the job's own timeout is the bound.
  export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-0}"
  local args=(-p "$prompt" --model "$JOB_MODEL")
  [ -n "$JOB_PERMISSION" ] && args+=(--permission-mode "$JOB_PERMISSION")
  if [ -n "$JOB_CLAUDE_ARGS" ]; then
    # Word splitting on purpose, without globbing
    set -f
    args+=($JOB_CLAUDE_ARGS)
    set +f
  fi
  # The interactive login is tried first: only it reaches the claude.ai connectors (Gmail, Calendar, Notion).
  # Its OAuth session can expire with nobody at the machine; then the run is retried once with the long-lived
  # token (`claude setup-token`), which signs in but has no connectors.
  local output status token
  output="$(mktemp)"
  # Run from the installed binary, never a copy: macOS keys the ~/Documents permission to the executable's path,
  # so a copy at a new path waits on a permission prompt nobody answers. The job itself never updates claude
  # (DISABLE_AUTOUPDATER): an update replaces the binary in place, and a run whose executable is replaced
  # mid-way loses that permission ("Operation not permitted"). `claude-update` updates once a day instead.
  export DISABLE_AUTOUPDATER=1
  claude "${args[@]}" 2>&1 | tee "$output"
  status=${PIPESTATUS[0]}
  if [ "$status" -ne 0 ] && grep -q "Failed to authenticate" "$output" \
    && token="$(secret_get CLAUDE_CODE_OAUTH_TOKEN 2> /dev/null)"; then
    echo "Login expired; retrying with CLAUDE_CODE_OAUTH_TOKEN (no claude.ai connectors in this run)"
    CLAUDE_CODE_OAUTH_TOKEN="$token" claude "${args[@]}"
    status=$?
  fi
  rm -f "$output"
  return "$status"
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

# Runs a job's --on-start or --on-finish hook with the run's context in KINGS_JOB_* variables; a hook
# that fails is logged and never fails the job. Prints the hook's last output line.
run_job_hook() {
  local hook="$1" out
  [ -n "$hook" ] || return 0
  out="$(cd "$JOB_WORKDIR" && PATH="$JOB_PATH" KINGS_JOB_NAME="$JOB_NAME" KINGS_JOB_STATUS="$2" \
    KINGS_JOB_EXIT="${3:-}" KINGS_JOB_LOG="$logfile" KINGS_JOB_REF="${KINGS_JOB_REF:-}" \
    /bin/bash -c "$hook" 2>> "$logfile" | tail -n 1)" || log "schedule $JOB_NAME: hook failed: $hook"
  printf '%s' "$out"
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
  if [ "$scheduled" -eq 1 ] && [ "$(source_enabled "$JOB_NAME")" = 0 ]; then
    log "schedule $JOB_NAME: disabled at the source, skipped"
    exit 0
  fi
  acquire_job_lock "$JOB_NAME"
  mkdir -p "$(log_dir "$JOB_NAME")"
  logfile="$(log_dir "$JOB_NAME")/run-$(date +%Y%m%d-%H%M%S).log"
  started="$(date +%s)"
  print_info "Running '$JOB_NAME' ($JOB_KIND); log: $logfile"
  # The start hook's last line (e.g. a report page id) reaches the job and the finish hook as KINGS_JOB_REF.
  KINGS_JOB_REF="$(run_job_hook "$JOB_ON_START" running)"
  export KINGS_JOB_REF
  {
    printf '== %s %s\n' "$JOB_NAME" "$(date '+%Y-%m-%d %H:%M:%S')"
    run_with_timeout "${JOB_TIMEOUT:-0}" run_job_body
  } > "$logfile" 2>&1
  status=$?
  # Most scheduled failures are a service down for a moment (an API's 502), so the run is tried once more after
  # a pause. Not after a timeout, which would hold the job for another full timeout.
  if [ "$status" -ne 0 ] && [ "$status" -ne 124 ] && [ "$scheduled" -eq 1 ]; then
    {
      printf '== failed (exit %s); retrying in %ss\n' "$status" "$RETRY_DELAY"
      sleep "$RETRY_DELAY"
      printf '== retry %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
      run_with_timeout "${JOB_TIMEOUT:-0}" run_job_body
    } >> "$logfile" 2>&1
    status=$?
  fi
  run_job_hook "$JOB_ON_FINISH" "$([ "$status" -eq 0 ] && printf ok || printf failed)" "$status" > /dev/null
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
  # The source shows the outcome too; a source that can't be reached never fails the run.
  [ "$JOB_MANAGED" = 1 ] && source_call result "$JOB_NAME" "$([ "$1" -eq 0 ] && printf ok || printf failed)" \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(($(date +%s) - $2))" >> "$3" 2>&1
  return 0
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

# A managed job's on/off comes from the source: a local change lasts until the next sync.
warn_if_managed() {
  [ "$JOB_MANAGED" = 1 ] && print_warn "'$1' is managed by the source: change it there, or the next sync undoes this"
  return 0
}

schedule_command_enable() {
  require_job "$1"
  load_job "$1"
  JOB_ENABLED=1
  write_job "$1"
  write_plist "$1"
  launch_load "$1"
  print_success "Enabled '$1'"
  warn_if_managed "$1"
}

schedule_command_disable() {
  require_job "$1"
  load_job "$1"
  JOB_ENABLED=0
  write_job "$1"
  launch_unload "$1"
  print_success "Disabled '$1' (kings schedule enable $1 turns it back on)"
  warn_if_managed "$1"
}

schedule_command_remove() {
  require_job "$1"
  launch_unload "$1"
  rm -f "$(job_file "$1")" "$(last_file "$1")" "$(plist_file "$1")"
  rm -rf "$(log_dir "$1")" "$(lock_dir "$1")"
  print_success "Removed '$1'"
}

# Calls the source command (KINGS_SCHEDULE_SOURCE) with the given arguments; fails when there is none.
source_call() {
  [ -n "$KINGS_SCHEDULE_SOURCE" ] || return 1
  /bin/bash -c "$KINGS_SCHEDULE_SOURCE \"\$@\"" _ "$@"
}

# "0" when the source says a job it manages is off; anything else (on, unknown, unreachable) lets it run.
source_enabled() {
  [ "$JOB_MANAGED" = 1 ] || return 0
  source_call enabled "$1" 2> /dev/null | tail -n 1
}

job_running() {
  local pid
  pid="$(cat "$(lock_dir "$1")/pid" 2> /dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null
}

# The settings that decide what runs and when, normalized (time, order of the days), so equal jobs compare equal.
job_signature() {
  local when
  if [ -n "$JOB_EVERY" ]; then
    when="every $JOB_EVERY"
  else
    parse_time "$JOB_TIME"
    when="$HOUR:$MINUTE $(weekday_numbers "$JOB_DAYS" | sort | tr '\n' ',')"
  fi
  printf '%s\n' "$when" "$JOB_KIND" "$JOB_COMMAND" "$JOB_PROMPT" "$JOB_MODEL" "$JOB_PERMISSION" "$JOB_CLAUDE_ARGS" \
    "$JOB_WORKDIR" "${JOB_TIMEOUT:-0}" "$JOB_ENABLED" "$JOB_NOTIFY" "$JOB_ON_START" "$JOB_ON_FINISH"
}

# Prints one change and, unless --dry-run, makes it. "adopt" only marks an identical local job as the
# source's. A running job is left for the next sync: reloading its agent would stop the run.
sync_apply() {
  local action="$1" name="$2" file="$3" path="$4"
  printf '%s %s\n' "$action" "$name"
  SYNC_CHANGES=$((SYNC_CHANGES + 1))
  [ "$SYNC_DRY" -eq 1 ] && return
  if job_running "$name"; then
    print_warn "'$name' is running; left for the next sync"
    return
  fi
  if [ "$action" = remove ]; then
    schedule_command_remove "$name"
    return
  fi
  clear_job
  . "$file"
  JOB_PATH="${path:-$PATH}" JOB_MANAGED=1
  if [ ! -d "$JOB_WORKDIR" ]; then
    print_warn "Skipped '$name': workdir does not exist ($JOB_WORKDIR)"
    return
  fi
  write_job "$name"
  [ "$action" = adopt ] && return
  write_plist "$name"
  if [ "$JOB_ENABLED" = 1 ]; then launch_load "$name"; else launch_unload "$name"; fi
}

# Brings one local job in line with the source's copy of it (an .env file the source wrote).
sync_job() {
  local name="$1" file="$2" wanted
  case "$name" in
    "" | -* | *[!a-z0-9-]*) print_warn "Skipped '$name': invalid job name"; return ;;
  esac
  if ! wanted="$(clear_job; . "$file" && job_signature 2> /dev/null)"; then
    print_warn "Skipped '$name': invalid time or days"
    return
  fi
  if [ ! -f "$(job_file "$name")" ]; then
    sync_apply add "$name" "$file" ""
    return
  fi
  load_job "$name"
  if [ "$(job_signature)" != "$wanted" ]; then
    sync_apply update "$name" "$file" "$JOB_PATH"
  elif [ "$JOB_MANAGED" != 1 ]; then
    sync_apply adopt "$name" "$file" "$JOB_PATH"
  fi
}

# Makes the local jobs match the source. Contract of the KINGS_SCHEDULE_SOURCE command:
#   <source> jobs <dir>         writes one <name>.env per job into <dir>, in the format write_job uses
#                               (JOB_PATH and JOB_MANAGED excluded); a non-zero exit means "unreachable"
#   <source> enabled <name>     prints 1 or 0 — checked before every scheduled run of a managed job
#   <source> result <name> <ok|failed> <time> <seconds>   after every run of a managed job
# Only jobs the source manages are changed or removed; jobs added by hand stay untouched. When the
# source can't be read, the last synced state stays in force.
schedule_command_sync() {
  local incoming file name managed=0
  SYNC_DRY=0 SYNC_CHANGES=0
  [ "$1" = "--dry-run" ] && SYNC_DRY=1
  if [ -z "$KINGS_SCHEDULE_SOURCE" ]; then
    print_error "No KINGS_SCHEDULE_SOURCE in config.env"
    exit 1
  fi
  incoming="$(mktemp -d)"
  trap 'rm -rf "$incoming"' EXIT
  if ! source_call jobs "$incoming"; then
    print_warn "Couldn't read the jobs from the source; the local jobs stay as they are"
    exit 0
  fi
  for file in "$incoming"/*.env; do
    [ -f "$file" ] || continue
    sync_job "$(basename "$file" .env)" "$file"
  done
  for file in "$SCHEDULE_DIR"/*.env; do
    [ -f "$file" ] || continue
    name="$(basename "$file" .env)"
    [ -f "$incoming/$name.env" ] && continue
    load_job "$name"
    [ "$JOB_MANAGED" = 1 ] && managed=$((managed + 1))
  done
  # An empty answer is more likely a broken source than "delete every job"
  if ! ls "$incoming"/*.env > /dev/null 2>&1 && [ "$managed" -gt 0 ]; then
    print_warn "The source returned no jobs; nothing removed"
    exit 0
  fi
  for file in "$SCHEDULE_DIR"/*.env; do
    [ -f "$file" ] || continue
    name="$(basename "$file" .env)"
    [ -f "$incoming/$name.env" ] && continue
    load_job "$name"
    [ "$JOB_MANAGED" = 1 ] && sync_apply remove "$name"
  done
  if [ "$SYNC_CHANGES" -eq 0 ]; then
    print_info "In sync: nothing to change"
  elif [ "$SYNC_DRY" -eq 1 ]; then
    print_info "$SYNC_CHANGES change(s); nothing applied (--dry-run)"
  else
    print_success "$SYNC_CHANGES change(s) applied"
  fi
}

# Prints an `add` line per job, enough to recreate them on a machine without the source.
schedule_command_export() {
  local file name
  for file in "$SCHEDULE_DIR"/*.env; do
    [ -f "$file" ] || continue
    name="$(basename "$file" .env)"
    load_job "$name"
    printf 'kings schedule add %q' "$name"
    if [ -n "$JOB_EVERY" ]; then
      printf ' --every %q' "$JOB_EVERY"
    else
      printf ' --at %q --days %q' "$JOB_TIME" "${JOB_DAYS:-daily}"
    fi
    if [ "$JOB_KIND" = script ]; then
      printf ' --script %q' "$JOB_COMMAND"
    else
      printf ' --ai %q --model %q' "$JOB_PROMPT" "$JOB_MODEL"
      [ -n "$JOB_PERMISSION" ] && printf ' --permission-mode %q' "$JOB_PERMISSION"
      [ -n "$JOB_CLAUDE_ARGS" ] && printf ' --claude-args %q' "$JOB_CLAUDE_ARGS"
    fi
    printf ' --workdir %q --timeout %q' "$JOB_WORKDIR" "${JOB_TIMEOUT:-0}"
    [ -n "$JOB_NOTIFY" ] && printf ' --notify %q' "$JOB_NOTIFY"
    [ -n "$JOB_ON_START" ] && printf ' --on-start %q' "$JOB_ON_START"
    [ -n "$JOB_ON_FINISH" ] && printf ' --on-finish %q' "$JOB_ON_FINISH"
    printf ' --replace\n'
    [ "$JOB_ENABLED" = 1 ] || printf 'kings schedule disable %q\n' "$name"
  done
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
  sync) schedule_command_sync "$2" ;;
  export) schedule_command_export ;;
  *) usage ;;
esac
