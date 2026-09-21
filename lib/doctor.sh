#!/usr/bin/env bash
# doctor.sh - the health check. Two halves: a generic check every capability
# gets for free from its own metadata, and the optional `doctor` script a
# capability ships for the invariants metadata cannot express. Both report
# into one file, so the summary can name every failure and the single command
# that fixes it (spec section 4: "doctor - optional; exit 0 healthy, prints
# findings", and the Verification gate "teeup doctor must exit 0 afterward").
# Requires core.sh, state.sh, capability.sh, pkg.sh, lazy.sh.

# The runner exports this. Empty means nobody is collecting, which is what a
# doctor script run straight through `cap_run` gets: it still prints, it just
# records nothing.
TEEUP_DOCTOR_REPORT="${TEEUP_DOCTOR_REPORT:-}"
export TEEUP_DOCTOR_REPORT

# Failures recorded by *this* process. A doctor script runs as its own
# `bash -eu`, so this counts that script's own findings and nothing else,
# which is exactly what doctor_verdict needs.
TEEUP_DOCTOR_FAILURES=0

doctor_ok() { ok "$*"; }
doctor_warn() { warn "$*"; }

# doctor_record <capability> <message> <fix-command>
# One tab-separated record per failure. A tab or a newline inside either
# field would split the record, so both are flattened to spaces rather than
# rejected: a check must never itself fail because a path it is reporting on
# has an odd character in it.
doctor_record() {
  local cap="$1" message="$2" fix="$3"
  if [[ -z "$TEEUP_DOCTOR_REPORT" ]]; then
    return 0
  fi
  printf '%s\t%s\t%s\n' \
    "$(printf '%s' "$cap" | tr '\t\n' '  ')" \
    "$(printf '%s' "$message" | tr '\t\n' '  ')" \
    "$(printf '%s' "$fix" | tr '\t\n' '  ')" >> "$TEEUP_DOCTOR_REPORT"
  return 0
}

# _doctor_report_failure <capability> <message> <fix-command>
# Print and record, for a caller that knows which capability it is speaking
# for. The runner uses it directly; a doctor script goes through doctor_fail.
_doctor_report_failure() {
  err "$2"
  doctor_record "$1" "$2" "$3"
  TEEUP_DOCTOR_FAILURES=$((TEEUP_DOCTOR_FAILURES + 1))
  return 0
}

# doctor_fail <message> <fix-command>
# What a capability's doctor script calls. It returns 0 on purpose: the
# script runs under `bash -eu` and must keep checking everything else, and
# the exit status is decided once, at the end, by doctor_verdict.
doctor_fail() {
  _doctor_report_failure "${TEEUP_CAP:-teeup}" "$1" "$2"
}

# The last line of every doctor script. Exit 0 healthy, as the spec requires,
# so `bash capabilities/<cap>/doctor` is still meaningful on its own.
doctor_verdict() { [[ "$TEEUP_DOCTOR_FAILURES" -eq 0 ]]; }

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
# true.
doctor_backend_can_answer() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) have brew ;;
    macports) have port ;;
    *) return 1 ;;
  esac
}

doctor_metadata_check() {
  local cap="$1" item candidate found app
  # Without the backend's own command there is no way to ask whether anything
  # is installed, and "not installed" would be teeup asserting something it
  # never checked. Say what is actually true: the check could not run.
  if ! doctor_backend_can_answer; then
    if [[ -n "$(cap_meta_get "$cap" packages)" ]] || { [[ -n "$(cap_meta_get "$cap" casks)" ]] && casks_supported; }; then
      doctor_warn "$(pkg_backend_label) is not on PATH, so teeup could not check what $cap installed."
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

# doctor_targets -> what `teeup doctor` with no argument checks: the
# capabilities this machine has installed and does not skip, in cap_list
# order. A capability that was never installed has nothing to be wrong with.
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

# doctor_summary <report-file>
# 0 when the report is empty, which is the spec's "teeup doctor must exit 0"
# gate. Otherwise one block per failure: what is wrong, and the one command
# that fixes it.
doctor_summary() {
  local report="$1" count cap message fix
  count=0
  if [[ -f "$report" ]]; then
    count="$(wc -l < "$report" | tr -d ' ')"
  fi
  echo ""
  if [[ "${count:-0}" -eq 0 ]]; then
    ok "teeup doctor: everything checked is healthy."
    return 0
  fi
  err "teeup doctor found $count problem(s):"
  while IFS=$'\t' read -r cap message fix || [[ -n "$cap" ]]; do
    if [[ -z "$cap" ]]; then
      continue
    fi
    printf '  %s: %s\n' "$cap" "$message" >&2
    printf '      fix: %s\n' "$fix" >&2
  done < "$report"
  return 1
}
