if [[ -n "${SEEDBOX_COMPONENT_BBR_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_BBR_SOURCED=1

: "${SEEDBOX_BBR_INSTALLER_URL:=https://raw.githubusercontent.com/jerry048/Trove/refs/heads/main/BBR-Install/BBRInstall.sh}"
: "${SEEDBOX_BBR_RAW_BASE:=https://raw.githubusercontent.com/jerry048/Trove/refs/heads/main/BBR-Install/BBR}"
: "${SEEDBOX_BBR_SYSCTL_DROPIN:=/etc/sysctl.d/90-seedbox-bbr.conf}"
: "${SEEDBOX_BBR_MODULES_LOAD_DROPIN:=/etc/modules-load.d/90-seedbox-bbr.conf}"
: "${SEEDBOX_BBR_LOCAL_INSTALLER:=${SEEDBOX_ROOT}/lib/components/bbr/BBRInstall.sh}"
: "${SEEDBOX_BBR_AUTO_GENERIC_KERNEL:=1}"

declare -g BBR_ALGO=""
declare -g BBR_INSTALLER_URL=""
declare -g BBR_INSTALLER_SHA256=""
declare -g BBR_RAW_BASE=""
declare -g BBR_LANG=""
declare -g BBR_WORK_DIR=""
declare -g BBR_SCRIPT=""
declare -g BBR_GENERIC_KERNEL_INSTALLED=0

bbr::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl bbr install --bbr-algo ALGO [选项]
  seedboxctl bbr uninstall [--bbr-algo ALGO]
  seedboxctl bbr status

算法：
  bbrv3         从 Trove/BBR-Install 安装预编译 BBRv3 内核包，需要重启。
  bbrx          DKMS 模块：tcp_bbrx
  bbrw          DKMS 模块：tcp_bbrw
  bbr_brutal    DKMS 模块：tcp_bbr_brutal
  bbrw_brutal   DKMS 模块：tcp_bbrw_brutal

选项：
  --bbr-script-url URL       覆盖 Trove BBRInstall.sh 地址
  --bbr-script-sha256 SHA    可选：运行前校验安装脚本 SHA-256
  --bbr-raw-base URL         覆盖 Trove BBR 资源目录
  --bbr-lang LANG            传递给 BBRInstall.sh 的语言参数（若脚本支持）
  --allow-unverified-bbr-installer
  --force-runtime            传递 --force-runtime 给 Trove 安装器
  --upgrade-system           若安装器支持，则传递 --upgrade-system
  --no-clear                 若安装器支持，则传递 --no-clear

说明：
  对 DKMS 类 BBR 算法，如果当前内核头文件本地不存在，且 apt 也无法安装 linux-headers-$(uname -r)，
  Seedbox 会自动安装发行版通用 kernel image 与 headers，然后提示你重启后重新运行 BBR 安装。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl bbr install --bbr-algo ALGO [options]
  seedboxctl bbr uninstall [--bbr-algo ALGO]
  seedboxctl bbr status

Algorithms:
  bbrv3         Prebuilt BBRv3 kernel package path from Trove/BBR-Install. Reboot required.
  bbrx          DKMS module: tcp_bbrx
  bbrw          DKMS module: tcp_bbrw
  bbr_brutal    DKMS module: tcp_bbr_brutal
  bbrw_brutal   DKMS module: tcp_bbrw_brutal

Options:
  --bbr-script-url URL       Override Trove BBRInstall.sh URL
  --bbr-script-sha256 SHA    Optional: verify installer script checksum before running
  --bbr-raw-base URL         Override Trove BBR payload base URL
  --bbr-lang LANG            Pass language to BBRInstall.sh when supported
  --allow-unverified-bbr-installer
  --force-runtime            Pass --force-runtime to Trove installer
  --upgrade-system           Pass --upgrade-system when supported by the installer
  --no-clear                 Pass --no-clear when supported by the installer

Notes:
  For DKMS BBR algorithms, if running-kernel headers are missing locally and apt cannot
  install linux-headers-$(uname -r), Seedbox automatically installs the distribution
  generic kernel image and headers, then asks you to reboot and rerun the BBR install.
USAGE
  fi
}

bbr::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install|apply|enable)
      args::parse "$@"
      args::has help && { bbr::usage; return 0; }
      log::init bbr-install
      bbr::install_from_parsed
      ;;
    uninstall|remove|disable)
      args::parse "$@"
      args::has help && { bbr::usage; return 0; }
      log::init bbr-uninstall
      bbr::uninstall_from_parsed
      ;;
    status)
      log::init bbr-status
      bbr::status
      ;;
    help|-h|--help)
      bbr::usage
      ;;
    *)
      ui::error "Unknown bbr command: ${sub}"
      bbr::usage
      return 2
      ;;
  esac
}

bbr::validate_algo() {
  case "$1" in
    bbrv3|bbrx|bbrw|bbr_brutal|bbrw_brutal) return 0 ;;
    *) ui::error "Unsupported BBR algorithm: $1"; return 2 ;;
  esac
}

bbr::load_args() {
  args::copy_value_alias bbr_algo algo
  BBR_ALGO="$(args::get bbr_algo)"
  BBR_INSTALLER_URL="$(args::get bbr_script_url "${SEEDBOX_BBR_INSTALLER_URL}")"
  BBR_INSTALLER_SHA256="$(args::get bbr_script_sha256 "${SEEDBOX_BBR_SCRIPT_SHA256:-}")"
  BBR_RAW_BASE="$(args::get bbr_raw_base "${SEEDBOX_BBR_RAW_BASE}")"
  BBR_LANG="$(args::get bbr_lang "${SEEDBOX_BBR_LANG:-}")"
  BBR_WORK_DIR="$(mktemp -d -t seedbox-bbr.XXXXXX)"
  BBR_SCRIPT="${BBR_WORK_DIR}/BBRInstall.sh"

  [[ -n "${BBR_ALGO}" ]] || { ui::error "Missing --bbr-algo"; return 2; }
  bbr::validate_algo "${BBR_ALGO}"
}

bbr::preflight() {
  detect::assert_root || return $?
  detect::assert_supported_os || return $?
  command -v bash >/dev/null 2>&1 || { ui::error "bash is required"; return 1; }
  command -v sha256sum >/dev/null 2>&1 || { ui::error "sha256sum is required"; return 1; }
  if [[ "${BBR_INSTALLER_URL}" == *'/main/'* || "${BBR_INSTALLER_URL}" == *'/refs/heads/main/'* ]]; then
    ui::warn "BBR installer URL uses a moving main branch. Pin --bbr-script-url and --bbr-raw-base to a commit for production."
  fi
}

bbr::download_installer() {
  local old_allow="${SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS:-0}" rc

  if [[ -r "${BBR_INSTALLER_URL}" ]]; then
    cp -f -- "${BBR_INSTALLER_URL}" "${BBR_SCRIPT}"
    chmod 0700 "${BBR_SCRIPT}" || return $?
    return 0
  fi

  if [[ -z "${BBR_INSTALLER_SHA256}" ]]; then
    export SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1
  fi
  download::fetch "${BBR_INSTALLER_URL}" "${BBR_SCRIPT}" "${BBR_INSTALLER_SHA256}" || {
    rc=$?
    export SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS="${old_allow}"
    if [[ "${BBR_INSTALLER_URL}" == "${SEEDBOX_BBR_INSTALLER_URL}" && -z "${BBR_INSTALLER_SHA256}" && -r "${SEEDBOX_BBR_LOCAL_INSTALLER}" ]]; then
      ui::warn "Could not download BBRInstall.sh; using bundled fallback: ${SEEDBOX_BBR_LOCAL_INSTALLER}"
      cp -f -- "${SEEDBOX_BBR_LOCAL_INSTALLER}" "${BBR_SCRIPT}"
      chmod 0700 "${BBR_SCRIPT}" || return $?
      return 0
    fi
    return "${rc}"
  }
  export SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS="${old_allow}"
  chmod 0700 "${BBR_SCRIPT}" || return $?
}

bbr::installer_supports_option() {
  local opt="$1"
  [[ -r "${BBR_SCRIPT}" ]] || return 1
  grep -q -- "${opt}" "${BBR_SCRIPT}"
}

bbr::run_installer() {
  local -a cmd
  local installer_lang="${BBR_LANG}"
  cmd=(bash "${BBR_SCRIPT}" --algo "${BBR_ALGO}" --raw-base "${BBR_RAW_BASE}")
  args::has force_runtime && cmd+=(--force-runtime)

  if [[ -n "${installer_lang}" ]]; then
    case "${installer_lang,,}" in
      zh|zh-cn|zh_hans|zh-hans|cn|simplified|simplified-chinese)
        if grep -q -- 'zh-CN' "${BBR_SCRIPT}"; then
          installer_lang="zh-CN"
        elif grep -q -- 'zh-TW' "${BBR_SCRIPT}"; then
          ui::warn "Downloaded BBR installer does not advertise Simplified Chinese; using zh-TW for the BBR subprocess only."
          installer_lang="zh-TW"
        fi
        ;;
    esac
    if bbr::installer_supports_option '--lang'; then
      cmd+=(--lang "${installer_lang}")
    else
      ui::warn "Downloaded BBR installer does not support --lang; continuing without it."
      installer_lang=""
    fi
  fi
  if args::has upgrade_system; then
    if bbr::installer_supports_option '--upgrade-system'; then
      cmd+=(--upgrade-system)
    else
      ui::warn "Downloaded BBR installer does not support --upgrade-system; continuing without it."
    fi
  fi
  if args::has no_clear; then
    if bbr::installer_supports_option '--no-clear'; then
      cmd+=(--no-clear)
    else
      ui::warn "Downloaded BBR installer does not support --no-clear; continuing without it."
    fi
  fi

  if [[ -n "${installer_lang}" ]]; then
    BBR_SYSCTL_DROPIN="${SEEDBOX_BBR_SYSCTL_DROPIN}"     BBR_MODULES_LOAD_DROPIN="${SEEDBOX_BBR_MODULES_LOAD_DROPIN}"     BBR_LANG="${installer_lang}"     "${cmd[@]}"
  else
    BBR_SYSCTL_DROPIN="${SEEDBOX_BBR_SYSCTL_DROPIN}"     BBR_MODULES_LOAD_DROPIN="${SEEDBOX_BBR_MODULES_LOAD_DROPIN}"     "${cmd[@]}"
  fi
}

bbr::is_dkms_algo() {
  [[ "${BBR_ALGO}" != "bbrv3" ]]
}

bbr::running_kernel_headers_usable() {
  local kernel build_dir headers_dir
  kernel="$(uname -r)"
  build_dir="/lib/modules/${kernel}/build"
  headers_dir="/usr/src/linux-headers-${kernel}"

  if [[ ! -e "${build_dir}" && -d "${headers_dir}" ]]; then
    mkdir -p -- "/lib/modules/${kernel}"
    ln -s -- "${headers_dir}" "${build_dir}" 2>/dev/null || true
  fi
  [[ -e "${build_dir}/Makefile" ]]
}

bbr::resolve_generic_kernel_packages() {
  detect::load_os
  detect::load_arch
  case "${SEEDBOX_OS_ID}" in
    debian)
      case "${SEEDBOX_ARCH}" in
        amd64) printf '%s\n%s\n' linux-image-amd64 linux-headers-amd64 ;;
        arm64) printf '%s\n%s\n' linux-image-arm64 linux-headers-arm64 ;;
        *) return 1 ;;
      esac
      ;;
    ubuntu)
      printf '%s\n%s\n' linux-image-generic linux-headers-generic
      ;;
    *)
      return 1
      ;;
  esac
}

bbr::prepare_dkms_headers_or_generic_kernel() {
  bbr::is_dkms_algo || return 0
  [[ "${SEEDBOX_BBR_AUTO_GENERIC_KERNEL}" == "1" ]] || return 0

  local kernel generic_output image_pkg headers_pkg
  local -a generic_packages=()
  kernel="$(uname -r)"

  if bbr::running_kernel_headers_usable; then
    ui::info "Detected running-kernel headers for ${kernel}."
    return 0
  fi

  ui::warn "Running-kernel headers are missing: linux-headers-${kernel}. Trying apt first."
  apt::update || return $?
  if apt::install "linux-headers-${kernel}"; then
    if bbr::running_kernel_headers_usable; then
      ui::info "Installed running-kernel headers for ${kernel}."
      return 0
    fi
    ui::warn "linux-headers-${kernel} was installed or attempted, but /lib/modules/${kernel}/build is still not usable for DKMS."
  else
    ui::warn "apt could not install linux-headers-${kernel}."
  fi

  if ! generic_output="$(bbr::resolve_generic_kernel_packages)"; then
    ui::error "Could not resolve a distribution generic kernel image/header package for this OS/architecture."
    return 1
  fi
  mapfile -t generic_packages <<<"${generic_output}"
  image_pkg="${generic_packages[0]:-}"
  headers_pkg="${generic_packages[1]:-}"
  [[ -n "${image_pkg}" && -n "${headers_pkg}" ]] || { ui::error "Could not resolve generic kernel package names."; return 1; }

  ui::warn "Installing generic kernel image and headers automatically: ${image_pkg} ${headers_pkg}"
  apt::install "${image_pkg}" "${headers_pkg}" || return $?
  if command -v update-grub >/dev/null 2>&1; then
    update-grub || ui::warn "update-grub failed; check bootloader configuration before rebooting."
  fi
  BBR_GENERIC_KERNEL_INSTALLED=1
  return 0
}

bbr::write_pending_generic_kernel_state() {
  state::write bbr default <<EOF_STATE
component=bbr
algo=${BBR_ALGO}
status=generic-kernel-installed
reason=missing-running-kernel-headers
installer_url=${BBR_INSTALLER_URL}
raw_base=${BBR_RAW_BASE}
sysctl=${SEEDBOX_BBR_SYSCTL_DROPIN}
modules_load=${SEEDBOX_BBR_MODULES_LOAD_DROPIN}
updated_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

bbr::write_state() {
  state::write bbr default <<EOF_STATE
component=bbr
algo=${BBR_ALGO}
status=installed
installer_url=${BBR_INSTALLER_URL}
raw_base=${BBR_RAW_BASE}
sysctl=${SEEDBOX_BBR_SYSCTL_DROPIN}
modules_load=${SEEDBOX_BBR_MODULES_LOAD_DROPIN}
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

bbr::install_from_parsed() {
  bbr::load_args || return $?
  ui::heading "Installing BBR congestion-control variant"
  ui::kv "Algorithm" "${BBR_ALGO}"
  ui::kv "Installer" "${BBR_INSTALLER_URL}"
  ui::log_location
  printf '\n'

  runner::must bbr.preflight "Preflight BBR installer" "" bbr::preflight || return $?
  runner::must bbr.headers "Prepare DKMS kernel headers" "" bbr::prepare_dkms_headers_or_generic_kernel || return $?
  if [[ "${BBR_GENERIC_KERNEL_INSTALLED}" == "1" ]]; then
    runner::must bbr.state "Save pending BBR state" "" bbr::write_pending_generic_kernel_state || return $?
    ui::warn "A generic kernel image and headers were installed because headers for the running kernel were unavailable. Reboot into the new generic kernel, then rerun the BBR install for ${BBR_ALGO}."
    ui::success "Generic kernel/header fallback completed for ${BBR_ALGO}; BBR module installation is pending until after reboot."
    return 0
  fi
  runner::must bbr.download "Download BBR installer" "" bbr::download_installer || return $?
  runner::must bbr.install "Run BBR installer" "" bbr::run_installer || return $?
  runner::must bbr.state "Save BBR state" "" bbr::write_state || return $?

  if [[ "${BBR_ALGO}" == "bbrv3" ]]; then
    ui::warn "BBRv3 kernel package installation requires a reboot before it can become active."
  fi
  ui::success "BBR installation flow completed for ${BBR_ALGO}."
}

bbr::state_algo() {
  local path
  path="$(state::path bbr default)"
  if [[ -r "${path}" ]]; then
    state::get "${path}" algo
  fi
}

bbr::uninstall_dkms_algo() {
  local algo="$1" version_dir version module="tcp_${algo}"
  if command -v dkms >/dev/null 2>&1 && [[ -d "/var/lib/dkms/${algo}" ]]; then
    for version_dir in "/var/lib/dkms/${algo}"/*; do
      [[ -d "${version_dir}" ]] || continue
      version="$(basename -- "${version_dir}")"
      dkms remove -m "${algo}" -v "${version}" --all || true
    done
  fi
  if [[ -r /proc/sys/net/ipv4/tcp_available_congestion_control ]] && grep -qw cubic /proc/sys/net/ipv4/tcp_available_congestion_control; then
    sysctl -w net.ipv4.tcp_congestion_control=cubic || true
  fi
  modprobe -r "${module}" 2>/dev/null || true
  depmod -a 2>/dev/null || true
}

bbr::uninstall_from_parsed() {
  detect::assert_root
  args::copy_value_alias bbr_algo algo
  local algo
  algo="$(args::get bbr_algo "$(bbr::state_algo)")"
  [[ -n "${algo}" ]] || { ui::error "No BBR state found. Pass --bbr-algo to remove a DKMS variant."; return 2; }
  bbr::validate_algo "${algo}"

  ui::heading "Uninstalling BBR configuration"
  ui::kv "Algorithm" "${algo}"
  ui::log_location
  printf '\n'

  if [[ "${algo}" == "bbrv3" ]]; then
    ui::warn "BBRv3 installed a kernel package. This command removes Seedbox-managed sysctl files only."
    ui::warn "Boot a known-good distro kernel, inspect dpkg -l 'linux-image*' 'linux-headers*' | grep -i bbr, then purge the specific BBR kernel packages manually."
  else
    runner::run bbr.dkms_remove "Remove DKMS module if present" "" bbr::uninstall_dkms_algo "${algo}" || true
  fi

  rm -f -- "${SEEDBOX_BBR_SYSCTL_DROPIN}" "${SEEDBOX_BBR_MODULES_LOAD_DROPIN}"
  state::remove bbr default
  ui::success "Seedbox-managed BBR configuration removed. A reboot may be required to fully revert kernel state."
}

bbr::status() {
  ui::heading "BBR status"
  if [[ -r /proc/sys/net/ipv4/tcp_congestion_control ]]; then
    ui::kv "Active" "$(cat /proc/sys/net/ipv4/tcp_congestion_control)"
  fi
  if [[ -r /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
    ui::kv "Available" "$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)"
  fi
  if command -v dkms >/dev/null 2>&1; then
    printf '\nDKMS:\n'
    dkms status 2>/dev/null | grep -E 'bbrx|bbrw|bbr_brutal|bbrw_brutal' || true
  fi
  printf '\nModules:\n'
  lsmod 2>/dev/null | grep -E '^tcp_(bbrx|bbrw|bbr_brutal|bbrw_brutal)' || true
  printf '\nManaged files:\n'
  ls -l "${SEEDBOX_BBR_SYSCTL_DROPIN}" "${SEEDBOX_BBR_MODULES_LOAD_DROPIN}" 2>/dev/null || true
}
