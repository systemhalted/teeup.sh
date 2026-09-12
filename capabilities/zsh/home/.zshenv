# ~/.zshenv - installed once by teeup; this copy is yours to edit.
# Read by every zsh, including the non-interactive one behind `ssh mac cmd`,
# which reads neither ~/.zprofile nor ~/.zshrc. Environment only.
[ -r "$HOME/.config/teeup/env" ] && . "$HOME/.config/teeup/env"
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/env" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/env"

# Your own exports below this line.
