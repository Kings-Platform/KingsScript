#!/bin/bash
# `kings site-icon <url> [--size N] [--out DIR] [--name FILE] [--list] [--source ICON_URL]`:
# saves the icon a site shows in the browser tab as a transparent PNG and prints its path.
# --list prints the icon candidates, best first; --source converts that one instead.

. "$KINGS_CORE/print.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
CHROME="${KINGS_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
URL="" SIZE=512 OUT_DIR="${KINGS_ICON_DIR:-$HOME/Desktop}" NAME="" LIST=0 SOURCE=""
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --size) SIZE="$2"; shift 2 ;;
      --out) OUT_DIR="$2"; shift 2 ;;
      --name) NAME="$2"; shift 2 ;;
      --list) LIST=1; shift ;;
      --source) SOURCE="$2"; shift 2 ;;
      *) URL="$1"; shift ;;
    esac
  done
  if [ -z "$URL" ]; then
    print_error "Usage: kings site-icon <url> [--size N] [--out DIR] [--name FILE] [--list] [--source ICON_URL]"
    exit 1
  fi
  case "$URL" in http*) ;; *) URL="https://$URL" ;; esac
}

check_tools() {
  command -v magick > /dev/null && return
  print_error "ImageMagick (magick) is required: brew install imagemagick"
  exit 1
}

# The URL after redirects is the base for relative icon paths.
fetch_page() {
  PAGE_URL="$(curl -sL -A "$UA" --max-time 20 -o "$WORK/page.html" -w '%{url_effective}' "$URL")"
  [ -s "$WORK/page.html" ] && return
  print_warn "Couldn't read the page; trying /favicon.ico only"
  : > "$WORK/page.html"
  PAGE_URL="$URL"
}

# Best first; --source replaces the discovery with a single candidate.
list_candidates() {
  if [ -n "$SOURCE" ]; then
    printf '%s\n' "$SOURCE"
  else
    python3 "$HERE/find-icons.py" "$PAGE_URL" < "$WORK/page.html"
  fi
}

print_list() {
  [ "$LIST" -eq 1 ] || return
  list_candidates
  exit 0
}

# Downloads the first candidate that answers with an image.
download_icon() {
  local candidate n=0
  while IFS= read -r candidate; do
    n=$((n + 1))
    case "$candidate" in
      data:*) python3 -c 'import sys,urllib.request; open(sys.argv[2],"wb").write(urllib.request.urlopen(sys.argv[1]).read())' "$candidate" "$WORK/icon.$n" 2> /dev/null ;;
      *) curl -sfL -A "$UA" --max-time 20 -o "$WORK/icon.$n" "$candidate" ;;
    esac
    [ -s "$WORK/icon.$n" ] || continue
    ICON_KIND="$(detect_kind "$WORK/icon.$n")"
    [ "$ICON_KIND" = "none" ] && continue
    ICON_FILE="$WORK/icon.$n.$ICON_KIND"
    mv "$WORK/icon.$n" "$ICON_FILE"
    ICON_SOURCE="${candidate:0:200}"
    return
  done < <(list_candidates)
  print_error "No icon found for $URL"
  exit 1
}

# The file's real format, used as its extension: ImageMagick can't recognize an ICO without
# one. `none` for anything else, like an HTML error page served with 200.
detect_kind() {
  case "$(file -b --mime-type "$1")" in
    image/svg+xml) printf 'svg' ;;
    image/vnd.microsoft.icon | image/x-icon) printf 'ico' ;;
    image/png) printf 'png' ;;
    image/gif) printf 'gif' ;;
    image/jpeg) printf 'jpg' ;;
    image/webp) printf 'webp' ;;
    *) head -c 2048 "$1" | grep -qi '<svg' && printf 'svg' || printf 'none' ;;
  esac
}

output_path() {
  if [ -z "$NAME" ]; then
    local host="${PAGE_URL#*://}"
    host="${host%%/*}"
    host="${host#www.}"
    NAME="${host%%.*}-icon.png"
  fi
  mkdir -p "$OUT_DIR"
  OUTPUT="$OUT_DIR/$NAME"
}

# ImageMagick's built-in SVG renderer drops gradients, so a browser engine comes first.
render_svg() {
  if command -v rsvg-convert > /dev/null; then
    rsvg-convert -w "$SIZE" -h "$SIZE" --keep-aspect-ratio "$ICON_FILE" -o "$OUTPUT" && return
  fi
  if [ -x "$CHROME" ]; then
    cp "$ICON_FILE" "$WORK/icon.svg"
    printf '<html><body style="margin:0;background:transparent"><img src="icon.svg" style="display:block;width:%spx;height:%spx;object-fit:contain"></body></html>' \
      "$SIZE" "$SIZE" > "$WORK/render.html"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
      --window-size="$SIZE,$SIZE" --screenshot="$OUTPUT" "file://$WORK/render.html" > /dev/null 2>&1
    [ -s "$OUTPUT" ] && return
  fi
  print_warn "No rsvg-convert or Chrome: rendering with ImageMagick, gradients may be lost"
  magick -background none -density 1024 "$ICON_FILE" -resize "${SIZE}x${SIZE}" "$OUTPUT"
}

# Takes the largest frame (an ICO holds several) and never upscales: a blown-up 32px icon is a blur.
convert_raster() {
  local frame
  frame="$(magick identify -format '%w %p\n' "$ICON_FILE" | sort -n | tail -1 | cut -d' ' -f2)"
  magick "$ICON_FILE[$frame]" -background none -resize "${SIZE}x${SIZE}>" "$OUTPUT"
}

convert_icon() {
  if [ "$ICON_KIND" = "svg" ]; then
    render_svg
  else
    convert_raster
  fi
  [ -s "$OUTPUT" ] && return
  print_error "Conversion failed for $ICON_SOURCE"
  exit 1
}

report() {
  local dims
  dims="$(magick identify -format '%wx%h' "$OUTPUT")"
  print_info "Source: $ICON_SOURCE ($ICON_KIND)"
  [ "$ICON_KIND" != "svg" ] && [ "${dims%%x*}" -lt 128 ] && print_warn "Only ${dims} available: the site publishes no larger icon"
  print_success "Saved $dims PNG"
  printf '%s\n' "$OUTPUT"
}

parse_args "$@"
check_tools
fetch_page
print_list
download_icon
output_path
convert_icon
report
