#!/usr/bin/env bash

# Only a starship that teeup installed; its config is then teeup's copy.
state_done check cap-starship || exit 0
config="$(user_config_dir)/starship.toml"
# Only teeup's original line; an edited one is the user's to keep.
if [[ -f "$config" && ! -L "$config" ]] && grep -q '^stashed = "$ "$' "$config"; then
  if ! backup="$(backup_copy "$config")"; then exit 1; fi
  [[ "$DRY_RUN" == "true" ]] || log "Backed up to $backup"
  # write_config_region writes through a temp file and rename (a failed write
  # never truncates the live config) and, when the file was untouched, records
  # the new content as its stock checksum so it still reads as teeup's.
  sed -e 's/^stashed = "$ "$/stashed = '"'"'\\$ '"'"'/' "$config" |
    write_config_region "$config" "Starship config (escaped stash symbol)" || exit 1
fi
