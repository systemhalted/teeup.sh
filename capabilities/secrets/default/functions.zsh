# teeup-env <secret-name> [VARIABLE]
# Exports one Keychain secret into the current shell and nowhere else. With no
# VARIABLE the secret name is upper-cased, so `teeup-env openai_api_key` sets
# OPENAI_API_KEY. Sourced by capabilities/zsh/default/rc.
teeup-env() {
  local name="$1" var value
  if [[ -z "$name" ]]; then
    print -u2 "usage: teeup-env <secret-name> [VARIABLE]"
    return 2
  fi
  var="${2:-${(U)name}}"
  value="$(teeup secret get "$name")" || return 1
  export "$var=$value"
  print "exported $var from the teeup Keychain"
}
