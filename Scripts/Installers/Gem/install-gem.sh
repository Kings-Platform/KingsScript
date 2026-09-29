#!/bin/bash
# `kings install-gem <gem> [version]`: installs a Ruby gem without admin rights (--user-install).
# When a dependency needs a newer Ruby, RubyGems suggests an older version to install first:
# that suggestion is followed, then the gem is tried again.

. "$KINGS_CORE/print.sh"
. "$KINGS_CORE/notify.sh"
. "$KINGS_CORE/timer.sh"

GEM="$1"
VERSION="$2"
PINNED_FILE="$(dirname "${BASH_SOURCE[0]}")/pinned-dependencies.txt"
MAX_ATTEMPTS=5

validate_input() {
  [ -n "$GEM" ] && return
  print_error "Usage: kings install-gem <gem> [version]"
  exit 1
}

is_installed() {
  gem list -i "^$1$" ${2:+-v "$2"} > /dev/null 2>&1
}

# Installs one gem, keeping gem's output in $OUTPUT for the suggestion lookup.
install_one() {
  print_info "Installing $1${2:+ $2}"
  OUTPUT="$(gem install "$1" ${2:+-v "$2"} --user-install 2>&1)"
  local status=$?
  log "$OUTPUT"
  return "$status"
}

# "gem install <name> -v <version>" suggested in the last failure, as "<name> <version>".
suggested_dependency() {
  printf '%s\n' "$OUTPUT" | grep -Eo "gem install [A-Za-z0-9_.-]+ -v [0-9.]+" | head -1 | awk '{ print $3, $5 }'
}

exit_if_installed() {
  is_installed "$GEM" "$VERSION" || return 0
  print_info "$GEM already installed"
  exit 0
}

install_pinned_dependencies() {
  local dependency version
  grep -v '^#' "$PINNED_FILE" | awk -v g="$GEM" '$1 == g { print $2, $3 }' |
    while read -r dependency version; do
      is_installed "$dependency" "$version" || install_one "$dependency" "$version" < /dev/null
    done
}

# Tries the gem, installing each suggested dependency in between, up to MAX_ATTEMPTS rounds.
install_with_suggestions() {
  local attempt suggestion
  for attempt in $(seq "$MAX_ATTEMPTS"); do
    install_one "$GEM" "$VERSION" && return 0
    suggestion="$(suggested_dependency)"
    [ -n "$suggestion" ] || return 1
    # shellcheck disable=SC2086
    install_one $suggestion || return 1
  done
  return 1
}

report() {
  if is_installed "$GEM" "$VERSION"; then
    print_success "$GEM installed in $(timer_elapsed)"
    notify_banner "kings install-gem" "$GEM installed"
  else
    print_error "Couldn't install $GEM — details in $(log_file)"
    notify_banner "kings install-gem" "$GEM failed"
    exit 1
  fi
}

validate_input
exit_if_installed
install_pinned_dependencies
install_with_suggestions
report
