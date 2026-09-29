#!/bin/bash
# `kings xcode-simulator [device]`: opens the Simulator, booting the device first when given.

. "$KINGS_CORE/print.sh"

DEVICE="$1"

# Already booted is fine; an unknown name is not.
boot_device() {
  [ -n "$DEVICE" ] || return 0
  local output
  output="$(xcrun simctl boot "$DEVICE" 2>&1)" && return 0
  printf '%s' "$output" | grep -q "current state: Booted" && return 0
  print_error "Couldn't boot '$DEVICE' (see: xcrun simctl list devices available)"
  exit 1
}

open_simulator() {
  open -a Simulator || { print_error "Simulator not found (is Xcode installed?)"; exit 1; }
}

boot_device
open_simulator
print_success "Simulator open${DEVICE:+: $DEVICE}"
