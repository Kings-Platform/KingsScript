#!/bin/bash
# Keeps the Claude Code plugins on the latest commit of their marketplaces, once a day.

exec "$(dirname "${BASH_SOURCE[0]}")/../../../AI/Update/ai-update.sh" --auto
