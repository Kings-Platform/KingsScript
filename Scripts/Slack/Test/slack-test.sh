#!/bin/bash
# `kings slack-test [channel_id]`: end-to-end check of a Slack app — reads the channel's last
# message and posts one back quoting it. Proves the token and scopes work.

. "$KINGS_CORE/print.sh"
. "$KINGS_CORE/secrets.sh"

CHANNEL="${1:-$KINGS_SLACK_CHANNEL}"
API="https://slack.com/api"

validate_input() {
  [ -n "$CHANNEL" ] && return
  print_error "Usage: kings slack-test <channel_id>   (or set KINGS_SLACK_CHANNEL in config.env)"
  exit 1
}

# Bot token from the SLACK_BOT_TOKEN env var or the Keychain (kings secret set SLACK_BOT_TOKEN).
load_token() {
  command -v jq > /dev/null || { print_error "jq not found. Install it with: brew install jq"; exit 1; }
  TOKEN="$(secret_get SLACK_BOT_TOKEN)"
  [ -n "$TOKEN" ] && return
  print_error "SLACK_BOT_TOKEN not set — run: kings secret set SLACK_BOT_TOKEN"
  exit 1
}

# Slack answers HTTP 200 even on errors; the verdict is in the "ok" field.
check_response() {
  [ "$(printf '%s' "$1" | jq -r '.ok')" = "true" ] && return
  print_error "$2: $(printf '%s' "$1" | jq -r '.error')"
  exit 1
}

read_last_message() {
  local response
  response="$(curl -s "$API/conversations.history?channel=$CHANNEL&limit=1" -H "Authorization: Bearer $TOKEN")"
  check_response "$response" "Couldn't read the channel"
  LAST_TEXT="$(printf '%s' "$response" | jq -r '.messages[0].text // "(no messages)"')"
  print_info "Last message: $LAST_TEXT"
}

post_reply() {
  local body response
  body="$(jq -n --arg channel "$CHANNEL" --arg text "Test OK — last message read: $LAST_TEXT" '{channel: $channel, text: $text}')"
  response="$(curl -s -X POST "$API/chat.postMessage" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$body")"
  check_response "$response" "Couldn't post the message"
  print_success "Message posted"
}

validate_input
load_token
read_last_message
post_reply
