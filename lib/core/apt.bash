# APT helpers with noninteractive defaults.

if [[ -n "${SEEDBOX_CORE_APT_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_APT_SOURCED=1

apt::available() {
  command -v apt-get >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1
}

apt::package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

apt::wait_for_dpkg() {
  local waited=0 max_wait="${1:-120}"
  while command -v fuser >/dev/null 2>&1 && fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if (( waited >= max_wait )); then
      ui::error "APT/dpkg lock is still held after ${max_wait}s."
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

apt::update() {
  apt::available || { ui::error "apt-get/dpkg-query not found"; return 1; }
  apt::wait_for_dpkg 120
  DEBIAN_FRONTEND=noninteractive apt-get update -y
}

apt::install() {
  apt::available || { ui::error "apt-get/dpkg-query not found"; return 1; }
  apt::wait_for_dpkg 120
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt::ensure_packages() {
  local missing=() pkg
  for pkg in "$@"; do
    if ! apt::package_installed "${pkg}"; then
      missing+=("${pkg}")
    fi
  done
  if ((${#missing[@]})); then
    apt::install "${missing[@]}"
  fi
}

apt::ensure_base() {
  apt::ensure_packages ca-certificates curl wget iproute2 procps coreutils
}
