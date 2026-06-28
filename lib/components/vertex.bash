# Vertex container lifecycle.

if [[ -n "${SEEDBOX_COMPONENT_VERTEX_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_VERTEX_SOURCED=1

: "${SEEDBOX_VERTEX_IMAGE:=lswl/vertex:stable}"

declare -g VERTEX_NAME=""
declare -g VERTEX_PORT=""
declare -g VERTEX_DATA_DIR=""
declare -g VERTEX_IMAGE=""
declare -g VERTEX_TZ=""
declare -g VERTEX_HOST_NETWORK="0"
declare -g VERTEX_WEB_USER=""
declare -g VERTEX_WEB_PASSWORD=""

vertex::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl vertex install [--user WebUI用户名] [--password-stdin|--password-file 文件|--password 密码] [选项]
  seedboxctl vertex upgrade [--vertex-image 镜像]
  seedboxctl vertex uninstall [--purge] [--yes]
  seedboxctl vertex status

安装选项：
  --vertex-port 端口
  --vertex-data-dir 目录
  --vertex-image 镜像
  --host-network
  --timezone 时区

默认值：
  镜像：lswl/vertex:stable
  数据：/root/vertex
  端口：3000
  时区：Asia/Shanghai

说明：
  默认网络会把宿主机端口映射到容器内 3000 端口。只有明确需要 Docker host 网络时才使用 --host-network。
  如果传入 --user 和密码选项，seedboxctl 会在首次启动前写入 Vertex WebUI 用户名和密码。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl vertex install [--user WEBUI_USER] [--password-stdin|--password-file FILE|--password PASSWORD] [options]
  seedboxctl vertex upgrade [--vertex-image IMAGE]
  seedboxctl vertex uninstall [--purge] [--yes]
  seedboxctl vertex status

Install options:
  --vertex-port PORT
  --vertex-data-dir DIR
  --vertex-image IMAGE
  --host-network
  --timezone TZ

Defaults:
  image: lswl/vertex:stable
  data:  /root/vertex
  port:  3000
  tz:    Asia/Shanghai

Notes:
  Default networking maps host PORT to container 3000. Use --host-network only if you explicitly want Docker host networking.
  When --user and a password option are provided, seedboxctl writes the Vertex WebUI username/password before first start.
USAGE
  fi
}

vertex::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install) args::parse "$@"; log::init vertex-install; vertex::install_from_parsed ;;
    upgrade) args::parse "$@"; log::init vertex-upgrade; vertex::upgrade_from_parsed ;;
    uninstall|remove) args::parse "$@"; log::init vertex-uninstall; vertex::uninstall_from_parsed ;;
    status) args::parse "$@"; log::init vertex-status; vertex::status ;;
    help|-h|--help) vertex::usage ;;
    *) ui::error "$(ui::tr "未知 Vertex 命令：${sub}" "Unknown vertex command: ${sub}")"; vertex::usage; return 2 ;;
  esac
}

vertex::password_args_supplied() {
  args::has password_stdin && return 0
  [[ -n "$(args::get password_file)" ]] && return 0
  [[ -n "$(args::get password)" ]] && return 0
  return 1
}

vertex::validate_web_username() {
  local username="$1"
  [[ -n "${username}" ]] || { ui::error "$(ui::tr "Vertex WebUI 用户名不能为空。" "Vertex WebUI username must not be empty.")"; return 1; }
  validate::safe_path "${username}" || { ui::error "$(ui::tr "Vertex WebUI 用户名不能包含换行符。" "Vertex WebUI username must not contain newlines.")"; return 1; }
  return 0
}

vertex::load_args() {
  VERTEX_NAME="$(args::get vertex_name vertex)"
  VERTEX_PORT="$(args::get vertex_port 3000)"
  VERTEX_DATA_DIR="$(args::get vertex_data_dir /root/vertex)"
  VERTEX_IMAGE="$(args::get vertex_image "${SEEDBOX_VERTEX_IMAGE}")"
  VERTEX_TZ="$(args::get timezone Asia/Shanghai)"
  VERTEX_HOST_NETWORK=0
  args::has host_network && VERTEX_HOST_NETWORK=1
  VERTEX_WEB_USER="$(args::get user)"
  VERTEX_WEB_PASSWORD=""

  validate::unprivileged_port "${VERTEX_PORT}" || { ui::error "$(ui::tr "无效的 Vertex 端口：${VERTEX_PORT}" "Invalid Vertex port: ${VERTEX_PORT}")"; return 2; }
  validate::safe_path "${VERTEX_DATA_DIR}" || { ui::error "$(ui::tr "无效的 Vertex 数据目录：${VERTEX_DATA_DIR}" "Invalid Vertex data dir: ${VERTEX_DATA_DIR}")"; return 2; }
  validate::safe_path "${VERTEX_NAME}" || { ui::error "$(ui::tr "无效的 Vertex 容器名：${VERTEX_NAME}" "Invalid Vertex container name: ${VERTEX_NAME}")"; return 2; }
  validate::safe_path "${VERTEX_TZ}" || { ui::error "$(ui::tr "无效的时区：${VERTEX_TZ}" "Invalid timezone: ${VERTEX_TZ}")"; return 2; }

  if [[ -n "${VERTEX_WEB_USER}" ]] || vertex::password_args_supplied; then
    [[ -n "${VERTEX_WEB_USER}" ]] || VERTEX_WEB_USER="admin"
    vertex::validate_web_username "${VERTEX_WEB_USER}" || return 2
    VERTEX_WEB_PASSWORD="$(secrets::read_password_from_args "$(ui::tr "Vertex WebUI 密码" "Vertex WebUI password")")" || return $?
  fi
}

vertex::preflight() {
  detect::assert_root
  detect::assert_supported_os
  ports::assert_free "${VERTEX_PORT}" "$(ui::tr "Vertex WebUI 端口" "Vertex WebUI port")"
  if [[ -n "${VERTEX_WEB_PASSWORD:-}" ]] && ! command -v md5sum >/dev/null 2>&1; then
    ui::error "$(ui::tr "需要 md5sum 才能写入 Vertex 密码。" "md5sum is required to write the Vertex password.")"
    return 1
  fi
}

vertex::ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    docker::install_from_parsed
  fi
}

vertex::create_data_dir() {
  install -d -m 0700 -o root -g root "${VERTEX_DATA_DIR}"
}

vertex::json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "${value}"
}

vertex::write_credentials() {
  [[ -n "${VERTEX_WEB_USER:-}" && -n "${VERTEX_WEB_PASSWORD:-}" ]] || return 0

  local data_dir settings pass_hash
  data_dir="${VERTEX_DATA_DIR}/data"
  settings="${data_dir}/setting.json"
  install -d -m 0700 -o root -g root "${data_dir}"
  pass_hash="$(printf '%s' "${VERTEX_WEB_PASSWORD}" | md5sum | awk '{print $1}')"

  if command -v python3 >/dev/null 2>&1; then
    VERTEX_SETTINGS_PATH="${settings}" \
    VERTEX_USERNAME="${VERTEX_WEB_USER}" \
    VERTEX_PASSWORD_HASH="${pass_hash}" \
    python3 - <<'PY'
import json
import os

path = os.environ["VERTEX_SETTINGS_PATH"]
username = os.environ["VERTEX_USERNAME"]
password_hash = os.environ["VERTEX_PASSWORD_HASH"]

try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
        if not isinstance(data, dict):
            data = {}
except FileNotFoundError:
    data = {}
except Exception:
    data = {}

data["username"] = username
data["password"] = password_hash

tmp = f"{path}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PY
  else
    local escaped_user
    escaped_user="$(vertex::json_escape "${VERTEX_WEB_USER}")"
    fs::write_file "${settings}" 0600 root root <<EOF_SETTINGS
{
  "username": "${escaped_user}",
  "password": "${pass_hash}"
}
EOF_SETTINGS
  fi

  chown root:root "${settings}" 2>/dev/null || true
  chmod 600 "${settings}" 2>/dev/null || true
  VERTEX_WEB_PASSWORD=""
}

vertex::run_container() {
  if docker ps -a --format '{{.Names}}' | grep -Fxq "${VERTEX_NAME}"; then
    docker rm -f "${VERTEX_NAME}"
  fi

  local app_port="3000"
  local docker_args=(run -d --name "${VERTEX_NAME}" --restart unless-stopped -v "${VERTEX_DATA_DIR}:/vertex" -e "TZ=${VERTEX_TZ}")
  if [[ "${VERTEX_HOST_NETWORK:-0}" == "1" ]]; then
    app_port="${VERTEX_PORT}"
    docker_args+=(--network host)
  else
    docker_args+=(-p "${VERTEX_PORT}:3000")
  fi
  docker_args+=(-e "PORT=${app_port}" "${VERTEX_IMAGE}")
  docker "${docker_args[@]}"
}

vertex::healthcheck() {
  docker ps --format '{{.Names}}' | grep -Fxq "${VERTEX_NAME}"
  ports::wait_for_listen "${VERTEX_PORT}" 30 || return 1
}

vertex::web_url() {
  local ip
  ip="$(public_ip::detect 2>/dev/null || true)"
  [[ -n "${ip}" ]] || ip="<server-ip>"
  printf 'http://%s:%s\n' "${ip}" "${VERTEX_PORT}"
}

vertex::write_state() {
  local host_network="no"
  [[ "${VERTEX_HOST_NETWORK:-0}" == "1" ]] && host_network="yes"
  state::write vertex "${VERTEX_NAME}" <<EOF_STATE
component=vertex
container=${VERTEX_NAME}
image=${VERTEX_IMAGE}
port=${VERTEX_PORT}
data_dir=${VERTEX_DATA_DIR}
timezone=${VERTEX_TZ}
host_network=${host_network}
web_user=${VERTEX_WEB_USER:-}
service=docker.container.${VERTEX_NAME}
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

vertex::install_from_parsed() {
  vertex::load_args || return $?
  ui::heading "$(ui::tr "正在安装 Vertex" "Installing Vertex")"
  ui::kv "$(ui::tr "镜像" "Image")" "${VERTEX_IMAGE}"
  ui::kv "$(ui::tr "端口" "Port")" "${VERTEX_PORT}"
  ui::kv "$(ui::tr "数据目录" "Data")" "${VERTEX_DATA_DIR}"
  if [[ -n "${VERTEX_WEB_USER:-}" ]]; then
    ui::kv "$(ui::tr "WebUI 用户名" "WebUI user")" "${VERTEX_WEB_USER}"
  fi
  ui::log_location
  printf '\n'

  runner::must vertex.preflight "$(ui::tr "预检" "Preflight checks")" "" vertex::preflight || return $?
  runner::must vertex.docker "$(ui::tr "安装/验证 Docker" "Install/verify Docker")" "docker.service" vertex::ensure_docker || return $?
  runner::must vertex.data "$(ui::tr "创建 Vertex 数据目录" "Create Vertex data directory")" "" vertex::create_data_dir || return $?
  runner::must vertex.credentials "$(ui::tr "写入 Vertex 登录信息" "Write Vertex login credentials")" "" vertex::write_credentials || return $?
  runner::must vertex.pull "$(ui::tr "拉取 Vertex 镜像" "Pull Vertex image")" "" docker pull "${VERTEX_IMAGE}" || return $?
  runner::must vertex.run "$(ui::tr "运行 Vertex 容器" "Run Vertex container")" "" vertex::run_container || return $?
  runner::must vertex.health "$(ui::tr "Vertex 健康检查" "Healthcheck Vertex")" "" vertex::healthcheck || return $?
  runner::must vertex.state "$(ui::tr "保存 Vertex 状态" "Save Vertex state")" "" vertex::write_state || return $?

  local link
  link="$(vertex::web_url)"
  ui::success "$(ui::tr "Vertex 已安装。链接：${link}" "Vertex installed. Link: ${link}")"
  if [[ -n "${VERTEX_WEB_USER:-}" ]]; then
    ui::success "$(ui::tr "Vertex WebUI 用户名：${VERTEX_WEB_USER}" "Vertex WebUI username: ${VERTEX_WEB_USER}")"
  else
    ui::warn "$(ui::tr "未指定 Vertex WebUI 密码；首次启动生成的默认密码通常位于 ${VERTEX_DATA_DIR}/data/password。" "No Vertex WebUI password was supplied; the first-start generated default password is usually stored under ${VERTEX_DATA_DIR}/data/password.")"
  fi
}

vertex::read_state() {
  local name path host_network
  name="$(args::get vertex_name vertex)"
  path="$(state::path vertex "${name}")"
  [[ -r "${path}" ]] || { ui::error "$(ui::tr "未找到 ${name} 的 Vertex 状态。" "No Vertex state found for ${name}.")"; return 1; }
  VERTEX_NAME="$(state::get "${path}" container)"
  VERTEX_IMAGE="$(state::get "${path}" image)"
  VERTEX_PORT="$(state::get "${path}" port)"
  VERTEX_DATA_DIR="$(state::get "${path}" data_dir)"
  VERTEX_TZ="$(state::get "${path}" timezone)"
  VERTEX_WEB_USER="$(state::get "${path}" web_user)"
  host_network="$(state::get "${path}" host_network)"
  [[ -n "${VERTEX_TZ}" ]] || VERTEX_TZ="Asia/Shanghai"
  if [[ "${host_network}" == "yes" || "${host_network}" == "1" ]]; then
    VERTEX_HOST_NETWORK=1
  else
    VERTEX_HOST_NETWORK=0
  fi
}

vertex::upgrade_from_parsed() {
  detect::assert_root
  vertex::read_state || return $?
  VERTEX_IMAGE="$(args::get vertex_image "${VERTEX_IMAGE}")"
  ui::heading "$(ui::tr "正在升级 Vertex" "Upgrading Vertex")"
  ui::kv "$(ui::tr "镜像" "Image")" "${VERTEX_IMAGE}"
  ui::kv "$(ui::tr "端口" "Port")" "${VERTEX_PORT}"
  ui::log_location
  printf '\n'
  runner::must vertex.pull "$(ui::tr "拉取 Vertex 镜像" "Pull Vertex image")" "" docker pull "${VERTEX_IMAGE}" || return $?
  runner::must vertex.run "$(ui::tr "重建 Vertex 容器" "Recreate Vertex container")" "" vertex::run_container || return $?
  runner::must vertex.health "$(ui::tr "Vertex 健康检查" "Healthcheck Vertex")" "" vertex::healthcheck || return $?
  runner::must vertex.state "$(ui::tr "更新 Vertex 状态" "Update Vertex state")" "" vertex::write_state || return $?
  ui::success "$(ui::tr "Vertex 升级完成。" "Vertex upgrade completed.")"
}

vertex::uninstall_from_parsed() {
  detect::assert_root
  vertex::read_state || return $?
  ui::heading "$(ui::tr "正在卸载 Vertex" "Uninstalling Vertex")"
  runner::run vertex.rm "$(ui::tr "删除 Vertex 容器" "Remove Vertex container")" "" docker rm -f "${VERTEX_NAME}" || true
  state::remove vertex "${VERTEX_NAME}"
  if args::has purge; then
    args::has yes || { ui::error "$(ui::tr "使用 --purge 清理 Vertex 时必须同时传入 --yes。" "Use --yes with --purge for Vertex.")"; return 1; }
    ui::warn "$(ui::tr "清理将删除 Vertex 数据目录：${VERTEX_DATA_DIR}" "Purge will remove Vertex data directory: ${VERTEX_DATA_DIR}")"
    rm -rf -- "${VERTEX_DATA_DIR}"
    ui::warn "$(ui::tr "已清理 Vertex 数据：${VERTEX_DATA_DIR}" "Purged Vertex data: ${VERTEX_DATA_DIR}")"
  fi
  ui::success "$(ui::tr "Vertex 卸载完成。" "Vertex uninstall completed.")"
}

vertex::status() {
  ui::heading "$(ui::tr "Vertex 状态" "Vertex status")"
  if command -v docker >/dev/null 2>&1; then
    docker ps -a --filter name=vertex
    docker logs --tail 80 vertex 2>/dev/null || true
  else
    ui::warn "$(ui::tr "未找到 docker 命令。" "docker command not found.")"
  fi
}
