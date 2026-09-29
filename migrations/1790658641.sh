#!/usr/bin/env bash

if cap_exists starship; then
  config="$(user_config_dir)/starship.toml"
  if [[ -f "$config" ]] && grep -q '^stashed = "$ "$' "$config"; then
    if ! backup="$(backup_copy "$config")"; then exit 1; fi
    log "Backed up to $backup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      # shellcheck disable=SC2016
      run_cmd bash -c 'sed -e "s/^stashed = \"\$ \"$/stashed = '"'"'\\\$ '"'"'/" "$1" > "$1.tmp" && mv "$1.tmp" "$1"' _ "$config"
    else
      tmp="$(mktemp)"
      sed -e 's/^stashed = "$ "$/stashed = '"'"'\\$ '"'"'/' "$config" > "$tmp" || { rm -f "$tmp"; exit 1; }
      # shellcheck disable=SC2016
      run_cmd bash -c 'cat "$1" > "$2"' _ "$tmp" "$config"
      rm -f "$tmp"
    fi
  fi
fi
