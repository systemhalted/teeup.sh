# teeup-env <secret-name> [VARIABLE]
# Exports one Keychain secret into the current shell and nowhere else. With no
# VARIABLE the secret name is upper-cased and sanitised into a legal
# identifier: every character outside [A-Za-z0-9_] becomes "_", and a name
# starting with a digit gets a leading "_" (zsh export dies on a name like
# "1KEY"). `teeup secret set` allows "." and "-" in names, so
# `teeup-env my.api-key` sets MY_API_KEY. Sourced by capabilities/zsh/default/rc.
teeup-env() {
  # Keep the secret out of a caller's `set -x` trace; zsh restores options on return.
  setopt localoptions noxtrace
  local name="$1" var value
  if [[ -z "$name" ]]; then
    print -u2 "usage: teeup-env <secret-name> [VARIABLE]"
    return 2
  fi
  if [[ -n "${2:-}" ]]; then
    var="$2"
  else
    var="${(U)name}"
    var="${var//[^A-Za-z0-9_]/_}"
    [[ "$var" == [0-9]* ]] && var="_$var"
  fi
  value="$(teeup secret get "$name")" || return 1
  export "$var=$value"
  print "exported $var from the teeup Keychain"
}
