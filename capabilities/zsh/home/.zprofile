# ~/.zprofile - installed once by teeup; this copy is yours to edit.
# Login shells only, after macOS's /etc/zprofile has run path_helper.
[ -r "$HOME/.config/teeup/env" ] && . "$HOME/.config/teeup/env"
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/profile" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/profile"

# Your own login-shell lines below this line.
