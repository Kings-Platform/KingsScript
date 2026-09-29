#!/bin/bash
# `kings secret set|delete|status <NAME>`: secrets in the Keychain. Values are never printed.

. "$(dirname "${BASH_SOURCE[0]}")/../../Core/secrets.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../../Core/print.sh"

usage() {
  print_error "Usage: kings secret set|delete|status <NAME> (letters, digits and _)"
  exit 1
}

# Prompts for the value and stores it.
secret_command_set() {
  secret_set "$1" && print_success "$1 stored in the Keychain"
}

secret_command_delete() {
  if secret_delete "$1"; then
    print_success "$1 removed from the Keychain"
  else
    print_warn "$1 was not in the Keychain"
  fi
}

# Where the secret comes from (env or keychain), never its value.
secret_command_status() {
  local source
  source="$(secret_source "$1")"
  printf '%s: %s\n' "$1" "${source:-not set}"
}

action="$1"
name="$2"
secret_valid_name "$name" || usage

case "$action" in
  set) secret_command_set "$name" ;;
  delete) secret_command_delete "$name" ;;
  status) secret_command_status "$name" ;;
  *) usage ;;
esac
