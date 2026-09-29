#!/bin/bash
# `kings secret set|delete|status <NAME>`: secrets in the Keychain. Values are never printed.

. "$(dirname "${BASH_SOURCE[0]}")/../../Core/secrets.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../../Core/print.sh"

action="$1"
name="$2"
if [ -z "$action" ] || ! secret_valid_name "$name"; then
  print_error "Usage: kings secret set|delete|status <NAME> (letters, digits and _)"
  exit 1
fi

case "$action" in
  set)
    secret_set "$name" && print_success "$name stored in the Keychain"
    ;;
  delete)
    if secret_delete "$name"; then
      print_success "$name removed from the Keychain"
    else
      print_warn "$name was not in the Keychain"
    fi
    ;;
  status)
    source="$(secret_source "$name")"
    printf '%s: %s\n' "$name" "${source:-not set}"
    ;;
  *)
    print_error "Usage: kings secret set|delete|status <NAME>"
    exit 1
    ;;
esac
