# Filesystem helpers.

if [[ -n "${SEEDBOX_CORE_FS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_FS_SOURCED=1

fs::ensure_dir() {
  local path="$1" mode="${2:-0755}" owner="${3:-}" group="${4:-}"
  fs::assert_no_symlink_components "${path}" || return $?
  mkdir -p -- "${path}" || return $?
  chmod "${mode}" "${path}" || return $?
  if [[ -n "${owner}" ]]; then
    chown "${owner}:${group:-${owner}}" "${path}" || return $?
  fi
}

fs::backup_file() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    cp -a -- "${path}" "${path}.bak.$(date '+%Y%m%d-%H%M%S')"
  fi
}

fs::write_file() {
  local path="$1" mode="${2:-0644}" owner="${3:-}" group="${4:-}"
  local dir tmp
  fs::assert_no_symlink_components "${path}" || return $?
  [[ ! -e "${path}" || -f "${path}" ]] || return 1
  dir="$(dirname -- "${path}")" || return $?
  mkdir -p -- "${dir}" || return $?
  tmp="$(mktemp "${dir}/.seedbox.XXXXXX")" || return $?
  local rc=0
  cat >"${tmp}" || rc=$?
  if ((rc == 0)); then chmod "${mode}" "${tmp}" || rc=$?; fi
  if ((rc == 0)) && [[ -n "${owner}" ]]; then
    chown "${owner}:${group:-${owner}}" "${tmp}" || rc=$?
  fi
  if ((rc == 0)); then mv -Tf -- "${tmp}" "${path}" || rc=$?; fi
  if ((rc != 0)); then rm -f -- "${tmp}"; fi
  return "${rc}"
}

# Shell checks are diagnostic; tenant operations also drop privileges so a
# concurrent path swap cannot turn them into privileged filesystem operations.
fs::assert_no_symlink_components() {
  local path="$1" current=/ part
  [[ "${path}" == /* && "${path}" != *[[:cntrl:]]* && "${path}" != *//* && "/${path}/" != */./* && "/${path}/" != */../* ]] || return 1
  local -a parts=()
  IFS=/ read -r -a parts <<<"${path}"
  for part in "${parts[@]}"; do
    [[ -n "${part}" ]] || continue
    current="${current%/}/${part}"
    [[ ! -L "${current}" ]] || {
      printf '%s\n' "$(ui::tr "路径中包含符号链接，已拒绝操作：${current}" "Symlinked path refused: ${current}")" >&2
      return 1
    }
  done
}

fs::assert_privileged_path() {
  local path="$1" current=/ part info uid mode
  fs::assert_no_symlink_components "${path}" || return $?
  local -a parts=()
  IFS=/ read -r -a parts <<<"${path}"
  for part in '' "${parts[@]}"; do
    [[ -z "${part}" ]] || current="${current%/}/${part}"
    [[ -e "${current}" ]] || continue
    info="$(stat -c '%u %a' -- "${current}")" || return $?
    IFS=' ' read -r uid mode <<<"${info}"
    [[ "${uid}" == 0 ]] && (((8#${mode} & 0022) == 0)) || {
      printf '%s\n' "$(ui::tr "特权操作路径的所有权或权限不可信：${current}" "Untrusted privileged path: ${current}")" >&2
      return 1
    }
  done
}

fs::assert_privileged_tree() {
  local path="$1" entry listing
  fs::assert_privileged_path "${path}" || return $?
  listing="$(mktemp)" || return $?
  find "${path}" -print0 >"${listing}" || {
    rm -f -- "${listing}"
    return 1
  }
  local rc=0
  while IFS= read -r -d '' entry; do
    fs::assert_privileged_path "${entry}" || {
      rc=1
      break
    }
  done <"${listing}"
  rm -f -- "${listing}"
  return "${rc}"
}

fs::as_user() {
  local user="$1" function="$2" script
  shift 2
  if [[ "$(id -u "${user}")" == "$(id -u)" ]]; then
    "${function}" "$@"
    return $?
  fi
  [[ ${EUID:-$(id -u)} -eq 0 ]] || return 1
  script="$(declare -f fs::assert_no_symlink_components fs::write_file fs::ensure_user_dir_current fs::backup_current fs::copy_current ui::tr ui::zh)" || return $?
  # Pass code from the trusted runtime, not a user-writable helper or login file.
  runuser -u "${user}" -- env -u BASH_ENV -u ENV PATH=/usr/sbin:/usr/bin:/sbin:/bin bash --noprofile --norc -c "${script}; ${function} \"\$@\"" seedbox-fs "$@"
}

fs::ensure_user_dir_current() {
  local path="$1" mode="${2:-0700}"
  fs::assert_no_symlink_components "${path}" || return $?
  if [[ -e "${path}" ]]; then
    [[ -d "${path}" && -w "${path}" && -x "${path}" ]]
    return $?
  fi
  # Existing parents are never chmod/chowned; umask protects newly made parents.
  (
    umask 077
    mkdir -p -- "${path}"
  ) || return $?
  chmod "${mode}" -- "${path}"
}

fs::ensure_user_dir() { fs::as_user "$1" fs::ensure_user_dir_current "$2" "${3:-0700}"; }
fs::write_file_as() { fs::as_user "$1" fs::write_file "$2" "${3:-0600}"; }

fs::backup_current() {
  local path="$1" suffix="${2:-pre-install}" backup rc=0
  fs::assert_no_symlink_components "${path}" || return $?
  [[ -f "${path}" ]] || return 1
  backup="$(mktemp "${path}.${suffix}.$(date +%Y%m%d-%H%M%S).XXXXXX")" || return $?
  cat -- "${path}" >"${backup}" || rc=$?
  if ((rc == 0)); then chmod 0600 "${backup}" || rc=$?; fi
  if ((rc != 0)); then
    rm -f -- "${backup}"
    return "${rc}"
  fi
  printf '%s\n' "${backup}"
}

fs::backup_as() { fs::as_user "$1" fs::backup_current "$2" "${3:-pre-install}"; }

fs::copy_current() {
  local source="$1" dest="$2" mode="${3:-0600}" tmp rc=0
  fs::assert_no_symlink_components "${source}" || return $?
  fs::assert_no_symlink_components "${dest}" || return $?
  [[ -f "${source}" && (! -e "${dest}" || -f "${dest}") ]] || return 1
  tmp="$(mktemp "$(dirname -- "${dest}")/.seedbox-copy.XXXXXX")" || return $?
  cat -- "${source}" >"${tmp}" || rc=$?
  if ((rc == 0)); then chmod "${mode}" "${tmp}" || rc=$?; fi
  if ((rc == 0)); then mv -Tf -- "${tmp}" "${dest}" || rc=$?; fi
  if ((rc != 0)); then rm -f -- "${tmp}"; fi
  return "${rc}"
}

fs::copy_file_as() { fs::as_user "$1" fs::copy_current "$2" "$3" "${4:-0600}"; }

fs::remove_if_empty_dir() {
  local path="$1"
  rmdir --ignore-fail-on-non-empty "${path}" 2>/dev/null || true
}

fs::safety() {
  command -v python3 >/dev/null 2>&1 || {
    ui::error "Python 3 is required for safe purge validation; no changes were made. Install python3 and retry."
    return 1
  }
  python3 -I "${SEEDBOX_ROOT}/lib/core/safefs.py" "$@"
}
