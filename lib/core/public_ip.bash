# Optional public IP detection.

if [[ -n "${SEEDBOX_CORE_PUBLIC_IP_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_PUBLIC_IP_SOURCED=1

public_ip::detect() {
  local url
  for url in \
    https://api.ipify.org \
    https://ifconfig.me/ip \
    https://ipinfo.io/ip; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsS --connect-timeout 3 --max-time 5 "${url}" 2>/dev/null | tr -d '\r\n' && return 0
    elif command -v wget >/dev/null 2>&1; then
      wget -qO- --timeout=5 "${url}" 2>/dev/null | tr -d '\r\n' && return 0
    fi
  done
  return 1
}
