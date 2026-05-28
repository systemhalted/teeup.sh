#!/usr/bin/env bash
# platform.sh — platform detection and unsupported-module policy

strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  echo "$value"
}

detect_linux_release() {
  DISTRO_ID=""
  DISTRO_ID_LIKE=""
  DISTRO_VERSION_ID=""

  if [[ -r /etc/os-release ]]; then
    while IFS='=' read -r key value; do
      value="$(strip_quotes "$value")"
      case "$key" in
        ID) DISTRO_ID="$value" ;;
        ID_LIKE) DISTRO_ID_LIKE="$value" ;;
        VERSION_ID) DISTRO_VERSION_ID="$value" ;;
      esac
    done < /etc/os-release
  fi

  if [[ -z "$DISTRO_ID" ]] && have lsb_release; then
    DISTRO_ID="$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    DISTRO_VERSION_ID="$(lsb_release -rs 2>/dev/null || true)"
  fi
}

detect_platform() {
  ARCH="$(uname -m)"
  OS="$(uname -s)"
  PLATFORM_FAMILY=""
  PLATFORM_LABEL=""

  case "$OS" in
    Darwin)
      PLATFORM_FAMILY="macos"
      MACOS_VERSION="$(sw_vers -productVersion)"
      PLATFORM_LABEL="macOS $MACOS_VERSION"
      ;;
    Linux)
      PLATFORM_FAMILY="linux"
      detect_linux_release
      if [[ -n "$DISTRO_ID" ]]; then
        PLATFORM_LABEL="Linux ${DISTRO_ID}${DISTRO_VERSION_ID:+ ${DISTRO_VERSION_ID}}"
      else
        PLATFORM_LABEL="Linux"
      fi
      ;;
    *)
      err "Unsupported OS: $OS"
      exit 1
      ;;
  esac
}

is_macos() {
  [[ "${PLATFORM_FAMILY:-}" == "macos" ]]
}

is_linux() {
  [[ "${PLATFORM_FAMILY:-}" == "linux" ]]
}

linux_distro_matches() {
  local token="$1"
  [[ " ${DISTRO_ID:-} ${DISTRO_ID_LIKE:-} " == *" $token "* ]]
}

normalize_strict_platform() {
  local strict_lower
  strict_lower=$(echo "${STRICT_PLATFORM:-false}" | tr '[:upper:]' '[:lower:]')
  case "$strict_lower" in
    true|1|yes|y) STRICT_PLATFORM="true" ;;
    false|0|no|n|"") STRICT_PLATFORM="false" ;;
    *)
      warn "Unknown STRICT_PLATFORM value '${STRICT_PLATFORM:-}'; defaulting to false"
      STRICT_PLATFORM="false"
      ;;
  esac
}

platform_supports_module() {
  local module="$1"
  PLATFORM_SUPPORT_REASON=""

  case "$module" in
    apps)
      if is_linux; then
        PLATFORM_SUPPORT_REASON="GUI app cask installs are currently macOS-only"
        return 1
      fi
      ;;
    macos-defaults)
      if ! is_macos; then
        PLATFORM_SUPPORT_REASON="macOS defaults tuning only applies to macOS"
        return 1
      fi
      ;;
  esac

  return 0
}

handle_unsupported_module() {
  local module="$1"
  local reason="$2"

  if [[ "${STRICT_PLATFORM:-false}" == "true" ]]; then
    err "Module '$module' is not supported on ${PLATFORM_LABEL:-this platform}: $reason"
    exit 1
  fi

  warn "Skipping module '$module' on ${PLATFORM_LABEL:-this platform}: $reason"
  remember_skipped "$module (unsupported: $reason)"
}
