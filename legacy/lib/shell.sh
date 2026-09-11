#!/usr/bin/env bash
# shell.sh — login-shell detection and cross-shell (teeup.common) integration

normalize_target_shell() {
  local value_lower
  value_lower=$(echo "${TARGET_SHELL:-}" | tr '[:upper:]' '[:lower:]')
  case "$value_lower" in
    bash|zsh) TARGET_SHELL="$value_lower" ;;
    auto|"") TARGET_SHELL="" ;;
    *)
      warn "Unknown TARGET_SHELL '${TARGET_SHELL:-}'; auto-detecting instead."
      TARGET_SHELL=""
      ;;
  esac
}

# Resolve the user's login shell into TARGET_SHELL (bash|zsh). Honors an explicit
# TARGET_SHELL override; otherwise reads the login shell from the passwd database
# (falling back to $SHELL), then to a per-platform default.
detect_target_shell() {
  normalize_target_shell
  if [[ -n "${TARGET_SHELL:-}" ]]; then
    return 0
  fi

  local login_shell=""
  if have getent; then
    login_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
  fi
  if [[ -z "$login_shell" ]]; then
    login_shell="${SHELL:-}"
  fi

  local shell_name=""
  if [[ -n "$login_shell" ]]; then
    shell_name="$(basename "$login_shell")"
  fi

  case "$shell_name" in
    *zsh) TARGET_SHELL="zsh" ;;
    *bash) TARGET_SHELL="bash" ;;
    *)
      if is_macos; then
        TARGET_SHELL="zsh"
      else
        TARGET_SHELL="bash"
      fi
      ;;
  esac
}

# Interactive rc file for the resolved target shell.
target_rc_file() {
  case "${TARGET_SHELL:-}" in
    zsh) echo "$ZSHRC" ;;
    *) echo "$BASHRC" ;;
  esac
}

append_teeup_common_source() {
  local file="$1"
  append_once "$file" "Added by teeup.sh - teeup.common" <<'EOF'
# Cross-shell tool integration written by teeup.sh.
if [ -r "$HOME/.teeup.common" ]; then
  . "$HOME/.teeup.common"
fi
EOF
}

# Wire the target shell's interactive rc file to source ~/.teeup.common. Called only
# on the managed-fallback path; when a dotfiles payload is present, its rc files
# source teeup.common themselves. Deliberately touches ONLY the target shell's rc so
# bash and zsh stay segregated deployments.
ensure_teeup_common_sourced() {
  append_teeup_common_source "$(target_rc_file)"
}
