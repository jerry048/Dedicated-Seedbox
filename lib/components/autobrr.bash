# autobrr lifecycle. Native binary install with systemd service.

if [[ -n "${SEEDBOX_COMPONENT_AUTOBRR_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_AUTOBRR_SOURCED=1

: "${SEEDBOX_AUTOBRR_API:=https://api.github.com/repos/autobrr/autobrr/releases/latest}"

autobrr::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl autobrr install --user 用户名 [--autobrr-port 端口] [--autobrr-url URL] [--autobrr-sha256 SHA256]
  seedboxctl autobrr upgrade --user 用户名 [--autobrr-url URL] [--autobrr-sha256 SHA256]
  seedboxctl autobrr uninstall --user 用户名 [--purge] [--yes]
  seedboxctl autobrr status --user 用户名

安全说明：
  如果资源 URL 符合 GitHub release 命名规则，seedboxctl 会自动下载匹配的 checksums.txt。
  仅在自定义或非标准 URL 时传入 --autobrr-sha256。无法解析校验和时，必须显式传入 --allow-unverified-downloads。
  如果省略 --autobrr-url，会通过 GitHub release API 自动发现最新 Linux 资源。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl autobrr install --user USER [--autobrr-port PORT] [--autobrr-url URL] [--autobrr-sha256 SHA256]
  seedboxctl autobrr upgrade --user USER [--autobrr-url URL] [--autobrr-sha256 SHA256]
  seedboxctl autobrr uninstall --user USER [--purge] [--yes]
  seedboxctl autobrr status --user USER

Security:
  seedboxctl automatically downloads the matching autobrr release checksums.txt file when the asset URL follows GitHub release naming.
  Provide --autobrr-sha256 only for custom/non-standard URLs. Without a resolved checksum, pass --allow-unverified-downloads explicitly.
  If --autobrr-url is omitted, the latest Linux asset URL is discovered through GitHub's release API.
USAGE
  fi
}

autobrr::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install) args::parse "$@"; log::init autobrr-install; autobrr::install_from_parsed ;;
    upgrade) args::parse "$@"; log::init autobrr-upgrade; autobrr::upgrade_from_parsed ;;
    uninstall|remove) args::parse "$@"; log::init autobrr-uninstall; autobrr::uninstall_from_parsed ;;
    status) args::parse "$@"; log::init autobrr-status; autobrr::status_from_parsed ;;
    help|-h|--help) autobrr::usage ;;
    *) ui::error "$(ui::tr "未知 autobrr 命令：${sub}" "Unknown autobrr command: ${sub}")"; autobrr::usage; return 2 ;;
  esac
}

autobrr::load_args() {
  AB_USER="$(args::get user)"
  [[ -n "${AB_USER}" ]] || { ui::error "$(ui::tr "需要 --user" "--user is required")"; return 2; }
  validate::die_username "${AB_USER}" || return 2
  AB_PORT="$(args::get autobrr_port 7474)"
  validate::unprivileged_port "${AB_PORT}" || { ui::error "$(ui::tr "无效的 autobrr 端口：${AB_PORT}" "Invalid autobrr port: ${AB_PORT}")"; return 2; }
  AB_HOME="$(user::home "${AB_USER}" 2>/dev/null || true)"
  AB_PREFIX="/opt/seedbox/autobrr"
  AB_BIN="${AB_PREFIX}/autobrr"
  AB_CTL="${AB_PREFIX}/autobrrctl"
  AB_CONFIG_DIR="${AB_HOME}/.config/autobrr"
  AB_CONFIG="${AB_CONFIG_DIR}/config.toml"
  AB_SERVICE="seedbox-autobrr-${AB_USER}.service"
  AB_URL="$(args::get autobrr_url)"
  AB_SHA256="$(args::get autobrr_sha256)"
  if args::has allow_unverified_downloads; then SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1; fi
}

autobrr::asset_arch_pattern() {
  detect::load_arch
  case "${SEEDBOX_ARCH}" in
    amd64) printf 'linux_x86_64' ;;
    arm64) printf 'linux_arm64' ;;
    *) return 1 ;;
  esac
}

autobrr::discover_latest_url() {
  local pattern
  pattern="$(autobrr::asset_arch_pattern)"
  curl -fsSL "${SEEDBOX_AUTOBRR_API}" \
    | grep 'browser_download_url' \
    | grep "${pattern}" \
    | grep '\.tar\.gz' \
    | head -n1 \
    | cut -d '"' -f4
}


autobrr::download_text() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 -o "${dest}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --timeout=30 -O "${dest}" "${url}"
  else
    ui::error "$(ui::tr "未安装 curl 或 wget。" "Neither curl nor wget is installed.")"
    return 1
  fi
}

autobrr::checksum_url_for_asset() {
  local url="$1" asset release_dir version
  url="${url%%\?*}"
  asset="${url##*/}"
  release_dir="${url%/*}"
  if [[ "${asset}" =~ ^autobrr_([0-9]+(\.[0-9]+){1,3})_.*\.tar\.gz$ ]]; then
    version="${BASH_REMATCH[1]}"
    printf '%s/autobrr_%s_checksums.txt\n' "${release_dir}" "${version}"
    return 0
  fi
  return 1
}

autobrr::resolve_sha256() {
  local url="$1" checksum_url tmp asset sha
  if [[ -n "${AB_SHA256}" && "${AB_SHA256}" != "auto" ]]; then
    printf '%s\n' "${AB_SHA256}"
    return 0
  fi
  checksum_url="$(autobrr::checksum_url_for_asset "${url}" || true)"
  [[ -n "${checksum_url}" ]] || return 1
  tmp="$(mktemp /tmp/autobrr.checksums.XXXXXX)"
  if ! autobrr::download_text "${checksum_url}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  asset="${url%%\?*}"
  asset="${asset##*/}"
  sha="$(awk -v asset="${asset}" '
    index($0, asset) {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[A-Fa-f0-9]{64}$/) { print tolower($i); exit }
      }
    }
  ' "${tmp}")"
  rm -f -- "${tmp}"
  [[ "${sha}" =~ ^[a-f0-9]{64}$ ]] || return 1
  printf '%s\n' "${sha}"
}

autobrr::preflight() {
  detect::assert_root || return $?
  detect::assert_supported_os || return $?
  detect::assert_supported_arch || return $?
  user::exists "${AB_USER}" || { ui::error "$(ui::tr "用户不存在：${AB_USER}" "User does not exist: ${AB_USER}")"; return 1; }
  ports::assert_free "${AB_PORT}" "$(ui::tr "autobrr WebUI 端口" "autobrr WebUI port")" || return $?
}

autobrr::packages() {
  apt::update || return $?
  apt::ensure_packages ca-certificates curl tar gzip || return $?
}

autobrr::download_and_extract() {
  local url tmp extract_dir sha
  url="${AB_URL}"
  if [[ -z "${url}" ]]; then
    url="$(autobrr::discover_latest_url)"
  fi
  [[ -n "${url}" ]] || { ui::error "$(ui::tr "无法发现 autobrr release 资源 URL。" "Could not discover autobrr release asset URL.")"; return 1; }

  sha="$(autobrr::resolve_sha256 "${url}" || true)"
  if [[ -z "${sha}" && "${SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS}" != "1" ]]; then
    ui::error "$(ui::tr "无法解析 autobrr 校验和：${url}" "Could not resolve autobrr checksum for: ${url}")"
    ui::error "$(ui::tr "需要匹配的 autobrr_<version>_checksums.txt release 资源，或传入 --autobrr-sha256 SHA256。" "Expected a matching autobrr_<version>_checksums.txt release asset, or pass --autobrr-sha256 SHA256.")"
    return 1
  fi

  tmp="$(mktemp /tmp/autobrr.XXXXXX.tar.gz)"
  download::fetch "${url}" "${tmp}" "${sha}" || return $?
  extract_dir="$(mktemp -d /tmp/autobrr.extract.XXXXXX)"
  if ! tar -xzf "${tmp}" -C "${extract_dir}"; then
    rm -rf -- "${tmp}" "${extract_dir}"
    ui::error "$(ui::tr "无法解压 autobrr release 归档。" "Could not extract autobrr release archive.")"
    return 1
  fi
  install -d -m 0755 -o root -g root "${AB_PREFIX}"
  local autobrr_bin autobrrctl_bin
  autobrr_bin="$(find "${extract_dir}" -type f -name autobrr -print -quit)"
  autobrrctl_bin="$(find "${extract_dir}" -type f -name autobrrctl -print -quit)"
  [[ -n "${autobrr_bin}" ]] || { rm -rf -- "${tmp}" "${extract_dir}"; ui::error "$(ui::tr "release 归档中未找到 autobrr 可执行文件。" "autobrr binary not found inside release archive.")"; return 1; }
  install -m 0755 -o root -g root "${autobrr_bin}" "${AB_BIN}"
  if [[ -n "${autobrrctl_bin}" ]]; then
    install -m 0755 -o root -g root "${autobrrctl_bin}" "${AB_CTL}"
  fi
  rm -rf -- "${tmp}" "${extract_dir}"
}

autobrr::write_config() {
  install -d -m 0700 -o "${AB_USER}" -g "${AB_USER}" "${AB_CONFIG_DIR}"
  if [[ ! -e "${AB_CONFIG}" ]] || args::has force; then
    fs::write_file "${AB_CONFIG}" 0600 "${AB_USER}" "${AB_USER}" <<EOF_CONFIG
host = "0.0.0.0"
port = ${AB_PORT}
baseUrl = "/"
logLevel = "INFO"
checkForUpdates = true

[database]
type = "sqlite"
path = "${AB_CONFIG_DIR}/autobrr.db"
EOF_CONFIG
  fi
}

autobrr::write_service() {
  systemd::write_unit "${AB_SERVICE}" <<EOF_SERVICE
[Unit]
Description=autobrr for ${AB_USER}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${AB_USER}
Group=${AB_USER}
Environment=HOME=${AB_HOME}
ExecStart=${AB_BIN} --config=${AB_CONFIG_DIR}
Restart=on-failure
RestartSec=5s
UMask=0077
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
EOF_SERVICE
  systemctl enable --now "${AB_SERVICE}"
}

autobrr::healthcheck() {
  systemd::is_active "${AB_SERVICE}"
  ports::wait_for_listen "${AB_PORT}" 30
}

autobrr::write_state() {
  state::write autobrr "${AB_USER}" <<EOF_STATE
component=autobrr
user=${AB_USER}
port=${AB_PORT}
binary=${AB_BIN}
config_dir=${AB_CONFIG_DIR}
config=${AB_CONFIG}
service=${AB_SERVICE}
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

autobrr::install_from_parsed() {
  autobrr::load_args || return $?
  ui::heading "$(ui::tr "正在安装 autobrr" "Installing autobrr")"
  ui::kv "$(ui::tr "用户" "User")" "${AB_USER}"
  ui::kv "$(ui::tr "端口" "Port")" "${AB_PORT}"
  ui::log_location
  printf '\n'
  runner::must autobrr.preflight "$(ui::tr "安装前检查" "Preflight checks")" "" autobrr::preflight || return $?
  runner::must autobrr.packages "$(ui::tr "安装软件包" "Install packages")" "" autobrr::packages || return $?
  runner::must autobrr.binary "$(ui::tr "下载/安装 autobrr" "Download/install autobrr")" "" autobrr::download_and_extract || return $?
  runner::must autobrr.config "$(ui::tr "写入 autobrr 配置" "Write autobrr config")" "" autobrr::write_config || return $?
  runner::must autobrr.service "$(ui::tr "配置/启动 autobrr 服务" "Configure/start autobrr service")" "${AB_SERVICE}" autobrr::write_service || return $?
  runner::must autobrr.health "$(ui::tr "检查 autobrr 健康状态" "Healthcheck autobrr")" "${AB_SERVICE}" autobrr::healthcheck || return $?
  runner::must autobrr.state "$(ui::tr "保存 autobrr 状态" "Save autobrr state")" "" autobrr::write_state || return $?
  local ip=""
  ip="$(public_ip::detect || true)"
  if [[ -n "${ip}" ]]; then
    ui::success "$(ui::tr "autobrr 已安装。链接：http://${ip}:${AB_PORT}" "autobrr installed at http://${ip}:${AB_PORT}")"
  else
    ui::success "$(ui::tr "autobrr 已安装。WebUI：http://<server-ip>:${AB_PORT}" "autobrr installed. WebUI: http://<server-ip>:${AB_PORT}")"
  fi
}

autobrr::read_state() {
  local user="$1" path
  path="$(state::path autobrr "${user}")"
  [[ -r "${path}" ]] || { ui::error "$(ui::tr "未找到 ${user} 的 autobrr 状态。" "No autobrr state found for ${user}.")"; return 1; }
  AB_USER="${user}"
  AB_PORT="$(state::get "${path}" port)"
  AB_BIN="$(state::get "${path}" binary)"
  AB_CONFIG_DIR="$(state::get "${path}" config_dir)"
  AB_CONFIG="$(state::get "${path}" config)"
  AB_SERVICE="$(state::get "${path}" service)"
  AB_HOME="$(user::home "${user}")"
  AB_PREFIX="$(dirname -- "${AB_BIN}")"
  AB_CTL="${AB_PREFIX}/autobrrctl"
  AB_URL="$(args::get autobrr_url)"
  AB_SHA256="$(args::get autobrr_sha256)"
  if args::has allow_unverified_downloads; then SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1; fi
}

autobrr::upgrade_from_parsed() {
  local user
  user="$(args::get user)"
  [[ -n "${user}" ]] || { ui::error "$(ui::tr "需要 --user" "--user is required")"; return 2; }
  autobrr::read_state "${user}"
  ui::heading "$(ui::tr "正在为 ${AB_USER} 升级 autobrr" "Upgrading autobrr for ${AB_USER}")"
  ui::log_location
  printf '\n'
  runner::must autobrr.stop "$(ui::tr "停止 autobrr" "Stop autobrr")" "${AB_SERVICE}" systemctl stop "${AB_SERVICE}" || return $?
  runner::must autobrr.binary "$(ui::tr "下载/安装 autobrr" "Download/install autobrr")" "" autobrr::download_and_extract || return $?
  runner::must autobrr.start "$(ui::tr "启动 autobrr" "Start autobrr")" "${AB_SERVICE}" systemctl start "${AB_SERVICE}" || return $?
  runner::must autobrr.health "$(ui::tr "检查 autobrr 健康状态" "Healthcheck autobrr")" "${AB_SERVICE}" autobrr::healthcheck || return $?
  ui::success "$(ui::tr "已为 ${AB_USER} 升级 autobrr。" "autobrr upgraded for ${AB_USER}.")"
}

autobrr::uninstall_from_parsed() {
  local user
  user="$(args::get user)"
  [[ -n "${user}" ]] || { ui::error "$(ui::tr "需要 --user" "--user is required")"; return 2; }
  autobrr::read_state "${user}"
  systemd::stop_disable "${AB_SERVICE}" || true
  rm -f -- "/etc/systemd/system/${AB_SERVICE}"
  systemctl daemon-reload 2>/dev/null || true
  if args::has purge; then
    args::has yes || { ui::error "$(ui::tr "使用 --purge 时必须同时传入 --yes。" "Use --yes with --purge.")"; return 1; }
    ui::warn "$(ui::tr "清理将删除 autobrr 配置目录：${AB_CONFIG_DIR}" "Purge will remove autobrr config directory: ${AB_CONFIG_DIR}")"
    rm -rf -- "${AB_CONFIG_DIR}"
  fi
  state::remove autobrr "${AB_USER}"
  ui::success "$(ui::tr "已为 ${AB_USER} 卸载 autobrr。" "autobrr uninstalled for ${AB_USER}.")"
}

autobrr::status_from_parsed() {
  local user
  user="$(args::get user)"
  [[ -n "${user}" ]] || { ui::error "$(ui::tr "需要 --user" "--user is required")"; return 2; }
  autobrr::read_state "${user}"
  systemctl status "${AB_SERVICE}" --no-pager -l || true
}
