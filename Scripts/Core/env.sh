#!/bin/bash
# Bootstrap sourced by every KingsScript module: resolves paths and loads the machine config.

KINGS_CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KINGS_ROOT="$(cd "$KINGS_CORE/../.." && pwd)"
KINGS_HOME="${KINGS_HOME:-$HOME/.kingsScripts}"
export KINGS_CORE KINGS_ROOT KINGS_HOME

if [ -f "$KINGS_HOME/config.env" ]; then
  set -a
  . "$KINGS_HOME/config.env"
  set +a
fi
