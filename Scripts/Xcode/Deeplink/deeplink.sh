#!/bin/bash
# `kings xcode-deeplink <url>`: opens a URL (deeplink or universal link) in the booted simulator.

. "$KINGS_CORE/print.sh"

URL="$1"

validate_input() {
  [ -n "$URL" ] && return
  print_error "Usage: kings xcode-deeplink <url>   (e.g. myapp://home)"
  exit 1
}

open_url() {
  xcrun simctl openurl booted "$URL" 2> /dev/null && return
  print_error "Couldn't open $URL — is a simulator booted and the app installed?"
  exit 1
}

validate_input
open_url
print_success "Opened $URL"
