# ~/.zshenv - installed once by teeup; this copy is yours to edit.
# Read by every zsh, including the non-interactive one behind `ssh mac cmd`,
# which reads neither ~/.zprofile nor ~/.zshrc. Environment only.
[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env"
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/env" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/env"
# A missing env layer above must not leave the shell on a failing status.
true

# Your own exports below this line.
