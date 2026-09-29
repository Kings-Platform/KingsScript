#!/bin/bash
# `kings git-swiftformatstaged`: formats only the staged .swift files of the current repo and
# stages them again, so the commit already goes in formatted.

. "$KINGS_CORE/print.sh"

SWIFT_VERSION="${KINGS_SWIFT_VERSION:-5.9}"

# Runs from the repo root, since git lists staged files relative to it.
enter_repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2> /dev/null)" || {
    print_error "Not a git repository: $PWD"
    exit 1
  }
  cd "$root" || exit 1
}

require_swiftformat() {
  command -v swiftformat > /dev/null && return
  print_error "SwiftFormat not found. Install it with: brew install swiftformat"
  exit 1
}

staged_swift_files() {
  git diff --cached --name-only --diff-filter=ACMR -- '*.swift'
}

# A file with unstaged changes too would have them pulled into the commit by the re-add.
is_partially_staged() {
  git diff --name-only -- "$1" | grep -qxF "$1"
}

format_staged_files() {
  local files file formatted=0 skipped=0 total=0
  files="$(staged_swift_files)"
  if [ -z "$files" ]; then
    print_info "No staged .swift files in $PWD"
    return
  fi

  while IFS= read -r file; do
    total=$((total + 1))
    if is_partially_staged "$file"; then
      print_warn "Skipped (partially staged): $file"
      skipped=$((skipped + 1))
      continue
    fi
    swiftformat "$file" --swiftversion "$SWIFT_VERSION" 2>&1 | grep -q "^1/1 files formatted" && formatted=$((formatted + 1))
    git add "$file"
  done <<< "$files"

  print_success "$formatted/$total file(s) formatted, $skipped skipped as partially staged"
}

enter_repo_root
require_swiftformat
format_staged_files
