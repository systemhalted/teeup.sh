#!/usr/bin/env bash
# capability.sh - the capability contract: metadata, ordering, execution, lint.
# A capability is a directory under capabilities/ holding a sourced
# `capability` metadata file and executable install/configure scripts.
# Requires core.sh, state.sh, answers.sh.

TEEUP_CAPS_DIR="${TEEUP_CAPS_DIR:-$TEEUP_PATH/capabilities}"
export TEEUP_CAPS_DIR

# Commands macOS ships; a PATH-last shim for these can never fire.
TEEUP_SHIM_FORBIDDEN="python3 ruby java git perl"

# The reserved "not applicable here" exit status an install or configure
# script hands back through not_applicable, below. 42 is not a value any
# command teeup shells out to (brew, port, ssh-keygen, security, ...) is
# documented to return on its own, so a script that never calls
# not_applicable is vanishingly unlikely to produce it by accident -- and
# cap_run does not trust the code alone anyway: it also requires the marker
# file that only not_applicable writes, so a coincidental `exit 42` from some
# other failure still reads as the real failure it is.
TEEUP_CAP_NA_EXIT=42

# not_applicable <message>
# The one sanctioned way for a capability's install or configure to say "this
# machine cannot have this capability" -- not a failure (bootstrap keeps
# going, teeup install's exit code stays 0) and not success either (nothing
# is marked done, `teeup has` still reports not-installed, `teeup status`
# shows it as its own state). <message> is what the user sees in place of
# instructions that could never have worked; state the fact, not an apology.
# A genuine error must still go through warn/die/a non-zero exit -- never
# call this to paper over one, or a real breakage would sail through
# bootstrap's core-tier gate unnoticed.
not_applicable() {
  warn "$*"
  [[ -n "${TEEUP_CAP_NA_MARKER:-}" ]] && : > "$TEEUP_CAP_NA_MARKER"
  exit "$TEEUP_CAP_NA_EXIT"
}

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
#
# Sets TEEUP_CAP_NA to "true" or "false" before returning, for the caller to
# read: "true" means the script called not_applicable rather than actually
# running, and cap_run has already turned that into a 0 return here (it is
# not a failure). A na_marker path is reserved with `mktemp -u` (named, not
# created) and handed to the script as TEEUP_CAP_NA_MARKER; only
# not_applicable ever creates that file, so treating TEEUP_CAP_NA_EXIT as the
# not-applicable answer requires both the code and the file, not the exit
# code alone.
cap_run() {
  local name="$1" verb="$2" dir script interactive rc=0 na_marker outer_cap="${TEEUP_CAP:-}" outer_dir="${TEEUP_CAP_DIR:-}"
  dir="$(cap_dir "$name")"
  script="$dir/$verb"
  if [[ ! -f "$script" ]]; then
    err "$name has no $verb script"
    return 1
  fi
  interactive="$(cap_meta_get "$name" interactive false)"
  TEEUP_CAP="$name"
  TEEUP_CAP_DIR="$dir"
  na_marker="$(mktemp -u)"
  TEEUP_CAP_NA_MARKER="$na_marker"
  export TEEUP_CAP TEEUP_CAP_DIR TEEUP_CAP_NA_MARKER
  TEEUP_CAP_NA=false
  # Tells run_logged that this one exit code is an answer, not a failure, for
  # the capability script it is about to run.
  TEEUP_RUN_NA_EXIT="$TEEUP_CAP_NA_EXIT" \
  run_logged "$name $verb" "$interactive" \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; source "$1"' bash "$script" || rc=$?
  if [[ $rc -eq $TEEUP_CAP_NA_EXIT && -e "$na_marker" ]]; then
    TEEUP_CAP_NA=true
    rc=0
  fi
  rm -f "$na_marker"
  unset TEEUP_CAP_NA_MARKER
  # A capability script that runs another one (ssh re-runs git's configure)
  # is still itself afterwards: copy_config_once reads TEEUP_CAP to scope
  # TEEUP_REFRESH and TEEUP_RESET to the capability they name.
  TEEUP_CAP="$outer_cap"
  TEEUP_CAP_DIR="$outer_dir"
  return $rc
}

# cap_install_verbs <name>
# install then configure, then record the outcome -- the one place that
# decides between state_done and state_na, shared by `teeup install`
# (bin/teeup) and bootstrap's core/daily tiers so the two entry points can
# never disagree about what a machine has. "Not applicable" from either verb
# wins over the other verb having genuinely run: a machine that cannot have
# the capability at all has nothing "done" about it. Returns 0 on success or
# not-applicable; non-zero (with neither marker touched) on a real failure,
# for the caller's own core-vs-daily handling. Leaves TEEUP_CAP_NA set to the
# combined "true"/"false" outcome, for a caller that wants to know (bootstrap
# only adds a capability to CONFIGURED_THIS_RUN when it was not).
cap_install_verbs() {
  local name="$1" na=false
  cap_run "$name" install || return 1
  [[ "$TEEUP_CAP_NA" == "true" ]] && na=true
  cap_run "$name" configure || return 1
  [[ "$TEEUP_CAP_NA" == "true" ]] && na=true
  if [[ "$na" == "true" ]]; then
    state_done clear "cap-$name" || true
    state_na mark "cap-$name"
  else
    state_na clear "cap-$name" || true
    state_done mark "cap-$name"
  fi
  TEEUP_CAP_NA="$na"
}

# cap_check -> lints every capability; prints one problem per line.
cap_check() {
  local problems=0 name dir tier provides p verb tpl base other d seen
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
      # A provides token becomes a file name under the shims directory and a
      # bare word on the shim's exec line, so it has to be a plain command
      # name: letters, digits and _.+- only, starting with a letter or digit.
      if ! [[ "$p" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]]; then
        echo "$name: provides token '$p' is not a plain command name"; problems=$((problems + 1))
      fi
    done
    # package_commands= maps a declared package to the command
    # `pkg_install <pkg> <command>` accepts in its place, so doctor can ask
    # the same question install asked. A pair naming a package the metadata
    # does not declare is dead text that silently does nothing, which is
    # worse than an error: the doctor goes on failing a healthy machine and
    # the entry that was meant to fix it looks present.
    for p in $(cap_meta_get "$name" package_commands); do
      case "$p" in
        *:?*)
          seen=" $(cap_meta_get "$name" packages) "
          case "$seen" in
            *" ${p%%:*} "*) ;;
            *) echo "$name: package_commands names '${p%%:*}', which is not in packages"; problems=$((problems + 1)) ;;
          esac
          ;;
        *) echo "$name: package_commands entry '$p' is not <package>:<command>"; problems=$((problems + 1)) ;;
      esac
    done
    # apps= is ";"-separated (names contain spaces); an entry becomes
    # "<name>.app" under /Applications and an argument to `open -a`.
    case "$(cap_meta_get "$name" apps)" in
      */*) echo "$name: apps must be application names, not paths"; problems=$((problems + 1)) ;;
    esac
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
  # theme_set renders every capability's themed/*.tpl into one flat directory
  # per mode, so two capabilities shipping the same basename would silently
  # render only the first. Globs expand sorted, so each template is compared
  # with the capabilities before its own.
  for tpl in "$TEEUP_CAPS_DIR"/*/themed/*.tpl; do
    [[ -f "$tpl" ]] || continue
    base="${tpl##*/}"
    name="${tpl%/themed/*}"
    name="${name##*/}"
    for d in "$TEEUP_CAPS_DIR"/*/themed; do
      other="${d%/themed}"
      other="${other##*/}"
      [[ "$other" == "$name" ]] && break
      if [[ -f "$d/$base" ]]; then
        echo "$name: themed/$base is also shipped by $other"; problems=$((problems + 1))
        break
      fi
    done
  done
  for tier in core daily; do
    for name in $(cap_tier_list "$tier"); do
      cap_exists "$name" || { echo "$tier.list: unknown capability $name"; problems=$((problems + 1)); }
    done
  done
  # One shim per command: two lazy capabilities providing the same command
  # would leave whichever sorts first owning the shim, silently.
  seen=" "
  for name in $(cap_list); do
    [[ "$(cap_meta_get "$name" tier)" == "lazy" ]] || continue
    for p in $(cap_meta_get "$name" provides); do
      case "$seen" in
        *" $p="*)
          other="${seen#*" $p="}"
          other="${other%% *}"
          echo "$name: provides $p, which $other already provides"; problems=$((problems + 1))
          ;;
        *) seen="$seen$p=$name " ;;
      esac
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

# cap_hook_eligible <name>
# A theme-apply or font-apply hook pushes the current theme or font into a tool
# teeup set up. A capability that was never installed has set nothing up, and
# a tool of the same name on the machine is not teeup's to drive, so its hooks
# wait until `teeup install` (or bootstrap) has marked it installed. The one
# exception is the capability whose own configure is running, before that
# marker exists: its configure exports TEEUP_CONFIGURING with its name, the
# same variable plan 3a's editor hooks check.
cap_hook_eligible() {
  if state_done check "cap-$1"; then return 0; fi
  [[ "${TEEUP_CONFIGURING:-}" == "$1" ]]
}

# cap_run_hooks <verb>
# Runs <verb> for every eligible capability that ships it, through
# cap_run_optional (so a skipped capability is left out and a failing hook
# warns). A for loop over a captured list, not `while read ... < <(cap_list)`:
# an interactive=true capability's hook inherits stdin, and reading it would
# swallow the names of the capabilities still waiting for their hooks.
cap_run_hooks() {
  local verb="$1" cap
  for cap in $(cap_list); do
    if cap_hook_eligible "$cap"; then
      cap_run_optional "$cap" "$verb"
    fi
  done
  return 0
}
