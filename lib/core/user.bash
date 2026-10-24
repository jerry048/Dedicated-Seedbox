# Linux user helpers.

if [[ -n "${SEEDBOX_CORE_USER_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_USER_SOURCED=1

user::exists() {
  id -u "$1" >/dev/null 2>&1
}

user::home() {
  local home
  home="$(getent passwd "$1" | awk -F: '{print $6}')" || return $?
  [[ "${home}" == /* && "${home}" != *[[:cntrl:]]* ]] || return 1
  printf '%s\n' "${home}"
}

user::ensure() {
  local user="$1" shell="${2:-/bin/bash}"
  validate::die_username "${user}" || return $?
  if ! user::exists "${user}"; then
    useradd -m -s "${shell}" "${user}" || return $?
  fi
  local home
  home="$(user::home "${user}")" || return $?
  if [[ -z "${home}" || ! -d "${home}" ]]; then
    ui::error "Could not determine home directory for ${user}."
    return 1
  fi
  fs::assert_no_symlink_components "${home}" || return $?
  [[ "$(stat -c %u -- "${home}")" == "$(id -u "${user}")" ]] || {
    ui::error "Existing home has the wrong owner: ${home}"
    return 1
  }
}

user::set_password() {
  local user="$1" password="$2"
  validate::die_username "${user}"
  printf '%s:%s\n' "${user}" "${password}" | chpasswd
}

user::run() {
  local user="$1"
  shift
  runuser -u "${user}" -- "$@"
}

user::run_shell() {
  local user="$1"
  shift
  runuser -u "${user}" -- bash -lc "$*"
}
