# Input validation helpers.

if [[ -n "${SEEDBOX_CORE_VALIDATE_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_VALIDATE_SOURCED=1

validate::username() {
  local user="$1"
  [[ "${user}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

validate::port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

validate::unprivileged_port() {
  local port="$1"
  validate::port "${port}" && (( port >= 1024 ))
}

validate::positive_int() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] && (( value > 0 ))
}

validate::component_name() {
  [[ "$1" =~ ^[a-z0-9_.-]+$ ]]
}

validate::safe_path() {
  local path="$1"
  [[ -n "${path}" && "${path}" != *$'\n'* && "${path}" != *$'\r'* ]]
}

validate::die_username() {
  local user="$1"
  if ! validate::username "${user}"; then
    ui::error "$(ui::tr "无效的用户名：${user}" "Invalid username: ${user}")"
    ui::error "$(ui::tr "允许的格式：^[a-z_][a-z0-9_-]{0,31}$" "Allowed format: ^[a-z_][a-z0-9_-]{0,31}$")"
    return 1
  fi
}
