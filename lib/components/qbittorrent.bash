# qBittorrent binary and per-user/rootless instance lifecycle.

if [[ -n "${SEEDBOX_COMPONENT_QBITTORRENT_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_QBITTORRENT_SOURCED=1

: "${SEEDBOX_QB_STATIC_BASE_URL:=https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Torrent%20Clients/qBittorrent}"
: "${SEEDBOX_QB_MANIFEST:=${SEEDBOX_ROOT}/manifests/qbittorrent.tsv}"

declare -g QB_USER=""
declare -g QB_WEBUI_USERNAME=""
declare -g QB_PASSWORD=""
declare -g QB_CACHE_MIB=""
declare -g QB_WEB_PORT=""
declare -g QB_INCOMING_PORT=""
declare -g QB_VERSION=""
declare -g QB_LIBTORRENT_VERSION=""
declare -g QB_SOURCE=""
declare -g QB_SERVICE_MODE=""
declare -g QB_TUNING_PROFILE=""
declare -g QB_TUNING_PROFILE_RESOLVED=""
declare -g QB_ROOTLESS="0"
declare -g QB_HOME=""
declare -g QB_BINARY=""
declare -g QB_UNIT=""
declare -g QB_CONFIG=""
declare -g QB_DATA_DIR=""
declare -g QB_RESTART_SCRIPT=""
declare -g QB_PASSWORD_LINE_OVERRIDE=""

declare -gr QB_ROOTLESS_UNIT="seedbox-qbittorrent.service"
declare -gr QB_ROOTLESS_CRON_MARKER_PREFIX="seedboxctl:qBittorrent"

qbittorrent::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl qbittorrent add-user --user 用户名 [选项]
  seedboxctl qbittorrent add-user --rootless [选项]
  seedboxctl qbittorrent install-self [选项]
  seedboxctl qbittorrent upgrade [--user 用户名] [选项]
  seedboxctl qbittorrent uninstall [--user 用户名] [--purge] [--yes]
  seedboxctl qbittorrent status [--user 用户名] [--json]
  seedboxctl qbittorrent logs [--user 用户名]
  seedboxctl list qbittorrent

常用安装/升级选项：
  --password-stdin | --password-file 文件 | --password 密码
  --cache MiB
  --qb-tuning-profile auto|legacy|1g-hdd|1g-hdd-raid0|1g-ssd|1g-nvme|1g-ceph|10g-hdd|10g-hdd-raid0|10g-ssd|10g-nvme|10g-ceph
  --web-port 端口 | --qb-web-port 端口 | --qb-port 端口
  --incoming-port 端口 | --qb-incoming-port 端口
  --source distro|static|existing
  --qb-version 版本
  --libtorrent-version 版本
  --service-mode system|user|screen|daemon|auto|prompt
  --webui-username 名称
  --allow-unverified-downloads

静态版说明：
  qBittorrent/libtorrent 的可用组合以 manifests/qbittorrent.tsv 为准。
  如果没有提供版本，或提供的组合不在清单中，交互式安装会列出清单中的可选组合让你选择。

调优 profile：
  --qb-tuning-profile auto 会按网卡速率和下载目录所在磁盘自动套用配置。
  指定 1g/10g + hdd/hdd-raid0/ssd/nvme/ceph 可强制使用对应表。
  使用 legacy 可保留旧版自动调优值。

升级/降级说明：
  安装器会按目标 qBittorrent 版本重写配置文件。
  兼容的既有 WebUI 密码哈希会被保留；如果目标版本需要另一种密码哈希格式，
  请传入 --password-stdin、--password-file 或 --password 以便安全地重新生成配置。

Root/admin 模式：
  --user 是拥有 qBittorrent 实例的 Linux 账号。
  默认启动方式为 systemd system service。
  root/admin 安装语法：seedboxctl qbittorrent add-user --user USER --password-stdin
  或：seedboxctl install --profile dedicated --components qbittorrent --user USER --password-stdin
  --source distro 使用系统 qbittorrent-nox 包；--source static 下载或使用固定版本的静态二进制。

Rootless/共享账号模式：
  使用 --rootless、install-self，或以普通用户运行 shared profile；不要使用 sudo/root。
  进程始终归当前 Unix 用户所有；--user 可以省略。
  可用 --webui-username 单独设置 WebUI 登录名。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl qbittorrent add-user --user USER [options]
  seedboxctl qbittorrent add-user --rootless [options]
  seedboxctl qbittorrent install-self [options]
  seedboxctl qbittorrent upgrade [--user USER] [options]
  seedboxctl qbittorrent uninstall [--user USER] [--purge] [--yes]
  seedboxctl qbittorrent status [--user USER] [--json]
  seedboxctl qbittorrent logs [--user USER]
  seedboxctl list qbittorrent

Common install/upgrade options:
  --password-stdin | --password-file FILE | --password PASSWORD
  --cache MIB
  --qb-tuning-profile auto|legacy|1g-hdd|1g-hdd-raid0|1g-ssd|1g-nvme|1g-ceph|10g-hdd|10g-hdd-raid0|10g-ssd|10g-nvme|10g-ceph
  --web-port PORT | --qb-web-port PORT | --qb-port PORT
  --incoming-port PORT | --qb-incoming-port PORT
  --source distro|static|existing
  --qb-version VERSION
  --libtorrent-version VERSION
  --service-mode system|user|screen|daemon|auto|prompt
  --webui-username NAME
  --allow-unverified-downloads

Static source notes:
  qBittorrent/libtorrent combinations are authoritative from manifests/qbittorrent.tsv.
  If a version is missing, or the supplied pair is not in the manifest, interactive installs
  list valid manifest choices and ask you to select one.

Tuning profile notes:
  --qb-tuning-profile auto applies the profile table from detected NIC speed and the download path storage.
  Specify 1g/10g plus hdd/hdd-raid0/ssd/nvme/ceph to force a table profile.
  Use legacy to keep the earlier automatic tuning values.

Upgrade/downgrade notes:
  The config file is rewritten for the selected qBittorrent version.
  Existing compatible WebUI password hashes are preserved. If the target
  version needs a different password-hash format, pass --password-stdin,
  --password-file, or --password so seedboxctl can regenerate it.

Root/admin mode:
  --user is the Linux account that owns the qBittorrent instance.
  Default service mode is system.
  Root/admin install syntax: seedboxctl qbittorrent add-user --user USER --password-stdin
  Or: seedboxctl install --profile dedicated --components qbittorrent --user USER --password-stdin
  Source distro installs the OS qbittorrent-nox package; source static downloads a pinned binary.

Rootless/shared-user mode:
  Use --rootless or install-self, or run the shared profile as a non-root user; do not use sudo/root.
  The process owner is always the current Unix user. --user may be omitted.
  Use --webui-username to set the WebUI login name independently.
  Default service mode is auto: user systemd service, then screen, then daemon/crontab fallback.
  Source static downloads only the selected qBittorrent binary to the user's home directory.
USAGE
  fi
}

qbittorrent::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    add-user|install)
      args::parse "$@"
      args::has help && { qbittorrent::usage; return 0; }
      log::init qbittorrent-add-user
      qbittorrent::install_from_parsed
      ;;
    install-self|install-rootless|self)
      args::parse "$@"
      args::has help && { qbittorrent::usage; return 0; }
      ARGS[rootless]=1
      log::init qbittorrent-install-self
      qbittorrent::install_from_parsed
      ;;
    upgrade)
      args::parse "$@"
      args::has help && { qbittorrent::usage; return 0; }
      log::init qbittorrent-upgrade
      qbittorrent::upgrade_from_parsed
      ;;
    uninstall|remove)
      args::parse "$@"
      args::has help && { qbittorrent::usage; return 0; }
      log::init qbittorrent-uninstall
      qbittorrent::uninstall_from_parsed
      ;;
    status)
      qbittorrent::status_cmd "$@"
      ;;
    logs)
      args::parse "$@"
      qbittorrent::logs "$(args::get user)"
      ;;
    help|-h|--help)
      qbittorrent::usage
      ;;
    *)
      ui::error "Unknown qBittorrent command: ${sub}"
      qbittorrent::usage
      return 2
      ;;
  esac
}

qbittorrent::normalize_qb_version() {
  local v="$1"
  v="${v#qBittorrent-}"
  v="${v#qbittorrent-}"
  printf '%s\n' "${v}"
}

qbittorrent::normalize_libtorrent_version() {
  local v="$1"
  v="${v#libtorrent-}"
  printf '%s\n' "${v}"
}

qbittorrent::normalize_service_mode() {
  local mode="$1"
  mode="${mode,,}"
  mode="${mode// /-}"
  mode="${mode//_/-}"
  case "${mode}" in
    local-user-service|local-user|user-service|systemd-user|user) printf 'user\n' ;;
    system|systemd) printf 'system\n' ;;
    screen) printf 'screen\n' ;;
    daemon|background) printf 'daemon\n' ;;
    auto|'') printf 'auto\n' ;;
    prompt|ask|interactive) printf 'prompt\n' ;;
    *) printf '%s\n' "${mode}" ;;
  esac
}

qbittorrent::config_family() {
  local version="$1"
  case "${version}" in
    4.1.*) printf 'classic_41\n' ;;
    4.2.*|4.3.*) printf 'classic_pbkdf2\n' ;;
    *) printf 'modern_pbkdf2\n' ;;
  esac
}

qbittorrent::static_url() {
  local qb_version="$1" lib_version="$2" repo_arch="$3"
  printf '%s/%s/qBittorrent-%s%%20-%%20libtorrent-%s/qbittorrent-nox\n' \
    "${SEEDBOX_QB_STATIC_BASE_URL}" "${repo_arch}" "${qb_version}" "${lib_version}"
}

qbittorrent::manifest_lookup_field() {
  local qb_version="$1" lib_version="$2" arch="$3" source="${4:-static}" field="${5:-6}"
  [[ -r "${SEEDBOX_QB_MANIFEST}" ]] || return 1
  awk -F'\t' -v qb="${qb_version}" -v lib="${lib_version}" -v arch="${arch}" -v source="${source}" -v field="${field}" '
    $0 ~ /^#/ || NF < field {next}
    $1==qb && $2==lib && $3==arch && $4==source {print $field; found=1; exit}
    END {if (!found) exit 1}
  ' "${SEEDBOX_QB_MANIFEST}"
}

qbittorrent::manifest_lookup_url() {
  qbittorrent::manifest_lookup_field "$1" "$2" "$3" "${4:-static}" 5
}

qbittorrent::manifest_lookup_sha256() {
  qbittorrent::manifest_lookup_field "$1" "$2" "$3" "${4:-static}" 6
}

declare -ga QB_MANIFEST_CHOICES=()

qbittorrent::manifest_pairs_for_arch() {
  local arch="$1" source="${2:-static}"
  [[ -r "${SEEDBOX_QB_MANIFEST}" ]] || return 1
  awk -F'\t' -v arch="${arch}" -v source="${source}" '
    $0 ~ /^#/ || NF < 4 {next}
    $3==arch && $4==source {print $1 "\t" $2}
  ' "${SEEDBOX_QB_MANIFEST}" | sort -u -V
}

qbittorrent::manifest_combo_exists() {
  local qb_version="$1" lib_version="$2" arch="$3" source="${4:-static}"
  [[ -r "${SEEDBOX_QB_MANIFEST}" ]] || return 1
  awk -F'\t' -v qb="${qb_version}" -v lib="${lib_version}" -v arch="${arch}" -v source="${source}" '
    $0 ~ /^#/ || NF < 4 {next}
    $1==qb && $2==lib && $3==arch && $4==source {found=1; exit}
    END {exit found ? 0 : 1}
  ' "${SEEDBOX_QB_MANIFEST}"
}

qbittorrent::load_manifest_choices() {
  local qb_version="$1" lib_version="$2" arch="$3" source="${4:-static}"
  QB_MANIFEST_CHOICES=()
  [[ -r "${SEEDBOX_QB_MANIFEST}" ]] || return 1
  mapfile -t QB_MANIFEST_CHOICES < <(
    awk -F'\t' -v qb="${qb_version}" -v lib="${lib_version}" -v arch="${arch}" -v source="${source}" '
      $0 ~ /^#/ || NF < 4 {next}
      $3==arch && $4==source && (qb=="" || $1==qb) && (lib=="" || $2==lib) {print $1 "\t" $2}
    ' "${SEEDBOX_QB_MANIFEST}" | sort -u -V
  )
}

qbittorrent::tty_available() {
  { : </dev/tty >/dev/tty; } 2>/dev/null
}

qbittorrent::show_manifest_choices() {
  local entry qb lib i=1
  if qbittorrent::tty_available; then
    {
      printf '%s
' "$(ui::tr "可用的静态 qBittorrent 版本组合：" "Available static qBittorrent build combinations:")"
      for entry in "${QB_MANIFEST_CHOICES[@]}"; do
        IFS=$'	' read -r qb lib <<<"${entry}"
        printf '  %2d) qBittorrent %s / libtorrent %s
' "${i}" "${qb}" "${lib}"
        i=$((i + 1))
      done
    } >/dev/tty
  else
    {
      printf '%s
' "$(ui::tr "可用的静态 qBittorrent 版本组合：" "Available static qBittorrent build combinations:")"
      for entry in "${QB_MANIFEST_CHOICES[@]}"; do
        IFS=$'	' read -r qb lib <<<"${entry}"
        printf '  %2d) qBittorrent %s / libtorrent %s
' "${i}" "${qb}" "${lib}"
        i=$((i + 1))
      done
    } >&2
  fi
}

qbittorrent::can_prompt_manifest_choice() {
  [[ -t 0 ]] || qbittorrent::tty_available
}

qbittorrent::read_manifest_choice() {
  local prompt="$1" value
  if qbittorrent::tty_available; then
    printf '%s' "${prompt}" >/dev/tty
    IFS= read -r value </dev/tty
  else
    printf '%s' "${prompt}" >&2
    IFS= read -r value
  fi
  printf '%s\n' "${value}"
}

qbittorrent::choose_manifest_pair() {
  local choice entry
  qbittorrent::show_manifest_choices
  while true; do
    choice="$(qbittorrent::read_manifest_choice "$(ui::tr "请选择编号：" "Select a build number: ")")"
    if [[ "${choice}" =~ ^[0-9]+$ && "${choice}" -ge 1 && "${choice}" -le ${#QB_MANIFEST_CHOICES[@]} ]]; then
      entry="${QB_MANIFEST_CHOICES[$((choice - 1))]}"
      IFS=$'\t' read -r QB_VERSION QB_LIBTORRENT_VERSION <<<"${entry}"
      ui::info "$(ui::tr "已选择 qBittorrent ${QB_VERSION} / libtorrent ${QB_LIBTORRENT_VERSION}" "Selected qBittorrent ${QB_VERSION} / libtorrent ${QB_LIBTORRENT_VERSION}")"
      return 0
    fi
    ui::warn "$(ui::tr "请输入列表中的有效编号。" "Please enter a valid number from the list.")"
  done
}

qbittorrent::resolve_static_manifest_selection() {
  detect::load_arch
  local arch="${SEEDBOX_ARCH}" reason=""

  [[ -r "${SEEDBOX_QB_MANIFEST}" ]] || {
    ui::error "$(ui::tr "找不到 qBittorrent 清单文件：${SEEDBOX_QB_MANIFEST}" "qBittorrent manifest not found: ${SEEDBOX_QB_MANIFEST}")"
    return 2
  }

  if [[ -n "${QB_VERSION}" && -n "${QB_LIBTORRENT_VERSION}" ]] && qbittorrent::manifest_combo_exists "${QB_VERSION}" "${QB_LIBTORRENT_VERSION}" "${arch}" static; then
    return 0
  fi

  if [[ -z "${QB_VERSION}" && -z "${QB_LIBTORRENT_VERSION}" ]]; then
    reason="$(ui::tr "未指定静态版 qBittorrent/libtorrent 版本。" "No static qBittorrent/libtorrent version was supplied.")"
  elif [[ -z "${QB_VERSION}" ]]; then
    reason="$(ui::tr "未指定 qBittorrent 版本。" "No qBittorrent version was supplied.")"
  elif [[ -z "${QB_LIBTORRENT_VERSION}" ]]; then
    reason="$(ui::tr "未指定 libtorrent 版本。" "No libtorrent version was supplied.")"
  else
    reason="$(ui::tr "清单中没有该静态版组合：qBittorrent ${QB_VERSION} / libtorrent ${QB_LIBTORRENT_VERSION} / ${arch}。" "Requested static pair is not in the manifest: qBittorrent ${QB_VERSION} / libtorrent ${QB_LIBTORRENT_VERSION} / ${arch}.")"
  fi

  qbittorrent::load_manifest_choices "${QB_VERSION}" "${QB_LIBTORRENT_VERSION}" "${arch}" static || return 2
  if ((${#QB_MANIFEST_CHOICES[@]} == 0)); then
    qbittorrent::load_manifest_choices "" "" "${arch}" static || return 2
  fi

  if ((${#QB_MANIFEST_CHOICES[@]} == 0)); then
    ui::error "$(ui::tr "清单中没有适用于 ${arch} 的静态 qBittorrent 条目。" "No static qBittorrent manifest entries are available for ${arch}.")"
    return 2
  fi

  ui::warn "${reason}"
  if ! qbittorrent::can_prompt_manifest_choice; then
    ui::error "$(ui::tr "当前不是交互式终端，无法选择版本。请使用 --qb-version 和 --libtorrent-version 指定下方某个组合。" "No interactive terminal is available for version selection. Re-run with --qb-version and --libtorrent-version using one of the choices below.")"
    qbittorrent::show_manifest_choices
    return 2
  fi

  qbittorrent::choose_manifest_pair
}

qbittorrent::list_available() {
  if ui::zh; then
    ui::heading "qBittorrent 来源"
    printf 'distro\t通过 APT 安装系统 qbittorrent-nox 包（仅 root/admin 模式）\n'
    printf 'existing\t使用 PATH、~/bin 或 ~/.local/bin 中已有的 qbittorrent-nox（适合 rootless）\n'
  else
    ui::heading "qBittorrent sources"
    printf 'distro\tOS package qbittorrent-nox from apt, root/admin mode only\n'
    printf 'existing\tUse an existing qbittorrent-nox from PATH or ~/bin, rootless-safe\n'
  fi

  if [[ -r "${SEEDBOX_QB_MANIFEST}" ]]; then
    if ui::zh; then
      printf '\n静态版清单条目：\n'
    else
      printf '\nStatic manifest entries:\n'
    fi
    awk -F'\t' '$0 !~ /^#/ && NF >= 6 {printf "  qb=%s lib=%s arch=%s source=%s sha256=%s\n", $1,$2,$3,$4,($6==""?"missing":$6)}' "${SEEDBOX_QB_MANIFEST}"
  else
    if ui::zh; then
      printf '\n未找到静态版清单：%s\n' "${SEEDBOX_QB_MANIFEST}"
    else
      printf '\nNo static manifest found at %s\n' "${SEEDBOX_QB_MANIFEST}"
    fi
  fi
}

qbittorrent::valid_webui_username() {
  local value="$1"
  [[ -n "${value}" && "${value}" != *$'\n'* && "${value}" != *$'\r'* ]]
}

qbittorrent::is_rootless_requested() {
  args::has rootless && return 0
  [[ "$(args::get profile)" == "shared" && ${EUID:-$(id -u)} -ne 0 ]] && return 0
  return 1
}

qbittorrent::reject_rootless_as_root() {
  ui::error "$(ui::tr "rootless qBittorrent 不能以 root/sudo 运行。请切换到目标普通用户后执行。" "Rootless qBittorrent cannot be run as root/sudo. Run it as the target normal user instead.")"
  ui::error "$(ui::tr "如需 root/admin 安装，请使用以下语法：" "For root/admin qBittorrent installs, use one of these commands:")"
  ui::error "  sudo seedboxctl qbittorrent add-user --user USER --password-stdin"
  ui::error "  sudo seedboxctl install --profile dedicated --components qbittorrent --user USER --password-stdin"
  return 2
}

qbittorrent::load_install_args() {
  args::copy_value_alias web_port qb_web_port
  args::copy_value_alias web_port qb_port
  args::copy_value_alias incoming_port qb_incoming_port
  args::copy_value_alias incoming_port listen_port
  args::copy_value_alias cache cache_mib
  args::copy_value_alias service_mode install_method
  args::copy_value_alias qb_tuning_profile qb_profile
  args::copy_value_alias qb_tuning_profile qbtuning_profile
  args::copy_value_alias webui_username webui_user
  args::copy_value_alias webui_username web_user

  QB_ROOTLESS=0
  qbittorrent::is_rootless_requested && QB_ROOTLESS=1
  if [[ "${QB_ROOTLESS}" == "1" && ${EUID:-$(id -u)} -eq 0 ]]; then
    qbittorrent::reject_rootless_as_root
    return 2
  fi

  local current_user requested_user requested_webui requested_source requested_mode
  current_user="$(id -un 2>/dev/null || printf user)"
  requested_user="$(args::get user)"
  requested_webui="$(args::get webui_username)"

  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    if [[ -z "${requested_user}" ]]; then
      QB_USER="${current_user}"
      QB_WEBUI_USERNAME="${requested_webui:-${current_user}}"
    elif [[ "${requested_user}" == "${current_user}" ]]; then
      QB_USER="${requested_user}"
      QB_WEBUI_USERNAME="${requested_webui:-${requested_user}}"
    else
      QB_USER="${current_user}"
      QB_WEBUI_USERNAME="${requested_webui:-${requested_user}}"
      ui::warn "Rootless mode runs as Unix user ${current_user}; using '${QB_WEBUI_USERNAME}' as the qBittorrent WebUI username."
    fi
  else
    QB_USER="${requested_user}"
    args::require user || return 2
    QB_WEBUI_USERNAME="${requested_webui:-${QB_USER}}"
  fi

  QB_CACHE_MIB="$(args::get cache 3072)"
  QB_WEB_PORT="$(args::get web_port 8080)"
  QB_INCOMING_PORT="$(args::get incoming_port 45000)"
  QB_VERSION="$(qbittorrent::normalize_qb_version "$(args::get qb_version)")"
  QB_LIBTORRENT_VERSION="$(qbittorrent::normalize_libtorrent_version "$(args::get libtorrent_version)")"
  requested_source="$(args::get source)"
  requested_mode="$(args::get service_mode)"

  if [[ -z "${requested_source}" ]]; then
    if [[ -n "${QB_VERSION}" || -n "${QB_LIBTORRENT_VERSION}" ]]; then
      QB_SOURCE="static"
    elif [[ "${QB_ROOTLESS}" == "1" ]]; then
      QB_SOURCE="existing"
    else
      QB_SOURCE="distro"
    fi
  else
    QB_SOURCE="${requested_source,,}"
  fi

  if [[ -z "${requested_mode}" ]]; then
    if [[ "${QB_ROOTLESS}" == "1" ]]; then
      QB_SERVICE_MODE="auto"
    else
      QB_SERVICE_MODE="system"
    fi
  else
    QB_SERVICE_MODE="$(qbittorrent::normalize_service_mode "${requested_mode}")"
  fi

  QB_TUNING_PROFILE="$(qbittorrent::normalize_tuning_profile "$(args::get qb_tuning_profile "${SEEDBOX_QB_TUNING_PROFILE:-auto}")")" || return $?

  if args::has allow_unverified_downloads; then
    SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1
  fi

  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    [[ -n "${QB_USER}" && "${QB_USER}" != *$'\n'* && "${QB_USER}" != *$'\r'* ]] || { ui::error "Could not determine a safe current Unix username."; return 2; }
  else
    validate::die_username "${QB_USER}" || return 2
  fi
  qbittorrent::valid_webui_username "${QB_WEBUI_USERNAME}" || { ui::error "Invalid WebUI username."; return 2; }
  validate::positive_int "${QB_CACHE_MIB}" || { ui::error "Invalid cache size: ${QB_CACHE_MIB}"; return 2; }
  validate::unprivileged_port "${QB_WEB_PORT}" || { ui::error "Invalid WebUI port: ${QB_WEB_PORT}"; return 2; }
  validate::unprivileged_port "${QB_INCOMING_PORT}" || { ui::error "Invalid incoming port: ${QB_INCOMING_PORT}"; return 2; }

  case "${QB_SOURCE}" in
    distro|static|existing) ;;
    *) ui::error "Invalid qBittorrent source: ${QB_SOURCE}"; return 2 ;;
  esac

  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    case "${QB_SERVICE_MODE}" in
      auto|prompt|user|screen|daemon) ;;
      system)
        ui::error "Rootless qBittorrent cannot use --service-mode system. Use user, screen, daemon, auto, or prompt."
        return 2
        ;;
      *) ui::error "Invalid rootless service mode: ${QB_SERVICE_MODE}"; return 2 ;;
    esac
    if [[ "${QB_SOURCE}" == "distro" ]]; then
      QB_SOURCE="existing"
      ui::warn "Rootless mode cannot install distro packages; using an existing qbittorrent-nox from PATH."
    fi
  else
    case "${QB_SERVICE_MODE}" in
      system|screen|daemon) ;;
      user|auto|prompt)
        ui::error "${QB_SERVICE_MODE} service mode is only for rootless/shared-user installs."
        return 2
        ;;
      *) ui::error "Invalid service mode: ${QB_SERVICE_MODE}"; return 2 ;;
    esac
  fi

  if [[ "${QB_SOURCE}" == "static" ]]; then
    qbittorrent::resolve_static_manifest_selection || return $?
  fi

  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    QB_UNIT="${QB_ROOTLESS_UNIT}"
  elif [[ "${QB_SERVICE_MODE}" == "system" ]]; then
    QB_UNIT="seedbox-qbittorrent-${QB_USER}.service"
  else
    QB_UNIT=""
  fi
}

qbittorrent::state_id() {
  printf '%s\n' "${1}"
}

qbittorrent::state_path_for_user() {
  local user="$1"
  state::path qbittorrent "$(qbittorrent::state_id "${user}")"
}

qbittorrent::preflight_install() {
  if [[ "${QB_ROOTLESS}" != "1" ]]; then
    detect::assert_root
  fi
  detect::assert_supported_os
  detect::assert_supported_arch
  if [[ -e "$(qbittorrent::state_path_for_user "${QB_USER}")" ]]; then
    if ! args::has force; then
      ui::error "qBittorrent instance for ${QB_USER} already exists. Use upgrade/status/uninstall, or --force to overwrite."
      return 1
    fi
  fi
  ports::assert_free "${QB_WEB_PORT}" "qBittorrent WebUI port"
  if [[ "${QB_INCOMING_PORT}" != "${QB_WEB_PORT}" ]]; then
    ports::assert_free "${QB_INCOMING_PORT}" "qBittorrent incoming port"
  fi
  if [[ "${QB_SERVICE_MODE}" == "system" ]]; then
    systemd::require
  fi
}

qbittorrent::ensure_packages() {
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    if [[ "${QB_SOURCE}" == "static" ]]; then
      if ! qbittorrent::local_static_binary >/dev/null 2>&1; then
        command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
          ui::error "Rootless static install requires curl or wget when the selected qbittorrent-nox binary is not bundled in this release tree."
          return 1
        }
      fi
    fi
    if [[ "$(qbittorrent::config_family "${QB_VERSION:-5}")" != "classic_41" ]]; then
      command -v python3 >/dev/null 2>&1 || {
        ui::error "Rootless install requires python3 to generate qBittorrent PBKDF2 password hashes."
        return 1
      }
    fi
    if [[ "${QB_SERVICE_MODE}" == "screen" ]]; then
      command -v screen >/dev/null 2>&1 || { ui::error "screen is not installed. Use --service-mode daemon or --service-mode auto."; return 1; }
    fi
    return 0
  fi

  apt::ensure_base
  apt::ensure_packages python3
  case "${QB_SOURCE}" in
    distro)
      apt::ensure_packages qbittorrent-nox
      ;;
    static)
      apt::ensure_packages ca-certificates curl
      ;;
    existing)
      command -v qbittorrent-nox >/dev/null 2>&1 || { ui::error "--source existing selected but qbittorrent-nox is not in PATH."; return 1; }
      ;;
  esac
  if [[ "${QB_SERVICE_MODE}" == "screen" ]]; then
    apt::ensure_packages screen
  fi
}

qbittorrent::ensure_user() {
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    QB_HOME="${HOME}"
    [[ -n "${QB_HOME}" && -d "${QB_HOME}" ]] || { ui::error "Could not determine current user's home directory."; return 1; }
  else
    user::ensure "${QB_USER}"
    if args::has set_system_password; then
      user::set_password "${QB_USER}" "${QB_PASSWORD}"
    fi
    QB_HOME="$(user::home "${QB_USER}")"
  fi
  QB_CONFIG="${QB_HOME}/.config/qBittorrent/qBittorrent.conf"
  QB_DATA_DIR="${QB_HOME}/qbittorrent/Downloads"
  QB_RESTART_SCRIPT="${QB_HOME}/.local/bin/seedbox-qbittorrent-restart"
}

qbittorrent::existing_binary() {
  local candidate
  for candidate in "${HOME}/bin/qbittorrent-nox" "${HOME}/.local/bin/qbittorrent-nox"; do
    [[ -x "${candidate}" ]] && { printf '%s\n' "${candidate}"; return 0; }
  done
  command -v qbittorrent-nox 2>/dev/null || return 1
}

qbittorrent::local_static_binary() {
  detect::load_arch
  local arch_dir lib lib_no_v lib_under lib_no_v_under candidate dir_name
  local -a candidates
  arch_dir="${SEEDBOX_ROOT}/Torrent Clients/qBittorrent/${SEEDBOX_REPO_ARCH}"
  [[ -d "${arch_dir}" ]] || return 1
  lib="${QB_LIBTORRENT_VERSION}"
  lib_no_v="${lib#v}"
  lib_under="${lib//./_}"
  lib_no_v_under="${lib_no_v//./_}"
  candidates=(
    "${arch_dir}/qBittorrent-${QB_VERSION} - libtorrent-${lib}/qbittorrent-nox"
    "${arch_dir}/qBittorrent-${QB_VERSION} - libtorrent-${lib_no_v}/qbittorrent-nox"
    "${arch_dir}/qBittorrent-${QB_VERSION} - libtorrent-${lib_under}/qbittorrent-nox"
    "${arch_dir}/qBittorrent-${QB_VERSION} - libtorrent-${lib_no_v_under}/qbittorrent-nox"
  )
  for candidate in "${candidates[@]}"; do
    [[ -f "${candidate}" ]] || continue
    chmod 0755 "${candidate}" 2>/dev/null || true
    [[ -x "${candidate}" ]] && { printf '%s\n' "${candidate}"; return 0; }
  done
  while IFS= read -r -d '' candidate; do
    chmod 0755 "${candidate}" 2>/dev/null || true
    [[ -x "${candidate}" ]] || continue
    dir_name="$(basename -- "$(dirname -- "${candidate}")")"
    ui::warn "Exact bundled qBittorrent ${QB_VERSION}/${QB_LIBTORRENT_VERSION} was not found; using bundled ${dir_name}."
    printf '%s\n' "${candidate}"
    return 0
  done < <(find "${arch_dir}" -maxdepth 2 -type f -path "*/qBittorrent-${QB_VERSION} - libtorrent-*/qbittorrent-nox" -print0 2>/dev/null | sort -z)
  return 1
}

qbittorrent::install_binary() {
  case "${QB_SOURCE}" in
    distro)
      QB_BINARY="$(command -v qbittorrent-nox || true)"
      [[ -x "${QB_BINARY}" ]] || { ui::error "qbittorrent-nox package installed but binary was not found."; return 1; }
      ;;
    existing)
      QB_BINARY="$(qbittorrent::existing_binary || true)"
      [[ -x "${QB_BINARY}" ]] || { ui::error "qbittorrent-nox was not found in PATH, ~/bin, or ~/.local/bin."; return 1; }
      ;;
    static)
      detect::load_arch
      local dir url sha convenience_link
      if [[ "${QB_ROOTLESS}" == "1" ]]; then
        dir="${QB_HOME}/.local/share/seedbox/qbittorrent/qBittorrent-${QB_VERSION}-libtorrent-${QB_LIBTORRENT_VERSION}-${SEEDBOX_ARCH}"
      else
        dir="/opt/seedbox/qbittorrent/qBittorrent-${QB_VERSION}-libtorrent-${QB_LIBTORRENT_VERSION}-${SEEDBOX_ARCH}"
      fi
      QB_BINARY="${dir}/qbittorrent-nox"
      mkdir -p "${dir}"
      url="$(qbittorrent::manifest_lookup_url "${QB_VERSION}" "${QB_LIBTORRENT_VERSION}" "${SEEDBOX_ARCH}" static || true)"
      if [[ -z "${url}" ]]; then
        url="$(qbittorrent::static_url "${QB_VERSION}" "${QB_LIBTORRENT_VERSION}" "${SEEDBOX_REPO_ARCH}")"
      fi
      local local_binary
      local_binary="$(qbittorrent::local_static_binary || true)"
      if [[ -n "${local_binary}" ]]; then
        install -m 0755 "${local_binary}" "${QB_BINARY}"
      else
        sha="$(qbittorrent::manifest_lookup_sha256 "${QB_VERSION}" "${QB_LIBTORRENT_VERSION}" "${SEEDBOX_ARCH}" static || true)"
        download::fetch "${url}" "${QB_BINARY}" "${sha}" || return $?
        chmod 0755 "${QB_BINARY}"
      fi
      if [[ "${QB_ROOTLESS}" == "1" ]]; then
        mkdir -p "${QB_HOME}/bin"
        convenience_link="${QB_HOME}/bin/qbittorrent-nox"
        if [[ -e "${convenience_link}" && ! -L "${convenience_link}" ]]; then
          mv -f -- "${convenience_link}" "${convenience_link}.bak.$(date '+%Y%m%d-%H%M%S')"
        fi
        ln -sfn "${QB_BINARY}" "${convenience_link}"
      else
        chown root:root "${QB_BINARY}" 2>/dev/null || true
      fi
      ;;
  esac
}

qbittorrent::pbkdf2_hash() {
  local password="$1"
  printf '%s' "${password}" | python3 -c 'import base64, hashlib, os, sys
password = sys.stdin.read().encode()
salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac("sha512", password, salt, 100000)
print(f"{base64.b64encode(salt).decode()}:{base64.b64encode(dk).decode()}")'
}

qbittorrent::password_config_line() {
  local user="$1" password="$2" qb_version="$3"
  case "$(qbittorrent::config_family "${qb_version:-5}")" in
    classic_41)
      local md5password
      md5password="$(printf '%s' "${password}" | md5sum | awk '{print $1}')"
      printf 'WebUI\\Password_ha1=@ByteArray(%s)\n' "${md5password}"
      ;;
    *)
      local pbkdf2
      pbkdf2="$(qbittorrent::pbkdf2_hash "${password}")"
      printf 'WebUI\\Password_PBKDF2="@ByteArray(%s)"\n' "${pbkdf2}"
      ;;
  esac
}

qbittorrent::password_args_supplied() {
  args::has password_stdin && return 0
  [[ -n "$(args::get password_file)" ]] && return 0
  [[ -n "$(args::get password)" ]] && return 0
  return 1
}

qbittorrent::existing_password_line() {
  local config="${1:-${QB_CONFIG}}"
  [[ -r "${config}" ]] || return 1
  grep -E '^[[:space:]]*WebUI\\Password(_PBKDF2|_ha1)?=' "${config}" | tail -n1 | sed 's/^[[:space:]]*//'
}

qbittorrent::password_line_matches_family() {
  local line="$1" family="$2"
  case "${family}" in
    classic_41)
      [[ "${line}" == 'WebUI\Password_ha1='* ]]
      ;;
    classic_pbkdf2|modern_pbkdf2)
      [[ "${line}" == 'WebUI\Password_PBKDF2='* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

qbittorrent::prepare_config_password_for_upgrade() {
  local family line
  QB_PASSWORD_LINE_OVERRIDE=""
  family="$(qbittorrent::config_family "${QB_VERSION:-5}")"

  if qbittorrent::password_args_supplied; then
    QB_PASSWORD="$(secrets::read_password_from_args)" || return $?
    return 0
  fi

  line="$(qbittorrent::existing_password_line "${QB_CONFIG}" || true)"
  if [[ -z "${line}" ]]; then
    ui::error "Cannot rewrite qBittorrent config without an existing WebUI password hash. Re-run upgrade with --password-stdin or --password-file."
    return 1
  fi

  if qbittorrent::password_line_matches_family "${line}" "${family}"; then
    QB_PASSWORD_LINE_OVERRIDE="${line}"
    return 0
  fi

  ui::error "This qBittorrent upgrade/downgrade changes the WebUI password-hash format. Re-run with --password-stdin or --password-file so the config can be regenerated safely."
  return 1
}

qbittorrent::version_ge() {
  local lhs="${1:-0}" rhs="${2:-0}" IFS='.'
  lhs="${lhs%%[-+~]*}"
  rhs="${rhs%%[-+~]*}"
  lhs="${lhs#v}"
  rhs="${rhs#v}"
  [[ -n "${lhs}" && "${lhs}" != "existing" && "${lhs}" != "distro" && "${lhs}" != "unknown" ]] || lhs="5"
  [[ -n "${rhs}" ]] || rhs="0"
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --compare-versions "${lhs}" ge "${rhs}" >/dev/null 2>&1
    return $?
  fi
  local -a a=() b=()
  read -r -a a <<<"${lhs}"
  read -r -a b <<<"${rhs}"
  local i av bv
  for i in 0 1 2 3; do
    av="${a[$i]:-0}"; bv="${b[$i]:-0}"
    av="${av//[^0-9]/}"; bv="${bv//[^0-9]/}"
    av="${av:-0}"; bv="${bv:-0}"
    (( av > bv )) && return 0
    (( av < bv )) && return 1
  done
  return 0
}

qbittorrent::uses_libtorrent2() {
  local lib="${QB_LIBTORRENT_VERSION:-}"
  lib="${lib#libtorrent-}"
  lib="${lib#v}"
  [[ "${lib}" =~ ^2(\.|$) ]]
}

qbittorrent::tuning_profiles_list() {
  printf '%s\n' auto legacy 1g-hdd 1g-hdd-raid0 1g-ssd 1g-nvme 1g-ceph 10g-hdd 10g-hdd-raid0 10g-ssd 10g-nvme 10g-ceph
}

qbittorrent::normalize_tuning_profile() {
  local value="${1:-auto}"
  value="${value,,}"
  value="${value// /-}"
  value="${value//_/-}"
  value="${value//gbps/g}"
  value="${value//gbit/g}"
  value="${value//gigabit/g}"
  value="${value//raid-0/raid0}"
  value="${value//--/-}"
  case "${value}" in
    ''|auto|detect|detected) printf 'auto\n' ;;
    legacy|old|classic|none|off|disabled) printf 'legacy\n' ;;
    1-hdd|1g-hdd|1gb-hdd) printf '1g-hdd\n' ;;
    1-raid0|1g-raid0|1gb-raid0|1-hdd-raid0|1g-hdd-raid0|1gb-hdd-raid0) printf '1g-hdd-raid0\n' ;;
    1-ssd|1g-ssd|1gb-ssd) printf '1g-ssd\n' ;;
    1-nvme|1g-nvme|1gb-nvme) printf '1g-nvme\n' ;;
    1-ceph|1g-ceph|1gb-ceph) printf '1g-ceph\n' ;;
    10-hdd|10g-hdd|10gb-hdd) printf '10g-hdd\n' ;;
    10-raid0|10g-raid0|10gb-raid0|10-hdd-raid0|10g-hdd-raid0|10gb-hdd-raid0) printf '10g-hdd-raid0\n' ;;
    10-ssd|10g-ssd|10gb-ssd) printf '10g-ssd\n' ;;
    10-nvme|10g-nvme|10gb-nvme) printf '10g-nvme\n' ;;
    10-ceph|10g-ceph|10gb-ceph) printf '10g-ceph\n' ;;
    *)
      ui::error "Invalid qBittorrent tuning profile: ${1}. Valid profiles: $(qbittorrent::tuning_profiles_list | paste -sd, - 2>/dev/null || qbittorrent::tuning_profiles_list | tr '\n' ',')"
      return 2
      ;;
  esac
}

qbittorrent::display_tuning_profile() {
  local value="${1:-auto}"
  case "${value}" in
    1g-hdd) printf '1G-HDD\n' ;;
    1g-hdd-raid0) printf '1G-HDD RAID0\n' ;;
    1g-ssd) printf '1G-SSD\n' ;;
    1g-nvme) printf '1G-NVMe\n' ;;
    1g-ceph) printf '1G-Ceph\n' ;;
    10g-hdd) printf '10G-HDD\n' ;;
    10g-hdd-raid0) printf '10G-HDD RAID0\n' ;;
    10g-ssd) printf '10G-SSD\n' ;;
    10g-nvme) printf '10G-NVMe\n' ;;
    10g-ceph) printf '10G-Ceph\n' ;;
    legacy) printf 'legacy\n' ;;
    auto) printf 'auto\n' ;;
    *) printf '%s\n' "${value}" ;;
  esac
}

qbittorrent::legacy_storage_tuning_values() {
  local aio=8 low_buffer=3072 buffer=15360 buffer_factor=200
  if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet; then
    :
  else
    local disk_name rotational
    disk_name="$(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1; exit}')"
    if [[ -n "${disk_name}" && -r "/sys/block/${disk_name}/queue/rotational" ]]; then
      rotational="$(cat "/sys/block/${disk_name}/queue/rotational")"
      if [[ "${rotational}" == "0" ]]; then
        aio=12; low_buffer=5120; buffer=20480; buffer_factor=250
      else
        aio=4; low_buffer=3072; buffer=10240; buffer_factor=150
      fi
    fi
  fi
  printf '%s %s %s %s\n' "${aio}" "${low_buffer}" "${buffer}" "${buffer_factor}"
}

qbittorrent::detect_network_tier() {
  local file speed max_speed=0 iface
  for file in /sys/class/net/*/speed; do
    [[ -r "${file}" ]] || continue
    iface="$(basename -- "$(dirname -- "${file}")")"
    [[ "${iface}" == "lo" ]] && continue
    speed="$(cat "${file}" 2>/dev/null || printf 0)"
    [[ "${speed}" =~ ^[0-9]+$ ]] || continue
    (( speed > max_speed )) && max_speed="${speed}"
  done
  if (( max_speed >= 10000 )); then
    printf '10g\n'
  else
    printf '1g\n'
  fi
}

qbittorrent::detect_storage_kind() {
  local path="${QB_DATA_DIR:-${QB_HOME:-/}}"
  storage::qbittorrent_kind_for_path "${path}"
}

qbittorrent::auto_tuning_profile() {
  local net disk
  net="$(qbittorrent::detect_network_tier)"
  disk="$(qbittorrent::detect_storage_kind || true)"
  case "${disk}" in
    hdd|hdd-raid0|ssd|nvme|ceph) printf '%s-%s\n' "${net}" "${disk}" ;;
    *) printf 'legacy\n' ;;
  esac
}

qbittorrent::profile_common_values() {
  case "$1" in
    1g-hdd) printf '4 1024 4096 150\n' ;;
    1g-hdd-raid0) printf '8 1024 8192 150\n' ;;
    1g-ssd) printf '12 1024 8192 200\n' ;;
    1g-nvme) printf '16 1024 16384 200\n' ;;
    1g-ceph) printf '8 1024 16384 200\n' ;;
    10g-hdd) printf '4 1024 16384 150\n' ;;
    10g-hdd-raid0) printf '8 1024 16384 150\n' ;;
    10g-ssd) printf '16 2048 32768 200\n' ;;
    10g-nvme) printf '32 2048 32768 200\n' ;;
    10g-ceph) printf '16 2048 32768 200\n' ;;
    *) return 1 ;;
  esac
}

qbittorrent::profile_libtorrent2_values() {
  case "$1" in
    1g-hdd) printf '1 Default\n' ;;
    1g-hdd-raid0) printf '2 Default\n' ;;
    1g-ssd) printf '4 Default\n' ;;
    1g-nvme) printf '8 MMap\n' ;;
    1g-ceph) printf '2 SimplePreadPwrite\n' ;;
    10g-hdd) printf '1 Default\n' ;;
    10g-hdd-raid0) printf '2 Default\n' ;;
    10g-ssd) printf '8 Default\n' ;;
    10g-nvme) printf '16 MMap\n' ;;
    10g-ceph) printf '4 SimplePreadPwrite\n' ;;
    *) return 1 ;;
  esac
}

qbittorrent::profile_qb455_values() {
  local mib req
  case "$1" in
    1g-hdd) mib=16; req=1000 ;;
    1g-hdd-raid0) mib=64; req=2000 ;;
    1g-ssd) mib=128; req=2000 ;;
    1g-nvme) mib=256; req=4000 ;;
    1g-ceph) mib=64; req=2000 ;;
    10g-hdd) mib=32; req=1000 ;;
    10g-hdd-raid0) mib=128; req=2000 ;;
    10g-ssd) mib=256; req=4000 ;;
    10g-nvme) mib=512; req=8000 ;;
    10g-ceph) mib=256; req=4000 ;;
    *) return 1 ;;
  esac
  printf '%s %s\n' "$((mib * 1024 * 1024))" "${req}"
}

declare -g QB_TUNE_ASYNC_IO_THREADS=""
declare -g QB_TUNE_SEND_BUFFER_LOW_WATERMARK=""
declare -g QB_TUNE_SEND_BUFFER_WATERMARK=""
declare -g QB_TUNE_SEND_BUFFER_WATERMARK_FACTOR=""
declare -g QB_TUNE_HASHING_THREADS=""
declare -g QB_TUNE_DISK_IO_TYPE=""
declare -g QB_TUNE_CONNECTION_SPEED=""
declare -g QB_TUNE_DISK_QUEUE_SIZE=""
declare -g QB_TUNE_REQUEST_QUEUE_SIZE=""
declare -g QB_TUNE_SOCKET_SEND_BUFFER_SIZE=""
declare -g QB_TUNE_SOCKET_RECEIVE_BUFFER_SIZE=""

qbittorrent::resolve_tuning_values() {
  local requested="${QB_TUNING_PROFILE:-${SEEDBOX_QB_TUNING_PROFILE:-auto}}" resolved common lt2 q455
  requested="$(qbittorrent::normalize_tuning_profile "${requested}")" || return $?
  if [[ "${requested}" == "auto" ]]; then
    resolved="$(qbittorrent::auto_tuning_profile)"
  else
    resolved="${requested}"
  fi
  QB_TUNING_PROFILE="${requested}"
  QB_TUNING_PROFILE_RESOLVED="${resolved}"
  QB_TUNE_HASHING_THREADS=""
  QB_TUNE_DISK_IO_TYPE=""
  QB_TUNE_CONNECTION_SPEED=""
  QB_TUNE_DISK_QUEUE_SIZE=""
  QB_TUNE_REQUEST_QUEUE_SIZE=""
  QB_TUNE_SOCKET_SEND_BUFFER_SIZE=""
  QB_TUNE_SOCKET_RECEIVE_BUFFER_SIZE=""

  if [[ "${resolved}" == "legacy" ]]; then
    IFS=' ' read -r QB_TUNE_ASYNC_IO_THREADS QB_TUNE_SEND_BUFFER_LOW_WATERMARK QB_TUNE_SEND_BUFFER_WATERMARK QB_TUNE_SEND_BUFFER_WATERMARK_FACTOR < <(qbittorrent::legacy_storage_tuning_values)
    return 0
  fi

  common="$(qbittorrent::profile_common_values "${resolved}" || true)"
  if [[ -z "${common}" ]]; then
    ui::warn "Could not resolve qBittorrent tuning profile '${resolved}'; falling back to legacy tuning values."
    QB_TUNING_PROFILE_RESOLVED="legacy"
    IFS=' ' read -r QB_TUNE_ASYNC_IO_THREADS QB_TUNE_SEND_BUFFER_LOW_WATERMARK QB_TUNE_SEND_BUFFER_WATERMARK QB_TUNE_SEND_BUFFER_WATERMARK_FACTOR < <(qbittorrent::legacy_storage_tuning_values)
    return 0
  fi
  IFS=' ' read -r QB_TUNE_ASYNC_IO_THREADS QB_TUNE_SEND_BUFFER_LOW_WATERMARK QB_TUNE_SEND_BUFFER_WATERMARK QB_TUNE_SEND_BUFFER_WATERMARK_FACTOR <<<"${common}"

  if qbittorrent::uses_libtorrent2; then
    lt2="$(qbittorrent::profile_libtorrent2_values "${resolved}" || true)"
    if [[ -n "${lt2}" ]]; then
      IFS=' ' read -r QB_TUNE_HASHING_THREADS QB_TUNE_DISK_IO_TYPE <<<"${lt2}"
      # qBittorrent only gained the SimplePreadPwrite disk I/O enum in 5.0.1.
      # Older libtorrent-2 builds have Posix as the closest non-mmap option.
      if [[ "${QB_TUNE_DISK_IO_TYPE}" == "SimplePreadPwrite" ]] && ! qbittorrent::version_ge "${QB_VERSION:-5}" "5.0.1"; then
        QB_TUNE_DISK_IO_TYPE="Posix"
      fi
    fi
  fi

  if qbittorrent::version_ge "${QB_VERSION:-5}" "4.4.5"; then
    QB_TUNE_CONNECTION_SPEED=500
  fi
  if qbittorrent::version_ge "${QB_VERSION:-5}" "4.5.5"; then
    q455="$(qbittorrent::profile_qb455_values "${resolved}" || true)"
    if [[ -n "${q455}" ]]; then
      IFS=' ' read -r QB_TUNE_DISK_QUEUE_SIZE QB_TUNE_REQUEST_QUEUE_SIZE <<<"${q455}"
    fi
  fi
  if qbittorrent::version_ge "${QB_VERSION:-5}" "4.6.7"; then
    QB_TUNE_SOCKET_SEND_BUFFER_SIZE=0
    QB_TUNE_SOCKET_RECEIVE_BUFFER_SIZE=0
  fi
  return 0
}

qbittorrent::session_tuning_config_lines() {
  [[ -n "${QB_TUNE_HASHING_THREADS}" ]] && printf 'Session\\HashingThreadsCount=%s\n' "${QB_TUNE_HASHING_THREADS}"
  [[ -n "${QB_TUNE_DISK_IO_TYPE}" ]] && printf 'Session\\DiskIOType=%s\n' "${QB_TUNE_DISK_IO_TYPE}"
  [[ -n "${QB_TUNE_CONNECTION_SPEED}" ]] && printf 'Session\\ConnectionSpeed=%s\n' "${QB_TUNE_CONNECTION_SPEED}"
  [[ -n "${QB_TUNE_DISK_QUEUE_SIZE}" ]] && printf 'Session\\DiskQueueSize=%s\n' "${QB_TUNE_DISK_QUEUE_SIZE}"
  [[ -n "${QB_TUNE_REQUEST_QUEUE_SIZE}" ]] && printf 'Session\\RequestQueueSize=%s\n' "${QB_TUNE_REQUEST_QUEUE_SIZE}"
  [[ -n "${QB_TUNE_SOCKET_SEND_BUFFER_SIZE}" ]] && printf 'Session\\SocketSendBufferSize=%s\n' "${QB_TUNE_SOCKET_SEND_BUFFER_SIZE}"
  [[ -n "${QB_TUNE_SOCKET_RECEIVE_BUFFER_SIZE}" ]] && printf 'Session\\SocketReceiveBufferSize=%s\n' "${QB_TUNE_SOCKET_RECEIVE_BUFFER_SIZE}"
  return 0
}

qbittorrent::install_instance_dirs() {
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    install -d -m 0700 "${QB_HOME}/.config" "${QB_HOME}/.config/qBittorrent" "${QB_HOME}/qbittorrent" "${QB_DATA_DIR}"
  else
    install -d -m 0700 -o "${QB_USER}" -g "${QB_USER}" "${QB_HOME}/.config" "${QB_HOME}/.config/qBittorrent" "${QB_HOME}/qbittorrent" "${QB_DATA_DIR}"
  fi
}

qbittorrent::write_config_file() {
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    fs::write_file "${QB_CONFIG}" 0600
  else
    fs::write_file "${QB_CONFIG}" 0600 "${QB_USER}" "${QB_USER}"
  fi
}

qbittorrent::write_config() {
  local aio low_buffer buffer buffer_factor family password_line tuning_extra
  qbittorrent::install_instance_dirs
  qbittorrent::resolve_tuning_values || return $?
  aio="${QB_TUNE_ASYNC_IO_THREADS}"
  low_buffer="${QB_TUNE_SEND_BUFFER_LOW_WATERMARK}"
  buffer="${QB_TUNE_SEND_BUFFER_WATERMARK}"
  buffer_factor="${QB_TUNE_SEND_BUFFER_WATERMARK_FACTOR}"
  tuning_extra="$(qbittorrent::session_tuning_config_lines)"
  family="$(qbittorrent::config_family "${QB_VERSION:-5}")"
  if [[ -n "${QB_PASSWORD_LINE_OVERRIDE:-}" ]]; then
    password_line="${QB_PASSWORD_LINE_OVERRIDE}"
  else
    password_line="$(qbittorrent::password_config_line "${QB_WEBUI_USERNAME}" "${QB_PASSWORD}" "${QB_VERSION:-5}")"
  fi

  case "${family}" in
    classic_41)
      qbittorrent::write_config_file <<EOF_CONF
[BitTorrent]
Session\\AsyncIOThreadsCount=${aio}
Session\\SendBufferLowWatermark=${low_buffer}
Session\\SendBufferWatermark=${buffer}
Session\\SendBufferWatermarkFactor=${buffer_factor}
${tuning_extra}

[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Connection\\PortRangeMin=${QB_INCOMING_PORT}
Downloads\\DiskWriteCacheSize=${QB_CACHE_MIB}
Downloads\\SavePath=${QB_DATA_DIR}/
Queueing\\QueueingEnabled=false
${password_line}
WebUI\\Port=${QB_WEB_PORT}
WebUI\\Username=${QB_WEBUI_USERNAME}
EOF_CONF
      ;;
    classic_pbkdf2)
      qbittorrent::write_config_file <<EOF_CONF
[BitTorrent]
Session\\AsyncIOThreadsCount=${aio}
Session\\SendBufferLowWatermark=${low_buffer}
Session\\SendBufferWatermark=${buffer}
Session\\SendBufferWatermarkFactor=${buffer_factor}
${tuning_extra}

[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Connection\\PortRangeMin=${QB_INCOMING_PORT}
Downloads\\DiskWriteCacheSize=${QB_CACHE_MIB}
Downloads\\SavePath=${QB_DATA_DIR}/
Queueing\\QueueingEnabled=false
${password_line}
WebUI\\Port=${QB_WEB_PORT}
WebUI\\Username=${QB_WEBUI_USERNAME}
EOF_CONF
      ;;
    modern_pbkdf2)
      qbittorrent::write_config_file <<EOF_CONF
[Application]
MemoryWorkingSetLimit=${QB_CACHE_MIB}

[BitTorrent]
Session\\AsyncIOThreadsCount=${aio}
Session\\DefaultSavePath=${QB_DATA_DIR}/
Session\\DiskCacheSize=${QB_CACHE_MIB}
Session\\Port=${QB_INCOMING_PORT}
Session\\QueueingSystemEnabled=false
Session\\SendBufferLowWatermark=${low_buffer}
Session\\SendBufferWatermark=${buffer}
Session\\SendBufferWatermarkFactor=${buffer_factor}
${tuning_extra}

[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
${password_line}
WebUI\\Port=${QB_WEB_PORT}
WebUI\\Username=${QB_WEBUI_USERNAME}
EOF_CONF
      ;;
  esac
}

qbittorrent::write_system_service() {
  QB_UNIT="seedbox-qbittorrent-${QB_USER}.service"
  systemd::write_unit "${QB_UNIT}" <<EOF_UNIT
[Unit]
Description=Seedbox qBittorrent-nox instance for ${QB_USER}
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
Type=simple
User=${QB_USER}
Group=${QB_USER}
Environment=HOME=${QB_HOME}
Environment=XDG_CONFIG_HOME=${QB_HOME}/.config
Environment=XDG_DATA_HOME=${QB_HOME}/.local/share
Environment=XDG_CACHE_HOME=${QB_HOME}/.cache
WorkingDirectory=${QB_HOME}
ExecStart=${QB_BINARY}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
UMask=0077
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectControlGroups=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
CapabilityBoundingSet=
LockPersonality=yes

[Install]
WantedBy=multi-user.target
EOF_UNIT
}

qbittorrent::rootless_user_systemd_available() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user show-environment >/dev/null 2>&1 || systemctl --user list-units >/dev/null 2>&1
}

qbittorrent::write_user_service() {
  local unit_dir="${QB_HOME}/.config/systemd/user"
  QB_UNIT="${QB_ROOTLESS_UNIT}"
  mkdir -p "${unit_dir}"
  fs::write_file "${unit_dir}/${QB_UNIT}" 0600 <<EOF_UNIT
[Unit]
Description=Seedbox qBittorrent-nox rootless instance
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
Type=simple
Environment=HOME=%h
Environment=XDG_CONFIG_HOME=%h/.config
Environment=XDG_DATA_HOME=%h/.local/share
Environment=XDG_CACHE_HOME=%h/.cache
WorkingDirectory=%h
ExecStart=${QB_BINARY}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
UMask=0077

[Install]
WantedBy=default.target
EOF_UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now "${QB_UNIT}"
}

qbittorrent::write_screen_launcher() {
  QB_UNIT=""
  local launcher="${QB_HOME}/.local/bin/seedbox-qbittorrent-start"
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    install -d -m 0700 "${QB_HOME}/.local/bin"
    fs::write_file "${launcher}" 0700 <<EOF_LAUNCHER
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=${QB_HOME@Q}
export XDG_CONFIG_HOME=${QB_HOME@Q}/.config
export XDG_DATA_HOME=${QB_HOME@Q}/.local/share
export XDG_CACHE_HOME=${QB_HOME@Q}/.cache
exec screen -DmS seedbox-qbittorrent ${QB_BINARY@Q}
EOF_LAUNCHER
  else
    install -d -m 0700 -o "${QB_USER}" -g "${QB_USER}" "${QB_HOME}/.local/bin"
    fs::write_file "${launcher}" 0700 "${QB_USER}" "${QB_USER}" <<EOF_LAUNCHER
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=${QB_HOME@Q}
export XDG_CONFIG_HOME=${QB_HOME@Q}/.config
export XDG_DATA_HOME=${QB_HOME@Q}/.local/share
export XDG_CACHE_HOME=${QB_HOME@Q}/.cache
exec screen -DmS seedbox-qbittorrent-${QB_USER} ${QB_BINARY@Q}
EOF_LAUNCHER
  fi
}

qbittorrent::write_daemon_launcher() {
  QB_UNIT=""
  local launcher="${QB_HOME}/.local/bin/seedbox-qbittorrent-start"
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    install -d -m 0700 "${QB_HOME}/.local/bin"
    fs::write_file "${launcher}" 0700 <<EOF_LAUNCHER
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=${QB_HOME@Q}
export XDG_CONFIG_HOME=${QB_HOME@Q}/.config
export XDG_DATA_HOME=${QB_HOME@Q}/.local/share
export XDG_CACHE_HOME=${QB_HOME@Q}/.cache
exec ${QB_BINARY@Q} -d </dev/null >/dev/null 2>&1
EOF_LAUNCHER
  else
    install -d -m 0700 -o "${QB_USER}" -g "${QB_USER}" "${QB_HOME}/.local/bin"
    fs::write_file "${launcher}" 0700 "${QB_USER}" "${QB_USER}" <<EOF_LAUNCHER
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=${QB_HOME@Q}
export XDG_CONFIG_HOME=${QB_HOME@Q}/.config
export XDG_DATA_HOME=${QB_HOME@Q}/.local/share
export XDG_CACHE_HOME=${QB_HOME@Q}/.cache
exec ${QB_BINARY@Q} -d </dev/null >/dev/null 2>&1
EOF_LAUNCHER
  fi
}

qbittorrent::cron_marker() {
  printf '%s:%s\n' "${QB_ROOTLESS_CRON_MARKER_PREFIX}" "${QB_USER}"
}

qbittorrent::remove_cron_restart() {
  command -v crontab >/dev/null 2>&1 || return 0
  local marker tmp
  marker="$(qbittorrent::cron_marker)"
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -v -F "${marker}" >"${tmp}" || true
  crontab "${tmp}" 2>/dev/null || true
  rm -f -- "${tmp}"
}

qbittorrent::install_cron_restart() {
  args::has no_cron && return 0
  command -v crontab >/dev/null 2>&1 || { ui::warn "crontab is not available; qBittorrent was started but automatic restart fallback was not installed."; return 0; }
  local marker escaped tmp
  marker="$(qbittorrent::cron_marker)"
  escaped="${QB_RESTART_SCRIPT//\"/\\\"}"
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -v -F "${marker}" >"${tmp}" || true
  printf '*/1 * * * * "%s" >/dev/null 2>&1 # %s\n' "${escaped}" "${marker}" >>"${tmp}"
  crontab "${tmp}"
  rm -f -- "${tmp}"
}

qbittorrent::write_rootless_restart_script() {
  local mode="$1"
  install -d -m 0700 "${QB_HOME}/.local/bin"
  case "${mode}" in
    screen)
      fs::write_file "${QB_RESTART_SCRIPT}" 0700 <<EOF_RESTART
#!/usr/bin/env bash
set -Eeuo pipefail
binary=${QB_BINARY@Q}
export HOME=${QB_HOME@Q}
export XDG_CONFIG_HOME=${QB_HOME@Q}/.config
export XDG_DATA_HOME=${QB_HOME@Q}/.local/share
export XDG_CACHE_HOME=${QB_HOME@Q}/.cache
pgrep -u "\$(id -u)" -f "\${binary}" >/dev/null 2>&1 && exit 0
exec screen -dmS seedbox-qbittorrent "\${binary}"
EOF_RESTART
      ;;
    daemon)
      fs::write_file "${QB_RESTART_SCRIPT}" 0700 <<EOF_RESTART
#!/usr/bin/env bash
set -Eeuo pipefail
binary=${QB_BINARY@Q}
export HOME=${QB_HOME@Q}
export XDG_CONFIG_HOME=${QB_HOME@Q}/.config
export XDG_DATA_HOME=${QB_HOME@Q}/.local/share
export XDG_CACHE_HOME=${QB_HOME@Q}/.cache
pgrep -u "\$(id -u)" -f "\${binary}" >/dev/null 2>&1 && exit 0
exec "\${binary}" -d </dev/null >/dev/null 2>&1
EOF_RESTART
      ;;
  esac
}

qbittorrent::rootless_prompt_service_mode() {
  if [[ ! -t 0 ]]; then
    QB_SERVICE_MODE="auto"
    return 0
  fi
  local selected
  ui::info "Choose qBittorrent startup method:"
  select selected in "Local User Service" "Screen" "Daemon"; do
    case "${selected}" in
      "Local User Service") QB_SERVICE_MODE="user"; break ;;
      "Screen") QB_SERVICE_MODE="screen"; break ;;
      "Daemon") QB_SERVICE_MODE="daemon"; break ;;
      *) ui::warn "Please choose a valid installation method." ;;
    esac
  done
}

qbittorrent::install_rootless_user_service() {
  qbittorrent::rootless_user_systemd_available || { ui::warn "systemctl --user is not available in this session."; return 1; }
  qbittorrent::write_user_service
  ui::warn "User systemd services may stop after logout unless the provider enables lingering or keeps the user manager active."
}

qbittorrent::install_rootless_screen() {
  command -v screen >/dev/null 2>&1 || { ui::warn "screen is not installed."; return 1; }
  qbittorrent::write_screen_launcher
  qbittorrent::write_rootless_restart_script screen
  HOME="${QB_HOME}" XDG_CONFIG_HOME="${QB_HOME}/.config" XDG_DATA_HOME="${QB_HOME}/.local/share" XDG_CACHE_HOME="${QB_HOME}/.cache" screen -dmS seedbox-qbittorrent "${QB_BINARY}"
  qbittorrent::install_cron_restart
}

qbittorrent::install_rootless_daemon() {
  qbittorrent::write_daemon_launcher
  qbittorrent::write_rootless_restart_script daemon
  HOME="${QB_HOME}" XDG_CONFIG_HOME="${QB_HOME}/.config" XDG_DATA_HOME="${QB_HOME}/.local/share" XDG_CACHE_HOME="${QB_HOME}/.cache" "${QB_BINARY}" -d </dev/null >/dev/null 2>&1
  qbittorrent::install_cron_restart
}

qbittorrent::install_rootless_service() {
  local requested="${QB_SERVICE_MODE}"
  if [[ "${requested}" == "prompt" ]]; then
    qbittorrent::rootless_prompt_service_mode
    requested="${QB_SERVICE_MODE}"
  fi

  case "${requested}" in
    user)
      qbittorrent::install_rootless_user_service
      QB_SERVICE_MODE="user"
      ;;
    screen)
      qbittorrent::install_rootless_screen
      QB_SERVICE_MODE="screen"
      ;;
    daemon)
      qbittorrent::install_rootless_daemon
      QB_SERVICE_MODE="daemon"
      ;;
    auto)
      if qbittorrent::install_rootless_user_service; then
        QB_SERVICE_MODE="user"
      elif qbittorrent::install_rootless_screen; then
        QB_SERVICE_MODE="screen"
      else
        ui::warn "Falling back to daemon mode."
        qbittorrent::install_rootless_daemon
        QB_SERVICE_MODE="daemon"
      fi
      ;;
  esac
}

qbittorrent::install_service() {
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    qbittorrent::install_rootless_service
    return 0
  fi

  case "${QB_SERVICE_MODE}" in
    system)
      qbittorrent::write_system_service
      systemd::enable_now "${QB_UNIT}"
      ;;
    screen)
      qbittorrent::write_screen_launcher
      user::run "${QB_USER}" screen -dmS "seedbox-qbittorrent-${QB_USER}" "${QB_BINARY}"
      ;;
    daemon)
      qbittorrent::write_daemon_launcher
      user::run "${QB_USER}" env HOME="${QB_HOME}" XDG_CONFIG_HOME="${QB_HOME}/.config" XDG_DATA_HOME="${QB_HOME}/.local/share" XDG_CACHE_HOME="${QB_HOME}/.cache" "${QB_BINARY}" -d </dev/null >/dev/null 2>&1
      ;;
  esac
}

qbittorrent::process_running() {
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    pgrep -u "$(id -u)" -f "${QB_BINARY}" >/dev/null 2>&1
  else
    pgrep -u "${QB_USER}" -f "${QB_BINARY}" >/dev/null 2>&1
  fi
}

qbittorrent::healthcheck() {
  case "${QB_SERVICE_MODE}" in
    system)
      systemd::is_active "${QB_UNIT}" || return 1
      ;;
    user)
      systemctl --user is-active --quiet "${QB_UNIT}" || qbittorrent::process_running || return 1
      ;;
    screen|daemon)
      qbittorrent::process_running || return 1
      ;;
  esac
  ports::wait_for_listen "${QB_WEB_PORT}" 30 || return 1
}

qbittorrent::write_state() {
  local id
  id="$(qbittorrent::state_id "${QB_USER}")"
  state::write qbittorrent "${id}" <<EOF_STATE
component=qbittorrent-instance
user=${QB_USER}
webui_username=${QB_WEBUI_USERNAME}
rootless=${QB_ROOTLESS}
source=${QB_SOURCE}
qb_version=${QB_VERSION:-existing}
libtorrent_version=${QB_LIBTORRENT_VERSION:-existing}
cache_mib=${QB_CACHE_MIB}
web_port=${QB_WEB_PORT}
incoming_port=${QB_INCOMING_PORT}
service_mode=${QB_SERVICE_MODE}
tuning_profile=${QB_TUNING_PROFILE:-auto}
tuning_profile_resolved=${QB_TUNING_PROFILE_RESOLVED:-}
service=${QB_UNIT}
binary=${QB_BINARY}
home=${QB_HOME}
config=${QB_CONFIG}
data=${QB_DATA_DIR}
restart_script=${QB_RESTART_SCRIPT}
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

qbittorrent::print_success() {
  local ip=""
  ip="$(public_ip::detect || true)"
  ui::heading "qBittorrent installed"
  ui::kv "Unix user" "${QB_USER}"
  ui::kv "WebUI user" "${QB_WEBUI_USERNAME}"
  ui::kv "Mode" "$([[ "${QB_ROOTLESS}" == "1" ]] && printf 'rootless/%s' "${QB_SERVICE_MODE}" || printf 'root/%s' "${QB_SERVICE_MODE}")"
  ui::kv "qBittorrent tuning" "$(qbittorrent::display_tuning_profile "${QB_TUNING_PROFILE_RESOLVED:-${QB_TUNING_PROFILE:-auto}}")"
  if [[ -n "${ip}" ]]; then
    ui::kv "WebUI" "http://${ip}:${QB_WEB_PORT}"
  else
    ui::kv "WebUI" "http://<server-ip>:${QB_WEB_PORT}"
  fi
  ui::kv "Config" "${QB_CONFIG}"
  [[ -n "${QB_UNIT}" ]] && ui::kv "Service" "${QB_UNIT}"
  [[ "${QB_SERVICE_MODE}" == "screen" ]] && ui::kv "Screen" "screen -r seedbox-qbittorrent"
  [[ -n "${QB_RESTART_SCRIPT}" && -f "${QB_RESTART_SCRIPT}" ]] && ui::kv "Restart script" "${QB_RESTART_SCRIPT}"
  ui::log_location
}

qbittorrent::install_from_parsed() {
  qbittorrent::load_install_args || return $?
  QB_PASSWORD="$(secrets::read_password_from_args)" || return $?

  ui::heading "Installing qBittorrent"
  ui::kv "Unix user" "${QB_USER}"
  ui::kv "WebUI user" "${QB_WEBUI_USERNAME}"
  ui::kv "Install mode" "$([[ "${QB_ROOTLESS}" == "1" ]] && printf rootless || printf root)"
  ui::kv "Source" "${QB_SOURCE}"
  if [[ "${QB_SOURCE}" == "static" ]]; then
    ui::kv "Version" "qBittorrent ${QB_VERSION} / libtorrent ${QB_LIBTORRENT_VERSION}"
  fi
  ui::kv "Service mode" "${QB_SERVICE_MODE}"
  ui::kv "WebUI port" "${QB_WEB_PORT}"
  ui::kv "Incoming port" "${QB_INCOMING_PORT}"
  ui::kv "qBittorrent tuning" "$(qbittorrent::display_tuning_profile "${QB_TUNING_PROFILE:-auto}")"
  ui::log_location
  printf '\n'

  runner::must qb.preflight "Preflight checks" "" qbittorrent::preflight_install || return $?
  runner::must qb.packages "Install/check required packages" "" qbittorrent::ensure_packages || return $?
  runner::must qb.user "Create/verify user paths" "" qbittorrent::ensure_user || return $?
  runner::must qb.binary "Install/locate qBittorrent binary" "" qbittorrent::install_binary || return $?
  runner::must qb.config "Write qBittorrent config" "" qbittorrent::write_config || return $?
  runner::must qb.service "Configure/start qBittorrent service" "${QB_UNIT}" qbittorrent::install_service || return $?
  runner::must qb.health "Healthcheck qBittorrent" "${QB_UNIT}" qbittorrent::healthcheck || return $?
  runner::must qb.state "Save instance state" "" qbittorrent::write_state || return $?
  qbittorrent::print_success
}

qbittorrent::read_state_for_user() {
  local user="$1" path
  path="$(qbittorrent::state_path_for_user "${user}")"
  [[ -r "${path}" ]] || { ui::error "No qBittorrent state found for user ${user}."; return 1; }
  QB_USER="${user}"
  QB_WEBUI_USERNAME="$(state::get "${path}" webui_username)"
  QB_ROOTLESS="$(state::get "${path}" rootless)"
  [[ -z "${QB_ROOTLESS}" ]] && QB_ROOTLESS=0
  QB_SOURCE="$(state::get "${path}" source)"
  QB_VERSION="$(state::get "${path}" qb_version)"
  QB_LIBTORRENT_VERSION="$(state::get "${path}" libtorrent_version)"
  QB_CACHE_MIB="$(state::get "${path}" cache_mib)"
  QB_WEB_PORT="$(state::get "${path}" web_port)"
  QB_INCOMING_PORT="$(state::get "${path}" incoming_port)"
  QB_SERVICE_MODE="$(state::get "${path}" service_mode)"
  QB_TUNING_PROFILE="$(state::get "${path}" tuning_profile)"
  QB_TUNING_PROFILE="${QB_TUNING_PROFILE:-auto}"
  QB_TUNING_PROFILE_RESOLVED="$(state::get "${path}" tuning_profile_resolved)"
  QB_UNIT="$(state::get "${path}" service)"
  QB_BINARY="$(state::get "${path}" binary)"
  QB_HOME="$(state::get "${path}" home)"
  QB_CONFIG="$(state::get "${path}" config)"
  QB_DATA_DIR="$(state::get "${path}" data)"
  QB_RESTART_SCRIPT="$(state::get "${path}" restart_script)"
}

qbittorrent::default_user_for_command() {
  local user
  user="$(args::get user)"
  if [[ -n "${user}" ]]; then
    printf '%s\n' "${user}"
  elif [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    id -un
  else
    printf '\n'
  fi
}

qbittorrent::stop_instance() {
  case "${QB_SERVICE_MODE}" in
    system)
      [[ -n "${QB_UNIT}" ]] && systemctl stop "${QB_UNIT}" 2>/dev/null || true
      ;;
    user)
      [[ -n "${QB_UNIT}" ]] && systemctl --user stop "${QB_UNIT}" 2>/dev/null || true
      ;;
    screen|daemon)
      if [[ -n "${QB_BINARY}" ]]; then
        if [[ "${QB_ROOTLESS}" == "1" ]]; then
          pkill -u "$(id -u)" -f "${QB_BINARY}" 2>/dev/null || true
        else
          pkill -u "${QB_USER}" -f "${QB_BINARY}" 2>/dev/null || true
        fi
      fi
      ;;
  esac
}

qbittorrent::start_instance() {
  case "${QB_SERVICE_MODE}" in
    system)
      systemd::restart "${QB_UNIT}"
      ;;
    user)
      systemctl --user restart "${QB_UNIT}"
      ;;
    screen)
      if [[ "${QB_ROOTLESS}" == "1" ]]; then
        HOME="${QB_HOME}" XDG_CONFIG_HOME="${QB_HOME}/.config" XDG_DATA_HOME="${QB_HOME}/.local/share" XDG_CACHE_HOME="${QB_HOME}/.cache" screen -dmS seedbox-qbittorrent "${QB_BINARY}"
      else
        user::run "${QB_USER}" screen -dmS "seedbox-qbittorrent-${QB_USER}" "${QB_BINARY}"
      fi
      ;;
    daemon)
      if [[ "${QB_ROOTLESS}" == "1" ]]; then
        HOME="${QB_HOME}" XDG_CONFIG_HOME="${QB_HOME}/.config" XDG_DATA_HOME="${QB_HOME}/.local/share" XDG_CACHE_HOME="${QB_HOME}/.cache" "${QB_BINARY}" -d </dev/null >/dev/null 2>&1
      else
        user::run "${QB_USER}" env HOME="${QB_HOME}" XDG_CONFIG_HOME="${QB_HOME}/.config" XDG_DATA_HOME="${QB_HOME}/.local/share" XDG_CACHE_HOME="${QB_HOME}/.cache" "${QB_BINARY}" -d </dev/null >/dev/null 2>&1
      fi
      ;;
  esac
}

qbittorrent::upgrade_from_parsed() {
  local user old_binary old_version old_lib old_source config_backup=""
  user="$(qbittorrent::default_user_for_command)"
  [[ -n "${user}" ]] || { ui::error "--user is required when running upgrade as root."; return 2; }
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then validate::die_username "${user}" || return 2; fi
  if [[ ${EUID:-$(id -u)} -ne 0 && "${user}" != "$(id -un)" ]]; then
    ui::error "Rootless upgrade can only manage the current Unix user's qBittorrent instance."
    return 2
  fi
  qbittorrent::read_state_for_user "${user}"
  if [[ "${QB_ROOTLESS}" != "1" ]]; then
    detect::assert_root
  fi

  args::copy_value_alias web_port qb_web_port
  args::copy_value_alias web_port qb_port
  args::copy_value_alias incoming_port qb_incoming_port
  args::copy_value_alias incoming_port listen_port
  args::copy_value_alias cache cache_mib
  args::copy_value_alias qb_tuning_profile qb_profile
  args::copy_value_alias qb_tuning_profile qbtuning_profile
  args::copy_value_alias webui_username webui_user
  args::copy_value_alias webui_username web_user

  QB_CACHE_MIB="$(args::get cache "${QB_CACHE_MIB}")"
  QB_WEB_PORT="$(args::get web_port "${QB_WEB_PORT}")"
  QB_INCOMING_PORT="$(args::get incoming_port "${QB_INCOMING_PORT}")"
  QB_WEBUI_USERNAME="$(args::get webui_username "${QB_WEBUI_USERNAME}")"
  QB_TUNING_PROFILE="$(qbittorrent::normalize_tuning_profile "$(args::get qb_tuning_profile "${QB_TUNING_PROFILE:-auto}")")" || return $?
  validate::positive_int "${QB_CACHE_MIB}" || { ui::error "Invalid cache size: ${QB_CACHE_MIB}"; return 2; }
  validate::unprivileged_port "${QB_WEB_PORT}" || { ui::error "Invalid WebUI port: ${QB_WEB_PORT}"; return 2; }
  validate::unprivileged_port "${QB_INCOMING_PORT}" || { ui::error "Invalid incoming port: ${QB_INCOMING_PORT}"; return 2; }
  qbittorrent::valid_webui_username "${QB_WEBUI_USERNAME}" || { ui::error "Invalid WebUI username."; return 2; }

  old_binary="${QB_BINARY}"
  old_version="${QB_VERSION}"
  old_lib="${QB_LIBTORRENT_VERSION}"
  old_source="${QB_SOURCE}"

  QB_SOURCE="$(args::get source "${QB_SOURCE}")"
  QB_VERSION="$(qbittorrent::normalize_qb_version "$(args::get qb_version "${QB_VERSION}")")"
  QB_LIBTORRENT_VERSION="$(qbittorrent::normalize_libtorrent_version "$(args::get libtorrent_version "${QB_LIBTORRENT_VERSION}")")"
  if args::has allow_unverified_downloads; then SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1; fi
  if [[ "${QB_SOURCE}" == "static" ]]; then
    qbittorrent::resolve_static_manifest_selection || return $?
  fi

  ui::heading "Upgrading qBittorrent for ${QB_USER}"
  ui::kv "From" "${old_source} qB=${old_version} lib=${old_lib}"
  ui::kv "To" "${QB_SOURCE} qB=${QB_VERSION} lib=${QB_LIBTORRENT_VERSION}"
  ui::kv "qBittorrent tuning" "$(qbittorrent::display_tuning_profile "${QB_TUNING_PROFILE:-auto}")"
  ui::log_location
  printf '\n'

  runner::must qb.upgrade.packages "Install/check upgrade dependencies" "" qbittorrent::ensure_packages || return $?
  runner::must qb.upgrade.password "Prepare config password/hash update" "" qbittorrent::prepare_config_password_for_upgrade || return $?
  runner::must qb.upgrade.binary "Install new qBittorrent binary" "" qbittorrent::install_binary || return $?
  if [[ -r "${QB_CONFIG}" ]]; then
    config_backup="$(mktemp)"
    cp -p -- "${QB_CONFIG}" "${config_backup}"
  fi
  runner::must qb.upgrade.stop "Stop qBittorrent" "${QB_UNIT}" qbittorrent::stop_instance || return $?
  runner::must qb.upgrade.config "Rewrite qBittorrent config" "" qbittorrent::write_config || return $?
  if [[ "${QB_SERVICE_MODE}" == "system" ]]; then
    runner::must qb.upgrade.service "Update systemd service" "${QB_UNIT}" qbittorrent::write_system_service || return $?
  elif [[ "${QB_SERVICE_MODE}" == "user" ]]; then
    runner::must qb.upgrade.service "Update user systemd service" "${QB_UNIT}" qbittorrent::write_user_service || return $?
  fi
  if ! runner::run qb.upgrade.start "Start upgraded qBittorrent" "${QB_UNIT}" qbittorrent::start_instance || ! runner::run qb.upgrade.health "Healthcheck upgraded qBittorrent" "${QB_UNIT}" qbittorrent::healthcheck; then
    ui::warn "Upgrade failed. Rolling back to previous binary."
    QB_BINARY="${old_binary}"
    QB_SOURCE="${old_source}"
    QB_VERSION="${old_version}"
    QB_LIBTORRENT_VERSION="${old_lib}"
    if [[ -n "${config_backup}" && -r "${config_backup}" ]]; then
      cp -p -- "${config_backup}" "${QB_CONFIG}" 2>/dev/null || true
    fi
    if [[ "${QB_SERVICE_MODE}" == "system" ]]; then
      qbittorrent::write_system_service >/dev/null 2>&1 || true
    elif [[ "${QB_SERVICE_MODE}" == "user" ]]; then
      qbittorrent::write_user_service >/dev/null 2>&1 || true
    fi
    qbittorrent::start_instance >/dev/null 2>&1 || true
    [[ -n "${config_backup}" ]] && rm -f -- "${config_backup}"
    return 1
  fi
  runner::must qb.upgrade.state "Update instance state" "" qbittorrent::write_state || return $?
  [[ -n "${config_backup}" ]] && rm -f -- "${config_backup}"
  ui::success "qBittorrent upgrade completed for ${QB_USER}. Config file was rewritten for the selected version."
}

qbittorrent::confirm_purge() {
  args::has yes && return 0
  if [[ ! -t 0 ]]; then
    ui::error "--purge requires --yes in non-interactive mode."
    return 1
  fi
  local answer
  printf 'Purge qBittorrent config and downloads for %s? Type PURGE to continue: ' "${QB_USER}" >&2
  IFS= read -r answer
  [[ "${answer}" == "PURGE" ]]
}

qbittorrent::uninstall_from_parsed() {
  local user path unit_path
  user="$(qbittorrent::default_user_for_command)"
  [[ -n "${user}" ]] || { ui::error "--user is required when running uninstall as root."; return 2; }
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then validate::die_username "${user}" || return 2; fi
  if [[ ${EUID:-$(id -u)} -ne 0 && "${user}" != "$(id -un)" ]]; then
    ui::error "Rootless uninstall can only manage the current Unix user's qBittorrent instance."
    return 2
  fi
  qbittorrent::read_state_for_user "${user}"
  if [[ "${QB_ROOTLESS}" != "1" ]]; then
    detect::assert_root
  fi
  path="$(qbittorrent::state_path_for_user "${user}")"

  ui::heading "Uninstalling qBittorrent for ${QB_USER}"
  ui::kv "State" "${path}"
  ui::log_location
  printf '\n'

  runner::run qb.uninstall.stop "Stop qBittorrent" "${QB_UNIT}" qbittorrent::stop_instance || true
  if [[ "${QB_SERVICE_MODE}" == "system" && -n "${QB_UNIT}" ]]; then
    runner::run qb.uninstall.disable "Disable systemd service" "${QB_UNIT}" systemd::stop_disable "${QB_UNIT}" || true
    rm -f -- "/etc/systemd/system/${QB_UNIT}"
    systemctl daemon-reload 2>/dev/null || true
  elif [[ "${QB_SERVICE_MODE}" == "user" && -n "${QB_UNIT}" ]]; then
    systemctl --user disable "${QB_UNIT}" 2>/dev/null || true
    unit_path="${QB_HOME}/.config/systemd/user/${QB_UNIT}"
    rm -f -- "${unit_path}"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  if [[ "${QB_ROOTLESS}" == "1" ]]; then
    qbittorrent::remove_cron_restart || true
    [[ -n "${QB_RESTART_SCRIPT}" ]] && rm -f -- "${QB_RESTART_SCRIPT}"
  fi
  state::remove qbittorrent "$(qbittorrent::state_id "${QB_USER}")"

  if args::has purge; then
    ui::warn "Purge will remove qBittorrent config/data for ${QB_USER}: ${QB_HOME}/.config/qBittorrent ${QB_HOME}/qbittorrent"
    qbittorrent::confirm_purge || return 1
    rm -rf -- "${QB_HOME}/.config/qBittorrent" "${QB_HOME}/qbittorrent"
    ui::warn "Purged qBittorrent config/data for ${QB_USER}."
  else
    ui::success "Uninstalled qBittorrent startup files for ${QB_USER}. Config/data kept."
  fi
}

qbittorrent::status_cmd() {
  args::parse "$@"
  local user json=0
  user="$(qbittorrent::default_user_for_command)"
  args::has json && json=1
  if [[ -n "${user}" ]]; then
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then validate::die_username "${user}" || return 2; fi
    local path service mode rootless port active
    path="$(qbittorrent::state_path_for_user "${user}")"
    [[ -r "${path}" ]] || { ui::error "No qBittorrent state found for ${user}."; return 1; }
    service="$(state::get "${path}" service)"
    mode="$(state::get "${path}" service_mode)"
    rootless="$(state::get "${path}" rootless)"
    port="$(state::get "${path}" web_port)"
    active="unknown"
    if [[ -n "${service}" ]]; then
      if [[ "${rootless}" == "1" && "${mode}" == "user" ]]; then
        systemctl --user is-active --quiet "${service}" && active=active || active=inactive
      elif [[ "${mode}" == "system" ]]; then
        systemd::is_active "${service}" && active=active || active=inactive
      fi
    elif ports::is_listening "${port}"; then
      active=active
    else
      active=inactive
    fi
    if (( json )); then
      printf '{"component":"qbittorrent","user":"%s","service":"%s","web_port":"%s","status":"%s","rootless":"%s"}\n' "${user}" "${service}" "${port}" "${active}" "${rootless:-0}"
    else
      cat "${path}"
      if [[ -n "${service}" ]]; then
        if [[ "${rootless}" == "1" && "${mode}" == "user" ]]; then
          systemctl --user status "${service}" --no-pager -l || true
        elif [[ "${mode}" == "system" ]]; then
          systemctl status "${service}" --no-pager -l || true
        fi
      fi
    fi
  else
    status::all "$@"
  fi
}

qbittorrent::logs() {
  local user="$1"
  if [[ -z "${user}" && ${EUID:-$(id -u)} -ne 0 ]]; then
    user="$(id -un)"
  fi
  [[ -n "${user}" ]] || { ui::error "--user is required when running logs as root."; return 2; }
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then validate::die_username "${user}" || return 2; fi
  qbittorrent::read_state_for_user "${user}"
  if [[ "${QB_SERVICE_MODE}" == "system" && -n "${QB_UNIT}" ]]; then
    ui::info "$(systemd::journal_cmd "${QB_UNIT}")"
    journalctl -u "${QB_UNIT}" -n 200 --no-pager
  elif [[ "${QB_SERVICE_MODE}" == "user" && -n "${QB_UNIT}" ]]; then
    ui::info "journalctl --user -u ${QB_UNIT} -n 200 --no-pager"
    journalctl --user -u "${QB_UNIT}" -n 200 --no-pager
  else
    ui::warn "This instance was installed with ${QB_SERVICE_MODE}. Check process output, screen session, or ${QB_RESTART_SCRIPT:-the restart script}."
  fi
}
