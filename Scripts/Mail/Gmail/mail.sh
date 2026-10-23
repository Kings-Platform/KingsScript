#!/bin/bash
# `kings mail send|attachments|auth|status`: Gmail from the command line, as the account set in
# config.env (KINGS_MAIL_ACCOUNT). Setup and every option: README.md next to this script.

. "$KINGS_CORE/print.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$KINGS_HOME/venvs/mail"

usage() {
  print_error "Usage: kings mail send|attachments|auth|status [options] (kings mail <subcommand> --help)"
  exit 1
}

# The Google libraries live in a virtualenv under KINGS_HOME, rebuilt when requirements.txt changes.
ensure_venv() {
  local stamp="$VENV/.requirements"
  cmp -s "$HERE/requirements.txt" "$stamp" && return
  print_info "Preparing the Python environment in $VENV"
  python3 -m venv "$VENV" &&
    log_run "$VENV/bin/pip" install --quiet --upgrade -r "$HERE/requirements.txt" &&
    cp "$HERE/requirements.txt" "$stamp" || {
    print_error "Could not install the mail dependencies (see today's log)"
    exit 1
  }
}

case "$1" in
  send | attachments | auth | status) ;;
  *) usage ;;
esac
ensure_venv
exec "$VENV/bin/python" "$HERE/gmail.py" "$@"
