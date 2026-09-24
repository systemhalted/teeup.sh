#!/usr/bin/env bash
# doctor.sh - the health check. Two halves: a generic check every capability
# gets for free from its own metadata, and the optional `doctor` script a
# capability ships for the invariants metadata cannot express. Both report
# into one file, so the summary can name every failure and the single command
# that fixes it (spec section 4: "doctor - optional; exit 0 healthy, prints
# findings", and the Verification gate "teeup doctor must exit 0 afterward").
# Requires core.sh, state.sh, capability.sh, pkg.sh, lazy.sh.
#
# `teeup doctor`'s exit status is tri-state, not boolean, because what a check
# learns is one of three things, not two: the machine is healthy, the machine
# has a confirmed problem, or the check could not run to a verdict at all (a
# file it needs is unreadable, the tool it has to ask is not answering). The
# third state used to collapse into "healthy" -- a doctor script that hit it
# called doctor_warn and moved on, and doctor never recorded that anything was
# left unverified. `teeup doctor` then exited 0, "everything checked is
# healthy," about a machine it never actually looked at. Three rounds of
# review found the same bug in a new place each time, because nothing forced
# a check that gave up to say so anywhere the exit status could see.
#
#   0 - doctor_verdict / doctor_summary: every check that ran reached a
#       verdict, and none of them found a problem. This is the only exit
#       status that means "I verified this machine is healthy."
#   1 - at least one doctor_fail: a check ran to completion and found a real
#       problem. Takes priority over an unrelated unknown in the same run.
#   2 - no doctor_fail, but at least one doctor_unknown: nothing is confirmed
#       broken, but something material could not be checked, so 0 would be a
#       claim doctor never verified.
#
# doctor_warn is for the fourth thing, which is not a verdict gap at all: a
# fact the check DID establish, that is worth a person's attention but is not
# itself a failure (a reminder to turn on an OS permission, a note that a
# just-created ssh-agent has not been used yet, a machine-file override that
# is working as configured). doctor_warn never touches the exit status --
# conflating "I checked, and here is a heads-up" with "I could not check" is
# exactly how the false-healthy bug kept coming back.

# The runner exports this. Empty means nobody is collecting, which is what a
# doctor script run straight through `cap_run` gets: it still prints, it just
# records nothing.
TEEUP_DOCTOR_REPORT="${TEEUP_DOCTOR_REPORT:-}"
export TEEUP_DOCTOR_REPORT

# Failures and unknowns recorded by *this* process. A doctor script runs as
# its own `bash -eu`, so these count that script's own findings and nothing
# else, which is exactly what doctor_verdict needs.
TEEUP_DOCTOR_FAILURES=0
TEEUP_DOCTOR_UNKNOWNS=0

doctor_ok() { ok "$*"; }
doctor_warn() { warn "$*"; }

# doctor_record <capability> <message> <fix-command> [<kind>]
# One tab-separated record per finding. A tab or a newline inside any field
# would split the record, so all three are flattened to spaces rather than
# rejected: a check must never itself fail because a path it is reporting on
# has an odd character in it. <kind> is "fail" or "unknown"; it defaults to
# "fail" so every record written before this field existed is still read
# correctly.
doctor_record() {
  local cap="$1" message="$2" fix="$3" kind="${4:-fail}"
  if [[ -z "$TEEUP_DOCTOR_REPORT" ]]; then
    return 0
  fi
  printf '%s\t%s\t%s\t%s\n' \
    "$(printf '%s' "$cap" | tr '\t\n' '  ')" \
    "$(printf '%s' "$message" | tr '\t\n' '  ')" \
    "$(printf '%s' "$fix" | tr '\t\n' '  ')" \
    "$kind" >> "$TEEUP_DOCTOR_REPORT"
  return 0
}

# _doctor_report_failure <capability> <message> <fix-command>
# Print and record, for a caller that knows which capability it is speaking
# for. The runner uses it directly; a doctor script goes through doctor_fail.
_doctor_report_failure() {
  err "$2"
  doctor_record "$1" "$2" "$3" fail
  TEEUP_DOCTOR_FAILURES=$((TEEUP_DOCTOR_FAILURES + 1))
  return 0
}

# _doctor_report_unknown <capability> <message> <fix-command>
# The same shape as _doctor_report_failure, for a check that could not reach
# a verdict at all rather than one that reached a bad one. Printed with its
# own symbol so the difference is visible in real time, not just in the exit
# status.
_doctor_report_unknown() {
  printf "%b %s\n" "❓" "$2" >&2
  doctor_record "$1" "$2" "$3" unknown
  TEEUP_DOCTOR_UNKNOWNS=$((TEEUP_DOCTOR_UNKNOWNS + 1))
  return 0
}

# doctor_fail <message> <fix-command>
# What a capability's doctor script calls for a confirmed problem. It returns
# 0 on purpose: the script runs under `bash -eu` and must keep checking
# everything else, and the exit status is decided once, at the end, by
# doctor_verdict.
doctor_fail() {
  _doctor_report_failure "${TEEUP_CAP:-teeup}" "$1" "$2"
}

# doctor_unknown <message> <fix-command>
# What a capability's doctor script calls when a check could not run to a
# verdict at all: the file it needed was unreadable, the command it needed to
# ask did not answer. Distinct from doctor_warn (a fact the check DID
# establish, and is not itself a failure) and from doctor_fail (a fact the
# check DID establish, and it is a failure): doctor_unknown is for not having
# established anything. Also returns 0, for the same reason doctor_fail does.
doctor_unknown() {
  _doctor_report_unknown "${TEEUP_CAP:-teeup}" "$1" "$2"
}

# The last line of every doctor script. 0 only when nothing failed AND
# nothing was left unverified, so `bash capabilities/<cap>/doctor` is still
# meaningful on its own: 0 healthy, 1 a confirmed problem, 2 nothing
# confirmed broken but something could not be checked.
doctor_verdict() {
  if [[ "$TEEUP_DOCTOR_FAILURES" -gt 0 ]]; then
    return 1
  fi
  if [[ "$TEEUP_DOCTOR_UNKNOWNS" -gt 0 ]]; then
    return 2
  fi
  return 0
}

_doctor_report_lines() {
  if [[ -n "$TEEUP_DOCTOR_REPORT" && -f "$TEEUP_DOCTOR_REPORT" ]]; then
    wc -l < "$TEEUP_DOCTOR_REPORT" | tr -d ' '
  else
    printf '0\n'
  fi
}

# doctor_metadata_check <capability>
# Everything the metadata already declares can be checked without a script,
# which is why most capabilities need no doctor of their own: packages and
# casks are installed, apps are in /Applications, and every command in
# provides= resolves to a real binary. `have` returns 1 for a command that
# resolves only inside the shims directory (phase 3b), so a lazy capability
# marked installed whose shim never got replaced is a finding rather than a
# pass. Always returns 0; the report carries the verdict.
# doctor_backend_can_answer -> 0 when the package manager's own command is
# here to be asked. Everything doctor says about packages and casks depends on
# it, and a missing brew or port makes "not installed" unknowable rather than
# true. `have` alone only proves the command is on PATH: a half-finished
# upgrade, a backend pointed at a broken prefix, or a shim that exits
# non-zero on every call is on PATH too and fails every real call, and
# passing this gate for one of those turns into a flood of confident, wrong
# "not installed" findings from every capability at once -- so this probes
# the backend's own cheap self-identifying command and treats a non-zero
# exit or empty output as "cannot answer", the same as not being on PATH.
# The answer is remembered per backend for the life of this process: one
# `teeup doctor` run asks this once per capability with packages or casks,
# and the answer cannot change mid-run.
#
# This is the ONE definition of "can the backend answer": every caller that
# needs to know -- doctor_metadata_check below and
# capabilities/package-manager/doctor -- calls this rather than rolling its
# own probe. Two definitions once meant a `brew` that exits 0 with no output
# was "cannot answer" here and "installed" in package-manager/doctor, in the
# same run (NI3). TEEUP_DOCTOR_BACKEND_OUT is the raw output (or error text)
# of the probe that produced the cached answer, for a caller that wants to
# say more than yes/no about why.
TEEUP_DOCTOR_BACKEND_ANSWER=""
TEEUP_DOCTOR_BACKEND_OUT=""
doctor_backend_can_answer() {
  _pkg_backend_resolve
  case "$TEEUP_DOCTOR_BACKEND_ANSWER" in
    "$TEEUP_PKG_BACKEND:0") return 0 ;;
    "$TEEUP_PKG_BACKEND:1") return 1 ;;
  esac
  local cmd out="" rc=0
  cmd="$(pkg_backend_cmd)"
  if [[ -n "$cmd" ]] && have "$cmd"; then
    case "$TEEUP_PKG_BACKEND" in
      homebrew) out="$("$cmd" --version 2>&1)" || rc=$? ;;
      macports) out="$("$cmd" version 2>&1)" || rc=$? ;;
    esac
  else
    rc=1
  fi
  # shellcheck disable=SC2034  # read by callers (capabilities/package-manager/doctor)
  TEEUP_DOCTOR_BACKEND_OUT="$out"
  # Both halves of the gate matter: a shim or a half-finished upgrade that
  # exits 0 with nothing on stdout is exactly as unable to answer as one that
  # exits non-zero, and a caller that only checked the exit status would read
  # it as a real, empty, healthy answer.
  if [[ "$rc" -eq 0 && -n "$out" ]]; then
    TEEUP_DOCTOR_BACKEND_ANSWER="$TEEUP_PKG_BACKEND:0"
    return 0
  fi
  TEEUP_DOCTOR_BACKEND_ANSWER="$TEEUP_PKG_BACKEND:1"
  return 1
}

doctor_metadata_check() {
  local cap="$1" item candidate found app
  # Without the backend's own command there is no way to ask whether anything
  # is installed, and "not installed" would be teeup asserting something it
  # never checked. Say what is actually true: the check could not run.
  if ! doctor_backend_can_answer; then
    if [[ -n "$(cap_meta_get "$cap" packages)" ]] || { [[ -n "$(cap_meta_get "$cap" casks)" ]] && casks_supported; }; then
      # "Not on PATH" is only true when it really is not on PATH: a backend
      # that is there but answered nothing (exit 0 and silent, or a non-zero
      # exit) just disproved that sentence, and saying it anyway points away
      # from the real cause (NI3).
      if have "$(pkg_backend_cmd)"; then
        _doctor_report_unknown "$cap" "teeup could not get an answer out of $(pkg_backend_cmd), so it could not check what $cap installed." "teeup doctor package-manager"
      else
        _doctor_report_unknown "$cap" "$(pkg_backend_label) is not on PATH, so teeup could not check what $cap installed." "teeup doctor package-manager"
      fi
    fi
  else
    for item in $(cap_meta_get "$cap" packages); do
      found=false
      for candidate in $(package_candidates "$item"); do
        if pkg_installed "$candidate"; then
          found=true
          break
        fi
      done
      if [[ "$found" == "true" ]]; then
        doctor_ok "package $item is installed."
      else
        _doctor_report_failure "$cap" "package $item is not installed." "teeup install $cap"
      fi
    done
  fi
  for item in $(cap_meta_get "$cap" casks); do
    # Whether this backend has casks at all is a fact about the backend, not a
    # question for its command: MacPorts has none whether or not `port` is
    # installed, so this answer stands even when nothing can be asked.
    if ! casks_supported; then
      doctor_warn "casks are not available with $(pkg_backend_label); install $item by hand."
      continue
    fi
    if ! doctor_backend_can_answer; then
      continue
    fi
    if cask_installed "$item"; then
      doctor_ok "cask $item is installed."
    else
      _doctor_report_failure "$cap" "cask $item is not installed." "teeup install $cap"
    fi
  done
  # App names can contain spaces, so they arrive one per line, never as words.
  while IFS= read -r app; do
    if [[ -z "$app" ]]; then
      continue
    fi
    if app_installed "$app"; then
      doctor_ok "$app.app is installed."
    else
      _doctor_report_failure "$cap" "$app.app is not installed." "teeup install $cap"
    fi
  done <<EOF_APPS
$(cap_apps "$cap")
EOF_APPS
  for item in $(cap_meta_get "$cap" provides); do
    if have "$item"; then
      doctor_ok "$item is on PATH."
    else
      _doctor_report_failure "$cap" "$item is not on PATH (a lazy shim does not count)." "teeup install $cap"
    fi
  done
  return 0
}

# _doctor_unsearchable_ancestor <path> -> prints the nearest ancestor
# directory of <path> (starting at its parent, walking up to and including
# $HOME) that exists but cannot be searched; prints nothing and fails when
# every ancestor up to $HOME is searchable. A negative `-e "$path"` is only
# trustworthy once this comes back empty: permissions damage from a `sudo
# ./bootstrap` or a bad umask lands on whichever directory a privileged
# process created first, and that is exactly as likely to be
# $TEEUP_STATE_DIR's own parent -- $XDG_STATE_HOME, e.g. ~/.local/state --
# left root-owned, as $TEEUP_STATE_DIR itself (NI-C: NB3's blind spot, one
# directory up).
_doctor_unsearchable_ancestor() {
  local path="$1" dir
  dir="$(dirname "$path")"
  while :; do
    if [[ -e "$dir" && ! -x "$dir" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    if [[ "$dir" == "$HOME" || "$dir" == "/" || "$dir" == "." ]]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# doctor_state_readable -> 0 when $TEEUP_STATE_DIR/done can be listed and
# searched, i.e. every state_done check below can be trusted. A tree left
# root-owned by `sudo ./bootstrap`, or a bad umask, fails every `-f` test in
# it silently and looks exactly like a bare machine; this tells the two
# apart before doctor_targets ever asks (B4). A directory that does not
# exist yet is a genuinely bare machine, not an unreadable one -- but that is
# only true when every ancestor up to $HOME can be searched: permissions
# damage lands on whichever directory a privileged process created first,
# which is as often the state tree's parent as the tree root itself (NI-C),
# and `[[ ! -e "$TEEUP_STATE_DIR/done" ]]` succeeds for the wrong reason (a
# `stat` that failed with EACCES) on a machine that is actually fully
# installed (NB3). So ancestors are checked first, then the root itself: an
# unsearchable directory anywhere on the way down fails outright, whatever
# done/ looks like from here.
doctor_state_readable() {
  local root="$TEEUP_STATE_DIR" dir="$TEEUP_STATE_DIR/done"
  if _doctor_unsearchable_ancestor "$root" >/dev/null; then
    return 1
  fi
  if [[ -e "$root" && ( ! -r "$root" || ! -x "$root" ) ]]; then
    return 1
  fi
  [[ ! -e "$dir" ]] || [[ -r "$dir" && -x "$dir" ]]
}

# doctor_report_state_unreadable -> the one failure that stands in for every
# state_done lookup this run could not trust, with a fix that addresses the
# permissions problem it actually is rather than replacing anything. Names
# whichever of an unsearchable ancestor, the tree root, or done/ itself is
# the one doctor_state_readable actually failed on (NB3, NI-C), rather than
# always pointing at done/.
doctor_report_state_unreadable() {
  local root="$TEEUP_STATE_DIR" target="$TEEUP_STATE_DIR/done" ancestor
  if ancestor="$(_doctor_unsearchable_ancestor "$root")" && [[ -n "$ancestor" ]]; then
    target="$ancestor"
  elif [[ -e "$root" && ( ! -r "$root" || ! -x "$root" ) ]]; then
    target="$root"
  fi
  _doctor_report_failure "teeup" \
    "$target could not be read, so teeup doctor cannot tell what is installed here." \
    "chmod u+rx \"$target\""
}

# doctor_targets -> what `teeup doctor` with no argument checks: the
# capabilities this machine has installed and does not skip, in cap_list
# order. A capability that was never installed has nothing to be wrong with.
# Callers must confirm doctor_state_readable first: an unreadable done/
# makes every state_done check below answer "no" for a reason that has
# nothing to do with what is installed.
doctor_targets() {
  local name
  for name in $(cap_list); do
    if state_done check "cap-$name" && ! cap_skipped "$name"; then
      printf '%s\n' "$name"
    fi
  done
  return 0
}

# doctor_installed_any -> 0 when anything at all is marked installed here,
# whatever TEEUP_SKIP says about it. doctor_targets deliberately leaves the
# skipped ones out; this tells an empty target list apart from an empty
# machine.
doctor_installed_any() {
  local name
  for name in $(cap_list); do
    if state_done check "cap-$name"; then
      return 0
    fi
  done
  return 1
}

# doctor_run_one <capability>
# Always returns 0: one capability that cannot be checked must not stop the
# rest, and the report, not this function, carries the verdict. A doctor
# script that exits non-zero having already said why is not counted twice.
doctor_run_one() {
  local cap="$1" script before
  log "== $cap: $(cap_meta_get "$cap" summary) =="
  # A capability this machine cannot have is not a broken one. Checking its
  # metadata would report every package it names as missing, exit 1, and
  # offer `teeup install`, which would answer not-applicable and change
  # nothing: a healthy machine described as broken, with a fix that is a
  # no-op.
  if state_na check "cap-$cap"; then
    doctor_ok "$cap is not applicable on this machine, so there is nothing to check."
    return 0
  fi
  if cap_skipped "$cap"; then
    doctor_warn "$cap is skipped on this machine (TEEUP_SKIP); checking it anyway."
  fi
  doctor_metadata_check "$cap"
  script="$(cap_dir "$cap")/doctor"
  if [[ -f "$script" ]]; then
    before="$(_doctor_report_lines)"
    if ! cap_run "$cap" doctor; then
      if [[ "$(_doctor_report_lines)" -eq "$before" ]]; then
        _doctor_report_failure "$cap" "its doctor script exited non-zero without saying why." "teeup configure $cap"
      fi
    fi
  fi
  return 0
}

# _doctor_print_records <record>...
# Each <record> is one cap/message/fix line, tab-joined by the caller (never
# containing a tab or newline itself: doctor_record already flattened both).
_doctor_print_records() {
  local rec cap message fix
  for rec in "$@"; do
    IFS=$'\t' read -r cap message fix <<<"$rec"
    printf '  %s: %s\n' "$cap" "$message" >&2
    printf '      fix: %s\n' "$fix" >&2
  done
}

# doctor_summary <report-file> [checked]
# 0 when the report is empty, which is the spec's "teeup doctor must exit 0"
# gate -- and the only exit status that means every check ran and none found
# a problem. Otherwise one block per confirmed failure, then one block per
# check that could not be run to a verdict at all, each with the one command
# that fixes it. `checked` defaults to true, the case every caller with an
# explicit or non-empty target list is in; a no-argument run that found
# nothing to check (a bare machine, or everything installed skipped) passes
# false so an empty report is not misread as "everything checked passed" --
# it is silence about nothing (B4).
#
# Returns 1 when at least one doctor_fail record is in the report (found
# problems -- takes priority over an unrelated unknown in the same run), 2
# when the report holds only doctor_unknown records (nothing confirmed
# broken, but something material could not be checked, so 0 would be a claim
# never verified), 0 otherwise. See the header comment for the full
# convention.
doctor_summary() {
  local report="$1" checked="${2:-true}" total=0 cap message fix kind
  local -a fail_lines=() unknown_lines=()
  local fail_count=0 unknown_count=0
  echo ""
  if [[ -f "$report" ]]; then
    total="$(wc -l < "$report" | tr -d ' ')"
  fi
  if [[ "${total:-0}" -eq 0 ]]; then
    if [[ "$checked" == "true" ]]; then
      ok "teeup doctor: everything checked is healthy."
    fi
    return 0
  fi
  while IFS=$'\t' read -r cap message fix kind || [[ -n "$cap" ]]; do
    if [[ -z "$cap" ]]; then
      continue
    fi
    if [[ "${kind:-fail}" == "unknown" ]]; then
      unknown_count=$((unknown_count + 1))
      unknown_lines[${#unknown_lines[@]}]="$cap"$'\t'"$message"$'\t'"$fix"
    else
      fail_count=$((fail_count + 1))
      fail_lines[${#fail_lines[@]}]="$cap"$'\t'"$message"$'\t'"$fix"
    fi
  done < "$report"
  if [[ "$fail_count" -gt 0 ]]; then
    err "teeup doctor found $fail_count problem(s):"
    _doctor_print_records "${fail_lines[@]}"
  fi
  if [[ "$unknown_count" -gt 0 ]]; then
    warn "teeup doctor could not verify $unknown_count item(s); the machine may or may not be healthy where these could not be checked:"
    _doctor_print_records "${unknown_lines[@]}"
  fi
  if [[ "$fail_count" -gt 0 ]]; then
    return 1
  fi
  return 2
}
