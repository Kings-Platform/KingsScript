#!/bin/bash
# `kings git-deletebranch [branch]`: deletes a local branch (the current one by default),
# switching to the default branch first when needed. The remote branch is left alone.

. "$KINGS_CORE/print.sh"

BRANCH="${1:-$(git branch --show-current 2> /dev/null)}"

validate_input() {
  [ -n "$BRANCH" ] && return
  print_error "Usage: kings git-deletebranch [branch] (inside a git repo, not in detached HEAD)"
  exit 1
}

# The branch origin/HEAD points to (main, develop...), falling back to main.
default_branch() {
  local ref
  ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2> /dev/null)"
  printf '%s\n' "${ref#refs/remotes/origin/}" | sed 's/^$/main/'
}

# Can't delete the branch it's on.
leave_branch() {
  [ "$(git branch --show-current)" = "$BRANCH" ] || return 0
  local target
  target="$(default_branch)"
  if [ "$target" = "$BRANCH" ]; then
    print_error "$BRANCH is the default branch; not deleting it"
    exit 1
  fi
  log_run git switch "$target" || { print_error "Couldn't switch to $target"; exit 1; }
  print_info "Switched to $target"
}

# -D because squash-merged branches never look merged to git.
delete_branch() {
  log_run git branch -D "$BRANCH" || { print_error "Couldn't delete $BRANCH"; exit 1; }
  log_run git fetch --prune
  print_success "Deleted $BRANCH"
}

validate_input
leave_branch
delete_branch
