#!/bin/bash
# macOS notifications. Texts go as osascript arguments, so quotes in them need no escaping.
#
#   notify_banner <title> <message>   Notification Center banner
#   notify_alert  <title> <message>   modal alert, waits for OK
#   notify_dialog <title> <message>   modal dialog, waits for OK

notify_banner() {
  osascript - "$1" "$2" > /dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

notify_alert() {
  osascript - "$1" "$2" > /dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display alert (item 1 of argv) message (item 2 of argv) buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

notify_dialog() {
  osascript - "$1" "$2" > /dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display dialog (item 2 of argv) with title (item 1 of argv) buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}
