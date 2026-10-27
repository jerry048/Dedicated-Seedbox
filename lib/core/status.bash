# Read-only state and runtime status collectors.

if [[ -n "${SEEDBOX_CORE_STATUS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_STATUS_SOURCED=1

# Status deliberately does not use state::path/list_paths or log::init: those
# helpers create/chmod directories. Collectors only read existing state/runtime.
declare -gA STATUS_STATE=() STATUS_ROW=() STATUS_UNIT=()
declare -g STATUS_OUTPUT='' STATUS_RC=0 STATUS_UNIT_ERROR=''

status::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl status [--json] [--check]
  seedboxctl COMPONENT status [--json] [--check] [OPTIONS]

只读查看当前用户可见的安装器受管实例，不启动或修复任何组件。
端口和版本是保存的设置，不代表应用健康检查结果。
--check 在预期未满足、无法验证或没有匹配记录时返回 1。
普通报告即使实例停止也返回 0；选项无效返回 2。
无法读取或枚举状态目录时，两种模式均返回 1。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl status [--json] [--check]
  seedboxctl COMPONENT status [--json] [--check] [OPTIONS]

Read-only overview of installer-managed instances visible to the current user.
Ports and versions are recorded settings, not application-health observations.
--check returns 1 for unmet/unverifiable expectations or an empty selection.
Normal reports return 0 even for stopped instances; invalid options return 2.
Failure to read/enumerate the state database returns 1 in either mode.
USAGE
  fi
}

status::json_escape() {
  local value="$1" char code i high low LC_ALL=C.UTF-8
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "${char}" in
      '"') printf '\\"' ;;
      '\') printf '\\\\' ;;
      *)
        printf -v code '%d' "'${char}"
        if ((code < 32 || code >= 127)); then
          if ((code > 65535)); then
            high=$((55296 + ((code - 65536) >> 10)))
            low=$((56320 + ((code - 65536) & 1023)))
            printf '\\u%04x\\u%04x' "${high}" "${low}"
          else printf '\\u%04x' "${code}"; fi
        else printf '%s' "${char}"; fi
        ;;
    esac
  done
}

status::query() {
  STATUS_OUTPUT='' STATUS_RC=0
  command -v timeout >/dev/null 2>&1 || {
    STATUS_RC=127
    return 0
  }
  # External queries are bounded and never prompt. Do not print their raw errors
  # (which can contain host/account details) into JSON or application log output.
  STATUS_OUTPUT="$(timeout --kill-after=1 4 "$@" </dev/null 2>&1)" || STATUS_RC=$?
}

status::path_readable() {
  local path="$1" current=/ part
  fs::assert_no_symlink_components "${path}" >/dev/null 2>&1 || return 1
  local -a parts=()
  IFS=/ read -r -a parts <<<"${path}"
  for part in "${parts[@]}"; do
    [[ -n "${part}" ]] || continue
    [[ -x "${current}" ]] || return 1
    current="${current%/}/${part}"
    [[ -e "${current}" ]] || return 0
  done
}

status::read_state() {
  local path="$1" size line key value payload='' count=0 LC_ALL=C
  STATUS_STATE=()
  status::path_readable "${path}" || return 1
  [[ -f "${path}" && ! -L "${path}" && -r "${path}" ]] || return 1
  size="$(stat -c %s -- "${path}" 2>/dev/null)" || return 1
  [[ "${size}" =~ ^[0-9]+$ ]] && ((size <= 65536)) || return 1
  # Bound the actual read too, and reject NUL bytes rather than silently
  # accepting Bash read's usual NUL-stripping behavior.
  IFS= read -r -d '' -n 65537 payload <"${path}" && return 1
  ((${#payload} <= 65536)) || return 1
  while IFS= read -r line || [[ -n "${line}" ]]; do
    count=$((count + 1))
    ((count <= 1024)) || return 1
    [[ -n "${line}" && "${line}" != \#* ]] || continue
    [[ "${line}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]] || return 1
    key="${line%%=*}" value="${line#*=}"
    [[ ! -v STATUS_STATE["${key}"] ]] || return 1
    STATUS_STATE["${key}"]="${value}"
  done <<<"${payload}"
}

status::reset_row() {
  STATUS_ROW=([id]="$1" [component]="$2" [user]='' [webui_user]='' [rootless]=''
    [service]='' [service_mode]='' [web_port]='' [recorded_version]=''
    [status]=unknown [runtime_state]=unknown [kind]=unknown [enabled]=unknown
    [last_job_result]='' [reason]='No reliable runtime observation' [check_ok]=false)
}

status::result() {
  STATUS_ROW[status]="$1" STATUS_ROW[runtime_state]="$2"
  STATUS_ROW[check_ok]="$3" STATUS_ROW[reason]="$4"
}

status::unit() {
  local unit="$1" mode="${2:-system}" line key value malformed=0
  STATUS_UNIT=() STATUS_UNIT_ERROR=''
  [[ "${unit}" =~ ^[a-zA-Z0-9_.@:-]+\.(service|timer)$ ]] || {
    STATUS_UNIT_ERROR='Invalid recorded unit'
    return 0
  }
  local -a command=(systemctl)
  [[ "${mode}" != user ]] || command+=(--user)
  status::query "${command[@]}" show --no-pager \
    --property=LoadState --property=ActiveState --property=SubState \
    --property=UnitFileState --property=Result --property=Type \
    --property=ExecMainCode --property=ExecMainStatus "${unit}"
  while IFS= read -r line; do
    key="${line%%=*}" value="${line#*=}"
    case "${key}" in
      LoadState | ActiveState | SubState | UnitFileState | Result | Type | ExecMainCode | ExecMainStatus)
        [[ "${line}" == *=* && ! -v STATUS_UNIT["${key}"] ]] || malformed=1
        STATUS_UNIT["${key}"]="${value}"
        ;;
    esac
  done <<<"${STATUS_OUTPUT}"
  if [[ "${STATUS_UNIT[LoadState]:-}" == not-found ]] && ((STATUS_RC == 0 || STATUS_RC == 1)); then return 0; fi
  if ((STATUS_RC != 0)); then
    STATUS_UNIT=()
    STATUS_UNIT_ERROR="Service manager unavailable, denied, or timed out (exit ${STATUS_RC})"
  elif ((malformed)) || [[ -z "${STATUS_UNIT[LoadState]:-}" || -z "${STATUS_UNIT[ActiveState]:-}" || -z "${STATUS_UNIT[SubState]:-}" || -z "${STATUS_UNIT[UnitFileState]:-}" || -z "${STATUS_UNIT[Result]:-}" ]]; then
    STATUS_UNIT_ERROR='Incomplete service-manager response'
  elif [[ "${unit}" == *.service ]] && { [[ -z "${STATUS_UNIT[Type]:-}" ]] || [[ ! "${STATUS_UNIT[ExecMainCode]:-}" =~ ^[0-9]+$ || ! "${STATUS_UNIT[ExecMainStatus]:-}" =~ ^[0-9]+$ ]]; }; then
    STATUS_UNIT_ERROR='Incomplete service execution result'
  fi
}

status::service_result() {
  local oneshot="${1:-0}"
  STATUS_ROW[enabled]="${STATUS_UNIT[UnitFileState]:-unknown}"
  if [[ -n "${STATUS_UNIT_ERROR}" ]]; then
    status::result unknown unknown false "${STATUS_UNIT_ERROR}"
  elif [[ "${STATUS_UNIT[LoadState]:-}" == not-found ]]; then
    status::result inactive missing false 'Recorded unit is missing'
  elif [[ "${STATUS_UNIT[LoadState]:-}" != loaded ]]; then
    status::result unknown unknown false "Unit load state: ${STATUS_UNIT[LoadState]:-unknown}"
  elif [[ "${STATUS_UNIT[ActiveState]}" == failed || "${STATUS_UNIT[Result]:-success}" != success ]]; then
    status::result inactive failed false "Unit result: ${STATUS_UNIT[Result]:-failed}"
  elif [[ "${oneshot}" == 1 && "${STATUS_UNIT[Type]:-}" == oneshot && "${STATUS_UNIT[ExecMainCode]:-}" == 1 && "${STATUS_UNIT[ExecMainStatus]:-}" == 0 && ("${STATUS_UNIT[ActiveState]}" == active || "${STATUS_UNIT[ActiveState]}" == inactive) ]]; then
    status::result active applied true 'Last oneshot execution succeeded; live tuning values are not revalidated'
  elif [[ "${oneshot}" == 0 && "${STATUS_UNIT[ActiveState]}" == active && "${STATUS_UNIT[SubState]:-}" == running ]]; then
    status::result active running true 'Managed systemd service is running'
  elif [[ "${STATUS_UNIT[ActiveState]}" == inactive ]]; then
    status::result inactive stopped false 'Managed unit is inactive'
  else status::result unknown "${STATUS_UNIT[ActiveState]}" false "Unit substate: ${STATUS_UNIT[SubState]:-unknown}"; fi
}

status::service() {
  STATUS_ROW[kind]=service
  status::unit "${STATUS_ROW[service]}" "${STATUS_ROW[service_mode]:-system}"
  status::service_result
}

status::deluge_identity() {
  local user="${STATUS_STATE[user]:-}"
  validate::username "${user}" && [[ "${STATUS_STATE[component]:-}" == deluge-instance &&
    "${STATUS_STATE[service_mode]:-}" == system &&
    "${STATUS_STATE[service]:-}" == "seedbox-deluged-${user}.service" &&
    "${STATUS_STATE[web_service]:-}" == "seedbox-deluge-web-${user}.service" ]]
}

status::deluge() {
  STATUS_ROW[kind]=service
  status::deluge_identity && [[ "${STATUS_ROW[id]}" == "${STATUS_ROW[user]}" ]] || {
    status::result unknown unknown false 'Invalid recorded Deluge service identities'
    return 0
  }
  local daemon_status daemon_runtime daemon_reason daemon_ok daemon_enabled web_enabled
  status::unit "${STATUS_STATE[service]}"
  status::service_result
  daemon_status="${STATUS_ROW[status]}" daemon_runtime="${STATUS_ROW[runtime_state]}"
  daemon_reason="${STATUS_ROW[reason]}" daemon_ok="${STATUS_ROW[check_ok]}" daemon_enabled="${STATUS_ROW[enabled]}"
  status::unit "${STATUS_STATE[web_service]}"
  status::service_result
  web_enabled="${STATUS_ROW[enabled]}"
  if [[ "${daemon_ok}" == true && "${STATUS_ROW[check_ok]}" == true ]]; then
    status::result active running true 'Deluge daemon and WebUI services are running; application health is not checked'
  elif [[ "${daemon_ok}" != true ]]; then
    status::result "${daemon_status}" "${daemon_runtime}" false "Deluge daemon: ${daemon_reason}; WebUI: ${STATUS_ROW[runtime_state]}"
  else
    STATUS_ROW[reason]="Deluge WebUI: ${STATUS_ROW[reason]}; daemon: running"
  fi
  if [[ "${daemon_enabled}" == "${web_enabled}" ]]; then STATUS_ROW[enabled]="${daemon_enabled}"; else STATUS_ROW[enabled]=mixed; fi
}

status::process() {
  STATUS_ROW[kind]=process
  local user="${STATUS_ROW[user]}" binary="${STATUS_STATE[binary]:-}" uid expected proc ruid euid state label a b c exe uncertain=0
  validate::username "${user}" && [[ "${binary}" == /* && "${binary}" != *[[:cntrl:]]* ]] || {
    status::result unknown unknown false 'Invalid recorded process identity'
    return 0
  }
  status::query id -u -- "${user}"
  [[ "${STATUS_RC}" == 0 && "${STATUS_OUTPUT}" =~ ^[0-9]+$ ]] || {
    status::result unknown unknown false 'Recorded Unix account is unavailable'
    return 0
  }
  uid="${STATUS_OUTPUT}"
  status::query readlink -e -- "${binary}"
  [[ "${STATUS_RC}" == 0 && -n "${STATUS_OUTPUT}" ]] || {
    status::result unknown unknown false 'Recorded executable is missing, inaccessible, or cannot be resolved'
    return 0
  }
  expected="${STATUS_OUTPUT}"
  local deadline=$((SECONDS + 4))
  [[ -d /proc && -r /proc ]] || {
    status::result unknown unknown false 'Process information is unavailable'
    return 0
  }
  for proc in /proc/[0-9]*; do
    ((SECONDS < deadline)) || {
      status::result unknown unknown false 'Process scan timed out'
      return 0
    }
    [[ -d "${proc}" ]] || continue
    ruid='' euid='' state=''
    if [[ ! -r "${proc}/status" ]]; then
      uncertain=1
      continue
    fi
    while IFS=$' \t' read -r label a b c; do
      [[ "${label}" != State: ]] || state="${a}"
      if [[ "${label}" == Uid: ]]; then
        ruid="${a}" euid="${b}"
        break
      fi
    done <"${proc}/status" 2>/dev/null || {
      uncertain=1
      continue
    }
    [[ "${state}" != Z && "${state}" != X ]] || continue
    if [[ -z "${ruid}" || -z "${euid}" || -z "${state}" ]]; then
      uncertain=1
      continue
    fi
    [[ "${ruid}" == "${uid}" && "${euid}" == "${uid}" ]] || continue
    exe="$(readlink -- "${proc}/exe" 2>/dev/null)" || {
      [[ ! -d "${proc}" ]] || uncertain=1
      continue
    }
    if [[ "${exe}" == "${expected}" ]]; then
      if [[ "${state}" == T || "${state}" == t ]]; then
        status::result inactive stopped false "Matching process is suspended (PID ${proc##*/})"
      else status::result active running true "Executable and Unix UID match (PID ${proc##*/}); application health is not checked"; fi
      return 0
    fi
  done
  if ((uncertain)); then
    status::result unknown unknown false 'Some process identities could not be inspected'
  else status::result inactive stopped false 'No process matches the recorded executable and Unix UID'; fi
}

status::timer() {
  STATUS_ROW[kind]=timer
  local timer="${STATUS_STATE[timer]:-}" active enabled
  status::unit "${timer}"
  status::service_result
  [[ -z "${STATUS_UNIT_ERROR}" && "${STATUS_UNIT[LoadState]:-}" == loaded && "${STATUS_UNIT[Result]}" == success ]] || return 0
  active="${STATUS_UNIT[ActiveState]}" enabled="${STATUS_UNIT[UnitFileState]:-unknown}"
  status::unit "${STATUS_ROW[service]}"
  STATUS_ROW[enabled]="${enabled}"
  if [[ -n "${STATUS_UNIT_ERROR}" || "${STATUS_UNIT[LoadState]:-}" != loaded ]]; then
    status::result unknown unknown false 'Timer job unit is missing or cannot be queried'
    return 0
  fi
  STATUS_ROW[last_job_result]="${STATUS_UNIT[Result]:-unknown}"
  if [[ "${STATUS_UNIT[ActiveState]}" == failed || "${STATUS_UNIT[Result]:-success}" != success || ("${STATUS_UNIT[ExecMainCode]:-0}" == 1 && "${STATUS_UNIT[ExecMainStatus]:-0}" != 0) ]]; then
    status::result inactive failed false "Last timer job result: ${STATUS_UNIT[Result]:-failed}"
  elif [[ "${active}" == failed ]]; then
    status::result inactive failed false 'Timer unit failed'
  elif [[ "${enabled}" == masked* ]]; then
    status::result inactive masked false 'Timer unit is masked'
  elif [[ "${active}" == active ]]; then
    status::result active waiting true 'Timer is active; an idle job service is normal'
  elif [[ "${active}" == inactive && "${enabled}" == disabled ]]; then
    status::result inactive disabled true 'Timer is intentionally disabled; last job has no recorded failure'
  elif [[ "${active}" == inactive ]]; then
    status::result inactive stopped false 'Timer is not active'
  else status::result unknown unknown false "Timer state cannot be verified: ${active}"; fi
}

status::docker_query() {
  status::query env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
    docker --host unix:///var/run/docker.sock "$@"
}

status::docker() {
  STATUS_ROW[kind]=service
  status::unit docker.service
  STATUS_ROW[enabled]="${STATUS_UNIT[UnitFileState]:-unknown}"
  local manager="${STATUS_UNIT[ActiveState]:-unavailable}"
  status::docker_query info --format '{{.ServerVersion}}'
  if [[ "${STATUS_RC}" == 0 && "${STATUS_OUTPUT}" =~ ^[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*$ ]]; then
    status::result active running true "Local system Docker daemon is reachable; unit state: ${manager}"
  else status::result unknown unknown false "Local system Docker daemon is unavailable, denied, or timed out; unit state: ${manager}"; fi
}

status::vertex() {
  STATUS_ROW[kind]=container
  local expected="${STATUS_STATE[container_id]:-}" name="${STATUS_STATE[container]:-}" data="${STATUS_STATE[data_dir]:-}"
  local id observed_name found=0 collision=0
  [[ "${name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ && "${data}" == /* && "${data}" != *[[:cntrl:]]* ]] || {
    status::result unknown unknown false 'Invalid recorded container identity'
    return 0
  }
  status::docker_query container ls -a --no-trunc --format '{{.ID}} {{.Names}}'
  ((STATUS_RC == 0)) || {
    status::result unknown unknown false 'Local Docker engine is unavailable, denied, or timed out'
    return 0
  }
  while IFS=' ' read -r id observed_name; do
    [[ -n "${id}${observed_name}" ]] || continue
    if [[ ! "${id}" =~ ^[0-9a-f]{64}$ || ! "${observed_name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
      status::result unknown unknown false 'Incomplete Docker container inventory'
      return 0
    fi
    [[ "${id}" != "${expected}" || "${observed_name}" != "${name}" ]] || found=1
    [[ "${observed_name}" != "${name}" || "${id}" == "${expected}" ]] || collision=1
  done <<<"${STATUS_OUTPUT}"
  if [[ ! "${expected}" =~ ^[0-9a-f]{64}$ ]]; then
    status::result unknown unknown false 'Legacy state has no verified container ID; manual review required'
    return 0
  fi
  if ((collision)); then
    status::result inactive identity-mismatch false 'An unrelated same-named container replaced the saved identity'
    return 0
  fi
  if ((! found)); then
    status::result inactive missing false 'Saved container ID/name is absent'
    return 0
  fi
  local template='{{.Id}}{{println}}{{.Name}}{{println}}{{.State.Status}}{{println}}{{.State.Running}}{{println}}{{with index .State "Health"}}{{.Status}}{{else}}none{{end}}{{println}}{{.State.ExitCode}}{{println}}{{range .Mounts}}{{if eq .Destination "/vertex"}}{{.Type}}{{println}}{{.Source}}{{println}}{{end}}{{end}}'
  status::docker_query inspect --format "${template}" "${expected}"
  ((STATUS_RC == 0)) || {
    status::result unknown unknown false 'Saved container could not be inspected'
    return 0
  }
  local -a details=()
  mapfile -t details <<<"${STATUS_OUTPUT}"
  if [[ "${#details[@]}" != 8 || "${details[0]}" != "${expected}" || "${details[1]}" != "/${name}" || "${details[6]}" != bind || "${details[7]}" != "${data}" ]]; then
    status::result inactive identity-mismatch false 'Container ID, name, or /vertex bind mount does not match saved state'
  elif [[ ! "${details[3]}" =~ ^(true|false)$ || ! "${details[4]}" =~ ^(none|healthy|unhealthy|starting)$ || ! "${details[5]}" =~ ^[0-9]+$ ]]; then
    status::result unknown unknown false 'Incomplete Docker container state'
  elif [[ "${details[2]}" == paused ]]; then
    status::result inactive paused false 'Container is paused'
  elif [[ "${details[4]}" == unhealthy ]]; then
    status::result inactive failed false 'Docker reports an unhealthy container'
  elif [[ "${details[4]}" == starting ]]; then
    status::result unknown starting false 'Docker healthcheck is still starting'
  elif [[ "${details[3]}" == true && "${details[2]}" == running ]]; then
    status::result active running true "Saved container is running; Docker health: ${details[4]} (not an application test)"
  elif [[ "${details[2]}" == exited && "${details[5]}" == 0 ]]; then
    status::result inactive stopped false 'Container exited successfully'
  else status::result inactive failed false "Container state: ${details[2]}; exit code: ${details[5]}"; fi
}

status::tuning() {
  STATUS_ROW[kind]=configuration
  local path
  for path in "${STATUS_STATE[defaults]:-/etc/default/seedbox-tuning}" "${STATUS_STATE[runtime_script]:-/usr/local/sbin/seedbox-runtime-tuning}"; do
    status::path_readable "${path}" || {
      status::result unknown unknown false 'Tuning configuration path cannot be inspected safely'
      return 0
    }
    [[ -f "${path}" && -r "${path}" ]] || {
      status::result inactive missing false 'Tuning defaults or boot helper is missing/unreadable'
      return 0
    }
  done
  status::unit "${STATUS_ROW[service]:-seedbox-safe-tuning.service}"
  status::service_result 1
}

status::kernel_value() {
  IFS= read -r STATUS_OUTPUT <"$1" 2>/dev/null
}

status::bbr() {
  STATUS_ROW[kind]=configuration
  local algorithm="${STATUS_STATE[algo]:-}" active available target
  if [[ "${STATUS_STATE[status]:-}" == generic-kernel-installed ]]; then
    status::result inactive pending-reboot false 'Kernel fallback recorded; reboot into it and rerun module installation as appropriate'
    return 0
  fi
  case "${algorithm}" in
    bbrv3)
      target="${STATUS_STATE[kernel_release]:-}"
      if [[ ! "${target}" =~ ^[A-Za-z0-9][A-Za-z0-9.+_~-]*$ || ${#target} -gt 255 ]]; then
        status::result unknown unknown false 'BBRv3 target kernel is not recorded or is invalid; reinstall with a kernel-reporting installer'
        return 0
      fi
      STATUS_ROW[recorded_version]="${target}"
      status::query uname -r
      if ((STATUS_RC != 0)) || [[ ! "${STATUS_OUTPUT}" =~ ^[A-Za-z0-9][A-Za-z0-9.+_~-]*$ ]]; then
        status::result unknown unknown false 'Running kernel release could not be verified'
        return 0
      fi
      if [[ "${STATUS_OUTPUT}" != "${target}" ]]; then
        status::result inactive pending-reboot false "Boot the recorded BBRv3 kernel ${target}; running kernel is ${STATUS_OUTPUT}"
        return 0
      fi
      algorithm=bbr
      ;;
    bbrx | bbrx_old | bbrw | bbr_brutal | bbrw_brutal) ;;
    *)
      status::result unknown unknown false 'Invalid recorded BBR algorithm'
      return 0
      ;;
  esac
  status::kernel_value /proc/sys/net/ipv4/tcp_congestion_control || {
    status::result unknown unknown false 'Current congestion control cannot be read'
    return 0
  }
  active="${STATUS_OUTPUT}"
  status::kernel_value /proc/sys/net/ipv4/tcp_available_congestion_control || {
    status::result unknown unknown false 'Available congestion controls cannot be read'
    return 0
  }
  available=" ${STATUS_OUTPUT} "
  if [[ "${active}" == "${algorithm}" && "${available}" == *" ${algorithm} "* ]]; then
    status::result active selected true "Kernel congestion control is ${algorithm}; registered in the running kernel (module or built-in)"
  elif [[ "${available}" == *" ${algorithm} "* ]]; then
    status::result inactive not-selected false "${algorithm} is available but the kernel currently selects ${active}"
  else status::result inactive unavailable false "${algorithm} is not registered in the running kernel; selected: ${active}"; fi
}

status::collect() {
  local path="$1" canonical="$2" id="$3" component
  status::reset_row "${id}" "${canonical}"
  status::read_state "${path}" || {
    status::result unknown unknown false 'State file is malformed, unreadable, oversized, or symlinked'
    return 0
  }
  component="${STATUS_STATE[component]:-}"
  STATUS_ROW[component]="${component:-${canonical}}"
  STATUS_ROW[user]="${STATUS_STATE[user]:-}"
  STATUS_ROW[webui_user]="${STATUS_STATE[webui_username]:-${STATUS_STATE[web_user]:-}}"
  STATUS_ROW[rootless]="${STATUS_STATE[rootless]:-}"
  STATUS_ROW[service]="${STATUS_STATE[service]:-}"
  STATUS_ROW[service_mode]="${STATUS_STATE[service_mode]:-}"
  STATUS_ROW[web_port]="${STATUS_STATE[web_port]:-${STATUS_STATE[port]:-}}"
  STATUS_ROW[recorded_version]="${STATUS_STATE[qb_version]:-}"
  [[ "${canonical}" != deluge ]] || STATUS_ROW[recorded_version]="${STATUS_STATE[deluge_version]:-}"
  if [[ ${EUID:-$(id -u)} -ne 0 && -n "${STATUS_ROW[user]}" && "${STATUS_ROW[user]}" != "$(id -un)" ]]; then
    status::result unknown unknown false "Recorded instance is outside the current Unix user's scope"
    return 0
  fi
  case "${canonical}:${component}" in
    deluge:deluge-instance) status::deluge ;;
    qbittorrent:qbittorrent-instance | qbittorrent:qbittorrent)
      case "${STATUS_ROW[service_mode]}" in
        system) status::service ;;
        user)
          if [[ "${STATUS_ROW[user]}" != "$(id -un)" ]]; then status::result unknown unknown false 'User systemd status must be queried as the instance owner'; else status::service; fi
          ;;
        screen | daemon) status::process ;;
        *) status::result unknown unknown false 'Unrecognized recorded startup mode' ;;
      esac
      ;;
    autobrr:autobrr) status::service ;;
    autoremove-torrents:autoremove-torrents) status::timer ;;
    docker:docker-engine) status::docker ;;
    vertex:vertex) status::vertex ;;
    tuning:tuning) status::tuning ;;
    bbr:bbr) status::bbr ;;
    docker:docker-purge)
      STATUS_ROW[kind]=maintenance
      status::result inactive pending false 'Interrupted Docker purge is recorded; review manually'
      ;;
    *) status::result unknown unknown false 'Unsupported or mismatched state record' ;;
  esac
}

status::render() {
  local json="$1" first="$2" key value
  if [[ "${json}" == 1 ]]; then
    [[ "${first}" == 1 ]] || printf ','
    printf '{'
    local separator=''
    for key in component user webui_user rootless service service_mode web_port status id kind runtime_state enabled recorded_version last_job_result reason; do
      printf '%s"%s":"%s"' "${separator}" "${key}" "$(status::json_escape "${STATUS_ROW[${key}]}")"
      separator=,
    done
    printf ',"check_ok":%s}' "${STATUS_ROW[check_ok]}"
  else
    local -a values=()
    for key in component id runtime_state web_port reason; do
      value="${STATUS_ROW[${key}]}"
      value="${value//[[:cntrl:]]/?}"
      values+=("${value:--}")
    done
    if ui::zh; then
      printf '%s / %s | %s | 记录端口：%s\n  %s\n' "${values[0]}" "${values[1]}" "$(ui::state_label "${values[2]}")" "${values[3]}" "$(ui::translate "${values[4]}")"
    else printf '%-24s %-16s %-18s %-14s %s\n' "${values[@]}"; fi
  fi
}

status::report() {
  local filter="${1:-}" wanted="${2:-}" json=0 first=1 count=0 failed=0 path name canonical id
  args::has json && json=1
  if [[ "${json}" == 1 ]]; then
    printf '{"instances":['
  elif ui::zh; then
    printf '%s\n' '组件 / 实例 | 状态 | 安装记录中的端口'
  else printf '%-24s %-16s %-18s %-14s %s\n' COMPONENT INSTANCE STATE 'PORT(recorded)' DETAILS; fi
  if ! status::path_readable "${SEEDBOX_STATE_DIR}" || { [[ -e "${SEEDBOX_STATE_DIR}" ]] && [[ ! -d "${SEEDBOX_STATE_DIR}" || ! -r "${SEEDBOX_STATE_DIR}" || ! -x "${SEEDBOX_STATE_DIR}" ]]; }; then
    [[ "${json}" != 1 ]] || printf ']}\n'
    printf '%s\n' "$(ui::translate 'Cannot safely read the state directory; no changes made.')" >&2
    return 1
  fi
  if [[ -d "${SEEDBOX_STATE_DIR}" ]]; then
    # A glob cannot distinguish an empty directory from an enumeration error.
    # Slash is a safe filename delimiter, including for hostile newline names.
    local -a enumerate=(find "${SEEDBOX_STATE_DIR}" -mindepth 1 -maxdepth 1 -name '*.env' ! -name '.*' -printf '%f/')
    if command -v timeout >/dev/null 2>&1; then
      status::query "${enumerate[@]}"
    else
      STATUS_RC=0
      STATUS_OUTPUT="$("${enumerate[@]}" 2>/dev/null)" || STATUS_RC=$?
    fi
    if ((STATUS_RC != 0)); then
      [[ "${json}" != 1 ]] || printf ']}\n'
      printf '%s\n' "$(ui::translate 'Cannot enumerate the state directory; no changes made.')" >&2
      return 1
    fi
    local -a names=()
    IFS=/ read -r -d '' -a names < <(printf '%s\0' "${STATUS_OUTPUT}") || true
    for name in "${names[@]}"; do
      [[ -n "${name}" ]] || continue
      path="${SEEDBOX_STATE_DIR}/${name}"
      canonical="${name%%.*}" id="${name#*.}" id="${id%.env}"
      [[ -z "${filter}" || "${canonical}" == "${filter}" ]] || continue
      [[ -z "${wanted}" || "${id}" == "${wanted}" ]] || continue
      status::collect "${path}" "${canonical}" "${id}"
      status::render "${json}" "${first}"
      first=0 count=$((count + 1))
      [[ "${STATUS_ROW[check_ok]}" == true ]] || failed=1
    done
  fi
  if ((count == 0)) && [[ -n "${filter}" ]]; then
    status::reset_row "${wanted:-all}" "${filter}"
    status::result inactive missing false 'No matching installer-managed state record'
    status::render "${json}" "${first}"
    failed=1
  elif ((count == 0)) && [[ "${json}" != 1 ]]; then printf '%s\n' "$(ui::translate 'No managed installations found in the current state scope.')"; fi
  [[ "${json}" != 1 ]] || printf ']}\n'
  if args::has check && { ((failed || count == 0)); }; then return 1; fi
}

status::all() {
  args::parse_for status "$@" || return $?
  args::has help && {
    status::usage
    return 0
  }
  status::report
}

status::component() {
  local component="$1" id=''
  case "${component}" in
    qbittorrent | deluge | autobrr | autoremove-torrents)
      id="$(args::get user)"
      if [[ -z "${id}" && ${EUID:-$(id -u)} -ne 0 ]]; then id="$(id -un)"; fi
      [[ -z "${id}" ]] || validate::die_username "${id}" || return 2
      ;;
    vertex)
      id="$(args::get vertex_name)"
      [[ -z "${id}" || "${id}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
        ui::error 'Invalid Vertex container name.'
        return 2
      }
      ;;
  esac
  status::report "${component}" "${id}"
}

status::logs() {
  logs::cli "$@"
}
