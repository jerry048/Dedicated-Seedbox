# Secret input helpers. Avoids printing passwords to logs.

if [[ -n "${SEEDBOX_CORE_SECRETS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_SECRETS_SOURCED=1

secrets::read_password_from_args() {
  local prompt="${1:-$(ui::tr "WebUI 密码" "WebUI password")}"
  local password="" cache="${SEEDBOX_PASSWORD_STDIN_CACHE:-}"
  if args::has password_stdin; then
    if [[ -n "${cache}" && -s "${cache}" ]]; then
      password="$(<"${cache}")"
    else
      password="$(cat)"
      if [[ -n "${cache}" ]]; then
        umask 077
        printf '%s' "${password}" >"${cache}"
      fi
    fi
  elif [[ -n "$(args::get password_file)" ]]; then
    local file
    file="$(args::get password_file)"
    [[ -r "${file}" ]] || { ui::error "$(ui::tr "密码文件不可读：${file}" "Password file is not readable: ${file}")"; return 1; }
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
