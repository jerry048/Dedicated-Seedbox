# State database helpers. Uses simple key=value files.

if [[ -n "${SEEDBOX_CORE_STATE_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_STATE_SOURCED=1

state::default_dir() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    printf '%s\n' "/var/lib/seedbox/state"
  else
    printf '%s\n' "${HOME}/.local/state/seedbox/state"
  fi
}

: "${SEEDBOX_STATE_DIR:=$(state::default_dir)}"

state::init() {
  mkdir -p "${SEEDBOX_STATE_DIR}"
  chmod 700 "${SEEDBOX_STATE_DIR}" 2>/dev/null || true
}

state::safe_id() {
  local value="$1"
  value="${value//[^a-zA-Z0-9_.-]/_}"
  printf '%s\n' "${value}"
}

state::path() {
  local component="$1" id="$2"
  state::init
  printf '%s/%s.%s.env\n' "${SEEDBOX_STATE_DIR}" "$(state::safe_id "${component}")" "$(state::safe_id "${id}")"
}

state::write() {
  local component="$1" id="$2" path
  path="$(state::path "${component}" "${id}")"
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    fs::write_file "${path}" 0600 root root
  else
    fs::write_file "${path}" 0600
  fi
}

state::remove() {
  local component="$1" id="$2" path
  path="$(state::path "${component}" "${id}")"
  rm -f -- "${path}"
}

state::list_paths() {
  state::init
  find "${SEEDBOX_STATE_DIR}" -maxdepth 1 -type f -name '*.env' -print 2>/dev/null | sort
}

state::get() {
  local path="$1" key="$2"
  awk -F= -v k="${key}" '$1==k {sub(/^[^=]*=/, ""); print; exit}' "${path}" 2>/dev/null
}

state::has_component() {
  local component="$1"
  state::init
  local comp
  comp="$(state::safe_id "${component}")"
  find "${SEEDBOX_STATE_DIR}" -maxdepth 1 -type f -name "${comp}.*.env" -print -quit 2>/dev/null | grep -q .
}

state::escape_value() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s\n' "${value}"
}

state::print_kv() {
  local key="$1" value="$2"
  printf '%s=%s\n' "${key}" "$(state::escape_value "${value}")"
}
