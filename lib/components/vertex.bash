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
declare -g VERTEX_CONTAINER_ID=""

vertex::usage() {
  printf '%s\n' "$(ui::tr '所有写入需 Python 3。升级保留数据快照及旧容器；--repair-data 需 --yes，--no-data-snapshot 放弃数据回滚。已有实例安装需 --force。' 'Python 3 is required for all changes. Upgrades retain snapshots/old containers; --repair-data requires --yes; --no-data-snapshot forfeits data rollback. Install over an existing managed instance requires --force.')"
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl vertex install [--user NAME] [--password-stdin | --password-file FILE | --password PASSWORD] [OPTIONS]
  seedboxctl vertex upgrade [--vertex-name NAME] [--vertex-image IMAGE] [OPTIONS]
  seedboxctl vertex uninstall [--vertex-name NAME] [--purge] [--yes]
  seedboxctl vertex status [--vertex-name NAME] [--json] [--check]
  seedboxctl vertex logs [--vertex-name NAME] [OPTIONS]

安装选项：
  --vertex-name NAME          默认：vertex
  --vertex-port PORT
  --vertex-data-dir DIR
  --vertex-image IMAGE
  --host-network
  --timezone TZ

默认值：
  镜像：lswl/vertex:stable
  数据：/root/vertex
  端口：3000
  时区：Asia/Shanghai

说明：
  默认网络会把宿主机端口映射到容器内 3000 端口。只有明确需要 Docker host 网络时才使用 --host-network。
  如果传入 --user 和密码选项，seedboxctl 会先让 Vertex 镜像初始化数据目录，再写入 Vertex WebUI 用户名和密码。
  写入凭据需要 Python 3；缺少时询问是否安装，拒绝则报错退出。无交互终端时可用 --yes 明确同意安装。
  无效或不可读的现有 setting.json 会报错，不会被空配置替换。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl vertex install [--user NAME] [--password-stdin | --password-file FILE | --password PASSWORD] [OPTIONS]
  seedboxctl vertex upgrade [--vertex-name NAME] [--vertex-image IMAGE] [OPTIONS]
  seedboxctl vertex uninstall [--vertex-name NAME] [--purge] [--yes]
  seedboxctl vertex status [--vertex-name NAME] [--json] [--check]
  seedboxctl vertex logs [--vertex-name NAME] [OPTIONS]

Install options:
  --vertex-name NAME          Default: vertex
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
  When --user and a password option are provided, seedboxctl lets the Vertex image initialize the data directory first, then writes the Vertex WebUI username/password before the final start.
  Credential updates require Python 3. If missing, installation is offered; declining aborts. Non-interactive runs need --yes to consent.
  Invalid or unreadable existing setting.json is an error, never replaced with an empty config.
USAGE
  fi
}

vertex::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install)
      args::parse_for vertex-install "$@" || return $?
      args::has help && {
        vertex::usage
        return 0
      }
      log::init vertex-install
      vertex::install_from_parsed
      ;;
    upgrade)
      args::parse_for vertex-upgrade "$@" || return $?
      args::has help && {
        vertex::usage
        return 0
      }
      log::init vertex-upgrade
      vertex::upgrade_from_parsed
      ;;
    uninstall | remove)
      args::parse_for vertex-remove "$@" || return $?
      args::has help && {
        vertex::usage
        return 0
      }
      log::init vertex-uninstall
      vertex::uninstall_from_parsed
      ;;
    status)
      args::parse_for vertex-status "$@" || return $?
      args::has help && {
        vertex::usage
        return 0
      }
      vertex::status
      ;;
    logs) logs::cli vertex "$@" ;;
    help | -h | --help)
      args::parse_for none "$@" || return $?
      vertex::usage
      ;;
    *)
      ui::error "$(ui::tr "未知 Vertex 命令：${sub}" "Unknown vertex command: ${sub}")"
      vertex::usage
      return 2
      ;;
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
  [[ -n "${username}" ]] || {
    ui::error "$(ui::tr "Vertex WebUI 用户名不能为空。" "Vertex WebUI username must not be empty.")"
    return 1
  }
  validate::safe_path "${username}" || {
    ui::error "$(ui::tr "Vertex WebUI 用户名不能包含换行符。" "Vertex WebUI username must not contain newlines.")"
    return 1
  }
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

  validate::unprivileged_port "${VERTEX_PORT}" || {
    ui::error "$(ui::tr "无效的 Vertex 端口：${VERTEX_PORT}" "Invalid Vertex port: ${VERTEX_PORT}")"
    return 2
  }
  validate::safe_path "${VERTEX_DATA_DIR}" || {
    ui::error "$(ui::tr "无效的 Vertex 数据目录：${VERTEX_DATA_DIR}" "Invalid Vertex data dir: ${VERTEX_DATA_DIR}")"
    return 2
  }
  validate::safe_path "${VERTEX_NAME}" || {
    ui::error "$(ui::tr "无效的 Vertex 容器名：${VERTEX_NAME}" "Invalid Vertex container name: ${VERTEX_NAME}")"
    return 2
  }
  validate::safe_path "${VERTEX_TZ}" || {
    ui::error "$(ui::tr "无效的时区：${VERTEX_TZ}" "Invalid timezone: ${VERTEX_TZ}")"
    return 2
  }

  if [[ -n "${VERTEX_WEB_USER}" ]] || vertex::password_args_supplied; then
    [[ -n "${VERTEX_WEB_USER}" ]] || VERTEX_WEB_USER="admin"
    vertex::validate_web_username "${VERTEX_WEB_USER}" || return 2
    VERTEX_WEB_PASSWORD="$(secrets::read_password_from_args "$(ui::tr "Vertex WebUI 密码" "Vertex WebUI password")")" || return $?
  fi
}

vertex::preflight() {
  detect::assert_root || return $?
  detect::assert_supported_os || return $?
  [[ "${VERTEX_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 2
  local existing_state
  existing_state="$(state::path vertex "${VERTEX_NAME}")" || return $?
  if ! args::has force || [[ ! -f "${existing_state}" || "$(state::get "${existing_state}" port)" != "${VERTEX_PORT}" || "$(state::get "${existing_state}" data_dir)" != "${VERTEX_DATA_DIR}" ]]; then
    ports::assert_free "${VERTEX_PORT}" "Vertex WebUI port" || return $?
  fi
  if [[ -n "${VERTEX_WEB_PASSWORD:-}" ]] && ! command -v md5sum >/dev/null 2>&1; then
    ui::error "$(ui::tr "需要 md5sum 才能写入 Vertex 密码。" "md5sum is required to write the Vertex password.")"
    return 1
  fi
}

vertex::credentials_python_available() {
  command -v python3 >/dev/null 2>&1 && python3 -I -c 'import json, os, tempfile' >/dev/null 2>&1
}

vertex::ensure_credentials_python() {
  vertex::credentials_python_available && return 0
  if ! args::has yes; then
    if ! hardware::can_prompt; then
      ui::error "$(ui::tr "写入 Vertex 凭据需要 Python 3。没有交互终端；请先安装 python3，或使用 --yes 明确同意安装。" "Python 3 is required for Vertex credentials. No interactive terminal: install python3 first or use --yes to consent to installation.")"
      return 1
    fi
    local answer
    answer="$(hardware::prompt_value "$(ui::tr "写入 Vertex 凭据需要 Python 3。现在安装 python3？(y/n)" "Python 3 is required for Vertex credentials. Install python3 now? (y/n)")" N)" || {
      ui::error "$(ui::tr "未获得 Python 3 安装同意；Vertex 安装已中止。" "Python 3 installation was not confirmed; Vertex installation aborted.")"
      return 1
    }
    case "${answer,,}" in
      y | yes) ;;
      *)
        ui::error "$(ui::tr "已拒绝安装 Python 3；Vertex 安装已中止，现有 Vertex 数据未修改。" "Python 3 installation declined; Vertex installation aborted without modifying existing Vertex data.")"
        return 1
        ;;
    esac
  fi
  apt::update || return $?
  apt::ensure_packages python3 || return $?
  vertex::credentials_python_available || {
    ui::error "$(ui::tr "安装后 Python 3 仍不可用；Vertex 安装已中止。" "Python 3 is still unavailable after installation; Vertex installation aborted.")"
    return 1
  }
}

vertex::ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    docker::install_from_parsed
  fi
}

vertex::create_data_dir() {
  fs::safety prepare-dir "${VERTEX_DATA_DIR}" || return $?
  if [[ ! -e "${VERTEX_DATA_DIR}" ]]; then
    install -d -m 0700 -o root -g root "${VERTEX_DATA_DIR}" || return $?
  fi
  fs::safety mark-empty "${VERTEX_DATA_DIR}" "vertex:${VERTEX_NAME}" || return $?
}

vertex::data_complete() {
  local file
  for file in data/setting.json db/sql.db config/config.yaml; do
    fs::assert_no_symlink_components "${VERTEX_DATA_DIR}/${file}" || return $?
    [[ -f "${VERTEX_DATA_DIR}/${file}" ]] || return 1
  done
}

vertex::container_exists() {
  local names
  names="$(docker container ls -a --format '{{.Names}}')" || return 2
  grep -Fxq -- "${VERTEX_NAME}" <<<"${names}"
}

vertex::guard_install() {
  local state exists=0
  state="$(state::path vertex "${VERTEX_NAME}")" || return $?
  vertex::container_exists || exists=$?
  ((exists <= 1)) || return "${exists}"
  if [[ "${exists}" == 0 || -e "${state}" ]]; then
    args::has force || {
      ui::error "Vertex already exists; use upgrade or --force for a backed-up replacement."
      return 1
    }
    [[ -f "${state}" && "$(state::get "${state}" data_dir)" == "${VERTEX_DATA_DIR}" ]] || {
      ui::error "Unmanaged/mismatched Vertex instance: review manually."
      return 1
    }
    if [[ "${exists}" == 0 ]]; then vertex::managed_id >/dev/null || return $?; fi
  fi
}

vertex::container_id() {
  local description
  description="$(docker inspect "${VERTEX_NAME}")" || return $?
  VERTEX_EXPECTED_NAME="${VERTEX_NAME}" VERTEX_EXPECTED_DATA="${VERTEX_DATA_DIR}" python3 -I -c '
import json, os, re, sys
data = json.load(sys.stdin)
if len(data) != 1:
    sys.exit("Ambiguous Vertex container")
item = data[0]
mounts = [m for m in item.get("Mounts", []) if m.get("Destination") == "/vertex"]
identity = item.get("Id", "")
if (not re.fullmatch("[0-9a-f]{64}", identity)
        or item.get("Name") != "/" + os.environ["VERTEX_EXPECTED_NAME"]
        or len(mounts) != 1 or mounts[0].get("Type") != "bind"
        or mounts[0].get("Source") != os.environ["VERTEX_EXPECTED_DATA"]):
    sys.exit("Vertex container identity/mount mismatch; review manually")
print(identity)
' <<<"${description}"
}

vertex::managed_id() {
  local saved actual path
  path="$(state::path vertex "${VERTEX_NAME}")" || return $?
  saved="$(state::get "${path}" container_id)" || return $?
  [[ "${saved}" =~ ^[0-9a-f]{64}$ ]] || {
    ui::error "Vertex state has no verified container ID. Review the container and record its full container_id in state before retrying."
    return 1
  }
  actual="$(vertex::container_id)" || return $?
  [[ "${actual}" == "${saved}" ]] || {
    ui::error "Stale Vertex container identity; refusing same-named replacement."
    return 1
  }
  printf '%s\n' "${actual}"
}

vertex::create_initialized_template() {
  local template_dir="$1"
  local init_name="${VERTEX_NAME}-init-${template_dir##*.}" init_id
  local waited=0 running

  install -d -m 0700 -o root -g root "${template_dir}" || return $?

  init_id="$(docker run -d --name "${init_name}" \
    -v "${template_dir}:/vertex" \
    -e "TZ=${VERTEX_TZ}" \
    "${VERTEX_IMAGE}")" || return $?
  [[ "${init_id}" =~ ^[0-9a-f]{64}$ ]] || {
    ui::error "Unconfirmed initialization container ID; retain ${template_dir} and inspect ${init_name}."
    return 1
  }

  while [[ "${waited}" -lt 60 ]]; do
    if [[ -f "${template_dir}/data/setting.json" &&
      -f "${template_dir}/db/sql.db" &&
      -f "${template_dir}/config/config.yaml" ]]; then
      docker stop "${init_id}" >/dev/null || return $?
      running="$(docker inspect --format '{{.State.Running}}' "${init_id}")" || return $?
      [[ "${running}" == false ]] || return 1
      docker rm "${init_id}" >/dev/null || return $?
      return 0
    fi

    running="$(docker inspect --format '{{.State.Running}}' "${init_id}")" || return $?
    if [[ "${running}" != true ]]; then
      docker logs "${init_id}" >&2 || true
      ui::error "$(ui::tr "Vertex 初始化容器在数据目录初始化完成前退出。" "Vertex initialization container exited before the data directory was initialized.")"
      return 1
    fi

    sleep 1
    waited=$((waited + 1))
  done

  docker logs "${init_id}" >&2 || true
  docker stop "${init_id}" >/dev/null 2>&1 || true
  ui::error "$(ui::tr "等待 Vertex 初始化数据目录超时。" "Timed out waiting for Vertex to initialize the data directory.")"
  return 1
}

vertex::merge_initialized_template() {
  local template_dir="$1"
  local path rel target

  while IFS= read -r -d '' path; do
    rel="${path#${template_dir}/}"
    fs::safety prepare-dir "${VERTEX_DATA_DIR}/${rel}" || return $?
    if [[ ! -e "${VERTEX_DATA_DIR}/${rel}" ]]; then mkdir -m 0700 -- "${VERTEX_DATA_DIR}/${rel}" || return $?; fi
  done < <(find "${template_dir}" -mindepth 1 -type d -print0)

  while IFS= read -r -d '' path; do
    rel="${path#${template_dir}/}"
    target="${VERTEX_DATA_DIR}/${rel}"
    fs::assert_no_symlink_components "${target}" || return $?
    if [[ ! -e "${target}" ]]; then
      fs::safety prepare-dir "$(dirname "${target}")" || return $?
      [[ -d "$(dirname "${target}")" ]] || return 1
      cp -a "${path}" "${target}" || return $?
      chown root:root "${target}" || return $?
    fi
  done < <(find "${template_dir}" -mindepth 1 -type f -print0)
}

vertex::initialize_data_dir() {
  local template_dir rc

  vertex::create_data_dir || return $?
  if ! args::has repair_data; then
    if vertex::data_complete; then return 0; fi
    local populated
    populated="$(find "${VERTEX_DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name .seedbox-managed -print -quit)" || return $?
    [[ -z "${populated}" ]] || {
      ui::error "Incomplete Vertex data: use upgrade --repair-data --yes (snapshot required)."
      return 1
    }
  fi
  template_dir="$(mktemp -d /tmp/vertex-template.XXXXXX)" || return 1

  rc=0
  vertex::create_initialized_template "${template_dir}" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    vertex::merge_initialized_template "${template_dir}" || rc=$?
  fi

  if ((rc == 0)); then
    rm -rf -- "${template_dir}" || return $?
  else ui::warn "Initialization failed; template/container retained for manual recovery: ${template_dir}"; fi
  return "${rc}"
}

vertex::write_credentials() {
  [[ -n "${VERTEX_WEB_USER:-}" && -n "${VERTEX_WEB_PASSWORD:-}" ]] || return 0
  fs::safety prepare-dir "${VERTEX_DATA_DIR}" || return $?
  fs::safety prepare-dir "${VERTEX_DATA_DIR}/data" || return $?
  fs::assert_no_symlink_components "${VERTEX_DATA_DIR}/data/setting.json" || return $?
  vertex::credentials_python_available || {
    ui::error "$(ui::tr "需要 Python 3；现有 Vertex 设置未修改。" "Python 3 is required; existing Vertex settings were not changed.")"
    return 1
  }

  local data_dir settings pass_hash
  data_dir="${VERTEX_DATA_DIR}/data"
  settings="${data_dir}/setting.json"
  pass_hash="$(printf '%s' "${VERTEX_WEB_PASSWORD}" | md5sum | awk '{print $1}')" || return $?
  [[ "${pass_hash}" =~ ^[0-9a-f]{32}$ ]] || {
    ui::error "Invalid Vertex password hash; settings were not changed."
    return 1
  }

  if ! VERTEX_SETTINGS_PATH="${settings}" \
    VERTEX_USERNAME="${VERTEX_WEB_USER}" \
    VERTEX_PASSWORD_HASH="${pass_hash}" \
    python3 -I - <<'PY'
import json
import os
import sys
import tempfile

path = os.environ["VERTEX_SETTINGS_PATH"]
directory = os.path.dirname(path)
temporary = None


def reject_constant(value):
    raise ValueError("Non-standard JSON constant")


def write_private(prefix, content):
    fd, name = tempfile.mkstemp(prefix=prefix, dir=directory)
    try:
        with os.fdopen(fd, "wb") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
    except BaseException:
        os.unlink(name)
        raise
    return name


def fingerprint(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


try:
    if os.path.islink(path):
        raise ValueError("Refusing to replace a settings symlink")
    original = None
    before = None
    try:
        with open(path, "rb") as handle:
            original = handle.read()
            before = os.fstat(handle.fileno())
        data = json.loads(original.decode("utf-8"), parse_constant=reject_constant)
    except FileNotFoundError:
        if os.path.lexists(path):
            raise ValueError("Settings path exists but cannot be opened")
        else:
            data = {}
    if not isinstance(data, dict):
        raise ValueError("Settings must be a JSON object")
    data["username"] = os.environ["VERTEX_USERNAME"]
    data["password"] = os.environ["VERTEX_PASSWORD_HASH"]
    content = (json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    if original is not None:
        backup = write_private("setting.json.pre-credentials.", original)
        print("Vertex settings backup: " + backup)
    temporary = write_private(".setting.json.", content)
    if before is not None:
        if fingerprint(os.stat(path, follow_symlinks=False)) != fingerprint(before):
            raise ValueError("Settings changed during update; retry with Vertex stopped")
    elif os.path.lexists(path):
        raise ValueError("Settings appeared during update; refusing to overwrite")
    os.replace(temporary, path)
    temporary = None
except (OSError, UnicodeError, ValueError) as error:
    print("Vertex settings update refused (" + type(error).__name__ + "); original setting.json was not replaced.", file=sys.stderr)
    sys.exit(1)
finally:
    if temporary is not None:
        os.unlink(temporary)
PY
  then
    return 1
  fi

  chown root:root "${settings}" || return $?
  chmod 600 "${settings}" || return $?
  rm -f "${data_dir}/password" 2>/dev/null || true
  VERTEX_WEB_PASSWORD=""
}

vertex::run_container() {
  local app_port="3000"
  local docker_args=(run -d --name "${VERTEX_NAME}" --restart unless-stopped -v "${VERTEX_DATA_DIR}:/vertex" -e "TZ=${VERTEX_TZ}")
  if [[ "${VERTEX_HOST_NETWORK:-0}" == "1" ]]; then
    app_port="${VERTEX_PORT}"
    docker_args+=(--network host)
  else
    docker_args+=(-p "${VERTEX_PORT}:3000")
  fi
  docker_args+=(-e "PORT=${app_port}" "${VERTEX_IMAGE}")
  VERTEX_CONTAINER_ID="$(docker "${docker_args[@]}")" || return $?
  [[ "${VERTEX_CONTAINER_ID}" =~ ^[0-9a-f]{64}$ ]] || return 1
}

vertex::http_ready() {
  python3 -I - "${VERTEX_PORT}" <<'PY'
import http.client
import sys

connection = http.client.HTTPConnection("127.0.0.1", int(sys.argv[1]), timeout=2)
try:
    connection.request("GET", "/")
    response = connection.getresponse()
    ready = 200 <= response.status < 400
except (OSError, http.client.HTTPException):
    ready = False
finally:
    connection.close()
sys.exit(0 if ready else 1)
PY
}

vertex::healthcheck() {
  local actual running attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    actual="$(vertex::container_id)" || return $?
    [[ "${actual}" == "${VERTEX_CONTAINER_ID}" ]] || return 1
    running="$(docker inspect --format '{{.State.Running}}' "${VERTEX_CONTAINER_ID}")" || return $?
    [[ "${running}" == true ]] || return 1
    if vertex::http_ready; then
      # A published Docker port can outlive the process that initially bound it.
      actual="$(vertex::container_id)" || return $?
      [[ "${actual}" == "${VERTEX_CONTAINER_ID}" ]] || return 1
      running="$(docker inspect --format '{{.State.Running}}' "${VERTEX_CONTAINER_ID}")" || return $?
      [[ "${running}" == true ]] || return 1
      return 0
    fi
    sleep 1
  done
  return 1
}

vertex::web_url() {
  local ip
  ip="$(public_ip::detect 2>/dev/null || true)"
  [[ -n "${ip}" ]] || ip="<server-ip>"
  printf 'http://%s:%s\n' "${ip}" "${VERTEX_PORT}"
}

# Retain old containers and snapshots. Never delete failed data to make a
# rollback fit; rename it aside and report its recovery path instead.
vertex::activate_transaction() {
  local operation="$1" state state_backup='' snapshot='' previous='' restart='' running=false
  local exists=0 rc=0 replacement=0 old_stopped=0 data_touched=0 old_id=''
  VERTEX_CONTAINER_ID=""
  state="$(state::path vertex "${VERTEX_NAME}")" || return $?
  if [[ -e "${state}" ]]; then state_backup="$(fs::backup_current "${state}" pre-upgrade)" || return $?; fi
  vertex::container_exists || exists=$?
  ((exists <= 1)) || return "${exists}"
  if [[ "${exists}" == 0 ]]; then
    old_id="$(vertex::managed_id)" || return $?
    running="$(docker inspect --format '{{.State.Running}}' "${old_id}")" || return $?
    restart="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${old_id}")" || return $?
    docker stop "${old_id}" || return $?
    old_stopped=1
  fi
  if args::has repair_data; then args::has yes && ! args::has no_data_snapshot || rc=2; fi
  if ((rc == 0)); then
    if args::has no_data_snapshot; then
      ui::warn "No Vertex snapshot: a failed new image may migrate data; the old container will NOT restart automatically."
    else
      fs::safety check-dir "${VERTEX_DATA_DIR}" || rc=$?
      if ((rc == 0)); then snapshot="$(mktemp -d "${VERTEX_DATA_DIR}.pre-upgrade.XXXXXX")" || rc=$?; fi
      if ((rc == 0)); then cp -a -- "${VERTEX_DATA_DIR}" "${snapshot}/data" || rc=$?; fi
    fi
  fi
  if ((rc == 0 && old_stopped)); then
    docker update --restart=no "${old_id}" || rc=$?
    if ((rc == 0)); then
      local backup_name="${VERTEX_NAME}.previous.$(date +%Y%m%d%H%M%S).$$"
      docker rename "${old_id}" "${backup_name}" || rc=$?
      if ((rc == 0)); then previous="${backup_name}"; fi
    fi
  fi
  if ((rc == 0)); then
    data_touched=1
    if [[ "${operation}" == install ]] || args::has repair_data; then vertex::initialize_data_dir || rc=$?; fi
    if ((rc == 0)) && [[ "${operation}" == install ]]; then vertex::write_credentials || rc=$?; fi
    if ((rc == 0)); then
      replacement=1
      vertex::run_container || rc=$?
    fi
    if ((rc == 0)); then vertex::healthcheck || rc=$?; fi
    if ((rc == 0)); then vertex::write_state || rc=$?; fi
  fi
  if ((rc != 0)); then
    local recover=0
    if ((replacement)); then
      # Remove only the ID returned by our run, even if its name changed.
      # An ambiguous failed run must not authorize deletion by name or data rollback.
      if [[ "${VERTEX_CONTAINER_ID}" =~ ^[0-9a-f]{64}$ ]]; then
        docker rm -f "${VERTEX_CONTAINER_ID}" || recover=1
      else recover=1; fi
    fi
    # Never restore/rename data while a failed replacement may still be alive.
    if ((data_touched && recover == 0)); then
      if [[ -n "${snapshot}" && -d "${snapshot}/data" ]]; then
        vertex::restore_data "${snapshot}" || recover=1
      else recover=1; fi
    fi
    if [[ -n "${previous}" ]]; then docker rename "${old_id}" "${VERTEX_NAME}" || recover=1; fi
    if ((old_stopped)); then
      if ((recover)); then
        docker update --restart=no "${old_id}" || true
      else
        docker update --restart="${restart:-no}" "${old_id}" || recover=1
        if ((recover == 0)) && [[ "${running}" == true ]]; then docker start "${old_id}" || recover=1; fi
      fi
    fi
    if [[ -n "${state_backup}" ]]; then fs::write_file "${state}" 0600 root root <"${state_backup}" || recover=1; fi
    ui::error "Vertex replacement failed; recovery status=${recover}. Snapshot: ${snapshot:-none}; previous container: ${previous:-original}."
    return "${rc}"
  fi
  ui::kv "Retained container backup" "${previous:-none}"
  ui::kv "Retained data snapshot" "${snapshot:-none}"
}

vertex::restore_data() {
  local snapshot="$1" staged failed
  fs::safety check-dir "${VERTEX_DATA_DIR}" || return $?
  fs::safety prepare-dir "${snapshot}" || return $?
  staged="$(mktemp -d "${VERTEX_DATA_DIR}.restore.XXXXXX")" || return $?
  cp -a -- "${snapshot}/data/." "${staged}/" || return $?
  failed="$(mktemp -d "${VERTEX_DATA_DIR}.failed.XXXXXX")" || return $?
  mv -T -- "${VERTEX_DATA_DIR}" "${failed}" || return $?
  if ! mv -T -- "${staged}" "${VERTEX_DATA_DIR}"; then
    mv -T -- "${failed}" "${VERTEX_DATA_DIR}" || true
    return 1
  fi
  ui::warn "Failed replacement data retained: ${failed}"
}

vertex::write_state() {
  local host_network="no" actual
  actual="$(vertex::container_id)" || return $?
  [[ "${actual}" == "${VERTEX_CONTAINER_ID}" ]] || return 1
  [[ "${VERTEX_HOST_NETWORK:-0}" == "1" ]] && host_network="yes"
  state::write vertex "${VERTEX_NAME}" <<EOF_STATE
component=vertex
container=${VERTEX_NAME}
container_id=${VERTEX_CONTAINER_ID}
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
  # Prompt in the parent shell, before any Docker/image/data changes. Never
  # read confirmation from a piped password stream or a redirected step log.
  vertex::ensure_credentials_python || return $?
  fs::safety prepare-dir "${VERTEX_DATA_DIR}" || return $?
  runner::must vertex.docker "$(ui::tr "安装/验证 Docker" "Install/verify Docker")" "docker.service" vertex::ensure_docker || return $?
  vertex::guard_install || return $?
  fs::safety prepare-dir "${VERTEX_DATA_DIR}" || return $?
  runner::must vertex.pull "Pull Vertex image" "" docker pull "${VERTEX_IMAGE}" || return $?
  vertex::create_data_dir || return $?
  runner::must vertex.activate "Activate/recover Vertex" "" vertex::activate_transaction install || return $?

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
  [[ -r "${path}" ]] || {
    ui::error "$(ui::tr "未找到 ${name} 的 Vertex 状态。" "No Vertex state found for ${name}.")"
    return 1
  }
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
  detect::assert_root || return $?
  vertex::read_state || return $?
  [[ "${VERTEX_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 2
  vertex::ensure_credentials_python || return $?
  fs::safety prepare-dir "${VERTEX_DATA_DIR}" || return $?
  if ! args::has repair_data; then vertex::data_complete || {
    ui::error "Incomplete data: use --repair-data --yes."
    return 1
  }; fi
  if args::has repair_data; then args::has yes && ! args::has no_data_snapshot || {
    ui::error "Repair requires --yes and a data snapshot."
    return 2
  }; fi
  VERTEX_IMAGE="$(args::get vertex_image "${VERTEX_IMAGE}")"
  ui::heading "$(ui::tr "正在升级 Vertex" "Upgrading Vertex")"
  ui::kv "$(ui::tr "镜像" "Image")" "${VERTEX_IMAGE}"
  ui::kv "$(ui::tr "端口" "Port")" "${VERTEX_PORT}"
  ui::log_location
  printf '\n'
  runner::must vertex.pull "$(ui::tr "拉取 Vertex 镜像" "Pull Vertex image")" "" docker pull "${VERTEX_IMAGE}" || return $?
  runner::must vertex.activate "Activate/recover Vertex upgrade" "" vertex::activate_transaction upgrade || return $?
  ui::success "$(ui::tr "Vertex 升级完成。" "Vertex upgrade completed.")"
}

vertex::uninstall_from_parsed() {
  detect::assert_root || return $?
  vertex::read_state || return $?
  [[ "${VERTEX_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ && "${VERTEX_NAME}" == "$(args::get vertex_name vertex)" ]] || {
    ui::error "Invalid Vertex uninstall state."
    return 2
  }
  ui::heading "$(ui::tr "正在卸载 Vertex" "Uninstalling Vertex")"
  if args::has purge; then
    args::has yes || {
      ui::error "$(ui::tr "使用 --purge 清理 Vertex 时必须同时传入 --yes。" "Use --yes with --purge for Vertex.")"
      return 1
    }
    fs::safety check-managed "${VERTEX_DATA_DIR}" "vertex:${VERTEX_NAME}" || return $?
    ui::warn "$(ui::tr "清理将删除 Vertex 数据目录：${VERTEX_DATA_DIR}" "Purge will remove Vertex data directory: ${VERTEX_DATA_DIR}")"
  fi
  runner::must vertex.rm "$(ui::tr "删除 Vertex 容器" "Remove Vertex container")" "" vertex::remove_container || return $?
  if args::has purge; then
    fs::safety remove-managed "${VERTEX_DATA_DIR}" "vertex:${VERTEX_NAME}" || return $?
    ui::warn "$(ui::tr "已清理 Vertex 数据：${VERTEX_DATA_DIR}" "Purged Vertex data: ${VERTEX_DATA_DIR}")"
  fi
  state::remove vertex "${VERTEX_NAME}" || return $?
  ui::success "$(ui::tr "Vertex 卸载完成。" "Vertex uninstall completed.")"
}

vertex::remove_container() {
  # Query the local engine first: an unavailable daemon is not an absent container.
  local names
  names="$(docker container ls -a --format '{{.Names}}')" || return $?
  if grep -Fxq -- "${VERTEX_NAME}" <<<"${names}"; then
    local identity
    identity="$(vertex::managed_id)" || return $?
    docker rm -f "${identity}" || return $?
  fi
}

vertex::status() {
  status::component vertex
}
