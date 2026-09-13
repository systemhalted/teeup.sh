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
# A theme is complete only with both modes: listing or resolving a half theme
# would let the wizard offer a name that theme_set then cannot render.
_theme_complete() { [[ -f "$1/dark.toml" && -f "$1/light.toml" ]]; }

# A theme name becomes a path component, a wizard option (split on spaces) and
# the content of current/theme.name, so it is kept to one plain word.
TEEUP_THEME_NAME_RE='^[a-z0-9][a-z0-9-]*$'

theme_dir() {
  local name="$1" d
  if ! [[ $name =~ $TEEUP_THEME_NAME_RE ]]; then
    warn "Invalid theme name: $name (use lower-case letters, digits and dashes)"
    return 1
  fi
  for d in "$TEEUP_CONFIG_DIR/themes/$name" "$TEEUP_THEMES_DIR/$name"; do
    if _theme_complete "$d"; then printf '%s\n' "$d"; return 0; fi
  done
  err "Unknown theme: $name (try: teeup theme list)"
  return 1
}

theme_list() {
  local d name
  for d in "$TEEUP_THEMES_DIR"/*/ "$TEEUP_CONFIG_DIR"/themes/*/; do
    _theme_complete "$d" || continue
    name="$(basename "$d")"
    if [[ $name =~ $TEEUP_THEME_NAME_RE ]]; then
      printf '%s\n' "$name"
    else
      warn "Ignoring theme ${d%/}: a theme name uses lower-case letters, digits and dashes"
    fi
  done | sort -u
}

theme_current() {
  local f="$TEEUP_STATE_DIR/current/theme.name"
  if [[ -f "$f" ]]; then cat "$f"; else printf 'none\n'; fi
}

# _theme_sed_escape <value>
# A palette value is user-supplied (a user theme under
# ~/.config/teeup/themes/<name>/ overrides a shipped one), so it must be
# escaped before it lands in a sed replacement: a literal backslash is
# doubled first (or it would escape whatever the next step inserts), then `&`
# (sed's "whole match" token) and `|` (this script's delimiter, which must be
# backslash-escaped to appear literally) get their own backslash. Built on
# replace_literal (lib/files.sh) rather than ${value//pat/repl}: bash 3.2
# mis-parses a quoted pattern containing certain characters in that form, and
# replace_literal is already the codebase's answer to that.
_theme_sed_escape() {
  local value="$1"
  value="$(replace_literal "$value" '\' '\\')"
  value="$(replace_literal "$value" '&' '\&')"
  value="$(replace_literal "$value" '|' '\|')"
  printf '%s\n' "$value"
}

# One sed substitution triple per key, appended to the shared script.
_theme_sed_entry() {
  local key="$1" value="$2" hex rgb
  printf 's|{{ %s }}|%s|g\n' "$key" "$(_theme_sed_escape "$value")" >> "$TEEUP_COLOR_SED"
  printf 's|{{ %s_strip }}|%s|g\n' "$key" "$(_theme_sed_escape "${value#\#}")" >> "$TEEUP_COLOR_SED"
  # Only a real six-digit hex colour gets an _rgb variant: `printf '%d' 0xzz`
  # fails, and under `set -e` that would abort the whole theme switch.
  case "$value" in
    \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
      hex="${value#\#}"
      rgb="$(printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}")"
      printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$(_theme_sed_escape "$rgb")" >> "$TEEUP_COLOR_SED"
      ;;
  esac
}

# theme_palette_load <file>
# bash 3.2 has no associative arrays, so the palette becomes one exported
# TEEUP_COLOR_<KEY> per key plus a space-separated key list, and the render
# table is a sed script built once here rather than once per template.
# The `sed` expression takes the value out of the double quotes, which is why
# a value may contain spaces (bat_theme) but never a double quote.
#
# Values land inside a shell `export`, Lua strings and TOML strings, and a
# user theme is untrusted input, so every value must be a colour or a plain
# name ("#89b4fa", "Monokai Extended Light"). Anything else (`$(...)`, a
# backtick, a backslash, a quote) makes the whole palette invalid rather than
# being escaped three different ways.
TEEUP_PALETTE_VALUE_RE='^[#A-Za-z0-9][A-Za-z0-9 ._-]*$'

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
    if ! [[ $value =~ $TEEUP_PALETTE_VALUE_RE ]]; then
      warn "Invalid palette value in $file: $key = \"$value\" (use a colour like #89b4fa or a name of letters, digits, spaces, dots, underscores and dashes)"
      return 1
    fi
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
  # The redirection creates $out before sed runs, so a failed render would
  # otherwise leave an empty or partial file under the final name.
  if ! sed -f "$TEEUP_COLOR_SED" "$tpl" > "$out"; then
    rm -f "$out"
    return 1
  fi
}

# theme_templates -> every template, user copies first.
# theme_set renders in this order and renders each basename once, so a user
# template of the same basename wins.
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

# _theme_set_abort <next> <name>
# Every failure after staging starts ends here: the half-rendered staging dir
# and the sed table go, and the theme in current/ is never touched.
_theme_set_abort() {
  local next="$1" name="$2"
  if [[ "$DRY_RUN" != "true" ]]; then rm -rf "$next"; fi
  if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then
    rm -f "$TEEUP_COLOR_SED"
    TEEUP_COLOR_SED=""
  fi
  err "Theme $name was not applied; the current theme is unchanged."
}

# theme_set <name>
# Render both modes into a staging directory, swap it into place, record the
# name, then let every capability pick the new files up. Rendering into a
# staging dir means a failure half way through leaves the old theme intact:
# a template that fails to render, or a rendered file that still holds a
# `{{ key }}` token the palette did not define, fails the whole switch before
# the swap.
#
# An unknown name warns and falls back to catppuccin rather than failing: the
# theme capability is core, so a non-zero exit here aborts the whole bootstrap.
TEEUP_THEME_FALLBACK="catppuccin"
export TEEUP_THEME_FALLBACK

theme_set() {
  local name="$1" dir mode tpl base out current next cap failed=0 missing user_bases cap_bases
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
      _theme_set_abort "$next" "$name"
      return 1
    fi
    if ! theme_palette_load "$dir/$mode.toml"; then
      _theme_set_abort "$next" "$name"
      return 1
    fi
    run_cmd mkdir -p "$next/$mode"
    # Rendered files share one flat namespace per mode. A user template
    # overriding a shipped one of the same basename is the feature and stays
    # quiet; two capabilities shipping one basename is a collision (cap_check
    # fails on it), so the one that loses is named, once rather than per mode.
    user_bases="/"
    cap_bases="/"
    while IFS= read -r tpl; do
      base="$(basename "$tpl" .tpl)"
      out="$next/$mode/$base"
      if [[ "${tpl%/*}" == "$TEEUP_CONFIG_DIR/themed" ]]; then
        user_bases="$user_bases$base/"
      else
        case "$cap_bases" in
          *"/$base/"*)
            if [[ "$mode" == "dark" ]]; then
              warn "$tpl was not rendered: another capability ships $base.tpl (teeup commands --check names both)"
            fi
            continue
            ;;
        esac
        cap_bases="$cap_bases$base/"
        case "$user_bases" in *"/$base/"*) continue ;; esac
      fi
      if ! theme_render "$tpl" "$out"; then
        warn "Could not render $tpl"
        failed=1
        continue
      fi
      if [[ "$DRY_RUN" != "true" ]] && grep -qF '{{ ' "$out"; then
        missing="$(grep -oE '[{][{] [A-Za-z0-9_]+ [}][}]' "$out" | sed -e 's/^[{][{] //' -e 's/ [}][}]$//' | sort -u | paste -s -d ' ' -)"
        warn "$tpl: the $name $mode palette has no value for: ${missing:-a malformed token}"
        failed=1
      fi
    done < <(theme_templates)
    if [[ "$DRY_RUN" != "true" ]]; then
      cp "$dir/$mode.toml" "$next/$mode/colors.toml"
    fi
  done
  if [[ $failed -ne 0 ]]; then
    _theme_set_abort "$next" "$name"
    return 1
  fi
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
  # A for loop over a captured list, not `while read ... < <(cap_list)`: an
  # interactive=true capability's hook inherits stdin, and reading it would
  # swallow the names of the capabilities still waiting for their hooks.
  for cap in $(cap_list); do
    cap_run_optional "$cap" theme-apply
  done
}
