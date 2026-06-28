# status/logs/doctor command implementations.

if [[ -n "${SEEDBOX_CORE_STATUS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_STATUS_SOURCED=1

status::json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

status::active_for_state() {
  local path="$1" service service_mode binary active="unknown"
  service="$(state::get "${path}" service)"
  service_mode="$(state::get "${path}" service_mode)"
  binary="$(state::get "${path}" binary)"
  if [[ "${service_mode}" == "system" && -n "${service}" ]] && command -v systemctl >/dev/null 2>&1; then
    systemd::is_active "${service}" && active=active || active=inactive
  elif [[ "${service_mode}" == "user" && -n "${service}" ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user is-active --quiet "${service}" && active=active || active=inactive
  elif [[ -n "${binary}" ]] && command -v pgrep >/dev/null 2>&1; then
    pgrep -f "${binary}" >/dev/null 2>&1 && active=active || active=inactive
  fi
  printf '%s\n' "${active}"
}

status::all() {
  args::parse "$@"
  local json=0
  args::has json && json=1

  if (( json )); then
    printf '{"instances":['
  else
    ui::heading "Seedbox status"
  fi

  local first=1 path component user webui_user rootless service service_mode web_port active
  while IFS= read -r path; do
    component="$(state::get "${path}" component)"
    user="$(state::get "${path}" user)"
    webui_user="$(state::get "${path}" webui_username)"
    rootless="$(state::get "${path}" rootless)"
    service="$(state::get "${path}" service)"
    service_mode="$(state::get "${path}" service_mode)"
    web_port="$(state::get "${path}" web_port)"
    active="$(status::active_for_state "${path}")"

    if (( json )); then
      (( first )) || printf ','
      first=0
      printf '{"component":"%s","user":"%s","webui_user":"%s","rootless":"%s","service":"%s","service_mode":"%s","web_port":"%s","status":"%s"}' \
        "$(status::json_escape "${component}")" \
        "$(status::json_escape "${user}")" \
        "$(status::json_escape "${webui_user}")" \
        "$(status::json_escape "${rootless}")" \
        "$(status::json_escape "${service}")" \
        "$(status::json_escape "${service_mode}")" \
        "$(status::json_escape "${web_port}")" \
        "$(status::json_escape "${active}")"
    else
      printf '%-24s user=%-16s webui=%-16s mode=%-10s service=%-32s status=%s web_port=%s\n' \
        "${component:-unknown}" "${user:-unknown}" "${webui_user:-${user:-unknown}}" "${service_mode:-unknown}" "${service:-none}" "${active}" "${web_port:-unknown}"
    fi
  done < <(state::list_paths)

  if (( json )); then
    printf ']}\n'
  fi
}

status::logs() {
  local component="${1:-}"; shift || true
  args::parse "$@"
  local user="$(args::get user)"
  case "${component}" in
    qbittorrent|qb)
      qbittorrent::logs "${user}"
      ;;
    *)
      ui::error "Unknown logs component: ${component:-missing}"
      return 2
      ;;
  esac
}

doctor::run() {
  args::parse "$@"
  log::init doctor
  ui::heading "Seedbox doctor"
  detect::public_summary | tee -a "${SEEDBOX_LOG_FILE}"
  printf '\n'
  ui::kv "Log" "${SEEDBOX_LOG_FILE}"
  ui::kv "State dir" "${SEEDBOX_STATE_DIR}"

  local ok=1
  detect::assert_supported_os || ok=0
  detect::assert_supported_arch || ok=0
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    apt::available || { ui::warn "APT is not available."; ok=0; }
  else
    ui::info "Non-root mode: skipping APT checks."
  fi
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { ui::warn "Neither curl nor wget is available."; ok=0; }

  if args::has bundle; then
    doctor::bundle
  fi

  if (( ok )); then
    ui::success "Doctor result: OK"
  else
    ui::warn "Doctor result: warnings or failures found"
    return 1
  fi
}

doctor::bundle() {
  local out base
  base="$(dirname -- "${SEEDBOX_LOG_FILE}")"
  out="${base}/doctor-bundle-$(date '+%Y%m%d-%H%M%S').tar.gz"
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    tar -czf "${out}" \
      --ignore-failed-read \
      -C / etc/os-release \
      -C "${base}" "$(basename -- "${SEEDBOX_LOG_FILE}")" \
      -C "${SEEDBOX_STATE_DIR%/}/.." "$(basename -- "${SEEDBOX_STATE_DIR}")" 2>/dev/null || true
  else
    tar -czf "${out}" \
      --ignore-failed-read \
      -C "${base}" "$(basename -- "${SEEDBOX_LOG_FILE}")" \
      -C "${SEEDBOX_STATE_DIR%/}/.." "$(basename -- "${SEEDBOX_STATE_DIR}")" 2>/dev/null || true
  fi
  ui::kv "Doctor bundle" "${out}"
}
