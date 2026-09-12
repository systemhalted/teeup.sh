# ~/.zprofile - installed once by teeup; this copy is yours to edit.
# Login shells only, after macOS's /etc/zprofile has run path_helper.
# configure renders the line below to a %q-quoted absolute path, which is why
# it carries no double quotes of its own; unrendered, it still works for the
# common case of an unquoted $HOME/XDG_CONFIG_HOME with no special characters.
[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env ] && . ${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/profile" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/profile"
# A missing profile layer above must not leave the shell on a failing status.
true

# Your own login-shell lines below this line.
