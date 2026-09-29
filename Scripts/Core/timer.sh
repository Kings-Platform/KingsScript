#!/bin/bash
# Elapsed time of the running script as HH:MM:SS. Bash's SECONDS starts at 0 with each process.

timer_elapsed() {
  printf '%02d:%02d:%02d\n' $((SECONDS / 3600)) $((SECONDS % 3600 / 60)) $((SECONDS % 60))
}
