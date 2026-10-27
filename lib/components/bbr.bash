if [[ -n "${SEEDBOX_COMPONENT_BBR_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_BBR_SOURCED=1

readonly SEEDBOX_BBR_DEFAULT_INSTALLER_URL='https://raw.githubusercontent.com/jerry048/Trove/refs/heads/main/BBR-Install/BBRInstall.sh'
: "${SEEDBOX_BBR_INSTALLER_URL:=${SEEDBOX_BBR_DEFAULT_INSTALLER_URL}}"
: "${SEEDBOX_BBR_RAW_BASE:=https://raw.githubusercontent.com/jerry048/Trove/refs/heads/main/BBR-Install/BBR}"
: "${SEEDBOX_BBR_SYSCTL_DROPIN:=/etc/sysctl.d/90-seedbox-bbr.conf}"
: "${SEEDBOX_BBR_MODULES_LOAD_DROPIN:=/etc/modules-load.d/90-seedbox-bbr.conf}"
: "${SEEDBOX_BBR_LOCAL_INSTALLER:=${SEEDBOX_ROOT}/lib/components/bbr/BBRInstall.sh}"
: "${SEEDBOX_BBR_AUTO_GENERIC_KERNEL:=1}"
# SHA-256 of this release's bundled installer (not of remote raw-base payloads).
readonly SEEDBOX_BBR_BUNDLED_SHA256='a68bdfbaf4ac46fe82f3b4b2f66df514627c16a8dd7e7c811009771068c2dcfd'
declare -g BBR_WORK_ID=""
declare -g BBR_USE_BUNDLED=0

declare -g BBR_ALGO=""
declare -g BBR_INSTALLER_URL=""
declare -g BBR_INSTALLER_SHA256=""
declare -g BBR_RAW_BASE=""
declare -g BBR_LANG=""
declare -g BBR_WORK_DIR=""
declare -g BBR_SCRIPT=""
declare -g BBR_GENERIC_KERNEL_INSTALLED=0
declare -g BBR_KERNEL_RELEASE=""
declare -g BBR_KERNEL_RESULT_FILE=""

bbr::usage() {
  printf '%s\n' "$(ui::tr '默认使用经 SHA-256 校验的随附安装器。自定义安装器需 SHA-256 或明确 --allow-unverified-bbr-installer；生产环境建议将 --bbr-raw-base 固定到提交。' 'The default bundled installer is SHA-256 verified. Custom installers need SHA-256 or explicit --allow-unverified-bbr-installer; pin --bbr-raw-base to a commit for production.')"
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl bbr install --bbr-algo ALGO [OPTIONS]
  seedboxctl bbr uninstall [--bbr-algo ALGO]
  seedboxctl bbr status [--json] [--check]
  seedboxctl bbr logs [OPTIONS]

算法：
  bbrv3         从 Trove/BBR-Install 安装预编译 BBRv3 内核包，需要重启。
  bbrx          DKMS 模块：tcp_bbrx
  bbrx_old      旧版 BBRx（保留 STARTUP 缺陷），兼容层模块：tcp_bbrx_old
  bbrw          DKMS 模块：tcp_bbrw
  bbr_brutal    DKMS 模块：tcp_bbr_brutal
  bbrw_brutal   DKMS 模块：tcp_bbrw_brutal

选项：
  --bbr-script-url URL       覆盖 Trove BBRInstall.sh 地址
  --bbr-script-sha256 SHA256  安装脚本校验和；不验证时需单独明确授权
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
  seedboxctl bbr install --bbr-algo ALGO [OPTIONS]
  seedboxctl bbr uninstall [--bbr-algo ALGO]
  seedboxctl bbr status [--json] [--check]
  seedboxctl bbr logs [OPTIONS]

Algorithms:
  bbrv3         Prebuilt BBRv3 kernel package path from Trove/BBR-Install. Reboot required.
  bbrx          DKMS module: tcp_bbrx
  bbrx_old      Legacy BBRx (STARTUP bug preserved), compatibility module: tcp_bbrx_old
  bbrw          DKMS module: tcp_bbrw
  bbr_brutal    DKMS module: tcp_bbr_brutal
  bbrw_brutal   DKMS module: tcp_bbrw_brutal

Options:
  --bbr-script-url URL       Override Trove BBRInstall.sh URL
  --bbr-script-sha256 SHA256  Installer checksum; unverified execution needs separate opt-in
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
    install | apply | enable)
      args::parse_for bbr-install "$@" || return $?
      args::has help && {
        bbr::usage
        return 0
      }
      log::init bbr-install
      bbr::install_from_parsed
      ;;
    uninstall | remove | disable)
      args::parse_for bbr-remove "$@" || return $?
      args::has help && {
        bbr::usage
        return 0
      }
      log::init bbr-uninstall
      bbr::uninstall_from_parsed
      ;;
    status)
      args::parse_for status "$@" || return $?
      args::has help && {
        bbr::usage
        return 0
      }
      bbr::status
      ;;
    logs) logs::cli bbr "$@" ;;
    help | -h | --help)
      args::parse_for none "$@" || return $?
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
    bbrv3 | bbrx | bbrx_old | bbrw | bbr_brutal | bbrw_brutal) return 0 ;;
    *)
      ui::error "Unsupported BBR algorithm: $1"
      return 2
      ;;
  esac
}

bbr::load_args() {
  args::copy_value_alias bbr_algo algo
  BBR_ALGO="$(args::get bbr_algo)"
  BBR_INSTALLER_URL="$(args::get bbr_script_url "${SEEDBOX_BBR_INSTALLER_URL}")"
  BBR_INSTALLER_SHA256="$(args::get bbr_script_sha256 "${SEEDBOX_BBR_SCRIPT_SHA256:-}")"
  BBR_RAW_BASE="$(args::get bbr_raw_base "${SEEDBOX_BBR_RAW_BASE}")"
  BBR_LANG="$(args::get bbr_lang "${SEEDBOX_BBR_LANG:-}")"
  BBR_WORK_DIR="" BBR_SCRIPT="" BBR_WORK_ID="" BBR_USE_BUNDLED=0
  BBR_GENERIC_KERNEL_INSTALLED=0 BBR_KERNEL_RELEASE="" BBR_KERNEL_RESULT_FILE=""
  if ! args::has bbr_script_url && [[ "${BBR_INSTALLER_URL}" == "${SEEDBOX_BBR_DEFAULT_INSTALLER_URL}" ]]; then
    BBR_USE_BUNDLED=1
    BBR_INSTALLER_URL="${SEEDBOX_BBR_LOCAL_INSTALLER}"
  fi

  [[ -n "${BBR_ALGO}" ]] || {
    ui::error "Missing --bbr-algo"
    return 2
  }
  bbr::validate_algo "${BBR_ALGO}"
}

bbr::preflight() {
  detect::assert_root || return $?
  detect::assert_supported_os || return $?
  if ! args::has force_runtime; then
    local runtime
    runtime="$(detect::virtualization)"
    case "${runtime}" in docker | podman | lxc | lxc-libvirt | openvz | systemd-nspawn | wsl | proot)
      ui::error "BBR requires a host/full VM; use --force-runtime only after reviewing the risk."
      return 2
      ;;
    esac
    if [[ -e /.dockerenv || -e /run/.containerenv ]] || grep -qi microsoft /proc/sys/kernel/osrelease; then
      ui::error "BBR refuses container/WSL package changes without --force-runtime."
      return 2
    fi
  fi
  command -v bash >/dev/null 2>&1 || {
    ui::error "bash is required"
    return 1
  }
  command -v sha256sum >/dev/null 2>&1 || {
    ui::error "sha256sum is required"
    return 1
  }
  [[ -z "${BBR_INSTALLER_SHA256}" || "${BBR_INSTALLER_SHA256}" =~ ^[[:xdigit:]]{64}$ ]] || {
    ui::error "Invalid explicitly supplied BBR installer SHA-256."
    return 2
  }
  if [[ "${BBR_USE_BUNDLED}" == 1 ]]; then
    bbr::verify_installer "${SEEDBOX_BBR_LOCAL_INSTALLER}" "${SEEDBOX_BBR_BUNDLED_SHA256}" || return $?
    if [[ -n "${BBR_INSTALLER_SHA256}" ]]; then bbr::verify_installer "${SEEDBOX_BBR_LOCAL_INSTALLER}" "${BBR_INSTALLER_SHA256}" || return $?; fi
    detect::load_os || return $?
    case "${SEEDBOX_OS_ID}:${SEEDBOX_OS_VERSION_ID:-}" in
      debian:11 | debian:11.* | debian:12 | debian:12.* | debian:13 | debian:13.* | ubuntu:20.04* | ubuntu:22.04* | ubuntu:24.04* | ubuntu:26.04*) ;;
      *)
        ui::error "The bundled BBR installer supports Debian 11/12/13 and Ubuntu 20.04/22.04/24.04/26.04 only."
        return 2
        ;;
    esac
    if [[ "${BBR_ALGO}" == bbrv3 && "${SEEDBOX_OS_ID}:${SEEDBOX_OS_VERSION_ID:-}" == ubuntu:20.04* ]]; then
      ui::error "No bundled BBRv3 kernel package is configured for Ubuntu 20.04; choose a DKMS variant."
      return 2
    fi
  fi
  if [[ "${BBR_USE_BUNDLED}" != 1 && -z "${BBR_INSTALLER_SHA256}" ]] && ! args::has allow_unverified_bbr_installer; then
    ui::error "Use --bbr-script-sha256 or explicitly --allow-unverified-bbr-installer."
    return 2
  fi
  if [[ "${BBR_INSTALLER_URL}" == *'/main/'* || "${BBR_INSTALLER_URL}" == *'/refs/heads/main/'* ]]; then
    ui::warn "BBR installer URL uses a moving main branch. Pin --bbr-script-url and --bbr-raw-base to a commit for production."
  fi
}

bbr::create_workdir() {
  BBR_WORK_DIR="$(mktemp -d /tmp/seedbox-bbr.XXXXXX)" || return $?
  [[ -n "${BBR_WORK_DIR}" && -d "${BBR_WORK_DIR}" ]] || return 1
  BBR_WORK_ID="$(stat -c '%d:%i' -- "${BBR_WORK_DIR}")" || return $?
  BBR_SCRIPT="${BBR_WORK_DIR}/BBRInstall.sh"
  BBR_KERNEL_RESULT_FILE="${BBR_WORK_DIR}/kernel-release"
}

bbr::cleanup_workdir() {
  [[ -n "${BBR_WORK_DIR}" ]] || return 0
  [[ "${BBR_WORK_DIR##*/}" == seedbox-bbr.* && -n "${BBR_WORK_ID}" ]] || return 1
  fs::assert_no_symlink_components "${BBR_WORK_DIR}" || return $?
  local target rest
  while IFS=' ' read -r _ _ _ _ target rest; do
    printf -v target '%b' "${target}"
    [[ "${target}" != "${BBR_WORK_DIR}" && "${target}" != "${BBR_WORK_DIR}/"* ]] || return 1
  done </proc/self/mountinfo
  [[ "$(stat -c '%d:%i' -- "${BBR_WORK_DIR}")" == "${BBR_WORK_ID}" ]] || return 1
  rm -rf --one-file-system -- "${BBR_WORK_DIR}"
}

bbr::verify_installer() {
  [[ "$2" =~ ^[[:xdigit:]]{64}$ ]] || return 2
  printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null
}

bbr::download_installer() {
  local old_allow="${SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS:-0}" rc
  [[ -z "${BBR_INSTALLER_SHA256}" || "${BBR_INSTALLER_SHA256}" =~ ^[[:xdigit:]]{64}$ ]] || return 2
  [[ -n "${BBR_WORK_DIR}" && "${BBR_SCRIPT}" == "${BBR_WORK_DIR}/BBRInstall.sh" ]] || return 1
  if [[ "${BBR_USE_BUNDLED}" == 1 ]]; then
    cp -f -- "${SEEDBOX_BBR_LOCAL_INSTALLER}" "${BBR_SCRIPT}" || return $?
    bbr::verify_installer "${BBR_SCRIPT}" "${SEEDBOX_BBR_BUNDLED_SHA256}" || return $?
    if [[ -n "${BBR_INSTALLER_SHA256}" ]]; then bbr::verify_installer "${BBR_SCRIPT}" "${BBR_INSTALLER_SHA256}" || return $?; fi
  elif [[ -r "${BBR_INSTALLER_URL}" ]]; then
    [[ -n "${BBR_INSTALLER_SHA256}" ]] || args::has allow_unverified_bbr_installer || return 2
    cp -f -- "${BBR_INSTALLER_URL}" "${BBR_SCRIPT}" || return $?
    if [[ -n "${BBR_INSTALLER_SHA256}" ]]; then bbr::verify_installer "${BBR_SCRIPT}" "${BBR_INSTALLER_SHA256}" || return $?; fi
  else
    [[ -n "${BBR_INSTALLER_SHA256}" ]] || args::has allow_unverified_bbr_installer || return 2
    if args::has allow_unverified_bbr_installer; then export SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1; fi
    rc=0
    download::fetch "${BBR_INSTALLER_URL}" "${BBR_SCRIPT}" "${BBR_INSTALLER_SHA256}" || rc=$?
    export SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS="${old_allow}"
    if ((rc != 0)); then
      # An explicit integrity contract never falls back to a different script.
      [[ "${rc}" == 75 && -z "${BBR_INSTALLER_SHA256}" && "${BBR_INSTALLER_URL}" == "${SEEDBOX_BBR_INSTALLER_URL}" ]] || return "${rc}"
      cp -f -- "${SEEDBOX_BBR_LOCAL_INSTALLER}" "${BBR_SCRIPT}" || return $?
      bbr::verify_installer "${BBR_SCRIPT}" "${SEEDBOX_BBR_BUNDLED_SHA256}" || return $?
    fi
  fi
  export SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS="${old_allow}"
  if [[ "${BBR_ALGO}" == bbrx_old ]]; then
    grep -Eq '^SUPPORTED_ALGOS=.*"bbrx_old"' "${BBR_SCRIPT}" || {
      ui::error "Selected installer does not support bbrx_old."
      return 1
    }
  fi
  chmod 0700 "${BBR_SCRIPT}" || return $?
}

bbr::installer_supports_option() {
  local opt="$1"
  [[ -r "${BBR_SCRIPT}" ]] || return 1
  grep -q -- "${opt}" "${BBR_SCRIPT}"
}

bbr::read_kernel_result() {
  BBR_KERNEL_RELEASE=""
  local file="${BBR_KERNEL_RESULT_FILE}" size kernel LC_ALL=C
  [[ -n "${file}" && -f "${file}" && ! -L "${file}" && -r "${file}" ]] || return 1
  size="$(stat -c %s -- "${file}")" || return $?
  [[ "${size}" =~ ^[0-9]+$ ]] && ((size > 0 && size <= 256)) || return 1
  IFS= read -r -d '' -n 257 kernel <"${file}" && return 1
  kernel="${kernel%$'\n'}"
  [[ "${kernel}" =~ ^[A-Za-z0-9][A-Za-z0-9.+_~-]*$ && ${#kernel} -le 255 && -f "/boot/vmlinuz-${kernel}" ]] || return 1
  BBR_KERNEL_RELEASE="${kernel}"
}

bbr::run_installer() {
  local -a cmd
  local installer_lang="${BBR_LANG}"
  cmd=(bash "${BBR_SCRIPT}" --algo "${BBR_ALGO}" --raw-base "${BBR_RAW_BASE}")
  args::has force_runtime && cmd+=(--force-runtime)

  if [[ -n "${installer_lang}" ]]; then
    case "${installer_lang,,}" in
      zh | zh-cn | zh_hans | zh-hans | cn | simplified | simplified-chinese)
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
    BBR_SYSCTL_DROPIN="${SEEDBOX_BBR_SYSCTL_DROPIN}" BBR_MODULES_LOAD_DROPIN="${SEEDBOX_BBR_MODULES_LOAD_DROPIN}" BBR_KERNEL_RESULT_FILE="${BBR_KERNEL_RESULT_FILE}" BBR_LANG="${installer_lang}" "${cmd[@]}" || return $?
  else
    BBR_SYSCTL_DROPIN="${SEEDBOX_BBR_SYSCTL_DROPIN}" BBR_MODULES_LOAD_DROPIN="${SEEDBOX_BBR_MODULES_LOAD_DROPIN}" BBR_KERNEL_RESULT_FILE="${BBR_KERNEL_RESULT_FILE}" "${cmd[@]}" || return $?
  fi
  if [[ "${BBR_ALGO}" == bbrv3 ]] && ! bbr::read_kernel_result; then
    ui::warn "BBRv3 target kernel was not reported or could not be verified; status will remain unverified."
  fi
  return 0
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
  [[ -n "${image_pkg}" && -n "${headers_pkg}" ]] || {
    ui::error "Could not resolve generic kernel package names."
    return 1
  }

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
kernel_release=${BBR_KERNEL_RELEASE}
installer_url=${BBR_INSTALLER_URL}
raw_base=${BBR_RAW_BASE}
sysctl=${SEEDBOX_BBR_SYSCTL_DROPIN}
modules_load=${SEEDBOX_BBR_MODULES_LOAD_DROPIN}
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

bbr::install_steps() {
  bbr::load_args || return $?
  ui::heading "Installing BBR congestion-control variant"
  ui::kv "Algorithm" "${BBR_ALGO}"
  ui::kv "Installer" "${BBR_INSTALLER_URL}"
  ui::log_location
  printf '\n'

  runner::must bbr.preflight "Preflight BBR installer" "" bbr::preflight || return $?
  runner::must bbr.workspace "Create private BBR workspace" "" bbr::create_workdir || return $?
  runner::must bbr.download "Download BBR installer" "" bbr::download_installer || return $?
  runner::must bbr.headers "Prepare DKMS kernel headers" "" bbr::prepare_dkms_headers_or_generic_kernel || return $?
  if [[ "${BBR_GENERIC_KERNEL_INSTALLED}" == "1" ]]; then
    runner::must bbr.state "Save pending BBR state" "" bbr::write_pending_generic_kernel_state || return $?
    ui::warn "A generic kernel image and headers were installed because headers for the running kernel were unavailable. Reboot into the new generic kernel, then rerun the BBR install for ${BBR_ALGO}."
    ui::success "Generic kernel/header fallback completed for ${BBR_ALGO}; BBR module installation is pending until after reboot."
    ui::pending "$(ui::tr "重启进入新通用内核后，重新安装 ${BBR_ALGO} 模块。" "Reboot into the new generic kernel, then rerun the ${BBR_ALGO} module installation.")"
    return 0
  fi
  runner::must bbr.install "Run BBR installer" "" bbr::run_installer || return $?
  runner::must bbr.state "Save BBR state" "" bbr::write_state || return $?

  if [[ "${BBR_ALGO}" == bbrv3 && (-z "${BBR_KERNEL_RELEASE}" || "$(uname -r)" != "${BBR_KERNEL_RELEASE}") ]]; then
    ui::warn "BBRv3 kernel package installation requires a reboot before it can become active."
    ui::pending "$(ui::tr '重启进入新安装的 BBRv3 内核，再执行 seedboxctl bbr status 检查。' 'Boot the installed BBRv3 kernel, then check seedboxctl bbr status.')"
  fi
  ui::success "BBR installation flow completed for ${BBR_ALGO}."
}

bbr::install_from_parsed() {
  local rc=0
  bbr::install_steps || rc=$?
  if ! bbr::cleanup_workdir; then
    ui::warn "Private BBR workspace retained for review: ${BBR_WORK_DIR}"
    ((rc != 0)) || rc=1
  fi
  return "${rc}"
}

bbr::state_algo() {
  local path
  path="$(state::path bbr default)"
  if [[ -r "${path}" ]]; then
    state::get "${path}" algo
  fi
}

bbr::module_loaded() { [[ -d "/sys/module/$1" ]]; }

bbr::uninstall_dkms_algo() {
  local algo="$1" version_dir version module active switched=0 rc=0
  module="tcp_${algo}"
  active="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" || active=""
  if [[ "${active}" == "${algo}" ]]; then
    sysctl -w net.ipv4.tcp_congestion_control=cubic || return $?
    switched=1
  fi
  # Unload by registered name before DKMS deletes the module file. rmmod also
  # handles a loaded module left behind by an earlier, partially failed removal.
  if bbr::module_loaded "${module}"; then
    rmmod "${module}" || rc=$?
    if ((rc != 0)); then
      if ((switched)); then
        sysctl -w "net.ipv4.tcp_congestion_control=${algo}" || ui::warn "Could not restore the previous congestion-control selection."
      fi
      ui::error "$(ui::tr "无法卸载模块 ${module}；请先关闭活动连接，再从使用 Cubic 的新会话或本地控制台重试。未移除 DKMS 文件。" "Module ${module} could not be unloaded; close active connections and retry from a Cubic session or local console. DKMS removal was not attempted.")"
      return "${rc}"
    fi
  fi
  if command -v dkms >/dev/null 2>&1 && [[ -d "/var/lib/dkms/${algo}" ]]; then
    for version_dir in "/var/lib/dkms/${algo}"/*; do
      [[ -d "${version_dir}" ]] || continue
      version="$(basename -- "${version_dir}")"
      dkms remove -m "${algo}" -v "${version}" --all || return $?
    done
  fi
  depmod -a || return $?
}

bbr::uninstall_from_parsed() {
  detect::assert_root || return $?
  args::copy_value_alias bbr_algo algo
  local algo cc_algo
  algo="$(args::get bbr_algo "$(bbr::state_algo)")"
  [[ -n "${algo}" ]] || {
    ui::error "No BBR state found. Pass --bbr-algo to remove a DKMS variant."
    return 2
  }
  bbr::validate_algo "${algo}" || return $?

  ui::heading "Uninstalling BBR configuration"
  ui::kv "Algorithm" "${algo}"
  ui::log_location
  printf '\n'

  if [[ "${algo}" == "bbrv3" ]]; then
    ui::warn "BBRv3 installed a kernel package. This command removes Seedbox-managed sysctl files only."
    ui::warn "Boot a known-good distro kernel, inspect dpkg -l 'linux-image*' 'linux-headers*' | grep -i bbr, then purge the specific BBR kernel packages manually."
  else
    runner::run bbr.dkms_remove "Remove DKMS module if present" "" bbr::uninstall_dkms_algo "${algo}" || return $?
  fi

  # Variants may coexist. Removing one must not delete another's boot default
  # or saved state (and removing bbrx must not match bbrx_old by prefix).
  cc_algo="${algo}"
  [[ "${algo}" != bbrv3 ]] || cc_algo=bbr
  if [[ -f "${SEEDBOX_BBR_SYSCTL_DROPIN}" ]] \
    && grep -Eq "^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=[[:space:]]*${cc_algo}([[:space:]]*(#.*)?)?$" "${SEEDBOX_BBR_SYSCTL_DROPIN}"; then
    rm -f -- "${SEEDBOX_BBR_SYSCTL_DROPIN}" || return $?
  fi
  if [[ -f "${SEEDBOX_BBR_MODULES_LOAD_DROPIN}" ]] \
    && grep -Eq "^[[:space:]]*tcp_${algo}[[:space:]]*(#.*)?$" "${SEEDBOX_BBR_MODULES_LOAD_DROPIN}"; then
    rm -f -- "${SEEDBOX_BBR_MODULES_LOAD_DROPIN}" || return $?
  fi
  if [[ "$(bbr::state_algo)" == "${algo}" ]]; then
    state::remove bbr default || return $?
  fi
  ui::success "Seedbox-managed BBR configuration removed. A reboot may be required to fully revert kernel state."
}

bbr::status() {
  status::component bbr
}
