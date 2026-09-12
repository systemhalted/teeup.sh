#!/usr/bin/env bash
# all.sh - source every teeup library in dependency order.
# Usage: TEEUP_PATH=/path/to/teeup; source "$TEEUP_PATH/lib/all.sh"
_teeup_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEEUP_PATH="${TEEUP_PATH:-$(dirname "$_teeup_lib_dir")}"
export TEEUP_PATH
# shellcheck source=lib/core.sh
source "$_teeup_lib_dir/core.sh"
for _teeup_lib in files state answers pkg ui capability; do
  # shellcheck source=/dev/null
  source "$_teeup_lib_dir/$_teeup_lib.sh"
done
unset _teeup_lib _teeup_lib_dir
