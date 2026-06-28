# Filesystem helpers.

if [[ -n "${SEEDBOX_CORE_FS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_FS_SOURCED=1

fs::ensure_dir() {
  local path="$1" mode="${2:-0755}" owner="${3:-}" group="${4:-}"
  mkdir -p -- "${path}"
  chmod "${mode}" "${path}" 2>/dev/null || true
  if [[ -n "${owner}" ]]; then
    chown "${owner}:${group:-${owner}}" "${path}" 2>/dev/null || true
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
  dir="$(dirname -- "${path}")"
  mkdir -p -- "${dir}"
  tmp="$(mktemp "${dir}/.seedbox.XXXXXX")"
  cat >"${tmp}"
  chmod "${mode}" "${tmp}" 2>/dev/null || true
  if [[ -n "${owner}" ]]; then
    chown "${owner}:${group:-${owner}}" "${tmp}" 2>/dev/null || true
  fi
  mv -f -- "${tmp}" "${path}"
}

fs::remove_if_empty_dir() {
  local path="$1"
  rmdir --ignore-fail-on-non-empty "${path}" 2>/dev/null || true
}
