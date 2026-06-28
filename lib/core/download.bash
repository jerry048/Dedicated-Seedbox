# Download helper. Verifies sha256 when provided. Refuses unverified downloads unless explicitly allowed.

if [[ -n "${SEEDBOX_CORE_DOWNLOAD_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_DOWNLOAD_SOURCED=1

: "${SEEDBOX_ALLOW_UNVERIFIED_DOWNLOADS:=0}"

download::fetch() {
  local url="$1" dest="$2" sha256="${3:-}"
  local tmp dir
  dir="$(dirname -- "${dest}")"
  mkdir -p -- "${dir}"
  tmp="$(mktemp "${dir}/.download.XXXXXX")"

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fL --retry 3 --connect-timeout 15 --max-time 300 -o "${tmp}" "${url}"; then
      rm -f -- "${tmp}"
      ui::error "Download failed: ${url}"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -O "${tmp}" "${url}"; then
      rm -f -- "${tmp}"
      ui::error "Download failed: ${url}"
      return 1
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

  mv -f -- "${tmp}" "${dest}"
}
