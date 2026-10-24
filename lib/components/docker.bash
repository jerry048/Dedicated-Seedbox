# Docker Engine installer for Debian/Ubuntu using official apt repository by default.

if [[ -n "${SEEDBOX_COMPONENT_DOCKER_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_DOCKER_SOURCED=1

: "${SEEDBOX_DOCKER_SOURCE:=official}"

docker::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl docker install [--docker-source {official|distro}] [OPTIONS]
  seedboxctl docker status [--json] [--check]
  seedboxctl docker logs [OPTIONS]
  seedboxctl docker uninstall [--purge] [--yes]

来源说明：
  official 使用 Docker 官方 APT 仓库，通过 /etc/apt/keyrings 和 Signed-By 校验仓库签名。
  distro 使用发行版的 docker.io，并在可用时安装 docker-compose-v2 或插件软件包。
  移除冲突软件包必须显式使用 --allow-docker-package-removal，--yes 不代表同意移除。

清理说明：
  --purge 需要能连接本机系统 Docker，或已有可验证的未完成清理记录。
  只删除经过校验的 DockerRootDir；保留独立 containerd 软件包及其数据。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl docker install [--docker-source {official|distro}] [OPTIONS]
  seedboxctl docker status [--json] [--check]
  seedboxctl docker logs [OPTIONS]
  seedboxctl docker uninstall [--purge] [--yes]

The official source uses Docker's apt repository with /etc/apt/keyrings and Signed-By.
Removing conflicting packages requires --allow-docker-package-removal, not --yes.
The distro source installs docker.io and docker-compose-v2/plugin packages when available.
Purge requires a reachable local system daemon (or a saved interrupted-purge record).
Only its validated DockerRootDir is deleted; standalone containerd packages/data are kept.
USAGE
  fi
}

docker::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install)
      args::parse_for docker-install "$@" || return $?
      args::has help && {
        docker::usage
        return 0
      }
      log::init docker-install
      docker::install_from_parsed
      ;;
    status)
      args::parse_for status "$@" || return $?
      args::has help && {
        docker::usage
        return 0
      }
      docker::status
      ;;
    uninstall | remove)
      args::parse_for docker-remove "$@" || return $?
      args::has help && {
        docker::usage
        return 0
      }
      log::init docker-uninstall
      docker::uninstall_from_parsed
      ;;
    logs) logs::cli docker "$@" ;;
    help | -h | --help)
      args::parse_for none "$@" || return $?
      docker::usage
      ;;
    *)
      ui::error "Unknown docker command: ${sub}"
      docker::usage
      return 2
      ;;
  esac
}

docker::preflight() {
  detect::assert_root || return $?
  detect::assert_supported_os || return $?
  detect::assert_supported_arch || return $?
  apt::available || {
    ui::error "APT is required for Docker installation."
    return 1
  }
}

docker::remove_conflicting_packages() {
  local conflicts=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
  local installed=() pkg
  for pkg in "${conflicts[@]}"; do
    apt::package_installed "${pkg}" && installed+=("${pkg}")
  done
  if ((${#installed[@]})); then
    args::has allow_docker_package_removal || {
      ui::error "Conflicting packages: ${installed[*]}. Explicitly pass --allow-docker-package-removal (not --yes)."
      return 2
    }
    DEBIAN_FRONTEND=noninteractive apt-get remove -y "${installed[@]}" || return $?
  fi
}

docker::install_official_repo() {
  detect::load_os
  local os_id="${SEEDBOX_OS_ID}" codename="${SEEDBOX_OS_CODENAME}" arch
  [[ "${os_id}" == "debian" || "${os_id}" == "ubuntu" ]] || return 1
  [[ -n "${codename}" ]] || {
    ui::error "Could not determine OS codename for Docker repo."
    return 1
  }
  arch="$(dpkg --print-architecture)"

  apt::ensure_packages ca-certificates curl gnupg || return $?
  install -m 0755 -d /etc/apt/keyrings || return $?
  local key
  key="$(mktemp /etc/apt/keyrings/.docker.XXXXXX)" || return $?
  if ! curl -fsSL "https://download.docker.com/linux/${os_id}/gpg" -o "${key}"; then
    rm -f -- "${key}"
    return 1
  fi
  chmod 0644 "${key}" || {
    rm -f -- "${key}"
    return 1
  }
  mv -Tf -- "${key}" /etc/apt/keyrings/docker.asc || {
    rm -f -- "${key}"
    return 1
  }

  fs::write_file /etc/apt/sources.list.d/docker.list 0644 root root <<EOF_REPO || return $?
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${os_id} ${codename} stable
EOF_REPO
  apt::update || return $?
  apt::install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

docker::install_distro() {
  apt::update || return $?
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
  case "${source}" in official | distro) ;; *)
    ui::error "Invalid --docker-source: ${source}"
    return 2
    ;;
  esac

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
      source=distro
    fi
  else
    runner::must docker.distro "Install Docker from distro repo" "docker.service" docker::install_distro || return $?
  fi
  runner::must docker.service "Enable/start Docker" "docker.service" docker::enable_service || return $?
  runner::must docker.state "Save Docker state" "" docker::write_state "${source}" || return $?
  ui::success "Docker installed. Be aware that Docker-published ports may bypass host firewall tools such as ufw unless explicitly handled."
}

docker::write_state() {
  local source="${1:-}"
  case "${source}" in official | distro) ;; *)
    ui::error "Missing or invalid installed Docker source."
    return 2
    ;;
  esac
  state::write docker engine <<EOF_STATE
component=docker-engine
source=${source}
service=docker.service
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

docker::status() {
  status::component docker
}

docker::purge_root() {
  local root pending identity
  # Never use DOCKER_HOST/contexts: this command removes local system packages.
  if command -v docker >/dev/null 2>&1 && root="$(docker --host unix:///var/run/docker.sock info --format '{{.DockerRootDir}}' 2>/dev/null)" && [[ -n "${root}" ]]; then
    printf '%s\n' "${root}"
    return 0
  fi
  pending="$(state::path docker purge)" || return $?
  if [[ -f "${pending}" && ! -L "${pending}" ]]; then
    root="$(state::get "${pending}" data_root)" || return $?
    identity="$(state::get "${pending}" data_identity)" || return $?
    if [[ -n "${root}" && "${identity}" =~ ^([0-9]+:[0-9]+|absent)$ ]]; then
      fs::safety check-docker "${root}" "${identity}" || return $?
      printf '%s\n' "${root}"
      return 0
    fi
  fi
  ui::error "Cannot determine the local Docker data root. Start the system daemon and retry; no default-directory deletion will be attempted."
  return 1
}

docker::stop_local_engine() {
  local units
  units="$(systemctl list-unit-files --all --no-legend --no-pager docker.socket docker.service)" || return $?
  if grep -q '^docker\.socket[[:space:]]' <<<"${units}"; then
    systemctl stop docker.socket || return $?
    systemctl disable docker.socket || return $?
  fi
  if grep -q '^docker\.service[[:space:]]' <<<"${units}"; then
    systemctl stop docker.service || return $?
    systemctl disable docker.service || return $?
  fi
  docker::assert_stopped
}

docker::assert_stopped() {
  local rc=0
  pgrep -x dockerd >/dev/null 2>&1 || rc=$?
  [[ "${rc}" == 1 ]] || {
    ui::error "Cannot prove dockerd is stopped; refusing data deletion."
    return 1
  }
}

docker::purge_packages() {
  local package status rc
  local -a packages=()
  # Distro-only hosts may not even know the official package names. Include
  # installed/partially installed packages and residual config, not unknowns.
  for package in docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin docker.io docker-compose-v2; do
    rc=0
    status="$(dpkg-query -W -f='${db:Status-Status}' "${package}" 2>/dev/null)" || rc=$?
    ((rc <= 1)) || return "${rc}"
    case "${status}" in installed | config-files | unpacked | half-configured | half-installed | triggers-awaited | triggers-pending) packages+=("${package}") ;; esac
  done
  if ((${#packages[@]})); then
    apt::wait_for_dpkg 120 || return $?
    DEBIAN_FRONTEND=noninteractive apt-get purge -y "${packages[@]}" || return $?
  fi
}

docker::uninstall_from_parsed() {
  local data_root data_identity
  detect::assert_root || return $?
  ui::heading "Uninstalling Docker"
  if args::has purge; then
    args::has yes || {
      ui::error "Use --yes with --purge for Docker."
      return 1
    }
    data_root="$(docker::purge_root)" || return $?
    fs::safety check-docker "${data_root}" || return $?
    data_identity=absent
    if [[ -e "${data_root}" ]]; then
      data_identity="$(stat -c '%d:%i' -- "${data_root}")" || return $?
    fi
    ui::warn "$(ui::tr "清理将删除 Docker 软件包及已验证的数据目录：${data_root}；保留独立 containerd 软件包和数据。" "Purge will remove Docker packages and the validated data root: ${data_root}; standalone containerd packages and data are kept.")"
  fi
  runner::must docker.stop "Stop/disable local Docker service and socket" "docker.service" docker::stop_local_engine || return $?
  if args::has purge; then
    state::write docker purge <<EOF_STATE || return $?
component=docker-purge
data_root=${data_root}
data_identity=${data_identity}
EOF_STATE
    docker::purge_packages || return $?
    # Recheck paths/mounts/layout after packages have been removed.
    docker::assert_stopped || return $?
    fs::safety remove-docker "${data_root}" "${data_identity}" || return $?
    state::remove docker purge || return $?
  fi
  state::remove docker engine || return $?
  ui::success "Docker uninstall completed."
}
