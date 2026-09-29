#!/bin/bash
# `kings git-prreview <PR>`: the PR's review comments as a markdown table, ready to paste into
# review notes. "GitHub ID" is the comment's real id, needed to reply to it (in_reply_to).

. "$KINGS_CORE/print.sh"

PR="$1"

validate_input() {
  [ -n "$PR" ] && return
  print_error "Usage: kings git-prreview <PR number>"
  exit 1
}

require_gh() {
  command -v gh > /dev/null && return
  print_error "GitHub CLI not found. Install it with: brew install gh"
  exit 1
}

# Repo of the current folder, as owner/name.
current_repo() {
  gh repo view --json nameWithOwner --jq .nameWithOwner
}

# One row per comment: sequence, id, first 80 characters of the body (single line) and author.
print_table() {
  local repo
  repo="$(current_repo)" || exit 1

  printf '| ID | GitHub ID | Comment | Author | Status |\n|---|---|---|---|---|\n'
  gh api "repos/$repo/pulls/$PR/comments" \
    --jq '.[] | [(.id | tostring), (.body | gsub("\r?\n"; " ") | .[0:80]), .user.login] | @tsv' |
    awk -F'\t' '{ print "| " NR " | " $1 " | " $2 " | " $3 " | pending |" }'
}

validate_input
require_gh
print_table
