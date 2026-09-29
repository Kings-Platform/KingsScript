#!/bin/bash
# Named blocks in ~/.zshrc, between "# >>> <name> >>>" and "# <<< <name> <<<" markers.
# Everything outside the block is left untouched.
#
#   zshrc_set_block <name> <content>   adds the block, or replaces it if it exists
#   zshrc_remove_block <name>          removes it
#   zshrc_has_block <name>             succeeds if it exists

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

zshrc_has_block() {
  [ -f "$ZSHRC" ] && grep -qxF "# >>> $1 >>>" "$ZSHRC"
}

# Writes the block in place of the old one, or appends it when there's none yet.
zshrc_set_block() {
  local begin="# >>> $1 >>>" end="# <<< $1 <<<" tmp
  tmp="$(mktemp)"
  touch "$ZSHRC"

  # Prints every line, swapping the old block (if any) for the new one.
  BLOCK="$begin
$2
$end" awk -v begin="$begin" -v end="$end" '
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
  local begin="# >>> $1 >>>" end="# <<< $1 <<<" tmp
  tmp="$(mktemp)"

  # Blank lines are held back until the next line shows whether they precede the block.
  awk -v begin="$begin" -v end="$end" '
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
