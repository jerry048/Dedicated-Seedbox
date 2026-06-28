# Docker Engine installer for Debian/Ubuntu using official apt repository by default.

if [[ -n "${SEEDBOX_COMPONENT_DOCKER_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_DOCKER_SOURCED=1

: "${SEEDBOX_DOCKER_SOURCE:=official}"

docker::usage() {
  cat <<'USAGE'
Usage:
  seedboxctl docker install [--docker-source official|distro]
  seedboxctl docker status
  seedboxctl docker uninstall [--purge] [--yes]

The official source uses Docker's apt repository with /etc/apt/keyrings and Signed-By.
The distro source installs docker.io and docker-compose-v2/plugin packages when available.
USAGE
}

docker::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install) args::parse "$@"; log::init docker-install; docker::install_from_parsed ;;
    status) log::init docker-status; docker::status ;;
    uninstall|remove) args::parse "$@"; log::init docker-uninstall; docker::uninstall_from_parsed ;;
    help|-h|--help) docker::usage ;;
    *) ui::error "Unknown docker command: ${sub}"; docker::usage; return 2 ;;
  esac
}

docker::preflight() {
  detect::assert_root
  detect::assert_supported_os
  detect::assert_supported_arch
  apt::available || { ui::error "APT is required for Docker installation."; return 1; }
}

docker::remove_conflicting_packages() {
  local conflicts=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
  local installed=() pkg
  for pkg in "${conflicts[@]}"; do
    apt::package_installed "${pkg}" && installed+=("${pkg}")
  done
  if ((${#installed[@]})); then
    DEBIAN_FRONTEND=noninteractive apt-get remove -y "${installed[@]}"
  fi
}

docker::install_official_repo() {
  detect::load_os
  local os_id="${SEEDBOX_OS_ID}" codename="${SEEDBOX_OS_CODENAME}" arch
  [[ "${os_id}" == "debian" || "${os_id}" == "ubuntu" ]] || return 1
  [[ -n "${codename}" ]] || { ui::error "Could not determine OS codename for Docker repo."; return 1; }
  arch="$(dpkg --print-architecture)"

  apt::ensure_packages ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${os_id}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  fs::write_file /etc/apt/sources.list.d/docker.list 0644 root root <<EOF_REPO
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${os_id} ${codename} stable
EOF_REPO
  apt::update
  apt::install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

docker::install_distro() {
  apt::update
  if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
    apt::install docker.io docker-compose-plugin
  elif apt-cache show docker-compose-v2 >/dev/null 2>&1; then
    apt::install docker.io docker-compose-v2
  else
    apt::install docker.io
  fi
}

docker::enable_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker
  else
    service docker start
  fi
}

docker::install_from_parsed() {
  local source
  source="$(args::get docker_source "${SEEDBOX_DOCKER_SOURCE}")"
  case "${source}" in official|distro) ;; *) ui::error "Invalid --docker-source: ${source}"; return 2 ;; esac

  ui::heading "Installing Docker"
  ui::kv "Source" "${source}"
  ui::log_location
  printf '\n'

  runner::must docker.preflight "Preflight checks" "" docker::preflight || return $?
  if [[ "${source}" == "official" ]]; then
    runner::must docker.conflicts "Remove conflicting Docker packages" "" docker::remove_conflicting_packages || return $?
    if ! runner::run docker.official "Install Docker from official repo" "docker.service" docker::install_official_repo; then
      ui::warn "Official Docker repo install failed. Falling back to distro docker.io."
      runner::must docker.distro "Install Docker from distro repo" "docker.service" docker::install_distro || return $?
    fi
  else
    runner::must docker.distro "Install Docker from distro repo" "docker.service" docker::install_distro || return $?
  fi
  runner::must docker.service "Enable/start Docker" "docker.service" docker::enable_service || return $?
  runner::must docker.state "Save Docker state" "" docker::write_state || return $?
  ui::success "Docker installed. Be aware that Docker-published ports may bypass host firewall tools such as ufw unless explicitly handled."
}

docker::write_state() {
  state::write docker engine <<EOF_STATE
component=docker-engine
source=$(args::get docker_source "${SEEDBOX_DOCKER_SOURCE}")
service=docker.service
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

docker::status() {
  ui::heading "Docker status"
  if command -v docker >/dev/null 2>&1; then
    docker --version || true
    docker compose version || true
  else
    ui::warn "docker command not found."
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl status docker --no-pager -l || true
  fi
}

docker::uninstall_from_parsed() {
  detect::assert_root
  ui::heading "Uninstalling Docker"
  runner::run docker.stop "Stop Docker" "docker.service" systemctl stop docker || true
  runner::run docker.disable "Disable Docker" "docker.service" systemctl disable docker || true
  if args::has purge; then
    args::has yes || { ui::error "Use --yes with --purge for Docker."; return 1; }
    ui::warn "Purge will remove Docker packages and delete Docker runtime data: /var/lib/docker /var/lib/containerd"
    DEBIAN_FRONTEND=noninteractive apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-compose-v2 2>/dev/null || true
    rm -rf /var/lib/docker /var/lib/containerd
  fi
  state::remove docker engine
  ui::success "Docker uninstall completed."
}
