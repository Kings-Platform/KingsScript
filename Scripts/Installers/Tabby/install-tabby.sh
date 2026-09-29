#!/bin/bash
# `kings install-tabby`: installs the Tabby terminal without admin rights — the app goes to
# ~/Apps (KINGS_APPS_DIR) instead of /Applications — and makes new Terminal windows open Tabby.

. "$KINGS_CORE/print.sh"
. "$KINGS_CORE/zshrc.sh"
. "$KINGS_CORE/timer.sh"

APPS_DIR="${KINGS_APPS_DIR:-$HOME/Apps}"
APP="$APPS_DIR/Tabby.app"
RELEASES_API="https://api.github.com/repos/Eugeny/tabby/releases/latest"
ZIP_SUFFIX="macos-$(uname -m).zip"

is_installed() {
  [ -d "$APP" ]
}

# Download link of the latest release's zip for this Mac's architecture.
latest_zip_url() {
  curl -s "$RELEASES_API" | grep '"browser_download_url"' | grep "$ZIP_SUFFIX\"" | cut -d '"' -f 4
}

download_and_unzip() {
  local url tmp
  url="$(latest_zip_url)"
  if [ -z "$url" ]; then
    print_error "No *$ZIP_SUFFIX in the latest release — download it manually into $APPS_DIR"
    exit 1
  fi

  tmp="$(mktemp -d)"
  print_info "Downloading $url"
  log_run curl -fL "$url" -o "$tmp/tabby.zip" || { print_error "Download failed"; exit 1; }

  mkdir -p "$APPS_DIR"
  log_run unzip -q -o "$tmp/tabby.zip" -d "$APPS_DIR"
  rm -rf "$tmp"
  is_installed || { print_error "Tabby.app not found in $APPS_DIR after unzipping"; exit 1; }
  print_success "Tabby installed in $APPS_DIR"
}

install_app() {
  if is_installed; then
    print_info "Tabby already installed: $APP"
  else
    download_and_unzip
  fi
}

# When a shell starts inside Apple's Terminal, opens Tabby on the same folder and closes Terminal.
setup_shell() {
  zshrc_set_block "kings:tabby" "export TABBY_HOME=\"$APP/Contents/MacOS/Tabby\"
if [[ \"\$TERM_PROGRAM\" == \"Apple_Terminal\" ]]; then
  setopt NO_CHECK_JOBS
  \"\$TABBY_HOME\" \"\$PWD\" & disown
  nohup osascript -e 'tell application \"Terminal\" to if front window exists then close front window' > /dev/null 2>&1 &
  exit
fi"
  print_info "Shell: Terminal now hands off to Tabby ($ZSHRC)"
}

print_title "Installing Tabby"
install_app
setup_shell
print_success "Done in $(timer_elapsed)"
