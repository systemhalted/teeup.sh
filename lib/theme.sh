#!/usr/bin/env bash
# theme.sh - semantic palettes, {{ token }} templates, staged swap, hooks.
# A theme is two files (dark.toml, light.toml) of `key = "value"` lines. Every
# capability that has colours ships themed/*.tpl; theme_set renders all of them
# for both modes, swaps the result into place and tells each capability to
# pick it up. Requires core.sh, files.sh and capability.sh.

TEEUP_THEMES_DIR="${TEEUP_THEMES_DIR:-$TEEUP_PATH/themes}"
export TEEUP_THEMES_DIR

# theme_dir <name>
# A user theme overrides a shipped one of the same name, the same way a user
# config overrides a shipped config. `die` is not used: this runs inside $( ),
# where die would only kill the substitution subshell.
theme_dir() {
  local name="$1" d
  d="$TEEUP_CONFIG_DIR/themes/$name"
  if [[ -f "$d/dark.toml" ]]; then printf '%s\n' "$d"; return 0; fi
  d="$TEEUP_THEMES_DIR/$name"
  if [[ -f "$d/dark.toml" ]]; then printf '%s\n' "$d"; return 0; fi
  err "Unknown theme: $name (try: teeup theme list)"
  return 1
}

theme_list() {
  local d
  {
    for d in "$TEEUP_THEMES_DIR"/*/; do
      if [[ -f "$d/dark.toml" ]]; then basename "$d"; fi
    done
    for d in "$TEEUP_CONFIG_DIR"/themes/*/; do
      if [[ -f "$d/dark.toml" ]]; then basename "$d"; fi
    done
  } 2>/dev/null | sort -u
}

theme_current() {
  local f="$TEEUP_STATE_DIR/current/theme.name"
  if [[ -f "$f" ]]; then cat "$f"; else printf 'none\n'; fi
}

# One sed substitution triple per key, appended to the shared script.
_theme_sed_entry() {
  local key="$1" value="$2" hex rgb
  printf 's|{{ %s }}|%s|g\n' "$key" "$value" >> "$TEEUP_COLOR_SED"
  printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}" >> "$TEEUP_COLOR_SED"
  # Only a real six-digit hex colour gets an _rgb variant: `printf '%d' 0xzz`
  # fails, and under `set -e` that would abort the whole theme switch.
  case "$value" in
    \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
      hex="${value#\#}"
      rgb="$(printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}")"
      printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$rgb" >> "$TEEUP_COLOR_SED"
      ;;
  esac
}

# theme_palette_load <file>
# bash 3.2 has no associative arrays, so the palette becomes one exported
# TEEUP_COLOR_<KEY> per key plus a space-separated key list, and the render
# table is a sed script built once here rather than once per template.
# The `sed` expression takes the value out of the double quotes, which is why
# a value may contain spaces (bat_theme) but never a double quote.
theme_palette_load() {
  local file="$1" key value upper old
  if [[ ! -f "$file" ]]; then
    err "Palette file not found: $file"
    return 1
  fi
  for old in ${TEEUP_COLOR_KEYS:-}; do
    upper="$(printf '%s' "$old" | tr '[:lower:]' '[:upper:]')"
    unset "TEEUP_COLOR_$upper"
  done
  TEEUP_COLOR_KEYS=""
  if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then rm -f "$TEEUP_COLOR_SED"; fi
  TEEUP_COLOR_SED="$(mktemp)"
  export TEEUP_COLOR_SED
  while read -r key value; do
    if [[ -z "$key" ]]; then continue; fi
    upper="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
    export "TEEUP_COLOR_$upper=$value"
    TEEUP_COLOR_KEYS="$TEEUP_COLOR_KEYS$key "
    _theme_sed_entry "$key" "$value"
  done < <(sed -n 's/^\([a-z][a-z0-9_]*\)[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1 \2/p' "$file")
  export TEEUP_COLOR_KEYS
}

# theme_render <tpl> <out>
theme_render() {
  local tpl="$1" out="$2"
  if [[ -z "${TEEUP_COLOR_SED:-}" || ! -f "${TEEUP_COLOR_SED:-}" ]]; then
    err "theme_render: call theme_palette_load first"
    return 1
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would render $(basename "$tpl") -> $out"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  sed -f "$TEEUP_COLOR_SED" "$tpl" > "$out"
}

# theme_templates -> every template, user copies first.
# theme_set renders in this order and never overwrites an output that already
# exists, so a user template of the same basename wins.
theme_templates() {
  local d f
  for f in "$TEEUP_CONFIG_DIR"/themed/*.tpl; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  for d in "$TEEUP_CAPS_DIR"/*/themed; do
    if [[ -d "$d" ]]; then
      for f in "$d"/*.tpl; do
        if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
      done
    fi
  done
  return 0
}

# theme_set <name>
# Render both modes into a staging directory, swap it into place, record the
# name, then let every capability pick the new files up. Rendering into a
# staging dir means a failure half way through leaves the old theme intact.
#
# An unknown name warns and falls back to catppuccin rather than failing: the
# theme capability is core, so a non-zero exit here aborts the whole bootstrap.
TEEUP_THEME_FALLBACK="catppuccin"
export TEEUP_THEME_FALLBACK

theme_set() {
  local name="$1" dir mode tpl out current next cap
  if ! dir="$(theme_dir "$name")"; then
    if [[ "$name" == "$TEEUP_THEME_FALLBACK" ]]; then
      if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then rm -f "$TEEUP_COLOR_SED"; fi
      return 1
    fi
    warn "Falling back to the $TEEUP_THEME_FALLBACK theme. Pick another with: teeup theme list"
    name="$TEEUP_THEME_FALLBACK"
    if ! dir="$(theme_dir "$name")"; then
      if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then rm -f "$TEEUP_COLOR_SED"; fi
      return 1
    fi
  fi
  current="$TEEUP_STATE_DIR/current/theme"
  next="$TEEUP_STATE_DIR/current/next-theme"
  if [[ -d "$next" ]]; then run_cmd rm -rf "$next"; fi
  for mode in dark light; do
    if [[ ! -f "$dir/$mode.toml" ]]; then
      err "Theme $name has no $mode.toml"
      if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then rm -f "$TEEUP_COLOR_SED"; fi
      return 1
    fi
    if ! theme_palette_load "$dir/$mode.toml"; then
      if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then rm -f "$TEEUP_COLOR_SED"; fi
      return 1
    fi
    run_cmd mkdir -p "$next/$mode"
    while IFS= read -r tpl; do
      out="$next/$mode/$(basename "$tpl" .tpl)"
      if [[ -e "$out" ]]; then continue; fi
      theme_render "$tpl" "$out" || warn "Could not render $tpl"
    done < <(theme_templates)
    if [[ "$DRY_RUN" != "true" ]]; then
      cp "$dir/$mode.toml" "$next/$mode/colors.toml"
    fi
  done
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would swap $next into $current and record theme $name"
  else
    if [[ -d "$current" ]]; then
      rm -rf "$current.prev"
      mv "$current" "$current.prev"
    fi
    mv "$next" "$current"
    rm -rf "$current.prev"
    printf '%s\n' "$name" > "$TEEUP_STATE_DIR/current/theme.name"
    ok "Theme set to $name"
  fi
  if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then
    rm -f "$TEEUP_COLOR_SED"
    TEEUP_COLOR_SED=""
  fi
  TEEUP_THEME_DIR="$current"
  TEEUP_THEME_NAME="$name"
  export TEEUP_THEME_DIR TEEUP_THEME_NAME
  while IFS= read -r cap; do
    cap_run_optional "$cap" theme-apply
  done < <(cap_list)
}
