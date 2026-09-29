#!/bin/bash
# `kings ai-update [--auto]`: updates the installed Claude Code plugins to the latest commit of their
# marketplace. Installed plugins are copies pinned to a commit, so editing a marketplace changes
# nothing until this runs. A marketplace that is a local clone is pulled first.
#
# --auto is what the daily checkup uses: it skips a local clone that isn't clean and on its default
# branch, since `claude plugin update` installs whatever commit is checked out — a work-in-progress
# branch would get installed by itself.

. "$KINGS_CORE/print.sh"
. "$KINGS_CORE/notify.sh"

AUTO=0
SKIPPED=""
UPDATED=""

parse_args() {
  case "$1" in
    --auto) AUTO=1 ;;
    "") ;;
    *)
      print_error "Usage: kings ai-update [--auto]"
      exit 1
      ;;
  esac
}

# Without Claude Code there's nothing to update — not an error for the checkup.
require_claude() {
  command -v claude > /dev/null && return
  if [ "$AUTO" -eq 1 ]; then
    log "Claude Code not found; nothing to update"
    exit 0
  fi
  print_error "Claude Code not found (the claude command)"
  exit 1
}

# Prints "<name>\t<path>" for each marketplace whose source is a local folder.
local_marketplaces() {
  claude plugin marketplace list --json 2> /dev/null | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    if m.get("source") == "directory":
        print(m["name"] + "\t" + m["path"])
'
}

default_branch() {
  local ref
  ref="$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD 2> /dev/null)"
  printf '%s\n' "${ref#refs/remotes/origin/}" | sed 's/^$/main/'
}

# Pulls a clean clone on its default branch. Otherwise --auto skips its plugins; a manual run
# installs the commit checked out, on purpose (useful to test a branch).
sync_clone() {
  local name="$1" path="$2" branch
  [ -d "$path/.git" ] || return 0
  branch="$(git -C "$path" branch --show-current)"

  if [ -n "$(git -C "$path" status --porcelain)" ] || [ "$branch" != "$(default_branch "$path")" ]; then
    if [ "$AUTO" -eq 1 ]; then
      SKIPPED="$SKIPPED $name"
      log "Skipped $name: $path is on '$branch' or has local changes"
    else
      print_warn "$name: installing the commit checked out on '$branch' (not pulled)"
    fi
    return 0
  fi
  log_run git -C "$path" pull --ff-only || print_warn "$name: couldn't pull $path"
}

sync_local_marketplaces() {
  local name path
  while IFS="$(printf '\t')" read -r name path; do
    [ -n "$name" ] && sync_clone "$name" "$path"
  done < <(local_marketplaces)
}

update_remote_marketplaces() {
  log_run claude plugin marketplace update || print_warn "Couldn't update the marketplaces"
}

# Prints "<plugin@marketplace>\t<scope>" for each installed plugin.
installed_plugins() {
  claude plugin list --json 2> /dev/null | python3 -c '
import json, sys
for p in json.load(sys.stdin):
    print(p["id"] + "\t" + p.get("scope", "user"))
'
}

# `claude plugin update` says "updated from X to Y" only when there was something new.
update_plugins() {
  local id scope output
  while IFS="$(printf '\t')" read -r id scope; do
    [ -n "$id" ] || continue
    case " $SKIPPED " in *" ${id#*@} "*) continue ;; esac
    output="$(claude plugin update "$id" --scope "$scope" 2>&1)"
    log "$output"
    case "$output" in
      *"updated from"*) UPDATED="$UPDATED ${id%@*}" ;;
    esac
  done < <(installed_plugins)
}

report() {
  if [ -n "$UPDATED" ]; then
    print_success "Updated:$UPDATED — restart running Claude sessions to apply"
    [ "$AUTO" -eq 1 ] && notify_banner "Claude plugins updated" "${UPDATED# } — restart Claude sessions to apply"
  else
    print_info "Plugins already up to date"
  fi
  [ -n "$SKIPPED" ] && print_warn "Skipped (clone not clean or not on its default branch):$SKIPPED"
  return 0
}

parse_args "$@"
require_claude
sync_local_marketplaces
update_remote_marketplaces
update_plugins
report
