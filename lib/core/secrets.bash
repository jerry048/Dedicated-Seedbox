# Secret input helpers. Avoids printing passwords to logs.

if [[ -n "${SEEDBOX_CORE_SECRETS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_SECRETS_SOURCED=1

declare -ga SEEDBOX_SECRET_FILES=() SEEDBOX_SECRET_IDENTITIES=()

secrets::track_file() {
  local path="$1" identity
  [[ -f "${path}" && ! -L "${path}" ]] || return 1
  identity="$(stat -c '%d:%i:%u' -- "${path}")" || return 1
  [[ "${identity##*:}" == "${EUID:-$(id -u)}" ]] || return 1
  SEEDBOX_SECRET_FILES+=("${path}")
  SEEDBOX_SECRET_IDENTITIES+=("${identity}")
}

secrets::cleanup_file() {
  local path="$1" index identity
  for index in "${!SEEDBOX_SECRET_FILES[@]}"; do
    [[ "${SEEDBOX_SECRET_FILES[index]}" == "${path}" ]] || continue
    identity="$(stat -c '%d:%i:%u' -- "${path}" 2>/dev/null || true)"
    if [[ -f "${path}" && ! -L "${path}" && "${identity}" == "${SEEDBOX_SECRET_IDENTITIES[index]}" ]]; then
      rm -f -- "${path}" || return $?
    fi
    unset 'SEEDBOX_SECRET_FILES[index]' 'SEEDBOX_SECRET_IDENTITIES[index]'
  done
}

secrets::cleanup() {
  local path
  for path in "${SEEDBOX_SECRET_FILES[@]}"; do secrets::cleanup_file "${path}" || true; done
}

# Keep the mktemp inode stable: a parent-shell cleanup record must remain valid
# even when password input is captured through command substitution.
secrets::write_password_cache() {
  local path="$1"
  fs::assert_no_symlink_components "${path}" || return $?
  [[ -f "${path}" && ! -L "${path}" && "$(stat -c '%u:%a:%h' -- "${path}")" == "${EUID:-$(id -u)}:600:1" ]] || return 1
  cat >"${path}"
}

secrets::read_password_from_args() {
  local prompt="${1:-$(ui::tr "WebUI 密码" "WebUI password")}"
  local password="" cache="${SEEDBOX_PASSWORD_STDIN_CACHE:-}"
  if args::has password_stdin; then
    if [[ -n "${cache}" && -s "${cache}" ]]; then
      password="$(<"${cache}")"
    else
      password="$(cat)" || return $?
      if [[ -n "${cache}" ]]; then
        umask 077
        printf '%s' "${password}" | secrets::write_password_cache "${cache}" || return $?
      fi
    fi
  elif [[ -n "$(args::get password_file)" ]]; then
    local file
    file="$(args::get password_file)"
    [[ -r "${file}" ]] || {
      ui::error "$(ui::tr "密码文件不可读：${file}" "Password file is not readable: ${file}")"
      return 1
    }
    password="$(<"${file}")"
  elif [[ -n "$(args::get password)" ]]; then
    password="$(args::get password)"
  else
    if [[ -t 0 ]]; then
      printf '%s: ' "${prompt}" >&2
      IFS= read -r -s password
      printf '\n' >&2
    else
      ui::error "$(ui::tr "需要密码。请使用 --password-stdin、--password-file 或 --password。" "Password is required. Use --password-stdin, --password-file, or --password.")"
      return 1
    fi
  fi

  if [[ -z "${password}" ]]; then
    ui::error "$(ui::tr "密码不能为空。" "Password must not be empty.")"
    return 1
  fi
  printf '%s' "${password}"
}
