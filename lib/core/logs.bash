# Read-only access to managed runtime and installer logs.
if [[ -n "${SEEDBOX_CORE_LOGS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_LOGS_SOURCED=1

declare -g LOGS_LINES=200 LOGS_SOURCE=auto LOGS_FOLLOW=0 LOGS_LIST=0 LOGS_SINCE=''
declare -g LOGS_USER='' LOGS_COMPONENT='' LOGS_PATH='' LOGS_ERROR=''

logs::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl logs COMPONENT [--user USER | --vertex-name NAME] [OPTIONS]
  seedboxctl COMPONENT logs [--user USER | --vertex-name NAME] [OPTIONS]
  seedboxctl logs installer [--run RUN_ID] [--step STEP_ID] [OPTIONS]

选项：
  --lines N       最近行数（1–10000，默认 200）
  --follow        持续查看一个来源，Ctrl+C 退出
  --since TIME    journal/Docker 时间筛选，不支持普通文件
  --source SOURCE auto|service|application|installer|all
  --list          列出来源，或安装器运行记录/步骤，不输出日志正文
  --run RUN_ID    安装器运行 ID（省略 .log）；默认最近匹配运行
  --step STEP_ID  从选定安装器运行中查看一个步骤

组件：qbittorrent、deluge、autobrr、autoremove-torrents、docker、vertex、tuning、bbr。
Deluge 的 service 来源同时包含 daemon 和 WebUI 日志。
只读，不安装依赖或修改权限。用户 systemd 日志需由实例所有者查询。
日志可能包含密码、令牌或私有地址；分享前请检查，不保证自动脱敏。
文件跟踪固定在已打开的文件上；轮转后请重新运行命令。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl logs COMPONENT [--user USER | --vertex-name NAME] [OPTIONS]
  seedboxctl COMPONENT logs [--user USER | --vertex-name NAME] [OPTIONS]
  seedboxctl logs installer [--run RUN_ID] [--step STEP_ID] [OPTIONS]

Options:
  --lines N       Last lines (1–10000, default 200)
  --follow        Stream one source until Ctrl+C
  --since TIME    Journal/Docker time filter; not supported for ordinary files
  --source SOURCE auto|service|application|installer|all
  --list          List sources, or installer runs/steps, without log contents
  --run RUN_ID    Installer run ID without .log; default: latest matching run
  --step STEP_ID  Read one step from the selected installer run

Components: qbittorrent, deluge, autobrr, autoremove-torrents, docker, vertex, tuning, bbr.
Deluge's service source includes both daemon and WebUI journals.
Read-only; never installs dependencies or changes permissions. Query user journals
as the instance owner. Logs may contain passwords, tokens, or private addresses:
review before sharing; automatic redaction is not guaranteed.
File following stays on the opened file; rerun after rotation.
USAGE
  fi
}

logs::error() {
  printf '%s\n' "$(ui::translate "$*")" >&2
}

logs::bounded() {
  command -v timeout >/dev/null 2>&1 || {
    logs::error 'Log query requires timeout; no dependencies installed.'
    return 1
  }
  local rc=0
  timeout --kill-after=1 "${LOGS_TIMEOUT:-8}" "$@" </dev/null || rc=$?
  if ((rc != 0)); then
    logs::error "Log source unavailable, denied, interrupted, or timed out (exit ${rc})."
    return 1
  fi
}

# Validate an open descriptor before reading; following never reopens a pathname.
logs::open_file() {
  local path="$1" privileged="${2:-0}" before after descriptor
  fs::assert_no_symlink_components "${path}" >/dev/null 2>&1 || return 1
  [[ "${privileged}" != 1 ]] || fs::assert_privileged_path "${path}" >/dev/null 2>&1 || return 1
  [[ -f "${path}" && -r "${path}" && ! -L "${path}" ]] || return 1
  before="$(stat -Lc '%d:%i' -- "${path}" 2>/dev/null)" || return 1
  exec {LOGS_FD}<"${path}" || return 1
  descriptor="/proc/${BASHPID}/fd/${LOGS_FD}"
  after="$(stat -Lc '%d:%i' -- "${descriptor}" 2>/dev/null)" || return 1
  [[ -f "${descriptor}" && "${before}" == "${after}" ]] || return 1
  [[ "$(readlink -- "${descriptor}" 2>/dev/null)" == "${path}" ]] || return 1
  fs::assert_no_symlink_components "${path}" >/dev/null 2>&1 || return 1
  [[ "$(stat -Lc '%d:%i' -- "${path}" 2>/dev/null)" == "${after}" ]] || return 1
}

logs::qsettings_path() {
  local raw="$1" out='' char digits code i=0
  if [[ "${raw}" == \"*\" ]]; then
    raw="${raw:1:${#raw}-2}"
  elif [[ "${raw}" == *[\",]* ]]; then return 1; fi
  while ((i < ${#raw})); do
    char="${raw:i:1}" i=$((i + 1))
    if [[ "${char}" == '\' ]]; then
      ((i < ${#raw})) || return 1
      char="${raw:i:1}" i=$((i + 1))
      case "${char}" in
        '\' | '"') ;;
        x)
          digits=''
          while ((i < ${#raw} && ${#digits} < 4)) && [[ "${raw:i:1}" == [0-9a-fA-F] ]]; do
            digits+="${raw:i:1}"
            i=$((i + 1))
          done
          [[ -n "${digits}" ]] || return 1
          code=$((16#${digits}))
          ((code >= 32 && code != 127 && (code < 55296 || code > 57343))) || return 1
          printf -v char '\\u%04x' "${code}"
          printf -v char '%b' "${char}"
          ;;
        *) return 1 ;;
      esac
    fi
    out+="${char}"
  done
  [[ "${out}" == /* && "${out}" != *[[:cntrl:]]* ]] || return 1
  printf '%s\n' "${out%/}"
}

logs::file_worker() (
  set -Eeuo pipefail
  local action="$1" path="$2" lines="$3" follow="$4" privileged="$5" home="${6:-}" LOGS_FD
  logs::open_file "${path}" "${privileged}" || {
    printf '%s\n' "$(ui::tr '日志或配置文件不存在、无法读取、已被替换，或未通过安全检查。' 'Log/config file missing, unreadable, replaced, or unsafe.')" >&2
    return 1
  }
  if [[ "${action}" == app-path ]]; then
    local content='' line section='' key value enabled=true directory="${home}/.local/share/qBittorrent/logs" seen_enabled=0 seen_path=0
    IFS= read -r -d '' -n 1048577 content <&"${LOGS_FD}" && return 1
    ((${#content} <= 1048576)) || return 1
    content="${content#$'\xef\xbb\xbf'}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%$'\r'}" line="${line#${line%%[![:space:]]*}}" line="${line%${line##*[![:space:]]}}"
      case "${line}" in
        \[*)
          [[ "${line}" == \[*\] ]] || {
            printf '%s\n' "$(ui::tr '应用配置的分区格式不正确，无法安全读取日志设置。' 'Malformed application config section.')" >&2
            return 1
          }
          section="${line:1:${#line}-2}"
          continue
          ;;
        '' | \#* | \;*) continue ;;
      esac
      [[ "${section}" == Application && "${line}" == *=* ]] || continue
      key="${line%%=*}" value="${line#*=}"
      key="${key%${key##*[![:space:]]}}" value="${value#${value%%[![:space:]]*}}"
      case "${key}" in
        'FileLogger\Enabled')
          ((seen_enabled == 0)) || return 1
          seen_enabled=1
          case "${value,,}" in true | 1) enabled=true ;; false | 0) enabled=false ;; *) return 1 ;; esac
          ;;
        'FileLogger\Path')
          ((seen_path == 0)) || return 1
          seen_path=1
          directory="$(logs::qsettings_path "${value}")" || {
            printf '%s\n' "$(ui::tr '自定义日志路径的 QSettings 编码无法可靠解析，不会猜测路径。' 'Custom QSettings log path cannot be decoded safely.')" >&2
            return 1
          }
          ;;
      esac
    done <<<"${content}"
    [[ "${enabled}" == true ]] || {
      printf '%s\n' "$(ui::tr 'qBittorrent 的文件日志已关闭；本命令不会自动开启日志。' 'qBittorrent application file logging is disabled.')" >&2
      return 1
    }
    printf '%s/qbittorrent.log\n' "${directory}"
  elif [[ "${action}" == content ]]; then
    local content='' LC_ALL=C
    IFS= read -r -d '' -n 4194305 content <&"${LOGS_FD}" && return 1
    ((${#content} <= 4194304)) || return 1
    printf '%s' "${content}"
  elif [[ "${action}" == read ]]; then
    if [[ "${follow}" == 1 ]]; then
      exec tail --lines="${lines}" --follow=descriptor -- "/proc/self/fd/${LOGS_FD}"
    else exec tail --lines="${lines}" <&"${LOGS_FD}"; fi
  elif [[ "${action}" != probe ]]; then return 1; fi
)

logs::worker() {
  local action="$1" path="$2" owner="${3:-}" privileged=0 script
  shift 3
  [[ ${EUID:-$(id -u)} -ne 0 || -n "${owner}" ]] || privileged=1
  script="$(declare -f logs::file_worker logs::open_file logs::qsettings_path fs::assert_no_symlink_components fs::assert_privileged_path ui::tr ui::zh)"
  local -a command=(env -u BASH_ENV -u ENV LC_ALL=C.UTF-8 bash --noprofile --norc -c "${script}; logs::file_worker \"\$@\"" seedbox-log-reader "${action}" "${path}" "${LOGS_LINES}" "${LOGS_FOLLOW}" "${privileged}" "$@")
  if [[ -n "${owner}" && "${owner}" != "$(id -un)" ]]; then
    [[ ${EUID:-$(id -u)} -eq 0 ]] || return 1
    command=(runuser -u "${owner}" -- "${command[@]}")
  fi
  if [[ "${action}" == read && "${LOGS_FOLLOW}" == 1 ]]; then
    logs::stream "${command[@]}"
  else logs::bounded "${command[@]}"; fi
}

logs::stream() (
  local child stream_group='' output_fd read_fd write_fd rc=0
  command -v setsid >/dev/null 2>&1 || {
    logs::error 'Following requires setsid; no dependencies installed.'
    return 1
  }
  exec {output_fd}>&1
  # setsid may fork when its caller is a process-group leader. The handshake
  # reports the actual session leader, independently of that wrapper's PID.
  coproc LOGS_STREAM {
    exec setsid --wait env -u BASH_ENV -u ENV bash --noprofile --norc -c 'output_fd="$1"; shift; printf "%s\n" "${BASHPID}"; exec "$@" >&"${output_fd}"' seedbox-log-stream "${output_fd}" "$@" </dev/null
  }
  child="${LOGS_STREAM_PID:-}"
  read_fd="${LOGS_STREAM[0]:-}" write_fd="${LOGS_STREAM[1]:-}"
  [[ "${child}" =~ ^[0-9]+$ && "${read_fd}" =~ ^[0-9]+$ && "${write_fd}" =~ ^[0-9]+$ ]] || {
    logs::error 'Log stream exited before initialization.'
    return 1
  }
  exec {write_fd}>&-
  logs::stop_stream() {
    if [[ "${stream_group}" =~ ^[0-9]+$ ]] && ((stream_group > 1)); then kill -TERM -- "-${stream_group}" 2>/dev/null || true; fi
    kill -TERM "${child}" 2>/dev/null || true
    sleep 0.2
    if [[ "${stream_group}" =~ ^[0-9]+$ ]] && ((stream_group > 1)); then kill -KILL -- "-${stream_group}" 2>/dev/null || true; fi
    kill -KILL "${child}" 2>/dev/null || true
    wait "${child}" 2>/dev/null || true
  }
  trap 'logs::stop_stream; exit 130' INT
  trap 'logs::stop_stream; exit 143' TERM HUP
  if ! IFS= read -r -t 4 stream_group <&"${read_fd}" || [[ ! "${stream_group}" =~ ^[0-9]+$ ]] || ((stream_group <= 1)); then
    logs::stop_stream
    logs::error 'Could not establish a bounded log-stream session.'
    return 1
  fi
  exec {read_fd}<&-
  exec {output_fd}>&-
  wait "${child}" || rc=$?
  ((rc == 0)) || {
    logs::error "Log stream ended unsuccessfully (exit ${rc})."
    return 1
  }
)

logs::select_state() {
  local component="$1" id='' name listing matches=0 selected=''
  case "${component}" in
    qbittorrent | deluge | autobrr | autoremove-torrents) id="$(args::get user)" ;;
    vertex) id="$(args::get vertex_name)" ;;
  esac
  status::path_readable "${SEEDBOX_STATE_DIR}" && [[ -d "${SEEDBOX_STATE_DIR}" && -r "${SEEDBOX_STATE_DIR}" && -x "${SEEDBOX_STATE_DIR}" ]] || {
    logs::error 'Managed state directory is missing, unreadable, or unsafe.'
    return 1
  }
  status::query find "${SEEDBOX_STATE_DIR}" -maxdepth 1 -mindepth 1 -name "${component}.*.env" -printf '%f/'
  ((STATUS_RC == 0)) || {
    logs::error 'Cannot enumerate managed instances.'
    return 1
  }
  listing="${STATUS_OUTPUT}"
  while IFS= read -r -d / name; do
    [[ -z "${id}" || "${name}" == "${component}.${id}.env" ]] || continue
    [[ "${name}" != docker.purge.env ]] || continue
    matches=$((matches + 1)) selected="${SEEDBOX_STATE_DIR}/${name}"
  done < <(printf '%s' "${listing}")
  ((matches == 1)) || {
    logs::error "Expected one managed instance; found ${matches}. Select --user USER or --vertex-name NAME where applicable."
    return 1
  }
  status::read_state "${selected}" || {
    logs::error 'Managed state is malformed, unreadable, or unsafe.'
    return 1
  }
  case "${component}:${STATUS_STATE[component]:-}" in
    deluge:deluge-instance) ;;
    qbittorrent:qbittorrent-instance | qbittorrent:qbittorrent | autobrr:autobrr | autoremove-torrents:autoremove-torrents | docker:docker-engine | vertex:vertex | tuning:tuning | bbr:bbr) ;;
    *)
      logs::error 'State component identity does not match.'
      return 1
      ;;
  esac
  LOGS_USER="${STATUS_STATE[user]:-}"
  if [[ "${component}" == qbittorrent ]]; then
    case "${STATUS_STATE[service_mode]:-}" in system | user | daemon | screen) ;; *)
      logs::error 'Invalid recorded qBittorrent startup mode.'
      return 1
      ;;
    esac
  fi
  if [[ "${component}" == qbittorrent || "${component}" == deluge || "${component}" == autobrr || "${component}" == autoremove-torrents ]]; then
    validate::username "${LOGS_USER}" && [[ "${selected##*/}" == "${component}.${LOGS_USER}.env" ]] || {
      logs::error 'Invalid recorded Unix account identity.'
      return 1
    }
    [[ ${EUID:-$(id -u)} -eq 0 || "${LOGS_USER}" == "$(id -un)" ]] || {
      logs::error 'Instance is outside the current Unix account scope.'
      return 1
    }
  fi
  if [[ "${component}" == deluge ]] && ! status::deluge_identity; then
    logs::error 'Invalid recorded Deluge service identities.'
    return 1
  fi
}

logs::application_path() {
  [[ "${LOGS_COMPONENT}" == qbittorrent ]] || {
    logs::error 'This component has no supported application-file source.'
    return 1
  }
  local home="${STATUS_STATE[home]:-}" config="${STATUS_STATE[config]:-}"
  [[ "${home}" == /* && "${home}" != *[[:cntrl:]]* && "${config}" == /* ]] || return 1
  LOGS_PATH="$(logs::worker app-path "${config}" "${LOGS_USER}" "${home}")" || return 1
  [[ "${LOGS_PATH}" == /* && "${LOGS_PATH}" != *[[:cntrl:]]* ]] || return 1
  logs::worker probe "${LOGS_PATH}" "${LOGS_USER}"
}

logs::journal() {
  local probe="${1:-0}" unit="${STATUS_STATE[service]:-}" mode="${STATUS_STATE[service_mode]:-system}"
  local -a command=(journalctl --quiet --no-pager --output=short-iso --lines="${LOGS_LINES}")
  [[ "${LOGS_COMPONENT}" != docker ]] || unit=docker.service
  [[ "${LOGS_COMPONENT}" != tuning ]] || unit="${STATUS_STATE[service]:-seedbox-safe-tuning.service}"
  [[ "${LOGS_COMPONENT}" != bbr ]] || {
    logs::error 'BBR has no dedicated daemon journal; use --source installer.'
    return 1
  }
  if [[ "${LOGS_COMPONENT}" == qbittorrent ]]; then
    case "${mode}" in
      system) ;;
      user)
        [[ "${LOGS_USER}" == "$(id -un)" ]] || {
          logs::error 'Query user journals as the instance owner; no automatic impersonation.'
          return 1
        }
        command+=(--user)
        ;;
      *)
        logs::error 'Daemon/screen stdout was not retained; trying the application file is possible.'
        return 1
        ;;
    esac
  fi
  [[ "${unit}" =~ ^[a-zA-Z0-9_.@:-]+\.service$ && "${unit}" != -* ]] || {
    logs::error 'Invalid recorded service unit.'
    return 1
  }
  command+=(-u "${unit}")
  if [[ "${LOGS_COMPONENT}" == deluge ]]; then
    status::deluge_identity || return 1
    command+=(-u "${STATUS_STATE[web_service]}")
  fi
  if [[ "${LOGS_COMPONENT}" == autoremove-torrents ]]; then
    unit="${STATUS_STATE[timer]:-}"
    [[ "${unit}" =~ ^[a-zA-Z0-9_.@:-]+\.timer$ && "${unit}" != -* ]] || return 1
    command+=(-u "${unit}")
  fi
  [[ -z "${LOGS_SINCE}" ]] || command+=(--since="${LOGS_SINCE}")
  if [[ "${probe}" == 1 ]]; then
    command+=(--lines=0)
    logs::bounded "${command[@]}" >/dev/null
  elif [[ "${LOGS_FOLLOW}" == 1 ]]; then
    logs::stream "${command[@]}" --follow
  else logs::bounded "${command[@]}"; fi
}

logs::container() {
  local probe="${1:-0}"
  STATUS_ROW=()
  status::vertex
  case "${STATUS_ROW[runtime_state]}" in running | stopped | failed | paused | starting) ;;
  *)
    logs::error "Container identity cannot be verified: $(ui::translate "${STATUS_ROW[reason]}")"
    return 1
    ;;
  esac
  local -a command=(env -u BASH_ENV -u ENV bash --noprofile --norc -c 'exec env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH docker --host unix:///var/run/docker.sock "$@" 2>&1' seedbox-docker-logs logs --tail "${LOGS_LINES}")
  [[ -z "${LOGS_SINCE}" ]] || command+=(--since "${LOGS_SINCE}")
  if [[ "${probe}" == 1 ]]; then
    command+=(--tail 0)
  elif [[ "${LOGS_FOLLOW}" == 1 ]]; then command+=(--follow); fi
  command+=("${STATUS_STATE[container_id]}")
  if [[ "${probe}" == 1 ]]; then
    logs::bounded "${command[@]}" >/dev/null
  elif [[ "${LOGS_FOLLOW}" == 1 ]]; then
    logs::stream "${command[@]}"
  else logs::bounded "${command[@]}"; fi
}

logs::run_matches() {
  local component="$1" run="$2" content="$3" prefix
  [[ "${component}" != installer ]] || return 0
  case "${component}" in
    qbittorrent) prefix=qb ;;
    autobrr) prefix=autobrr ;;
    autoremove-torrents) prefix=art ;;
    *) prefix="${component}" ;;
  esac
  [[ "${run}" == "${component}-"* || ("${component}" == autoremove-torrents && "${run}" == autoremove-*) ]] && return 0
  [[ "${content}" == *"BEGIN step=${prefix}."* ]]
}

logs::installer() {
  local component="$1" probe="${2:-0}" base="${SEEDBOX_LOG_BASE:-$(log::default_base)}" wanted="$(args::get run)" step="$(args::get step)"
  local name run content path selected='' selected_content='' newest='' stamp action state failed step_id line record log_path deadline=$((SECONDS + 8)) scanned=0 LOGS_TIMEOUT
  status::path_readable "${base}" && [[ -d "${base}" && -r "${base}" && -x "${base}" ]] || {
    logs::error 'Installer log directory is missing, unreadable, or unsafe.'
    return 1
  }
  [[ ${EUID:-$(id -u)} -ne 0 ]] || fs::assert_privileged_path "${base}" >/dev/null 2>&1 || {
    logs::error 'Untrusted installer log directory.'
    return 1
  }
  # Only this controlled symlink is accepted, and only within the log directory.
  if [[ -L "${base}/latest.log" ]]; then
    path="$(readlink -e -- "${base}/latest.log" 2>/dev/null)" || path=''
    [[ "${path%/*}" == "${base}" ]] || logs::error 'Ignoring an unsafe or dangling latest.log link.'
  fi
  status::query find "${base}" -mindepth 1 -maxdepth 1 -name '*.log' ! -name latest.log -printf '%f/'
  ((STATUS_RC == 0)) || {
    logs::error 'Cannot enumerate installer logs.'
    return 1
  }
  local listing="${STATUS_OUTPUT}" found=0
  while IFS= read -r -d / name; do
    ((SECONDS < deadline && scanned < 1024)) || {
      logs::error 'Installer log discovery exceeded its time/run budget; use --run RUN_ID.'
      return 1
    }
    [[ "${name}" =~ ^([a-zA-Z0-9_-]+)-([0-9]{8}-[0-9]{6})(\.[a-zA-Z0-9]+)?\.log$ ]] || continue
    action="${BASH_REMATCH[1]}" stamp="${BASH_REMATCH[2]}" run="${name%.log}"
    [[ -z "${wanted}" || "${wanted}" == "${run}" ]] || continue
    scanned=$((scanned + 1))
    LOGS_TIMEOUT=$((deadline - SECONDS))
    ((LOGS_TIMEOUT > 0)) || {
      logs::error 'Installer discovery timed out.'
      return 1
    }
    content="$(logs::worker content "${base}/${name}" '')" || {
      [[ -z "${wanted}" ]] && continue
      return 1
    }
    logs::run_matches "${component}" "${run}" "${content}" || continue
    found=$((found + 1))
    if [[ "${LOGS_LIST}" == 1 && -z "${wanted}" ]]; then
      failed=''
      while IFS= read -r line; do
        ((SECONDS < deadline)) || {
          logs::error 'Installer discovery timed out.'
          return 1
        }
        [[ "${line}" == *' [ERROR] FAIL step='* ]] || continue
        record="${line#*FAIL step=}" step_id="${record%% *}"
        [[ "${step_id}" =~ ^[a-zA-Z0-9_.-]+$ && "${step_id}" != *..* && "${step_id}" != -* ]] || continue
        failed+="${step_id} "
      done <<<"${content}"
      if ui::zh; then
        printf '%s | 操作：%s | 记录时间：%s | 失败步骤：%s\n' "${run}" "$(ui::action_label "${action}")" "${stamp}" "${failed:--}"
      else printf '%s action=%s timestamp=%s failed_steps=%s\n' "${run}" "${action}" "${stamp}" "${failed:--}"; fi
    fi
    stamp="$(stat -c %Y -- "${base}/${name}" 2>/dev/null)" || return 1
    [[ "${stamp}" =~ ^[0-9]+$ ]] || return 1
    if [[ -z "${selected}" ]] || ((stamp > newest)) || { [[ "${stamp}" == "${newest}" && "${run}" > "${selected##*/}" ]]; }; then
      selected="${base}/${name}" selected_content="${content}" newest="${stamp}"
    fi
  done < <(printf '%s' "${listing}")
  LOGS_TIMEOUT=8
  ((found > 0)) || {
    logs::error 'No matching retained installer run found.'
    return 1
  }
  [[ "${LOGS_LIST}" != 1 || -n "${wanted}" ]] || return 0
  LOGS_PATH="${selected}"
  if [[ -n "${step}" || "${LOGS_LIST}" == 1 ]]; then
    local matched=0
    while IFS= read -r line; do
      [[ "${line}" == *' step='* && "${line}" == *' log='* ]] || continue
      record="${line#* step=}" step_id="${record%% *}"
      [[ "${step_id}" =~ ^[a-zA-Z0-9_.-]+$ && "${step_id}" != -* && "${step_id}" != *..* ]] || continue
      log_path="${line##* log=}"
      [[ "${log_path}" == "${base}/steps/"* && "${log_path##*/}" == "${step_id}.log" && "${log_path#"${base}/steps/"}" != */*/* ]] || continue
      if [[ "${LOGS_LIST}" == 1 ]]; then
        state=unknown
        [[ "${line}" != *' OK step='* ]] || state=OK
        [[ "${line}" != *' FAIL step='* ]] || state=FAIL
        if ui::zh; then
          printf '%s | 结果：%s\n' "${step_id}" "$(ui::state_label "${state}")"
        else printf '%s result=%s\n' "${step_id}" "${state}"; fi
      elif [[ "${step_id}" == "${step}" ]]; then LOGS_PATH="${log_path}" matched=1; fi
    done <<<"${selected_content}"
    [[ "${LOGS_LIST}" != 1 ]] || return 0
    ((matched)) || {
      logs::error 'Selected step has no recorded log in this run.'
      return 1
    }
  fi
  logs::worker probe "${LOGS_PATH}" '' || return 1
  [[ "${probe}" != 1 ]] || return 0
  logs::error "Installer source: ${LOGS_PATH} (current account scope; component runs are not filtered by instance user)."
  if [[ -z "${step}" ]]; then
    while IFS= read -r line; do
      [[ "${line}" == *' [ERROR] FAIL step='* ]] || continue
      record="${line#*FAIL step=}"
      step_id="${record%% *}"
      [[ "${step_id}" =~ ^[a-zA-Z0-9_.-]+$ && "${step_id}" != *..* && "${step_id}" != -* ]] || continue
      run="${selected##*/}" run="${run%.log}"
      logs::error "Failed step: ${record%% *} (use --run ${run} --step ${record%% *})."
    done <<<"${selected_content}"
  fi
  logs::worker read "${LOGS_PATH}" ''
}

logs::source() {
  local source="$1" probe="${2:-0}"
  case "${source}" in
    installer)
      if [[ "${probe}" == 1 ]]; then local LOGS_LIST=0; fi
      logs::installer "${LOGS_COMPONENT}" "${probe}"
      ;;
    application)
      logs::application_path || return 1
      [[ "${probe}" != 1 ]] || return 0
      logs::error "Application source: ${LOGS_PATH}"
      logs::worker read "${LOGS_PATH}" "${LOGS_USER}"
      ;;
    service)
      [[ "${probe}" == 1 ]] || logs::error "Service source: ${LOGS_COMPONENT}"
      if [[ "${LOGS_COMPONENT}" == vertex ]]; then logs::container "${probe}"; else logs::journal "${probe}"; fi
      ;;
  esac
}

logs::report() {
  LOGS_COMPONENT="$1" LOGS_USER='' LOGS_PATH=''
  local source state_ok=0 failed=0
  if [[ "${LOGS_COMPONENT}" == installer || "${LOGS_SOURCE}" == installer || "${LOGS_COMPONENT}" == bbr && "${LOGS_SOURCE}" == auto && "${LOGS_LIST}" != 1 ]]; then
    if args::has user || args::has vertex_name; then logs::error 'Installer runs are component-scoped; instance selectors do not filter historical runs.'; fi
    logs::installer "${LOGS_COMPONENT}"
    return $?
  fi
  if [[ "${LOGS_COMPONENT}" == bbr ]]; then
    state_ok=1
  else logs::select_state "${LOGS_COMPONENT}" && state_ok=1; fi
  if [[ "${LOGS_SOURCE}" == auto && "${LOGS_LIST}" != 1 ]]; then
    ((state_ok)) || return 1
    source=service
    if [[ "${LOGS_COMPONENT}" == qbittorrent && "${STATUS_STATE[service_mode]:-}" != system && "${STATUS_STATE[service_mode]:-}" != user ]]; then source=application; fi
    if [[ -n "${LOGS_SINCE}" && "${source}" == application ]]; then
      logs::error '--since is not supported for application files.'
      return 2
    fi
    if logs::source "${source}" 1; then
      logs::source "${source}"
      return $?
    fi
    logs::error "Primary ${source} source unavailable."
    if [[ "${LOGS_COMPONENT}" == qbittorrent && -z "${LOGS_SINCE}" && "${source}" != application ]]; then
      logs::error 'Trying the qBittorrent application log.'
      logs::source application
      return $?
    fi
    return 1
  fi
  local -a sources=()
  if [[ "${LOGS_SOURCE}" == all || "${LOGS_SOURCE}" == auto ]]; then
    [[ "${LOGS_COMPONENT}" == bbr ]] || sources+=(service)
    [[ "${LOGS_COMPONENT}" != qbittorrent ]] || sources+=(application)
    sources+=(installer)
  else sources=("${LOGS_SOURCE}"); fi
  for source in "${sources[@]}"; do
    if [[ "${source}" != installer ]] && ((! state_ok)); then
      [[ "${LOGS_LIST}" != 1 ]] || printf '%s %s\n' "${source}" "$(ui::state_label unavailable)"
      failed=1
      continue
    fi
    if [[ "${LOGS_LIST}" == 1 ]]; then
      if logs::source "${source}" 1; then printf '%s %s\n' "${source}" "$(ui::state_label available)"; else
        printf '%s %s\n' "${source}" "$(ui::state_label unavailable)"
        failed=1
      fi
    else logs::source "${source}" || failed=1; fi
  done
  ((failed == 0))
}

logs::cli() {
  local component="${1:-}" context=logs key value
  [[ $# -eq 0 ]] || shift
  case "${component}" in
    qb) component=qbittorrent ;;
    autoremove_torrents) component=autoremove-torrents ;;
    help | --help | -h | '')
      args::parse_for logs "$@" || return $?
      logs::usage
      return 0
      ;;
  esac
  case "${component}" in
    qbittorrent | deluge | autobrr | autoremove-torrents) context=logs-user ;;
    vertex) context=logs-vertex ;;
    docker | tuning | bbr | installer) ;;
    *)
      logs::error "Unknown logs component: ${component}"
      return 2
      ;;
  esac
  args::parse_for "${context}" "$@" || return $?
  args::has help && {
    logs::usage
    return 0
  }
  ! args::has yes || {
    logs::error '--yes is not supported by read-only log queries.'
    return 2
  }
  LOGS_LINES="$(args::get lines 200)" LOGS_SOURCE="$(args::get source auto)" LOGS_SINCE="$(args::get since)" LOGS_FOLLOW=0 LOGS_LIST=0
  args::has follow && LOGS_FOLLOW=1
  args::has list && LOGS_LIST=1
  [[ "${LOGS_LINES}" =~ ^[1-9][0-9]{0,4}$ ]] && ((LOGS_LINES <= 10000)) || {
    logs::error '--lines must be 1–10000.'
    return 2
  }
  case "${LOGS_SOURCE}" in auto | service | application | installer | all) ;; *)
    logs::error 'Invalid log source.'
    return 2
    ;;
  esac
  if args::has since; then
    [[ -n "${LOGS_SINCE}" && "${LOGS_SINCE}" != -* && "${LOGS_SINCE}" != *[[:cntrl:]]* ]] || {
      logs::error 'Invalid --since value.'
      return 2
    }
  fi
  if [[ "${LOGS_FOLLOW}" == 1 && ("${LOGS_SOURCE}" == all || "${LOGS_LIST}" == 1) ]]; then
    logs::error '--follow requires one source and cannot be combined with --list or --source all.'
    return 2
  fi
  if [[ -n "${LOGS_SINCE}" && ("${component}" == installer || "${component}" == bbr || "${LOGS_SOURCE}" == installer || "${LOGS_SOURCE}" == application || "${LOGS_SOURCE}" == all) ]]; then
    logs::error '--since requires a journal/Docker source, not files or --source all.'
    return 2
  fi
  for key in run step; do
    if args::has "${key}"; then
      value="$(args::get "${key}")"
      [[ "${value}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ && "${value}" != *..* ]] || {
        logs::error "Invalid --${key} selector."
        return 2
      }
      [[ "${component}" == installer || "${LOGS_SOURCE}" == installer || "${component}" == bbr && "${LOGS_SOURCE}" == auto ]] || {
        logs::error '--run/--step require an installer source.'
        return 2
      }
    fi
  done
  [[ "${LOGS_LIST}" != 1 ]] || { ! args::has step && ! args::has lines && ! args::has since; } || {
    logs::error '--list cannot be combined with --step, --lines, or --since.'
    return 2
  }
  [[ "${component}" != installer || "${LOGS_SOURCE}" == auto || "${LOGS_SOURCE}" == installer ]] || {
    logs::error 'installer only supports the installer source.'
    return 2
  }
  [[ "${LOGS_SOURCE}" != application || "${component}" == qbittorrent ]] || {
    logs::error 'Application-file logs are supported only for qBittorrent.'
    return 2
  }
  [[ "${component}" != bbr || "${LOGS_SOURCE}" != service ]] || {
    logs::error 'BBR has no dedicated daemon log; use --source installer.'
    return 2
  }
  if [[ "${context}" == logs-user ]]; then
    value="$(args::get user)"
    if [[ -z "${value}" && ${EUID:-$(id -u)} -ne 0 ]]; then
      value="$(id -un)"
      ARGS[user]="${value}"
    fi
    if [[ -z "${value}" && "${LOGS_SOURCE}" != installer ]]; then
      logs::error '--user is required for user-owned logs when running as root.'
      return 2
    fi
    [[ -z "${value}" ]] || validate::die_username "${value}" || return 2
    [[ -z "${value}" || ${EUID:-$(id -u)} -eq 0 || "${value}" == "$(id -un)" ]] || {
      logs::error 'Cannot query another Unix account.'
      return 1
    }
  elif [[ "${context}" == logs-vertex ]]; then
    value="$(args::get vertex_name)"
    [[ -z "${value}" || "${value}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ && "${value}" != -* ]] || {
      logs::error 'Invalid Vertex name.'
      return 2
    }
  fi
  [[ "${LOGS_LIST}" == 1 ]] || logs::error "$(ui::tr '日志可能包含凭据、令牌或私有地址；分享前请检查。' 'Logs may contain credentials, tokens, or private addresses; review before sharing.')"
  if [[ "${component}" == qbittorrent ]]; then
    qbittorrent::logs "$(args::get user)"
  else logs::report "${component}"; fi
}
