#!/bin/bash
# Secrets never live in files. An environment variable with the secret's name wins;
# otherwise it comes from the macOS Keychain (service "kings", account = secret name).
#
#   secret_get <NAME>      prints the value, fails if not set
#   secret_source <NAME>   prints where it comes from: env, keychain or nothing
#   secret_set <NAME>      stores in the Keychain, prompting for the value
#   secret_delete <NAME>   removes from the Keychain

KINGS_KEYCHAIN_SERVICE="kings"

secret_valid_name() {
  case "$1" in
    '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;;
  esac
}

_secret_keychain() {
  security find-generic-password -s "$KINGS_KEYCHAIN_SERVICE" -a "$1" -w 2> /dev/null
}

secret_get() {
  secret_valid_name "$1" || return 1
  if [ -n "${!1}" ]; then
    printf '%s\n' "${!1}"
    return 0
  fi
  _secret_keychain "$1"
}

secret_source() {
  secret_valid_name "$1" || return 1
  if [ -n "${!1}" ]; then
    echo env
  elif _secret_keychain "$1" > /dev/null; then
    echo keychain
  fi
}

secret_set() {
  secret_valid_name "$1" || return 1
  security add-generic-password -U -s "$KINGS_KEYCHAIN_SERVICE" -a "$1" -w
}

secret_delete() {
  secret_valid_name "$1" || return 1
  security delete-generic-password -s "$KINGS_KEYCHAIN_SERVICE" -a "$1" > /dev/null 2>&1
}
