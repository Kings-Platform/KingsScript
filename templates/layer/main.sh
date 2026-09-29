#!/bin/bash
# Layer dispatcher. Contract with KingsScript:
#   - `help` prints one line per command (the core shows it under the layer's name)
#   - a command this layer doesn't own exits 127, so the next layer gets a chance
#   - the core library is at $KINGS_CORE (e.g. `. "$KINGS_CORE/print.sh"`)

LAYER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmd="$1"
[ $# -gt 0 ] && shift

case "$cmd" in
  help)
    printf '  %-34s %s\n' "hello [name]" "Example command"
    ;;
  hello)
    exec "$LAYER_DIR/Scripts/Hello/hello.sh" "$@"
    ;;
  *)
    exit 127
    ;;
esac
