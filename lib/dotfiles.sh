#!/usr/bin/env bash
# dotfiles.sh — recognise which tool a dotfiles directory is built for.
#
# teeup does not replace chezmoi or GNU Stow: it provisions the machine and hands
# $HOME to whichever manager the user's repo expects. These helpers are pure
# shell (no logging, no side effects) so the wizard can source them too.

# Print the manager a dotfiles directory is laid out for:
#   chezmoi  .chezmoiroot / .chezmoi.*.tmpl / .chezmoiignore / any top-level dot_* entry
#   stow     .stow-local-ignore / .stowrc / a top-level non-dot dir holding a dotted entry
#   native   teeup's flat layout: zshrc or bashrc at the top level
#   none     nothing recognised (also for a missing directory)
detect_dotfiles_manager() {
  local dir="$1" entry sub
  [[ -d "$dir" ]] || { echo "none"; return 0; }

  for entry in .chezmoiroot .chezmoi.toml.tmpl .chezmoi.yaml.tmpl .chezmoi.json.tmpl .chezmoiignore; do
    if [[ -e "$dir/$entry" ]]; then echo "chezmoi"; return 0; fi
  done
  for entry in "$dir"/dot_*; do
    if [[ -e "$entry" ]]; then echo "chezmoi"; return 0; fi
  done

  for entry in .stow-local-ignore .stowrc; do
    if [[ -e "$dir/$entry" ]]; then echo "stow"; return 0; fi
  done
  for sub in "$dir"/*/; do
    [[ -d "$sub" ]] || continue
    for entry in "$sub".??*; do
      if [[ -e "$entry" ]]; then echo "stow"; return 0; fi
    done
  done

  if [[ -f "$dir/zshrc" || -f "$dir/bashrc" ]]; then echo "native"; return 0; fi
  echo "none"
}

# Print the stow packages to apply from DIR, space-separated and sorted.
# STOW_PACKAGES overrides. Otherwise every top-level non-dot directory that
# contains a dotted entry is a package; when both bash and zsh packages exist
# only the TARGET_SHELL one survives. Empty output means "no packages": the
# directory is a flat mirror of $HOME and the caller stows it as one package.
stow_packages() {
  local dir="$1" sub name entry pkgs="" other_shell
  if [[ -n "${STOW_PACKAGES:-}" ]]; then
    echo "$STOW_PACKAGES"
    return 0
  fi
  # Only apply shell filtering if both bash and zsh packages exist
  if [[ -d "$dir/bash" && -d "$dir/zsh" ]]; then
    case "${TARGET_SHELL:-bash}" in
      zsh) other_shell="bash" ;;
      *)   other_shell="zsh" ;;
    esac
  fi
  for sub in "$dir"/*/; do
    [[ -d "$sub" ]] || continue
    name="$(basename "$sub")"
    [[ "$name" == "$other_shell" ]] && continue
    for entry in "$sub".??*; do
      if [[ -e "$entry" ]]; then
        pkgs="${pkgs:+$pkgs }$name"
        break
      fi
    done
  done
  echo "$pkgs"
}
