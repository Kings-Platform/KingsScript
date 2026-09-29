#!/bin/bash
# Adds, replaces or removes the KingsScript block in ~/.zshrc, leaving the rest untouched.

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
ZSHRC_BEGIN="# >>> kings >>>"
ZSHRC_END="# <<< kings <<<"

# Writes the block in place of the old one, or appends it when there's none yet.
zshrc_set_block() {
  local block="$ZSHRC_BEGIN
$1
$ZSHRC_END"
  local tmp
  tmp="$(mktemp)"
  touch "$ZSHRC"

  # Prints every line, swapping the old block (if any) for the new one.
  BLOCK="$block" awk -v begin="$ZSHRC_BEGIN" -v end="$ZSHRC_END" '
    $0 == begin { print ENVIRON["BLOCK"]; skipping = 1; replaced = 1; next }
    $0 == end   { skipping = 0; next }
    !skipping   { print }
    END         { if (!replaced) printf "\n%s\n", ENVIRON["BLOCK"] }
  ' "$ZSHRC" > "$tmp"

  # cat instead of mv keeps the file's permissions and any symlink to it.
  cat "$tmp" > "$ZSHRC"
  rm -f "$tmp"
}

# Deletes the block, plus the blank line that zshrc_set_block added before it.
zshrc_remove_block() {
  [ -f "$ZSHRC" ] || return 0
  local tmp
  tmp="$(mktemp)"

  # Blank lines are held back until the next line shows whether they precede the block.
  awk -v begin="$ZSHRC_BEGIN" -v end="$ZSHRC_END" '
    $0 == begin { if (blanks > 0) blanks--; skipping = 1; next }
    $0 == end   { skipping = 0; next }
    skipping    { next }
    $0 == ""    { blanks++; next }
                { while (blanks > 0) { print ""; blanks-- } print }
    END         { while (blanks > 0) { print ""; blanks-- } }
  ' "$ZSHRC" > "$tmp"

  cat "$tmp" > "$ZSHRC"
  rm -f "$tmp"
}
