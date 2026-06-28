# Linux user helpers.

if [[ -n "${SEEDBOX_CORE_USER_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_USER_SOURCED=1

user::exists() {
  id -u "$1" >/dev/null 2>&1
}

user::home() {
  getent passwd "$1" | awk -F: '{print $6}'
}

user::ensure() {
  local user="$1" shell="${2:-/bin/bash}"
  validate::die_username "${user}"
  if ! user::exists "${user}"; then
    useradd -m -s "${shell}" "${user}"
  fi
  local home
  home="$(user::home "${user}")"
  if [[ -z "${home}" || ! -d "${home}" ]]; then
    ui::error "Could not determine home directory for ${user}."
    return 1
  fi
  chown "${user}:${user}" "${home}" 2>/dev/null || true
}

user::set_password() {
  local user="$1" password="$2"
  validate::die_username "${user}"
  printf '%s:%s\n' "${user}" "${password}" | chpasswd
}

user::run() {
  local user="$1"; shift
  runuser -u "${user}" -- "$@"
}

user::run_shell() {
  local user="$1"; shift
  runuser -u "${user}" -- bash -lc "$*"
}
