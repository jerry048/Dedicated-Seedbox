# Step runner with consistent OK/FAIL status and per-step logs.

if [[ -n "${SEEDBOX_CORE_RUNNER_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_RUNNER_SOURCED=1

runner::run() {
  local id="$1" desc="$2" unit_hint="${3:-}"
  shift 3
  local step_log rc
  SEEDBOX_STEP_INDEX=$((SEEDBOX_STEP_INDEX + 1))
  if [[ -z "${SEEDBOX_STEP_DIR}" ]]; then
    log::init run
  fi
  step_log="${SEEDBOX_STEP_DIR}/${id//[^a-zA-Z0-9_.-]/_}.log"

  local display_desc
  display_desc="$(ui::translate "${desc}")"
  printf '[%02d] %-48s ' "${SEEDBOX_STEP_INDEX}" "${display_desc}"
  log::info "BEGIN step=${id} desc=${display_desc}"
  : >"${step_log}"
  chmod 600 "${step_log}" 2>/dev/null || true

  if "$@" >>"${step_log}" 2>&1; then
    ui::color setaf 2; printf '%s\n' "$(ui::tr "完成" "OK")"; ui::reset
    log::info "OK step=${id} log=${step_log}"
    return 0
  else
    rc=$?
    ui::color setaf 1; printf '%s\n' "$(ui::tr "失败" "FAIL")"; ui::reset
    log::error "FAIL step=${id} rc=${rc} log=${step_log}"
    diagnose::from_log "${step_log}" "${unit_hint}"
    return "${rc}"
  fi
}

runner::must() {
  runner::run "$@" || return $?
}
