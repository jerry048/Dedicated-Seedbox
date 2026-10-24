# Shared, read-only storage/network detection and interactive confirmation.
# Resolve once in the parent shell, before entering a logged runner step.
if [[ -n "${SEEDBOX_CORE_HARDWARE_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_HARDWARE_SOURCED=1

declare -g HARDWARE_READY=0
declare -g HARDWARE_STORAGE_PATH=""
declare -g HARDWARE_STORAGE_KIND=""
declare -g HARDWARE_INTERFACE=""
declare -g HARDWARE_LINK_MBPS=""
declare -g HARDWARE_SAVED_STORAGE_PATH="" HARDWARE_SAVED_STORAGE_KIND="" HARDWARE_SAVED_INTERFACE="" HARDWARE_SAVED_LINK_MBPS=""

hardware::load_state() {
  local path="$1" prefix="${2:-}"
  HARDWARE_SAVED_STORAGE_PATH="" HARDWARE_SAVED_STORAGE_KIND="" HARDWARE_SAVED_INTERFACE="" HARDWARE_SAVED_LINK_MBPS=""
  [[ -r "${path}" ]] || return 0
  HARDWARE_SAVED_STORAGE_PATH="$(state::get "${path}" "${prefix}storage_path")"
  HARDWARE_SAVED_STORAGE_KIND="$(state::get "${path}" "${prefix}storage_kind")"
  HARDWARE_SAVED_INTERFACE="$(state::get "${path}" "${prefix}interface")"
  HARDWARE_SAVED_LINK_MBPS="$(state::get "${path}" "${prefix}link_mbps")"
}

hardware::network_tier() {
  if (($1 > 1000)); then printf 'over1g\n'; else printf '1g\n'; fi
}

hardware::host_storage_class() {
  case "$1" in
    hdd | hdd-raid0) printf 'hdd\n' ;;
    nvme) printf 'nvme\n' ;;
    ssd | ceph) printf 'sata-ssd\n' ;;
    *) return 1 ;;
  esac
}

hardware::normalize_storage() {
  case "${1,,}" in
    hdd | hdd-raid0 | nvme | ceph) printf '%s\n' "${1,,}" ;;
    ssd | sata-ssd | sata_ssd) printf 'ssd\n' ;;
    *) return 1 ;;
  esac
}

hardware::valid_interface() {
  [[ "$1" =~ ^[A-Za-z0-9_.:-]{1,15}$ ]]
}

hardware::interface_exists() {
  hardware::valid_interface "$1" && [[ -d "/sys/class/net/$1" ]]
}

hardware::interface_active() {
  local state carrier
  [[ "$1" != lo ]] || return 1
  state="$(cat "/sys/class/net/$1/operstate" 2>/dev/null || true)"
  carrier="$(cat "/sys/class/net/$1/carrier" 2>/dev/null || true)"
  [[ "${state}" == up || ("${state}" == unknown && "${carrier}" == 1) ]]
}

hardware::route_interface() {
  local family destination iface
  # route get does not send packets. Respect routing rather than the fastest NIC.
  for family in -4 -6; do
    if [[ "${family}" == -4 ]]; then destination=1.1.1.1; else destination=2606:4700:4700::1111; fi
    iface="$(ip "${family}" route get "${destination}" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}' || true)"
    if hardware::interface_exists "${iface}" && hardware::interface_active "${iface}"; then
      printf '%s\n' "${iface}"
      return 0
    fi
  done
  return 1
}

hardware::detect_interface() {
  local iface path
  iface="$(hardware::route_interface 2>/dev/null || true)"
  if [[ -n "${iface}" ]]; then
    printf '%s\n' "${iface}"
    return 0
  fi
  # Last resort: an active physical NIC, never an unrelated down/virtual NIC.
  for path in /sys/class/net/*; do
    [[ -e "${path}/device" ]] || continue
    iface="${path##*/}"
    hardware::interface_active "${iface}" || continue
    printf '%s\n' "${iface}"
    return 0
  done
  return 1
}

hardware::valid_speed() {
  # Exclude unknown sentinels such as -1 or UINT_MAX returned by some drivers.
  [[ "$1" =~ ^[0-9]{1,8}$ ]] && ((10#$1 > 0 && 10#$1 <= 10000000))
}

hardware::interface_speed() {
  local iface="$1" seen="${2:-}" speed lower child
  hardware::interface_exists "${iface}" || return 1
  case " ${seen} " in *" ${iface} "*) return 1 ;; esac
  speed="$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || true)"
  if hardware::valid_speed "${speed}"; then
    printf '%s\n' "${speed}"
    return 0
  fi
  if command -v ethtool >/dev/null 2>&1; then
    speed="$(ethtool "${iface}" 2>/dev/null | awk '$1 == "Speed:" && $2 ~ /^[0-9]+Mb\/s$/ {sub(/Mb\/s$/, "", $2); print $2; exit}' || true)"
    if hardware::valid_speed "${speed}"; then
      printf '%s\n' "${speed}"
      return 0
    fi
  fi
  # VLAN/bond devices may expose speed only on an active lower interface.
  for lower in "/sys/class/net/${iface}"/lower_*; do
    [[ -e "${lower}" ]] || continue
    child="${lower##*/lower_}"
    hardware::interface_active "${child}" || continue
    speed="$(hardware::interface_speed "${child}" "${seen} ${iface}" 2>/dev/null || true)"
    if hardware::valid_speed "${speed}"; then
      printf '%s\n' "${speed}"
      return 0
    fi
  done
  return 1
}

hardware::parse_link_speed() {
  local value="${1,,}" number multiplier=1 whole fraction speed
  case "${value}" in
    *g)
      number="${value%g}"
      multiplier=1000
      ;;
    *m) number="${value%m}" ;;
    *) number="${value}" ;;
  esac
  if [[ ! "${number}" =~ ^([0-9]{1,7})(\.([0-9]{1,3}))?$ ]]; then
    ui::error "Invalid link speed: $1"
    return 2
  fi
  whole="${BASH_REMATCH[1]}"
  fraction="${BASH_REMATCH[3]:-0}000"
  fraction="${fraction:0:3}"
  speed=$((10#${whole} * multiplier + 10#${fraction} * multiplier / 1000))
  if ! hardware::valid_speed "${speed}"; then
    ui::error "Invalid link speed: $1"
    return 2
  fi
  printf '%s\n' "${speed}"
}

hardware::configured_download_path() {
  local config="$1" value
  [[ -r "${config}" ]] || return 1
  value="$(awk '
    /^\[/ {section=$0; sub(/\r$/, "", section); next}
    {sub(/\r$/, "")}
    section == "[BitTorrent]" && /^Session\\DefaultSavePath=/ {sub(/^[^=]*=/, ""); modern=$0}
    section == "[Preferences]" && /^Downloads\\SavePath=/ {sub(/^[^=]*=/, ""); old=$0}
    END {if (modern != "") print modern; else if (old != "") print old}
  ' "${config}")"
  value="${value#\"}"
  value="${value%\"}"
  [[ "${value}" == /* && "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || return 1
  printf '%s\n' "${value}"
}

hardware::default_storage_path() {
  local fallback="${1:-/}" path config data
  path="$(args::get storage_path)"
  if [[ -n "${path}" ]]; then
    printf '%s\n' "${path}"
    return 0
  fi
  if [[ -n "${HARDWARE_SAVED_STORAGE_PATH}" ]]; then
    printf '%s\n' "${HARDWARE_SAVED_STORAGE_PATH}"
    return 0
  fi
  if [[ -n "${QB_DATA_DIR:-}" ]]; then
    printf '%s\n' "${QB_DATA_DIR}"
    return 0
  fi
  while IFS= read -r path; do
    [[ "${path##*/}" == qbittorrent.*.env ]] || continue
    config="$(state::get "${path}" config)"
    data="$(hardware::configured_download_path "${config}" 2>/dev/null || state::get "${path}" data)"
    [[ -n "${data}" ]] || continue
    printf '%s\n' "${data}"
    return 0
  done < <(state::list_paths 2>/dev/null || true)
  printf '%s\n' "${fallback}"
}

hardware::tty_available() {
  { : </dev/tty >/dev/tty; } 2>/dev/null
}

hardware::can_prompt() {
  [[ -t 0 ]] || hardware::tty_available
}

hardware::prompt_value() {
  local label="$1" default="$2" value
  if hardware::tty_available; then
    printf '%s [%s]: ' "${label}" "${default}" >/dev/tty
    IFS= read -r value </dev/tty || return 1
  else
    printf '%s [%s]: ' "${label}" "${default}" >&2
    IFS= read -r value || return 1
  fi
  printf '%s\n' "${value:-${default}}"
}

hardware::resolve() {
  [[ "${HARDWARE_READY}" == 1 ]] && return 0
  local path kind iface speed requested interactive=0
  hardware::can_prompt && interactive=1
  ui::heading "$(ui::tr "确认存储和网络调优参数" "Confirm storage and network tuning")"
  path="$(hardware::default_storage_path "${1:-/}")"
  while :; do
    if ((interactive)); then
      path="$(hardware::prompt_value "$(ui::tr "用于调优的存储路径" "Storage path for tuning")" "${path}")" || return 1
    fi
    if [[ "${path}" == /* && "${path}" != *$'\n'* && "${path}" != *$'\r'* ]]; then break; fi
    ui::error "$(ui::tr "存储路径必须是绝对路径且不能包含换行。" "Storage path must be absolute and contain no newlines.")"
    ((interactive)) || return 2
    path="${1:-/}"
  done
  ui::kv "$(ui::tr "挂载来源" "Mount source")" "$(storage::mount_source "${path}" 2>/dev/null || true)"
  local saved_kind="${HARDWARE_SAVED_STORAGE_KIND}" saved_iface="${HARDWARE_SAVED_INTERFACE}" saved_speed="${HARDWARE_SAVED_LINK_MBPS}"
  requested="$(args::get storage "${saved_kind:-auto}")"
  if [[ "${requested}" == auto || -z "${requested}" ]]; then
    kind="$(storage::qbittorrent_kind_for_path "${path}" 2>/dev/null || true)"
    if [[ -z "${kind}" ]]; then
      ui::warn "$(ui::tr "无法识别存储，默认使用 HDD；请确认或用 --storage 覆盖。" "Storage could not be identified; defaulting to HDD. Confirm or override with --storage.")"
      kind=hdd
    fi
    if storage::path_is_network_or_fuse "${path}"; then
      ui::warn "$(ui::tr "远程/FUSE 存储默认使用 Ceph 兼容配置；这并不代表其实际后端是 Ceph。" "Remote/FUSE storage defaults to the Ceph-compatible profile; this does not identify its physical backend as Ceph.")"
    fi
  else
    kind="$(hardware::normalize_storage "${requested}")" || {
      ui::error "Invalid storage class: ${requested}"
      return 2
    }
  fi
  while :; do
    if ((interactive)); then
      kind="$(hardware::prompt_value "$(ui::tr "存储类型 (hdd/hdd-raid0/ssd/nvme/ceph)" "Storage type (hdd/hdd-raid0/ssd/nvme/ceph)")" "${kind}")" || return 1
    fi
    if kind="$(hardware::normalize_storage "${kind}")"; then break; fi
    ui::error "$(ui::tr "无效的存储类型。" "Invalid storage type.")"
    ((interactive)) || return 2
    kind=hdd
  done
  iface="$(args::get interface "$(args::get netdev "${saved_iface:-auto}")")"
  if ! args::has interface && ! args::has netdev && [[ "${iface}" != auto ]] && ! hardware::interface_exists "${iface}"; then
    ui::warn "Saved interface ${iface} is no longer available; detecting the routed interface."
    iface=auto
  fi
  if [[ "${iface}" == auto || -z "${iface}" ]]; then
    iface="$(hardware::detect_interface 2>/dev/null || true)"
    if [[ -z "${iface}" ]]; then
      iface=auto
      ui::warn "$(ui::tr "无法识别路由网卡；网卡和速率将使用回退值。" "Could not identify the routed interface; interface/speed detection will use fallback values.")"
    fi
  fi
  while :; do
    if ((interactive)); then
      iface="$(hardware::prompt_value "$(ui::tr "网络接口" "Network interface")" "${iface}")" || return 1
    fi
    [[ "${iface}" != auto ]] || iface="$(hardware::detect_interface 2>/dev/null || printf 'auto')"
    if [[ "${iface}" == auto ]] || hardware::interface_exists "${iface}"; then break; fi
    ui::error "Invalid network interface: ${iface}"
    ((interactive)) || return 2
    iface="$(hardware::detect_interface 2>/dev/null || printf 'auto')"
  done
  requested="$(args::get link_speed_mbps "$(args::get link_speed "${saved_speed}")")"
  if [[ -n "${requested}" && "${requested}" != auto ]]; then
    speed="$(hardware::parse_link_speed "${requested}")" || return $?
  else
    speed="$(hardware::interface_speed "${iface}" 2>/dev/null || true)"
    if ! hardware::valid_speed "${speed}"; then
      speed=1000
      ui::warn "$(ui::tr "无法识别链路速率，默认使用 1000 Mbps。" "Link speed could not be identified; defaulting to 1000 Mbps.")"
    fi
  fi
  while :; do
    if ((interactive)); then
      speed="$(hardware::prompt_value "$(ui::tr "用于调优的带宽 (Mbps；可输入提供商限速)" "Bandwidth for tuning (Mbps; override for provider limits)")" "${speed}")" || return 1
    fi
    if speed="$(hardware::parse_link_speed "${speed}")"; then break; fi
    ((interactive)) || return 2
    speed=1000
  done
  HARDWARE_STORAGE_PATH="${path}"
  HARDWARE_STORAGE_KIND="${kind}"
  HARDWARE_INTERFACE="${iface}"
  HARDWARE_LINK_MBPS="${speed}"
  HARDWARE_READY=1
  log::info "Shared tuning selection: path=${path} storage=${kind} interface=${iface} link_mbps=${speed} interactive=${interactive}"
  ui::kv "Storage" "${kind} (${path})"
  ui::kv "Interface" "${iface}"
  ui::kv "$(ui::tr "带宽 (Mbps)" "Bandwidth (Mbps)")" "${speed}"
  ui::kv "$(ui::tr "自动配置档" "Automatic profile")" "$(hardware::network_tier "${speed}")-${kind}"
  if ((! interactive)); then
    ui::info "$(ui::tr "没有交互终端；使用以上检测值或显式指定值。" "No interactive terminal; using the detected or explicitly supplied values above.")"
  fi
}
