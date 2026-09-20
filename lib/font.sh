#!/usr/bin/env bash
# font.sh - one family name for every tool, switchable with one command.
# The name lives in $TEEUP_STATE_DIR/current/font; WezTerm (and, from phase 3,
# Neovim, Zed and VS Code) read it and a font-apply hook tells them to reload.
# Requires core.sh, files.sh, pkg.sh and capability.sh.

TEEUP_FONT_DEFAULT="JetBrainsMono Nerd Font"
export TEEUP_FONT_DEFAULT

font_file() { printf '%s/current/font\n' "$TEEUP_STATE_DIR"; }

font_current() {
  local f
  f="$(font_file)"
  if [[ -s "$f" ]]; then head -1 "$f"; else printf '%s\n' "$TEEUP_FONT_DEFAULT"; fi
}

# Lower-case, drop spaces, underscores and hyphens, then drop a trailing
# "nerdfont", so "Cascadia Mono", "cascadia-mono" and "CaskaydiaMono Nerd Font"
# all normalise to the same key.
_font_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' _-' | sed 's/nerdfont$//'
}

# _font_row <name> -> "<cask> <family...>"; returns 1 when the name is unknown.
_font_row() {
  local key
  key="$(_font_key "$1")"
  case "$key" in
    jetbrainsmono|jetbrains) echo "font-jetbrains-mono-nerd-font JetBrainsMono Nerd Font" ;;
    cascadiamono|cascadiacode|cascadia|caskaydiamono|caskaydia) echo "font-caskaydia-mono-nerd-font CaskaydiaMono Nerd Font" ;;
    firacode|fira) echo "font-fira-code-nerd-font FiraCode Nerd Font" ;;
    hack) echo "font-hack-nerd-font Hack Nerd Font" ;;
    meslo|meslolg|meslolgs) echo "font-meslo-lg-nerd-font MesloLGS Nerd Font" ;;
    *) return 1 ;;
  esac
}

font_cask() {
  local row
  if ! row="$(_font_row "$1")"; then
    err "Unknown font: $1 (try: teeup install font list)"
    return 1
  fi
  printf '%s\n' "${row%% *}"
}

font_family() {
  local row
  if ! row="$(_font_row "$1")"; then
    err "Unknown font: $1 (try: teeup install font list)"
    return 1
  fi
  printf '%s\n' "${row#* }"
}

font_table() {
  printf '%-16s %-24s %s\n' "NAME" "FAMILY" "CASK"
  printf '%-16s %-24s %s\n' "JetBrainsMono" "JetBrainsMono Nerd Font" "font-jetbrains-mono-nerd-font"
  printf '%-16s %-24s %s\n' "Cascadia Mono" "CaskaydiaMono Nerd Font" "font-caskaydia-mono-nerd-font"
  printf '%-16s %-24s %s\n' "Fira Code" "FiraCode Nerd Font" "font-fira-code-nerd-font"
  printf '%-16s %-24s %s\n' "Hack" "Hack Nerd Font" "font-hack-nerd-font"
  printf '%-16s %-24s %s\n' "Meslo" "MesloLGS Nerd Font" "font-meslo-lg-nerd-font"
}

# font_set <name>
# The same three steps as a theme switch: install, record, tell everyone.
font_set() {
  local requested="${1:-}" family cask
  if [[ -z "$requested" ]]; then
    err "Usage: teeup install font <name>   (teeup install font list shows the names)"
    return 1
  fi
  if [[ "$requested" == "list" ]]; then
    font_table
    return 0
  fi
  family="$(font_family "$requested")" || return 1
  cask="$(font_cask "$requested")" || return 1
  cask_install "$cask" || return 1
  # write_managed_file warns on its own refusal (M11: a state file that is not
  # writable). Without this guard the refusal would abort `teeup install font`
  # under `bash -eu` before a single font-apply hook ran. The hooks are skipped
  # deliberately rather than run anyway: they would set a family that
  # current/font does not record, and the next `teeup install font` or
  # `theme set` would put the old one back.
  if ! write_managed_file "$(font_file)" "font family" <<FONT_STATE
$family
FONT_STATE
  then
    warn "Could not record $family in $(font_file); the editors were not told about it."
    return 1
  fi
  TEEUP_FONT_FAMILY="$family"
  export TEEUP_FONT_FAMILY
  cap_run_hooks font-apply
  ok_unless_dry "Font set to $family"
}
