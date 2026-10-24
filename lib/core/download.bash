# Download helper. Verifies sha256 when provided. Refuses unverified downloads unless explicitly allowed.

if [[ -n "${SEEDBOX_CORE_DOWNLOAD_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_DOWNLOAD_SOURCED=1

: "${SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS:=0}"

download::fetch() {
  local url="$1" dest="$2" sha256="${3:-}"
  local tmp dir transport_rc=0
  [[ -z "${sha256}" || "${sha256}" == SKIP || "${sha256}" =~ ^[[:xdigit:]]{64}$ ]] || {
    ui::error "Invalid SHA-256."
    return 2
  }
  fs::assert_no_symlink_components "${dest}" || return $?
  dir="$(dirname -- "${dest}")" || return $?
  mkdir -p -- "${dir}" || return $?
  tmp="$(mktemp "${dir}/.download.XXXXXX")" || return $?

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 --max-time 300 -o "${tmp}" "${url}" || transport_rc=$?
    if ((transport_rc != 0)); then
      rm -f -- "${tmp}"
      ui::error "Download failed: ${url}"
      case "${transport_rc}" in 5 | 6 | 7 | 18 | 22 | 28 | 35 | 52 | 55 | 56 | 60) return 75 ;; *) return 1 ;; esac
    fi
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${tmp}" "${url}" || transport_rc=$?
    if ((transport_rc != 0)); then
      rm -f -- "${tmp}"
      ui::error "Download failed: ${url}"
      case "${transport_rc}" in 4 | 5 | 7 | 8) return 75 ;; *) return 1 ;; esac
    fi
  else
    rm -f -- "${tmp}"
    ui::error "Neither curl nor wget is installed."
    return 1
  fi

  if [[ -n "${sha256}" && "${sha256}" != "SKIP" ]]; then
    if ! printf '%s  %s\n' "${sha256}" "${tmp}" | sha256sum -c - >/dev/null; then
      rm -f -- "${tmp}"
      ui::error "Downloaded artifact checksum verification failed: ${url}"
      return 1
    fi
  else
    if [[ "${SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS}" != "1" ]]; then
      rm -f -- "${tmp}"
      ui::error "Refusing unverified download: ${url}"
      return 1
    fi
    ui::warn "Unverified download allowed: ${url}"
  fi

  local rc=0
  mv -Tf -- "${tmp}" "${dest}" || rc=$?
  if ((rc != 0)); then rm -f -- "${tmp}"; fi
  return "${rc}"
}
