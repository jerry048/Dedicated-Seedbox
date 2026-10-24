# Deluge lifecycle. Each supported application/libtorrent ABI stays private.
if [[ -n "${SEEDBOX_COMPONENT_DELUGE_SOURCED:-}" ]]; then return 0; fi
readonly SEEDBOX_COMPONENT_DELUGE_SOURCED=1

deluge::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl deluge {install|add-user} --user USER [OPTIONS]
  seedboxctl deluge upgrade --user USER [OPTIONS]
  seedboxctl deluge uninstall --user USER [--purge] [--yes]
  seedboxctl deluge build-runtime [OPTIONS]
  seedboxctl deluge status [--user USER] [--json] [--check]
  seedboxctl deluge logs [--user USER] [OPTIONS]

安装选项：
  --deluge-version VERSION      1.3.15（默认）|2.2.0
  --deluge-libtorrent-version VERSION  1.3.15: 1.1.14；2.2.0: 1.2.20|2.0.15（默认）
  --deluge-web-port PORT       默认 8112（也可用 --web-port）
  --deluge-rpc-port PORT       默认 58846（也可用 --rpc-port）
  --deluge-incoming-port PORT  默认 45000（也可用 --incoming-port）
  --deluge-cache-mib N         仅 libtorrent 1.x，默认 256 MiB（也可用 --cache-mib）
  --jobs N                    编译任务数（默认 2）
  --source-dir DIR            校验过的本地源码目录
  --password-stdin            从标准输入读取 WebUI 密码
  --password-file FILE        从私有文件读取 WebUI 密码
  --password PASSWORD         WebUI 密码；建议使用 stdin 或密码文件

需要 root、systemd、Debian 12+ 或 Ubuntu 22.04+。不支持 rootless。
Deluge 1.3.15、Python 2 和旧版 TLS 已停止维护，使用前请阅读安全提示。
2.2.0 使用独立 Python 3 和版本组合专用运行环境；libtorrent 2.x 不支持旧版磁盘缓存参数。
WebUI/RPC 仅监听回环地址；远程访问请用 SSH 隧道。
upgrade 保留版本组合和设置；跨主版本/ABI 切换需手动迁移。卸载保留下载和会话数据；
--purge 仅删除五个活动设置文件，保留插件、恢复快照和下载。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl deluge {install|add-user} --user USER [OPTIONS]
  seedboxctl deluge upgrade --user USER [OPTIONS]
  seedboxctl deluge uninstall --user USER [--purge] [--yes]
  seedboxctl deluge build-runtime [OPTIONS]
  seedboxctl deluge status [--user USER] [--json] [--check]
  seedboxctl deluge logs [--user USER] [OPTIONS]

Install options:
  --deluge-version VERSION      1.3.15 (default)|2.2.0
  --deluge-libtorrent-version VERSION  1.3.15: 1.1.14; 2.2.0: 1.2.20|2.0.15 (default)
  --deluge-web-port PORT       Default 8112 (alias: --web-port)
  --deluge-rpc-port PORT       Default 58846 (alias: --rpc-port)
  --deluge-incoming-port PORT  Default 45000 (alias: --incoming-port)
  --deluge-cache-mib N         libtorrent 1.x only; default 256 MiB (alias: --cache-mib)
  --jobs N                    Build jobs (default 2)
  --source-dir DIR            Verified local source directory
  --password-stdin            Read the WebUI password from stdin
  --password-file FILE        Read the WebUI password from a private file
  --password PASSWORD         WebUI password; prefer stdin or a password file

Requires root, systemd, Debian 12+ or Ubuntu 22.04+; no rootless mode.
Deluge 1.3.15, Python 2 and legacy TLS are unsupported; review the security guidance.
2.2.0 uses private Python 3 and pair-specific runtimes; libtorrent 2.x has no legacy disk cache option.
WebUI/RPC bind to loopback only. Use an SSH tunnel for remote access.
Upgrade preserves the selected pair/settings; major/ABI switches require manual migration. Uninstall keeps data;
--purge removes only five active settings files, not plugins, snapshots or downloads.
USAGE
  fi
}

deluge::require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || {
    ui::error "$(ui::tr 'Deluge 管理操作需要 root；不支持 rootless。' 'Deluge management requires root; rootless is not supported.')"
    return 2
  }
}

deluge::warn_legacy() {
  [[ "${DE_VERSION:-1.3.15}" == 1.3.15 ]] || return 0
  ui::warn "$(ui::tr 'Deluge 1.3.15、Python 2 和旧版 TLS 均已停止维护；请勿公开 WebUI/RPC。' 'Deluge 1.3.15, Python 2 and legacy TLS are unsupported; do not publish WebUI/RPC.')"
}

deluge::set_runtime() {
  DE_VERSION="$1" DE_LT_VERSION="$2"
  case "${DE_VERSION}:${DE_LT_VERSION}" in
    1.3.15:1.1.14)
      DE_PREFIX=/opt/deluge-1.3.15
      DE_PYTHON="${DE_PREFIX}/bin/python2.7"
      ;;
    2.2.0:1.2.20 | 2.2.0:2.0.15)
      DE_PREFIX="/opt/deluge-2.2.0-lt-${DE_LT_VERSION}"
      DE_PYTHON="${DE_PREFIX}/bin/python3"
      ;;
    *)
      ui::error "$(ui::tr '不支持的 Deluge/libtorrent 版本组合。' 'Unsupported Deluge/libtorrent pair.')"
      return 2
      ;;
  esac
}

deluge::select_runtime() {
  local version lib
  version="$(args::get deluge_version 1.3.15)"
  lib="$(args::get deluge_libtorrent_version)"
  if ! args::csv_contains "$(args::get components deluge)" qbittorrent && args::has libtorrent_version; then
    [[ -z "${lib}" || "${lib#v}" == "${ARGS[libtorrent_version]#v}" ]] || return 2
    lib="${lib:-$(args::get libtorrent_version)}"
  fi
  [[ -n "${lib}" ]] || { if [[ "${version#v}" == 1.3.15 ]]; then lib=1.1.14; else lib=2.0.15; fi; }
  deluge::set_runtime "${version#v}" "${lib#v}"
}

deluge::build_runtime() {
  local jobs source
  jobs="$(args::get jobs 2)" source="$(args::get source_dir)"
  [[ "${jobs}" =~ ^[1-9][0-9]?$ ]] || return 2
  local -a command=(bash "${SEEDBOX_ROOT}/lib/components/deluge/build-runtime.sh" --jobs "${jobs}")
  if [[ "${DE_VERSION:-1.3.15}" == 2.2.0 ]]; then
    command=(bash "${SEEDBOX_ROOT}/lib/components/deluge/build-runtime-2.sh" --libtorrent-version "${DE_LT_VERSION}" --jobs "${jobs}")
  fi
  if [[ -n "${source}" ]]; then
    fs::assert_no_symlink_components "${source}" || return $?
    command+=(--source-dir "${source}")
  fi
  "${command[@]}" </dev/null
}

deluge::ensure_packages() {
  if command -v python3 >/dev/null && command -v curl >/dev/null && command -v ss >/dev/null; then return 0; fi
  apt::update || return $?
  apt::install python3 curl ca-certificates iproute2
}

deluge::require_platform() (
  source /etc/os-release
  case "${ID}:${VERSION_ID}" in
    debian:*) [[ "${VERSION_ID%%.*}" -ge 12 ]] || return 2 ;;
    ubuntu:*) [[ "${VERSION_ID%%.*}" -ge 22 ]] || return 2 ;;
    *) return 2 ;;
  esac
  case "$(uname -m)" in x86_64 | aarch64) ;; *) return 2 ;; esac
)

deluge::prepare_password() {
  local cache="${SEEDBOX_PASSWORD_STDIN_CACHE:-}" file password
  DE_PASSWORD_FILE="$(mktemp /run/seedbox-deluge-password.XXXXXX)" || return $?
  secrets::track_file "${DE_PASSWORD_FILE}" || return $?
  if args::has password_stdin; then
    if [[ -n "${cache}" && -s "${cache}" ]]; then
      [[ -f "${cache}" && ! -L "${cache}" ]] || return 1
      head -c 4097 -- "${cache}" >"${DE_PASSWORD_FILE}" || return $?
    else
      head -c 4097 >"${DE_PASSWORD_FILE}" || return $?
      if [[ -n "${cache}" ]]; then
        secrets::write_password_cache "${cache}" <"${DE_PASSWORD_FILE}" || return $?
      fi
    fi
  elif args::has password_file; then
    file="$(args::get password_file)"
    [[ -f "${file}" && ! -L "${file}" && -r "${file}" ]] || return 1
    head -c 4097 -- "${file}" >"${DE_PASSWORD_FILE}" || return $?
  elif args::has password; then
    printf '%s' "${ARGS[password]}" >"${DE_PASSWORD_FILE}" || return $?
  else
    password="$(secrets::read_password_from_args)" || return $?
    printf '%s' "${password}" >"${DE_PASSWORD_FILE}" || return $?
    unset password
  fi
  python3 -I "${SEEDBOX_ROOT}/lib/core/delugeconfig.py" password <"${DE_PASSWORD_FILE}"
}

deluge::identity() {
  DE_USER="$(args::get user)"
  validate::die_username "${DE_USER}" || return 2
  if user::exists "${DE_USER}"; then
    [[ "$(id -u "${DE_USER}")" != 0 ]] || return 2
  fi
  DE_UNIT="seedbox-deluged-${DE_USER}.service"
  DE_WEB_UNIT="seedbox-deluge-web-${DE_USER}.service"
  DE_STATE="${SEEDBOX_STATE_DIR}/deluge.${DE_USER}.env"
}

deluge::paths() {
  DE_UID="$(id -u "${DE_USER}")" || return $?
  [[ "${DE_UID}" != 0 ]] || return 2
  DE_HOME="$(user::home "${DE_USER}")" || return $?
  [[ "${DE_HOME}" != / ]] || return 1
  fs::assert_no_symlink_components "${DE_HOME}" || return $?
  [[ -d "${DE_HOME}" && "$(stat -c %u -- "${DE_HOME}")" == "${DE_UID}" ]] || return 1
  DE_CONFIG="${DE_HOME}/.config/deluge"
  DE_DATA="${DE_HOME}/deluge/download"
}

deluge::config() {
  user::run "${DE_USER}" env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH \
    python3 -I "${SEEDBOX_ROOT}/lib/core/delugeconfig.py" "$@" --deluge-version "${DE_VERSION:-1.3.15}" --libtorrent-version "${DE_LT_VERSION:-1.1.14}"
}

deluge::load_install_args() {
  deluge::identity || return $?
  deluge::select_runtime || return $?
  local pair canonical alias
  for pair in 'deluge_web_port:web_port' 'deluge_rpc_port:rpc_port' 'deluge_incoming_port:incoming_port' 'deluge_cache_mib:cache_mib'; do
    canonical="${pair%:*}" alias="${pair#*:}"
    # Generic client options belong to qBittorrent in a combined install.
    if [[ "${alias}" == rpc_port ]] || ! args::csv_contains "$(args::get components deluge)" qbittorrent; then
      if args::has "${canonical}" && args::has "${alias}" && [[ "$(args::get "${canonical}")" != "$(args::get "${alias}")" ]]; then
        ui::error "$(ui::tr 'Deluge 选项与别名值冲突。' 'Conflicting Deluge option and alias values.')"
        return 2
      fi
      args::copy_value_alias "${canonical}" "${alias}"
    fi
  done
  DE_WEB_PORT="$(args::get deluge_web_port 8112)"
  DE_RPC_PORT="$(args::get deluge_rpc_port 58846)"
  DE_INCOMING_PORT="$(args::get deluge_incoming_port 45000)"
  DE_CACHE_MIB="$(args::get deluge_cache_mib 256)"
  local port
  for port in "${DE_WEB_PORT}" "${DE_RPC_PORT}" "${DE_INCOMING_PORT}"; do
    [[ "${port}" =~ ^[1-9][0-9]{3,4}$ ]] && validate::unprivileged_port "${port}" || return 2
  done
  [[ "${DE_WEB_PORT}" != "${DE_RPC_PORT}" && "${DE_WEB_PORT}" != "${DE_INCOMING_PORT}" && "${DE_RPC_PORT}" != "${DE_INCOMING_PORT}" ]] || return 2
  [[ "${DE_CACHE_MIB}" =~ ^[1-9][0-9]{0,6}$ ]] && ((DE_CACHE_MIB <= 1048576)) || return 2
  if [[ "${DE_LT_VERSION}" == 2.0.15 ]] && args::has deluge_cache_mib; then
    ui::error "$(ui::tr 'libtorrent 2.x 不使用旧版磁盘缓存；请去掉 --deluge-cache-mib/--cache-mib。' 'libtorrent 2.x does not use the legacy disk cache; omit --deluge-cache-mib/--cache-mib.')"
    return 2
  fi
  [[ "$(args::get jobs 2)" =~ ^[1-9][0-9]?$ ]] || return 2
}

deluge::lock() {
  fs::assert_privileged_path /run/seedbox-deluge/instance.lock || return $?
  fs::ensure_dir /run/seedbox-deluge 0700 root root || return $?
  exec {DE_LOCK_FD}>/run/seedbox-deluge/instance.lock || return $?
  flock -n "${DE_LOCK_FD}"
}

deluge::unit_text() {
  local kind="$1" executable=deluged options='-d -u 127.0.0.1'
  [[ "${kind}" != web ]] || {
    executable=deluge-web
    options='-i 127.0.0.1'
    [[ "${DE_VERSION:-1.3.15}" != 2.2.0 ]] || options='-d -i 127.0.0.1'
  }
  cat <<EOF
# Managed by seedboxctl: Deluge ${DE_VERSION:-1.3.15}.
[Unit]
Description=Seedbox Deluge ${DE_VERSION:-1.3.15} ${kind} for ${DE_USER}
After=network-online.target
Wants=network-online.target
EOF
  [[ "${kind}" != web ]] || printf 'After=%s\nRequires=%s\n' "${DE_UNIT}" "${DE_UNIT}"
  cat <<EOF

[Service]
Type=simple
User=${DE_USER}
WorkingDirectory=~
UMask=0077
Environment=PYTHONNOUSERSITE=1
Environment=SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
Environment=SSL_CERT_DIR=/etc/ssl/certs
UnsetEnvironment=PYTHONHOME PYTHONPATH LD_LIBRARY_PATH XDG_CONFIG_HOME XDG_DATA_HOME
ExecStart=${DE_PREFIX:-/opt/deluge-1.3.15}/bin/${executable} ${options} -L info
Restart=on-failure
RestartSec=5
TimeoutStopSec=45
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK

[Install]
WantedBy=multi-user.target
EOF
}

# Refuse foreign units, aliases, transient replacements and administrator drop-ins.
deluge::check_units() {
  local managed="${1:-0}" unit root path key digest output
  for unit in "${DE_UNIT}" "${DE_WEB_UNIT}"; do
    for root in /etc/systemd/system /run/systemd/system /usr/local/lib/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
      for path in "${root}/${unit}.d" "${root}/service.d" "${root}/seedbox-.service.d" "${root}/seedbox-deluge-.service.d" "${root}/seedbox-deluged-.service.d" "${root}/seedbox-deluge-web-.service.d"; do
        [[ ! -e "${path}" && ! -L "${path}" ]] || return 1
      done
      path="${root}/${unit}"
      if [[ -e "${path}" || -L "${path}" ]]; then
        [[ "${managed}" == 1 && "${root}" == /etc/systemd/system && -f "${path}" && ! -L "${path}" ]] || return 1
        fs::assert_privileged_path "${path}" || return $?
      fi
    done
    if [[ "${managed}" == 1 ]]; then
      key=unit_sha256
      [[ "${unit}" != "${DE_WEB_UNIT}" ]] || key=web_unit_sha256
      digest="$(sha256sum "/etc/systemd/system/${unit}")" || return $?
      [[ "${digest%% *}" == "${STATUS_STATE[${key}]:-}" ]] || return 1
    fi
    local query_rc=0
    output="$(systemctl show --no-pager --property=LoadState --property=FragmentPath --property=DropInPaths "${unit}")" || query_rc=$?
    ((query_rc == 0)) || { [[ "${managed}" == 0 && "${output}" == *LoadState=not-found* ]] || return 1; }
    [[ "${output}" == *FragmentPath=* && "${output}" == *DropInPaths=* ]] || return 1
    while IFS= read -r path; do
      case "${path}" in
        DropInPaths=) ;;
        DropInPaths=*) return 1 ;;
        FragmentPath=) [[ "${managed}" != 1 ]] || return 1 ;;
        FragmentPath=*) [[ "${managed}" == 1 && "${path#*=}" == "/etc/systemd/system/${unit}" ]] || return 1 ;;
      esac
    done <<<"${output}"
  done
}

deluge::read_state_for_user() {
  fs::assert_privileged_path "${DE_STATE}" || return $?
  status::read_state "${DE_STATE}" || return $?
  local recorded_version="${STATUS_STATE[deluge_version]:-1.3.15}" recorded_lib="${STATUS_STATE[libtorrent_version]:-1.1.14}"
  if args::has deluge_libtorrent_version && args::has libtorrent_version; then
    [[ "${ARGS[deluge_libtorrent_version]#v}" == "${ARGS[libtorrent_version]#v}" ]] || return 2
  fi
  if args::has deluge_version || args::has deluge_libtorrent_version || args::has libtorrent_version; then
    local requested_version="$(args::get deluge_version "${recorded_version}")" requested_lib="$(args::get deluge_libtorrent_version "$(args::get libtorrent_version "${recorded_lib}")")"
    [[ "${requested_version#v}" == "${recorded_version}" && "${requested_lib#v}" == "${recorded_lib}" ]] || {
      ui::error "$(ui::tr '版本/ABI 切换需手动迁移或使用新 Unix 账号；upgrade 保留已记录的版本组合。' 'Version/ABI switches require manual migration or a new Unix account; upgrade preserves the recorded pair.')"
      return 2
    }
  fi
  deluge::set_runtime "${recorded_version}" "${recorded_lib}" || return $?
  deluge::paths || return $?
  [[ "${STATUS_STATE[component]:-}" == deluge-instance && "${STATUS_STATE[user]:-}" == "${DE_USER}" &&
    "${STATUS_STATE[uid]:-}" == "${DE_UID}" && "${STATUS_STATE[home]:-}" == "${DE_HOME}" &&
    "${STATUS_STATE[config]:-}" == "${DE_CONFIG}" && "${STATUS_STATE[service]:-}" == "${DE_UNIT}" &&
    "${STATUS_STATE[web_service]:-}" == "${DE_WEB_UNIT}" && "${STATUS_STATE[service_mode]:-}" == system ]] || return 1
  deluge::check_units 1
}

deluge::read_settings() {
  local output key value
  output="$(deluge::config read)" || return $?
  while IFS='=' read -r key value; do
    case "${key}" in
      web_port) DE_WEB_PORT="${value}" ;;
      rpc_port) DE_RPC_PORT="${value}" ;;
      incoming_port) DE_INCOMING_PORT="${value}" ;;
      cache_mib) DE_CACHE_MIB="${value}" ;;
      data) DE_DATA="${value}" ;;
    esac
  done <<<"${output}"
}

deluge::write_state() {
  local daemon_hash web_hash
  daemon_hash="$(sha256sum "/etc/systemd/system/${DE_UNIT}")" || return $?
  web_hash="$(sha256sum "/etc/systemd/system/${DE_WEB_UNIT}")" || return $?
  state::write deluge "${DE_USER}" <<EOF
component=deluge-instance
user=${DE_USER}
uid=${DE_UID}
rootless=0
source=private-runtime
deluge_version=${DE_VERSION}
libtorrent_version=${DE_LT_VERSION}
cache_mib=${DE_CACHE_MIB}
web_port=${DE_WEB_PORT}
rpc_port=${DE_RPC_PORT}
incoming_port=${DE_INCOMING_PORT}
service_mode=system
service=${DE_UNIT}
web_service=${DE_WEB_UNIT}
unit_sha256=${daemon_hash%% *}
web_unit_sha256=${web_hash%% *}
binary=${DE_PREFIX}/bin/deluged
runtime=${DE_PREFIX}
home=${DE_HOME}
config=${DE_CONFIG}
data=${DE_DATA}
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF
}

deluge::write_services() {
  deluge::unit_text daemon | fs::write_file "/etc/systemd/system/${DE_UNIT}" 0644 root root || return $?
  deluge::unit_text web | fs::write_file "/etc/systemd/system/${DE_WEB_UNIT}" 0644 root root || return $?
  systemd::daemon_reload
}

deluge::start() { systemctl enable --now "${DE_UNIT}" "${DE_WEB_UNIT}"; }
deluge::stop() { systemctl stop "${DE_WEB_UNIT}" "${DE_UNIT}"; }
deluge::disable() { systemctl disable --now "${DE_WEB_UNIT}" "${DE_UNIT}"; }

deluge::refresh_port_reservations() {
  declare -F tuning::refresh_reserved_ports >/dev/null 2>&1 || return 0
  tuning::refresh_reserved_ports
}

deluge::confirm_purge() {
  args::has yes && return 0
  [[ -t 0 ]] || {
    ui::error "$(ui::tr '--purge 在非交互模式下需要 --yes。' '--purge requires --yes in non-interactive mode.')"
    return 1
  }
  local answer
  printf '%s' "$(ui::tr '仅删除 Deluge 活动设置（保留下载）？输入 PURGE 继续：' 'Remove active Deluge settings only (downloads kept)? Type PURGE to continue: ')" >&2
  IFS= read -r answer || return 1
  [[ "${answer}" == PURGE ]]
}

deluge::healthcheck() {
  local attempt unit pid
  for ((attempt = 0; attempt < 30; attempt++)); do
    if systemd::is_active "${DE_UNIT}" && systemd::is_active "${DE_WEB_UNIT}"; then
      if [[ -n "${DE_PASSWORD_FILE:-}" ]]; then
        user::run "${DE_USER}" python3 -I "${SEEDBOX_ROOT}/lib/components/deluge/check-instance.py" \
          --web-port "${DE_WEB_PORT}" --deluge-version "${DE_VERSION}" <"${DE_PASSWORD_FILE}" && break
      else
        user::run "${DE_USER}" env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH PYTHONNOUSERSITE=1 \
          "${DE_PYTHON}" -s "${SEEDBOX_ROOT}/lib/components/deluge/rpc-check.py" --rpc-port "${DE_RPC_PORT}" --deluge-version "${DE_VERSION}" \
          && curl --fail --silent --max-time 5 --noproxy '*' "http://127.0.0.1:${DE_WEB_PORT}/" >/dev/null && break
      fi
    fi
    sleep 1
  done
  ((attempt < 30)) || return 1
  for unit in "${DE_UNIT}" "${DE_WEB_UNIT}"; do
    pid="$(systemctl show -p MainPID --value "${unit}")" || return $?
    [[ "${pid}" =~ ^[1-9][0-9]*$ && "$(stat -c %u "/proc/${pid}")" == "${DE_UID}" &&
    "$(user::run "${DE_USER}" readlink "/proc/${pid}/exe")" == "$(readlink -e -- "${DE_PYTHON}")" ]] || return 1
  done
}

deluge::preflight_install() {
  systemd::require || return $?
  deluge::lock || return $?
  fs::assert_privileged_path "${DE_STATE}" || return $?
  [[ ! -e "${DE_STATE}" ]] || {
    ui::error "$(ui::tr '实例已存在，请使用 upgrade。' 'Instance already exists; use upgrade.')"
    return 1
  }
  deluge::check_units || return $?
  local port
  for port in "${DE_WEB_PORT}" "${DE_RPC_PORT}" "${DE_INCOMING_PORT}"; do ports::assert_free "${port}" || return $?; done
  # A socket bind also fails closed if listener enumeration is incomplete.
  python3 - "${DE_WEB_PORT}" "${DE_RPC_PORT}" "${DE_INCOMING_PORT}" <<'PY' || return $?
import socket
import sys
sockets = []
try:
    for port in map(int, sys.argv[1:]):
        for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
            connection = socket.socket(socket.AF_INET, kind)
            sockets.append(connection)
            if kind == socket.SOCK_STREAM:
                connection.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            connection.bind(("0.0.0.0", port))
finally:
    for connection in sockets:
        connection.close()
PY
  if user::exists "${DE_USER}"; then
    deluge::paths || return $?
    deluge::config preflight || return $?
  fi
}

deluge::ensure_user() {
  user::ensure "${DE_USER}" || return $?
  deluge::paths || return $?
  deluge::config preflight
}

deluge::write_config() {
  deluge::config create --web-port "${DE_WEB_PORT}" --rpc-port "${DE_RPC_PORT}" \
    --incoming-port "${DE_INCOMING_PORT}" --cache-mib "${DE_CACHE_MIB}" <"${DE_PASSWORD_FILE}"
}

deluge::print_success() {
  ui::heading "$(ui::tr "Deluge ${DE_VERSION} / libtorrent ${DE_LT_VERSION} 已就绪" "Deluge ${DE_VERSION} / libtorrent ${DE_LT_VERSION} ready")"
  ui::kv "$(ui::tr 'Unix 用户' 'Unix user')" "${DE_USER}"
  ui::kv WebUI "http://127.0.0.1:${DE_WEB_PORT}"
  ui::kv "$(ui::tr '配置' 'Config')" "${DE_CONFIG}"
  ui::kv "$(ui::tr '服务' 'Services')" "${DE_UNIT}, ${DE_WEB_UNIT}"
  ui::pending "$(ui::tr '远程访问 WebUI 请使用 SSH 隧道；不要开放 WebUI/RPC 公网端口。' 'Use an SSH tunnel for remote WebUI access; do not expose WebUI/RPC publicly.')"
  ui::log_location
}

deluge::operation_cleanup() {
  local rc="$1"
  if ((rc != 0 && DE_ACTIVATING)); then deluge::disable || true; fi
  if ((rc != 0 && DE_UPGRADE_STOPPED)); then
    deluge::stop || true
    if [[ -n "${DE_SNAPSHOT}" ]]; then
      deluge::config restore --snapshot "${DE_SNAPSHOT}" || ui::warn "$(ui::tr '配置自动恢复失败；请保留快照并手动检查。' 'Automatic settings restore failed; retain the snapshot and review manually.')"
    fi
    if ((DE_RECONCILING)); then
      printf '%s\n' "${DE_OLD_UNIT}" | fs::write_file "/etc/systemd/system/${DE_UNIT}" 0644 root root || true
      printf '%s\n' "${DE_OLD_WEB_UNIT}" | fs::write_file "/etc/systemd/system/${DE_WEB_UNIT}" 0644 root root || true
      printf '%s\n' "${DE_OLD_STATE}" | fs::write_file "${DE_STATE}" 0600 root root || true
      systemd::daemon_reload || true
    fi
    ui::warn "$(ui::tr "升级未完成；服务保持停止，恢复快照：${DE_SNAPSHOT:-none}" "Upgrade incomplete; services left stopped; recovery snapshot: ${DE_SNAPSHOT:-none}")"
  fi
  [[ -z "${DE_PASSWORD_FILE}" ]] || secrets::cleanup_file "${DE_PASSWORD_FILE}" || true
  if [[ -n "${DE_LOCK_FD}" ]]; then exec {DE_LOCK_FD}>&-; fi
}

# Dynamic scope keeps credentials and locks local without losing runner counters
# or the combined profile's progress/summary state in a subshell.
deluge::managed_operation() {
  local DE_PASSWORD_FILE='' DE_ACTIVATING=0 DE_UPGRADE_STOPPED=0 DE_SNAPSHOT='' DE_LOCK_FD=''
  local DE_RECONCILING=0 DE_OLD_UNIT='' DE_OLD_WEB_UNIT='' DE_OLD_STATE=''
  local rc=0 saved_traps saved_umask
  saved_umask="$(umask)"
  umask 077
  saved_traps="$(trap -p INT TERM HUP)"
  trap 'deluge::operation_cleanup 130; exit 130' INT
  trap 'deluge::operation_cleanup 143; exit 143' TERM HUP
  "$@" || rc=$?
  deluge::operation_cleanup "${rc}"
  trap - INT TERM HUP
  [[ -z "${saved_traps}" ]] || eval "${saved_traps}"
  umask "${saved_umask}"
  return "${rc}"
}

deluge::install_from_parsed() { deluge::managed_operation deluge::install_steps; }
deluge::install_steps() {
  set +x
  deluge::require_root || return $?
  deluge::load_install_args || return $?
  deluge::warn_legacy || return $?
  deluge::require_platform || {
    ui::error "$(ui::tr 'Deluge 需要 Debian 12+ 或 Ubuntu 22.04+（amd64/arm64）。' 'Deluge requires Debian 12+ or Ubuntu 22.04+ (amd64/arm64).')"
    return 2
  }
  systemd::require || return $?
  runner::must deluge.packages "Install/check required packages" "" deluge::ensure_packages || return $?
  runner::must deluge.preflight "Preflight checks" "" deluge::preflight_install || return $?
  # Validation happens before any build, profile creation, or service activation.
  deluge::prepare_password || return $?
  runner::must deluge.runtime "$(ui::tr '编译/验证 Deluge 私有运行环境' 'Build/verify private Deluge runtime')" "" deluge::build_runtime || return $?
  runner::must deluge.user "Create/verify user paths" "" deluge::ensure_user || return $?
  deluge::check_units || return $?
  runner::must deluge.config "$(ui::tr '创建 Deluge 配置' 'Create Deluge configuration')" "" deluge::write_config || return $?
  if [[ "${DE_LT_VERSION}" == 2.0.15 ]]; then DE_CACHE_MIB=n/a; fi
  runner::must deluge.units "$(ui::tr '写入 Deluge 服务' 'Write Deluge services')" "${DE_UNIT}" deluge::write_services || return $?
  # Retain an identity record even if readiness fails, so uninstall is possible.
  runner::must deluge.state "Save instance state" "" deluge::write_state || return $?
  DE_ACTIVATING=1
  runner::must deluge.service "$(ui::tr '启动 Deluge 服务' 'Start Deluge services')" "${DE_UNIT}" deluge::start || return $?
  runner::must deluge.health "$(ui::tr '检查 Deluge WebUI/RPC' 'Check Deluge WebUI/RPC')" "${DE_UNIT}" deluge::healthcheck || return $?
  DE_ACTIVATING=0
  deluge::refresh_port_reservations || ui::warn "$(ui::tr '未能更新主机端口保留设置。' 'Could not update host port reservations.')"
  deluge::print_success
}

deluge::upgrade_from_parsed() { deluge::managed_operation deluge::upgrade_steps; }
deluge::upgrade_steps() {
  deluge::require_root || return $?
  deluge::identity || return $?
  systemd::require || return $?
  deluge::lock || return $?
  deluge::read_state_for_user || return $?
  deluge::warn_legacy || return $?
  # This version-pinned upgrade reconciles managed services, not the shared ABI.
  runner::must deluge.runtime "$(ui::tr '编译/验证 Deluge 私有运行环境' 'Build/verify private Deluge runtime')" "" deluge::build_runtime || return $?
  deluge::check_units 1 || return $?
  DE_OLD_UNIT="$(cat -- "/etc/systemd/system/${DE_UNIT}")" || return $?
  DE_OLD_WEB_UNIT="$(cat -- "/etc/systemd/system/${DE_WEB_UNIT}")" || return $?
  DE_OLD_STATE="$(cat -- "${DE_STATE}")" || return $?
  DE_UPGRADE_STOPPED=1
  runner::must deluge.stop "$(ui::tr '停止 Deluge 服务' 'Stop Deluge services')" "${DE_UNIT}" deluge::stop || return $?
  DE_SNAPSHOT="$(deluge::config snapshot)" || return $?
  ui::kv "$(ui::tr '升级前配置快照' 'Pre-upgrade config snapshot')" "${DE_SNAPSHOT}"
  deluge::read_settings || return $?
  DE_RECONCILING=1
  runner::must deluge.units "$(ui::tr '写入 Deluge 服务' 'Write Deluge services')" "${DE_UNIT}" deluge::write_services || return $?
  runner::must deluge.state "Save instance state" "" deluge::write_state || return $?
  runner::must deluge.service "$(ui::tr '启动 Deluge 服务' 'Start Deluge services')" "${DE_UNIT}" deluge::start || return $?
  runner::must deluge.health "$(ui::tr '检查 Deluge WebUI/RPC' 'Check Deluge WebUI/RPC')" "${DE_UNIT}" deluge::healthcheck || return $?
  DE_UPGRADE_STOPPED=0
  deluge::refresh_port_reservations || ui::warn "$(ui::tr '未能更新主机端口保留设置。' 'Could not update host port reservations.')"
  deluge::print_success
}

deluge::uninstall_from_parsed() { deluge::managed_operation deluge::uninstall_steps; }
deluge::uninstall_steps() {
  deluge::require_root || return $?
  deluge::identity || return $?
  systemd::require || return $?
  deluge::lock || return $?
  deluge::read_state_for_user || return $?
  if args::has purge; then
    deluge::confirm_purge || return 1
  fi
  runner::must deluge.disable "$(ui::tr '停止并禁用 Deluge 服务' 'Stop and disable Deluge services')" "${DE_UNIT}" deluge::disable || return $?
  if args::has purge; then runner::must deluge.purge "$(ui::tr '仅删除 Deluge 活动设置' 'Remove active Deluge settings only')" "" deluge::config purge || return $?; fi
  rm -f -- "/etc/systemd/system/${DE_WEB_UNIT}" "/etc/systemd/system/${DE_UNIT}" || return $?
  systemd::daemon_reload || return $?
  state::remove deluge "${DE_USER}" || return $?
  deluge::refresh_port_reservations || ui::warn "$(ui::tr '未能更新主机端口保留设置。' 'Could not update host port reservations.')"
  ui::info "$(ui::tr 'Deluge 服务已卸载；私有运行环境、下载和会话数据均已保留。' 'Deluge services removed; private runtime, downloads and session data are kept.')"
}

deluge::cli() {
  local action="${1:-help}" context
  (($# == 0)) || shift
  case "${action}" in
    install | add-user) context=deluge-install ;;
    upgrade) context=deluge-upgrade ;;
    uninstall) context=deluge-remove ;;
    build-runtime) context=deluge-build ;;
    status) context=deluge-status ;;
    logs)
      logs::cli deluge "$@"
      return $?
      ;;
    help | --help | -h)
      deluge::usage
      return 0
      ;;
    *)
      deluge::usage
      return 2
      ;;
  esac
  args::parse_for "${context}" "$@" || return $?
  args::has help && {
    deluge::usage
    return 0
  }
  [[ "${action}" != status ]] || {
    status::component deluge
    return $?
  }
  deluge::require_root || return $?
  log::init "deluge-${action}" || return $?
  case "${action}" in
    install | add-user) deluge::install_from_parsed ;;
    upgrade) deluge::upgrade_from_parsed ;;
    uninstall) deluge::uninstall_from_parsed ;;
    build-runtime)
      deluge::select_runtime || return $?
      deluge::warn_legacy || return $?
      runner::must deluge.runtime "$(ui::tr '编译/验证 Deluge 私有运行环境' 'Build/verify private Deluge runtime')" "" deluge::build_runtime
      ;;
  esac
}
