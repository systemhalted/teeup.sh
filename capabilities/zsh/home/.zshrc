# ~/.zshrc - installed once by teeup; this copy is yours to edit.
# Interactive shells. The thick layer lives in the teeup checkout, so teeup
# upgrades improve it without touching this file.
# configure renders the line below to a %q-quoted absolute path, which is why
# it carries no double quotes of its own; unrendered, it still works for the
# common case of an unquoted $HOME/XDG_CONFIG_HOME with no special characters.
[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env ] && . ${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/rc" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/rc"

# Machine-specific and personal lines belong in ~/.config/zsh/local.zsh, which
# is sourced last so it wins over everything above. The XDG expansion matches
# what `configure` used to place the file (lib/core.sh's user_config_dir).
[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.zsh" ] &&
  . "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.zsh"

# A missing local.zsh above must not leave the shell on a failing status;
# starship's prompt character reads $status, and this is the first prompt.
true
