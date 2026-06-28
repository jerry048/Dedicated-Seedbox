# OS, architecture, and runtime feature detection.

if [[ -n "${SEEDBOX_CORE_DETECT_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_DETECT_SOURCED=1

declare -g SEEDBOX_OS_ID=""
declare -g SEEDBOX_OS_NAME=""
declare -g SEEDBOX_OS_VERSION_ID=""
declare -g SEEDBOX_OS_CODENAME=""
declare -g SEEDBOX_ARCH=""
declare -g SEEDBOX_REPO_ARCH=""

detect::load_os() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    SEEDBOX_OS_ID="${ID:-unknown}"
    SEEDBOX_OS_NAME="${NAME:-${ID:-unknown}}"
    SEEDBOX_OS_VERSION_ID="${VERSION_ID:-0}"
    SEEDBOX_OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  else
    SEEDBOX_OS_ID="unknown"
    SEEDBOX_OS_NAME="$(uname -s)"
    SEEDBOX_OS_VERSION_ID="0"
    SEEDBOX_OS_CODENAME=""
  fi
}

detect::version_ge() {
  local have="$1" want="$2"
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --compare-versions "${have}" ge "${want}"
  else
    [[ "$(printf '%s\n%s\n' "${want}" "${have}" | sort -V | head -n1)" == "${want}" ]]
  fi
}

detect::assert_supported_os() {
  detect::load_os
  case "${SEEDBOX_OS_ID}" in
    debian)
      if ! detect::version_ge "${SEEDBOX_OS_VERSION_ID}" "11"; then
        ui::error "Unsupported Debian version: ${SEEDBOX_OS_VERSION_ID}"
        ui::error "Supported Debian versions: 11 or newer, including 12 and 13."
        return 1
      fi
      ;;
    ubuntu)
      if ! detect::version_ge "${SEEDBOX_OS_VERSION_ID}" "20.04"; then
        ui::error "Unsupported Ubuntu version: ${SEEDBOX_OS_VERSION_ID}"
        ui::error "Supported Ubuntu versions: 20.04 or newer, including 24.04 and 26.04."
        return 1
      fi
      ;;
    *)
      ui::error "Unsupported OS: ${SEEDBOX_OS_NAME} (${SEEDBOX_OS_ID})"
      ui::error "Only modern Debian and Ubuntu are supported."
      return 1
      ;;
  esac
}

detect::load_arch() {
  local machine
  machine="$(uname -m)"
  case "${machine}" in
    x86_64|amd64)
      SEEDBOX_ARCH="amd64"
      SEEDBOX_REPO_ARCH="x86_64"
      ;;
    aarch64|arm64)
      SEEDBOX_ARCH="arm64"
      SEEDBOX_REPO_ARCH="ARM64"
      ;;
    *)
      SEEDBOX_ARCH="${machine}"
      SEEDBOX_REPO_ARCH="${machine}"
      ;;
  esac
}

detect::assert_supported_arch() {
  detect::load_arch
  case "${SEEDBOX_ARCH}" in
    amd64|arm64) return 0 ;;
    *)
      ui::error "Unsupported CPU architecture: ${SEEDBOX_ARCH}"
      ui::error "Supported architectures: amd64/x86_64 and arm64/aarch64."
      return 1
      ;;
  esac
}

detect::assert_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    ui::error "This command must be run as root."
    return 1
  fi
}

detect::has_systemd() {
  command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system || -d /etc/systemd/system ]]
}

detect::systemd_runtime_active() {
  command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1
}

detect::virtualization() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt 2>/dev/null || true
  fi
}

detect::default_iface() {
  if command -v ip >/dev/null 2>&1; then
    ip route show default 2>/dev/null | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
  fi
}

detect::public_summary() {
  detect::load_os
  detect::load_arch
  printf 'OS: %s %s (%s)\n' "${SEEDBOX_OS_NAME}" "${SEEDBOX_OS_VERSION_ID}" "${SEEDBOX_OS_CODENAME:-unknown-codename}"
  printf 'Arch: %s\n' "${SEEDBOX_ARCH}"
  printf 'Systemd: %s\n' "$(detect::has_systemd && printf yes || printf no)"
  printf 'Virtualization: %s\n' "$(detect::virtualization || true)"
  printf 'Default interface: %s\n' "$(detect::default_iface || true)"
}
