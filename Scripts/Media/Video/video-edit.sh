#!/bin/bash
# `kings video-edit <files|folders|links>... --name NAME [options]`: joins the clips in recording
# order, speeds them up and burns captions. Every option: README.md next to this script.

. "$KINGS_CORE/print.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$KINGS_HOME/venvs/video"

check_tools() {
  command -v ffmpeg > /dev/null && return
  print_error "ffmpeg is required: brew install ffmpeg"
  exit 1
}

# Whisper (MLX, Apple silicon) and Pillow live in a virtualenv, rebuilt when requirements.txt changes.
ensure_venv() {
  local stamp="$VENV/.requirements"
  cmp -s "$HERE/requirements.txt" "$stamp" && return
  print_info "Preparing the Python environment in $VENV"
  python3 -m venv "$VENV" &&
    log_run "$VENV/bin/pip" install --quiet --upgrade -r "$HERE/requirements.txt" &&
    cp "$HERE/requirements.txt" "$stamp" || {
    print_error "Could not install the video dependencies (see today's log)"
    exit 1
  }
}

check_tools
ensure_venv
exec "$VENV/bin/python" "$HERE/video_edit.py" "$@"
