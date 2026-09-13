#!/usr/bin/env bash
# capability.sh - the capability contract: metadata, ordering, execution, lint.
# A capability is a directory under capabilities/ holding a sourced
# `capability` metadata file and executable install/configure scripts.
# Requires core.sh, state.sh, answers.sh.

TEEUP_CAPS_DIR="${TEEUP_CAPS_DIR:-$TEEUP_PATH/capabilities}"
export TEEUP_CAPS_DIR

# Commands macOS ships; a PATH-last shim for these can never fire.
TEEUP_SHIM_FORBIDDEN="python3 ruby java git perl"

cap_dir() { printf '%s/%s\n' "$TEEUP_CAPS_DIR" "$1"; }

cap_exists() { [[ -f "$(cap_dir "$1")/capability" ]]; }

cap_list() {
  local d
  for d in "$TEEUP_CAPS_DIR"/*/; do
    [[ -f "$d/capability" ]] || continue
    basename "$d"
  done | sort
}

# cap_meta_get <name> <key> [default]
# The metadata file is sourced in a subshell so its assignments never leak.
cap_meta_get() {
  local name="$1" key="$2" default="${3:-}" file
  file="$(cap_dir "$name")/capability"
  [[ -f "$file" ]] || die "Unknown capability: $name"
  (
    set +eu
    # shellcheck source=/dev/null
    source "$file"
    value="${!key:-}"
    [[ -n "$value" ]] || value="$default"
    printf '%s\n' "$value"
  )
}

# cap_tier_list <core|daily> -> names in manifest order
cap_tier_list() {
  local file="$TEEUP_CAPS_DIR/$1.list"
  [[ -f "$file" ]] || return 0
  grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$'
}

# cap_order <name...> -> names with their requires first, each once.
# Visited is marked before recursing so a cycle cannot loop forever.
cap_order() {
  _TEEUP_CAP_VISITED=" "
  local c
  for c in "$@"; do _cap_visit "$c"; done
}

_cap_visit() {
  local c="$1" r
  case "$_TEEUP_CAP_VISITED" in *" $c "*) return 0 ;; esac
  cap_exists "$c" || die "Unknown capability: $c"
  _TEEUP_CAP_VISITED="$_TEEUP_CAP_VISITED$c "
  for r in $(cap_meta_get "$c" requires); do _cap_visit "$r"; done
  printf '%s\n' "$c"
}

cap_skipped() {
  case " ${TEEUP_SKIP:-} " in *" $1 "*) return 0 ;; esac
  return 1
}

# cap_run <name> <verb>
# Runs capabilities/<name>/<verb> as a fresh `bash -eu` with the libraries
# loaded and the answers file sourced. Wrapped in run_logged, which closes
# stdin unless the capability declares interactive=true.
cap_run() {
  local name="$1" verb="$2" dir script interactive
  dir="$(cap_dir "$name")"
  script="$dir/$verb"
  if [[ ! -f "$script" ]]; then
    err "$name has no $verb script"
    return 1
  fi
  interactive="$(cap_meta_get "$name" interactive false)"
  TEEUP_CAP="$name"
  TEEUP_CAP_DIR="$dir"
  export TEEUP_CAP TEEUP_CAP_DIR
  run_logged "$name $verb" "$interactive" \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; source "$1"' bash "$script"
}

# cap_check -> lints every capability; prints one problem per line.
cap_check() {
  local problems=0 name dir tier provides p verb
  for name in $(cap_list); do
    dir="$(cap_dir "$name")"
    tier="$(cap_meta_get "$name" tier)"
    [[ -n "$(cap_meta_get "$name" summary)" ]] || { echo "$name: summary is empty"; problems=$((problems + 1)); }
    case "$tier" in
      core|daily|lazy) ;;
      *) echo "$name: tier must be core, daily or lazy (got '$tier')"; problems=$((problems + 1)) ;;
    esac
    for verb in install configure; do
      if [[ ! -f "$dir/$verb" ]]; then
        echo "$name: missing $verb script"; problems=$((problems + 1))
      elif [[ ! -x "$dir/$verb" ]]; then
        echo "$name: $verb is not executable"; problems=$((problems + 1))
      fi
    done
    provides="$(cap_meta_get "$name" provides)"
    for p in $provides; do
      case " $TEEUP_SHIM_FORBIDDEN " in
        *" $p "*) echo "$name: provides must not list $p (macOS ships it, a shim can never fire)"; problems=$((problems + 1)) ;;
      esac
    done
    case "$tier" in
      core|daily)
        cap_tier_list "$tier" | grep -qx "$name" || { echo "$name: tier is $tier but it is not listed in $tier.list"; problems=$((problems + 1)); }
        ;;
      lazy)
        for verb in core daily; do
          cap_tier_list "$verb" | grep -qx "$name" && { echo "$name: tier is lazy but it is listed in $verb.list"; problems=$((problems + 1)); }
        done
        ;;
    esac
    for p in $(cap_meta_get "$name" requires); do
      cap_exists "$p" || { echo "$name: requires unknown capability $p"; problems=$((problems + 1)); }
    done
  done
  for tier in core daily; do
    for name in $(cap_tier_list "$tier"); do
      cap_exists "$name" || { echo "$tier.list: unknown capability $name"; problems=$((problems + 1)); }
    done
  done
  [[ $problems -eq 0 ]]
}

# cap_run_optional <name> <verb>
# The hook runner behind theme-apply and font-apply: a capability that has no
# opinion about themes simply ships no theme-apply, and a broken hook warns
# instead of aborting the switch (Omarchy's hook rule). cap_run itself is the
# strict version and stays that way, because `teeup configure nope` must fail.
cap_run_optional() {
  local name="$1" verb="$2"
  if cap_skipped "$name"; then return 0; fi
  [[ -f "$(cap_dir "$name")/$verb" ]] || return 0
  cap_run "$name" "$verb" || warn "$name $verb failed; continuing."
  return 0
}
