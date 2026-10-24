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
  seedboxctl autobrr install --user USER [--autobrr-port PORT] [--autobrr-url URL] [--autobrr-sha256 SHA256] [OPTIONS]
  seedboxctl autobrr upgrade --user USER [--autobrr-url URL] [--autobrr-sha256 SHA256] [OPTIONS]
  seedboxctl autobrr uninstall --user USER [--purge] [--yes]
  seedboxctl autobrr status [--user USER] [--json] [--check]
  seedboxctl autobrr logs [--user USER] [OPTIONS]

安全说明：
  下载地址符合 GitHub 发布包的命名规则时，会自动下载对应的 checksums.txt；失败时尝试使用 GitHub 发布接口提供的文件校验摘要。
  自定义或非标准下载地址请用 --autobrr-sha256 提供校验值。无法取得校验值时，只有确认风险后才能使用 --allow-unverified-downloads。
  省略 --autobrr-url 时，会通过 GitHub 发布接口查找最新的 Linux tar.gz 安装包。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl autobrr install --user USER [--autobrr-port PORT] [--autobrr-url URL] [--autobrr-sha256 SHA256] [OPTIONS]
  seedboxctl autobrr upgrade --user USER [--autobrr-url URL] [--autobrr-sha256 SHA256] [OPTIONS]
  seedboxctl autobrr uninstall --user USER [--purge] [--yes]
  seedboxctl autobrr status [--user USER] [--json] [--check]
  seedboxctl autobrr logs [--user USER] [OPTIONS]

Security:
  seedboxctl automatically downloads the matching autobrr release checksums.txt file when the asset URL follows GitHub release naming; if that fails, it falls back to the asset digest from GitHub's release API.
  Provide --autobrr-sha256 only for custom/non-standard URLs. Without a resolved checksum, pass --allow-unverified-downloads explicitly.
  If --autobrr-url is omitted, the latest Linux tar.gz asset URL is discovered through GitHub's release API.
USAGE
  fi
}

autobrr::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install)
      args::parse_for autobrr-install "$@" || return $?
      args::has help && {
        autobrr::usage
        return 0
      }
      log::init autobrr-install
      autobrr::install_from_parsed
      ;;
    upgrade)
      args::parse_for autobrr-upgrade "$@" || return $?
      args::has help && {
        autobrr::usage
        return 0
      }
      log::init autobrr-upgrade
      autobrr::upgrade_from_parsed
      ;;
    uninstall | remove)
      args::parse_for autobrr-remove "$@" || return $?
      args::has help && {
        autobrr::usage
        return 0
      }
      log::init autobrr-uninstall
      autobrr::uninstall_from_parsed
      ;;
    status)
      args::parse_for autobrr-status "$@" || return $?
      args::has help && {
        autobrr::usage
        return 0
      }
      autobrr::status_from_parsed
      ;;
    logs) logs::cli autobrr "$@" ;;
    help | -h | --help)
      args::parse_for none "$@" || return $?
      autobrr::usage
      ;;
    *)
      ui::error "$(ui::tr "未知 autobrr 命令：${sub}" "Unknown autobrr command: ${sub}")"
      autobrr::usage
      return 2
      ;;
  esac
}

autobrr::load_args() {
  AB_USER="$(args::get user)"
  [[ -n "${AB_USER}" ]] || {
    ui::error "$(ui::tr "需要 --user" "--user is required")"
    return 2
  }
  validate::die_username "${AB_USER}" || return 2
  AB_PORT="$(args::get autobrr_port 7474)"
  validate::unprivileged_port "${AB_PORT}" || {
    ui::error "$(ui::tr "无效的 autobrr 端口：${AB_PORT}" "Invalid autobrr port: ${AB_PORT}")"
    return 2
  }
  AB_HOME="$(user::home "${AB_USER}" 2>/dev/null || true)"
  AB_PREFIX="/opt/seedbox/autobrr"
  AB_BIN="${AB_PREFIX}/autobrr"
  AB_CTL="${AB_PREFIX}/autobrrctl"
  AB_CONFIG_DIR="${AB_HOME}/.config/autobrr"
  AB_CONFIG="${AB_CONFIG_DIR}/config.toml"
  [[ -n "${AB_HOME}" ]] || return 1
  fs::assert_no_symlink_components "${AB_CONFIG}" || return $?
  [[ ! -e "${AB_CONFIG}" || -f "${AB_CONFIG}" ]] || return 1
  AB_SERVICE="seedbox-autobrr-${AB_USER}.service"
  if [[ -r "${AB_CONFIG}" ]] && ! args::has force; then
    local existing_port
    existing_port="$(autobrr::config_port "${AB_CONFIG}")" || return $?
    validate::unprivileged_port "${existing_port}" || {
      ui::error "Invalid autobrr config port: ${existing_port}"
      return 2
    }
    AB_PORT="$(args::get autobrr_port "${existing_port}")"
    validate::unprivileged_port "${AB_PORT}" || {
      ui::error "Invalid autobrr config port: ${AB_PORT}"
      return 2
    }
  fi
  AB_URL="$(args::get autobrr_url)"
  AB_SHA256="$(args::get autobrr_sha256)"
  if args::has allow_unverified_downloads; then SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1; fi
}

autobrr::asset_arch_patterns() {
  detect::load_arch
  case "${SEEDBOX_ARCH}" in
    # autobrr's tarball uses x86_64, while its Linux packages use amd64.
    # Keep amd64 as a fallback for future/alternate release naming.
    amd64) printf '%s\n' linux_x86_64 linux_amd64 ;;
    # autobrr currently publishes linux_arm64.tar.gz. Accept aarch64 too so
    # custom/mirrored release URLs can still resolve on 64-bit ARM systems.
    arm64) printf '%s\n' linux_arm64 linux_aarch64 ;;
    *) return 1 ;;
  esac
}

autobrr::asset_arch_pattern() {
  autobrr::asset_arch_patterns | head -n1
}

autobrr::asset_name_from_url() {
  local url="$1"
  url="${url%%\?*}"
  url="${url%%#*}"
  printf '%s\n' "${url##*/}"
}

autobrr::discover_latest_url() {
  local patterns
  patterns="$(autobrr::asset_arch_patterns)" || return 1
  curl -fsSL "${SEEDBOX_AUTOBRR_API}" | awk -v patterns="${patterns}" '
    BEGIN { n = split(patterns, pat, "\n") }
    /"browser_download_url"[[:space:]]*:/ {
      url = $0
      sub(/^.*"browser_download_url"[[:space:]]*:[[:space:]]*"/, "", url)
      sub(/"[[:space:],}]*$/, "", url)
      if (url !~ /[.]tar[.]gz$/) next
      for (i = 1; i <= n; i++) {
        if (pat[i] != "" && index(url, pat[i])) { print url; exit }
      }
    }
  '
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

autobrr::normalize_sha256() {
  local sha="$1"
  sha="${sha#sha256:}"
  sha="${sha#SHA256:}"
  sha="$(printf '%s' "${sha}" | tr '[:upper:]' '[:lower:]')"
  [[ "${sha}" =~ ^[a-f0-9]{64}$ ]] || return 1
  printf '%s\n' "${sha}"
}

autobrr::checksum_url_for_asset() {
  local url="$1" asset release_dir version
  url="${url%%\?*}"
  url="${url%%#*}"
  asset="${url##*/}"
  release_dir="${url%/*}"
  if [[ "${asset}" =~ ^autobrr_v?([0-9]+(\.[0-9]+){1,3}([-+][A-Za-z0-9._-]+)?)_.*[.]tar[.]gz$ ]]; then
    version="${BASH_REMATCH[1]}"
    printf '%s/autobrr_%s_checksums.txt\n' "${release_dir}" "${version}"
    return 0
  fi
  return 1
}

autobrr::github_api_url_for_asset() {
  local url="$1"
  url="${url%%\?*}"
  url="${url%%#*}"
  if [[ "${url}" =~ ^https://github[.]com/([^/]+)/([^/]+)/releases/download/([^/]+)/[^/]+$ ]]; then
    printf 'https://api.github.com/repos/%s/%s/releases/tags/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi
  if [[ "${url}" =~ ^https://github[.]com/([^/]+)/([^/]+)/releases/latest/download/[^/]+$ ]]; then
    printf 'https://api.github.com/repos/%s/%s/releases/latest\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

autobrr::resolve_sha256_from_github_api() {
  local url="$1" api tmp asset sha
  api="$(autobrr::github_api_url_for_asset "${url}" || true)"
  [[ -n "${api}" ]] || return 1
  asset="$(autobrr::asset_name_from_url "${url}")"
  tmp="$(mktemp /tmp/autobrr.release.XXXXXX)"
  if ! autobrr::download_text "${api}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  sha="$(awk -v asset="${asset}" '
    function json_string_value(line, value) {
      value = line
      sub(/^[^:]*:[[:space:]]*"/, "", value)
      sub(/",?[[:space:]]*$/, "", value)
      return value
    }
    /"name"[[:space:]]*:/ {
      name = json_string_value($0)
      in_asset = (name == asset)
      next
    }
    in_asset && /"digest"[[:space:]]*:/ {
      digest = json_string_value($0)
      sub(/^sha256:/, "", digest)
      if (length(digest) == 64 && digest ~ /^[A-Fa-f0-9]+$/) { print tolower(digest); exit }
    }
  ' "${tmp}")"
  rm -f -- "${tmp}"
  autobrr::normalize_sha256 "${sha}" || return 1
}

autobrr::resolve_sha256_from_checksums() {
  local url="$1" checksum_url tmp asset sha
  checksum_url="$(autobrr::checksum_url_for_asset "${url}" || true)"
  [[ -n "${checksum_url}" ]] || return 1
  tmp="$(mktemp /tmp/autobrr.checksums.XXXXXX)"
  if ! autobrr::download_text "${checksum_url}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  asset="$(autobrr::asset_name_from_url "${url}")"
  sha="$(awk -v asset="${asset}" '
    {
      asset_seen = 0
      sha = ""
      for (i = 1; i <= NF; i++) {
        token = $i
        gsub(/^\*/, "", token)
        gsub(/^[(]/, "", token)
        gsub(/[)]=?$/, "", token)
        gsub(/^.*\//, "", token)
        if (token == asset) asset_seen = 1
        if (length(token) == 64 && token ~ /^[A-Fa-f0-9]+$/) sha = tolower(token)
      }
      if (asset_seen && sha != "") { print sha; exit }
    }
  ' "${tmp}")"
  rm -f -- "${tmp}"
  autobrr::normalize_sha256 "${sha}" || return 1
}

autobrr::resolve_sha256() {
  local url="$1" sha
  if [[ -n "${AB_SHA256}" && "${AB_SHA256}" != "auto" ]]; then
    autobrr::normalize_sha256 "${AB_SHA256}"
    return $?
  fi
  sha="$(autobrr::resolve_sha256_from_checksums "${url}" || true)"
  if [[ -z "${sha}" ]]; then
    sha="$(autobrr::resolve_sha256_from_github_api "${url}" || true)"
  fi
  [[ -n "${sha}" ]] || return 1
  printf '%s\n' "${sha}"
}

autobrr::preflight() {
  detect::assert_root || return $?
  detect::assert_supported_os || return $?
  detect::assert_supported_arch || return $?
  user::exists "${AB_USER}" || {
    ui::error "$(ui::tr "用户不存在：${AB_USER}" "User does not exist: ${AB_USER}")"
    return 1
  }
  fs::assert_no_symlink_components "${AB_CONFIG}" || return $?
  if [[ -r "${AB_CONFIG}" && "${AB_PORT}" == "$(autobrr::config_port "${AB_CONFIG}")" ]] && systemd::is_active "${AB_SERVICE}"; then
    return 0 # The existing instance already owns this unchanged port.
  fi
  ports::assert_free "${AB_PORT}" "$(ui::tr "autobrr WebUI 端口" "autobrr WebUI port")" || return $?
}

autobrr::packages() {
  apt::update || return $?
  apt::ensure_packages ca-certificates curl tar gzip python3 util-linux || return $?
}

autobrr::download_and_extract() {
  local url tmp extract_dir sha
  url="${AB_URL}"
  if [[ -z "${url}" ]]; then
    url="$(autobrr::discover_latest_url)"
  fi
  [[ -n "${url}" ]] || {
    ui::error "$(ui::tr "无法发现 autobrr release 资源 URL。" "Could not discover autobrr release asset URL.")"
    return 1
  }

  if [[ -n "${AB_SHA256:-}" && "${AB_SHA256}" != auto ]]; then
    sha="$(autobrr::normalize_sha256 "${AB_SHA256}")" || {
      ui::error "Invalid explicitly supplied autobrr SHA-256."
      return 2
    }
  else
    sha="$(autobrr::resolve_sha256 "${url}" || true)"
  fi
  if [[ -z "${sha}" && "${SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS}" != "1" ]]; then
    ui::error "$(ui::tr "无法解析 autobrr 校验和：${url}" "Could not resolve autobrr checksum for: ${url}")"
    ui::error "$(ui::tr "需要匹配的 autobrr_<version>_checksums.txt release 资源、GitHub release API digest，或传入 --autobrr-sha256 SHA256。" "Expected a matching autobrr_<version>_checksums.txt release asset, GitHub release API digest, or pass --autobrr-sha256 SHA256.")"
    return 1
  fi

  tmp="$(mktemp /tmp/autobrr.XXXXXX.tar.gz)" || return $?
  download::fetch "${url}" "${tmp}" "${sha}" || {
    rm -f -- "${tmp}"
    return 1
  }
  extract_dir="$(mktemp -d /tmp/autobrr.extract.XXXXXX)" || {
    rm -f -- "${tmp}"
    return 1
  }
  if ! python3 -I - "${tmp}" <<'PY'
import pathlib
import sys
import tarfile
with tarfile.open(sys.argv[1], "r:gz") as archive:
    for entry in archive.getmembers():
        path = pathlib.PurePosixPath(entry.name)
        if path.is_absolute() or ".." in path.parts or not (entry.isfile() or entry.isdir()):
            raise ValueError("Unsafe autobrr archive entry: " + entry.name)
PY
  then
    rm -rf -- "${tmp}" "${extract_dir}"
    return 1
  fi
  if ! tar -xzf "${tmp}" -C "${extract_dir}"; then
    rm -rf -- "${tmp}" "${extract_dir}"
    ui::error "$(ui::tr "无法解压 autobrr release 归档。" "Could not extract autobrr release archive.")"
    return 1
  fi
  fs::assert_privileged_path "${AB_PREFIX}" || {
    rm -rf -- "${tmp}" "${extract_dir}"
    return 1
  }
  install -d -m 0755 -o root -g root "${AB_PREFIX}" || {
    rm -rf -- "${tmp}" "${extract_dir}"
    return 1
  }
  local autobrr_bin autobrrctl_bin
  autobrr_bin="$(find "${extract_dir}" -type f -name autobrr -print -quit)"
  autobrrctl_bin="$(find "${extract_dir}" -type f -name autobrrctl -print -quit)"
  [[ -n "${autobrr_bin}" ]] || {
    rm -rf -- "${tmp}" "${extract_dir}"
    ui::error "$(ui::tr "release 归档中未找到 autobrr 可执行文件。" "autobrr binary not found inside release archive.")"
    return 1
  }
  local binary_tmp rc=0
  binary_tmp="$(mktemp "${AB_PREFIX}/.autobrr.XXXXXX")" || {
    rm -rf -- "${tmp}" "${extract_dir}"
    return 1
  }
  install -m 0755 -o root -g root "${autobrr_bin}" "${binary_tmp}" || rc=$?
  if ((rc == 0)); then mv -Tf -- "${binary_tmp}" "${AB_BIN}" || rc=$?; fi
  if [[ -n "${autobrrctl_bin}" ]]; then
    if ((rc == 0)); then install -m 0755 -o root -g root "${autobrrctl_bin}" "${binary_tmp}" || rc=$?; fi
    if ((rc == 0)); then mv -Tf -- "${binary_tmp}" "${AB_CTL}" || rc=$?; fi
  fi
  rm -rf -- "${tmp}" "${extract_dir}" "${binary_tmp}"
  return "${rc}"
}

autobrr::config_port() {
  user::run "${AB_USER}" awk '
    /^[[:space:]]*\[/ {exit}
    /^[[:space:]]*(port|"port"|\047port\047)[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*(#.*)?$/, "")
      print; found=1; exit
    }
    END {if (!found) print "7474"}
  ' "$1"
}

autobrr::write_config() {
  fs::ensure_user_dir "${AB_USER}" "${AB_CONFIG_DIR}" || return $?
  fs::assert_no_symlink_components "${AB_CONFIG}" || return $?
  if [[ -e "${AB_CONFIG}" ]] && args::has force; then fs::backup_as "${AB_USER}" "${AB_CONFIG}" || return $?; fi
  if [[ ! -e "${AB_CONFIG}" ]] || args::has force; then
    fs::write_file_as "${AB_USER}" "${AB_CONFIG}" 0600 <<EOF_CONFIG
host = "0.0.0.0"
port = ${AB_PORT}
baseUrl = "/"
logLevel = "INFO"
checkForUpdates = true

[database]
type = "sqlite"
path = "${AB_CONFIG_DIR}/autobrr.db"
EOF_CONFIG
  elif args::has autobrr_port; then
    local content
    # Only change the root port, never a similarly named key in a table.
    content="$(user::run "${AB_USER}" cat -- "${AB_CONFIG}" | awk -v port="${AB_PORT}" '
      BEGIN {root=1; changed=0}
      root && (index($0, "\"\"\"") || index($0, "\047\047\047")) {
        print "Cannot safely edit an autobrr config with multiline root strings; set its port manually." >"/dev/stderr"
        unsafe=1; exit 2
      }
      /^[[:space:]]*\[/ {if (root && !changed) {print "port = " port; changed=1}; root=0}
      root && /^[[:space:]]*(port|"port"|\047port\047)[[:space:]]*=/ {
        sub(/=[[:space:]]*[0-9]+/, "= " port); changed=1
      }
      {print}
      END {if (!unsafe && !changed) print "port = " port}
    ')" || return $?
    printf '%s\n' "${content}" | fs::write_file_as "${AB_USER}" "${AB_CONFIG}" 0600
  else
    AB_PORT="$(autobrr::config_port "${AB_CONFIG}")"
    validate::unprivileged_port "${AB_PORT}" || {
      ui::error "Invalid autobrr config port: ${AB_PORT}"
      return 2
    }
  fi
}

autobrr::write_service() {
  systemd::write_unit "${AB_SERVICE}" <<EOF_SERVICE || return $?
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
  systemctl enable "${AB_SERVICE}" || return $?
  systemctl restart "${AB_SERVICE}"
}

autobrr::healthcheck() {
  systemd::is_active "${AB_SERVICE}" || return $?
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
  local user="$1" path inspect_config="${2:-1}"
  path="$(state::path autobrr "${user}")"
  [[ -r "${path}" ]] || {
    ui::error "$(ui::tr "未找到 ${user} 的 autobrr 状态。" "No autobrr state found for ${user}.")"
    return 1
  }
  AB_USER="${user}"
  AB_PORT="$(state::get "${path}" port)"
  AB_BIN="$(state::get "${path}" binary)"
  AB_CONFIG_DIR="$(state::get "${path}" config_dir)"
  AB_CONFIG="$(state::get "${path}" config)"
  if [[ "${inspect_config}" == 1 && -f "${AB_CONFIG}" && ! -L "${AB_CONFIG}" ]]; then
    AB_PORT="$(autobrr::config_port "${AB_CONFIG}")"
    validate::unprivileged_port "${AB_PORT}" || {
      ui::error "Invalid autobrr config port: ${AB_PORT}"
      return 2
    }
  fi
  AB_SERVICE="$(state::get "${path}" service)"
  AB_HOME="$(user::home "${user}")" || return $?
  AB_PREFIX="$(dirname -- "${AB_BIN}")"
  AB_CTL="${AB_PREFIX}/autobrrctl"
  AB_URL="$(args::get autobrr_url)"
  AB_SHA256="$(args::get autobrr_sha256)"
  if args::has allow_unverified_downloads; then SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS=1; fi
}

autobrr::upgrade_from_parsed() {
  local user
  user="$(args::get user)"
  [[ -n "${user}" ]] || {
    ui::error "$(ui::tr "需要 --user" "--user is required")"
    return 2
  }
  autobrr::read_state "${user}" || return $?
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
  detect::assert_root || return $?
  user="$(args::get user)"
  [[ -n "${user}" ]] || {
    ui::error "$(ui::tr "需要 --user" "--user is required")"
    return 2
  }
  validate::die_username "${user}" || return 2
  autobrr::read_state "${user}" 0 || return $?
  [[ "${AB_SERVICE}" == "seedbox-autobrr-${user}.service" && "${AB_CONFIG}" == "${AB_CONFIG_DIR}/config.toml" ]] || {
    ui::error "Invalid autobrr uninstall state."
    return 2
  }
  if args::has purge; then
    args::has yes || {
      ui::error "$(ui::tr "使用 --purge 时必须同时传入 --yes。" "Use --yes with --purge.")"
      return 1
    }
    fs::safety check-files "${AB_CONFIG_DIR}" --owner "${AB_USER}" config.toml autobrr.db autobrr.db-shm autobrr.db-wal || return $?
    ui::warn "$(ui::tr "只删除 ${AB_CONFIG_DIR} 中的 config.toml 和默认 autobrr.db 数据库文件；保留目录及其他文件。" "Remove only config.toml and default autobrr.db database files in ${AB_CONFIG_DIR}; keep the directory and other files.")"
  fi
  systemctl stop "${AB_SERVICE}" || return $?
  if args::has purge; then
    fs::safety remove-files "${AB_CONFIG_DIR}" --owner "${AB_USER}" config.toml autobrr.db autobrr.db-shm autobrr.db-wal || return $?
  fi
  systemctl disable "${AB_SERVICE}" || return $?
  rm -f -- "/etc/systemd/system/${AB_SERVICE}" || return $?
  systemctl daemon-reload || return $?
  state::remove autobrr "${AB_USER}" || return $?
  ui::success "$(ui::tr "已为 ${AB_USER} 卸载 autobrr。" "autobrr uninstalled for ${AB_USER}.")"
}

autobrr::status_from_parsed() {
  status::component autobrr
}
