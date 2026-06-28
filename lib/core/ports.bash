# Port availability helpers.

if [[ -n "${SEEDBOX_CORE_PORTS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_PORTS_SOURCED=1

ports::is_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[:.])${port}$"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tuln 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[:.])${port}$"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 || lsof -nP -iUDP:"${port}" >/dev/null 2>&1
  else
    return 1
  fi
}

ports::owner() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1" pid=" $2 " user=" $3; exit}'
  elif command -v ss >/dev/null 2>&1; then
    ss -H -lntup 2>/dev/null | grep -E "(^|[:.])${port}[[:space:]]" | head -n1 || true
  fi
}

ports::assert_free() {
  local port="$1" label="${2:-$(ui::tr "端口" "port")}"
  validate::port "${port}" || { ui::error "$(ui::tr "无效的 ${label}：${port}" "Invalid ${label}: ${port}")"; return 1; }
  if ports::is_listening "${port}"; then
    ui::error "$(ui::tr "${label} ${port} 已被占用。" "${label} ${port} is already in use.")"
    local owner
    owner="$(ports::owner "${port}" || true)"
    [[ -n "${owner}" ]] && ui::error "$(ui::tr "当前监听进程：${owner}" "Current listener: ${owner}")"
    return 1
  fi
}

ports::wait_for_listen() {
  local port="$1" timeout="${2:-30}" waited=0
  while (( waited < timeout )); do
    if ports::is_listening "${port}"; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
