#!/bin/bash
# Moves each past month's daily logs into logs/YYYY-MM.zip. Every pending month is handled,
# so a machine that stayed off for a while catches up in a single run.

. "$(dirname "${BASH_SOURCE[0]}")/../../../Core/log.sh"

# Months found in the daily log names (YYYY-MM-DD.log), current one excluded.
past_months() {
  local current month
  current="$(date +%Y-%m)"
  for month in $(ls | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}\)-[0-9]\{2\}\.log$/\1/p' | sort -u); do
    [[ "$month" < "$current" ]] && printf '%s\n' "$month"
  done
}

# -m deletes the logs once they are in the zip.
archive_month() {
  zip -q -m "$1.zip" "$1"-*.log || return 1
  log "Archived $1 logs into $1.zip"
}

cd "$KINGS_LOG_DIR" 2> /dev/null || exit 0
for month in $(past_months); do
  archive_month "$month" || exit 1
done
