# Step runner with consistent OK/FAIL status and per-step logs.

if [[ -n "${SEEDBOX_CORE_RUNNER_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_RUNNER_SOURCED=1
declare -g RUNNER_HEARTBEAT_PID='' RUNNER_HEARTBEAT_GROUP=''

runner::stop_heartbeat() {
  if [[ "${RUNNER_HEARTBEAT_GROUP}" =~ ^[0-9]+$ ]] && ((RUNNER_HEARTBEAT_GROUP > 1)); then
    kill -TERM -- "-${RUNNER_HEARTBEAT_GROUP}" 2>/dev/null || true
    kill -KILL -- "-${RUNNER_HEARTBEAT_GROUP}" 2>/dev/null || true
  fi
  if [[ "${RUNNER_HEARTBEAT_PID}" =~ ^[0-9]+$ ]]; then
    kill -TERM "${RUNNER_HEARTBEAT_PID}" 2>/dev/null || true
    wait "${RUNNER_HEARTBEAT_PID}" 2>/dev/null || true
  fi
  RUNNER_HEARTBEAT_PID='' RUNNER_HEARTBEAT_GROUP=''
}

runner::start_heartbeat() {
  local index="$1" desc="$2" output_fd read_fd write_fd parent="${BASHPID}"
  [[ -t 1 && "${TERM:-dumb}" != dumb && "${SEEDBOX_PROGRESS:-auto}" != never ]] || return 0
  command -v setsid >/dev/null 2>&1 && [[ -d /proc/self/fd ]] || return 0
  runner::stop_heartbeat
  exec {output_fd}>&1
  coproc UI_HEARTBEAT {
    # A display helper must not keep maintenance locks or secret-input FDs open.
    for _runner_path in /proc/"${BASHPID}"/fd/*; do
      _runner_fd="${_runner_path##*/}"
      if [[ "${_runner_fd}" =~ ^[0-9]+$ ]] && ((_runner_fd > 2 && _runner_fd != output_fd && _runner_fd != 255)); then exec {_runner_fd}>&-; fi
    done
    exec setsid --wait env -u BASH_ENV -u ENV bash --noprofile --norc -c '
      output_fd="$1"; parent="$2"; index="$3"; label="$4"; desc="$5"; unit="$6"
      printf "%s\n" "${BASHPID}"
      trap "exit 0" TERM INT HUP
      while sleep 5; do
        kill -0 "${parent}" 2>/dev/null || exit 0
        printf "[%02d] [%s] %s (%s%s)\n" "${index}" "${label}" "${desc}" "${SECONDS}" "${unit}" >&"${output_fd}"
      done' seedbox-progress "${output_fd}" "${parent}" "${index}" "$(ui::tr '仍在执行' 'WAIT')" "${desc}" "$(ui::tr ' 秒' 's')" </dev/null
  }
  RUNNER_HEARTBEAT_PID="${UI_HEARTBEAT_PID:-}"
  read_fd="${UI_HEARTBEAT[0]:-}" write_fd="${UI_HEARTBEAT[1]:-}"
  if [[ "${read_fd}" =~ ^[0-9]+$ && "${write_fd}" =~ ^[0-9]+$ ]]; then
    exec {write_fd}>&-
    IFS= read -r -t 2 RUNNER_HEARTBEAT_GROUP <&"${read_fd}" || runner::stop_heartbeat
    exec {read_fd}<&-
  else runner::stop_heartbeat; fi
  exec {output_fd}>&-
  return 0
}

runner::run() {
  local id="$1" desc="$2" unit_hint="${3:-}"
  shift 3
  local step_log rc started="${SECONDS}" elapsed step_index heartbeat_before="${RUNNER_HEARTBEAT_PID}" owns_heartbeat=0
  SEEDBOX_STEP_INDEX=$((SEEDBOX_STEP_INDEX + 1))
  step_index="${SEEDBOX_STEP_INDEX}"
  if [[ -z "${SEEDBOX_STEP_DIR}" ]]; then
    log::init run
  fi
  step_log="${SEEDBOX_STEP_DIR}/${id//[^a-zA-Z0-9_.-]/_}.log"

  local display_desc
  display_desc="$(ui::translate "${desc}")"
  printf '[%02d] [%s] %s\n' "${step_index}" "$(ui::tr '进行中' 'RUN')" "${display_desc}"
  log::info "BEGIN step=${id} desc=${display_desc}"
  : >"${step_log}" || return $?
  chmod 600 "${step_log}" 2>/dev/null || true
  runner::start_heartbeat "${step_index}" "${display_desc}"
  if [[ -n "${RUNNER_HEARTBEAT_PID}" && "${RUNNER_HEARTBEAT_PID}" != "${heartbeat_before}" ]]; then owns_heartbeat=1; fi

  # Bash disables errexit throughout this conditional call. Step functions must
  # explicitly propagate required failures; a subshell would lose their globals.
  if "$@" >>"${step_log}" 2>&1; then
    rc=0
  else rc=$?; fi
  if ((owns_heartbeat)); then runner::stop_heartbeat; fi
  elapsed=$((SECONDS - started))
  if ((rc == 0)); then
    ui::color setaf 2
    printf '[%02d] [%s] %s (%s%s)\n' "${step_index}" "$(ui::tr '完成' 'OK')" "${display_desc}" "${elapsed}" "$(ui::tr ' 秒' 's')"
    ui::reset
    UI_DONE_COUNT=$((UI_DONE_COUNT + 1))
    log::info "OK step=${id} log=${step_log}"
    return 0
  else
    ui::color setaf 1
    printf '[%02d] [%s] %s (%s%s)\n' "${step_index}" "$(ui::tr '失败' 'FAIL')" "${display_desc}" "${elapsed}" "$(ui::tr ' 秒' 's')"
    ui::reset
    UI_FAILED_COUNT=$((UI_FAILED_COUNT + 1)) UI_LAST_FAILED_STEP="${id}"
    log::error "FAIL step=${id} rc=${rc} log=${step_log}"
    diagnose::from_log "${step_log}" "${unit_hint}" "${id}"
    return "${rc}"
  fi
}

runner::must() {
  runner::run "$@" || return $?
}
