# Seedbox tuning with feature detection. Sysctl tuning is generated from RAM/storage/link speed.
# Non-sysctl NIC/disk tuning is best-effort and never fatal.

if [[ -n "${SEEDBOX_COMPONENT_TUNING_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_TUNING_SOURCED=1

tuning::usage() {
  cat <<'USAGE'
Usage:
  seedboxctl tuning apply [options]
  seedboxctl tuning uninstall
  seedboxctl tuning status

Options:
  --storage auto|hdd|ssd|sata-ssd|nvme   Storage class for dirty page policy. Default: auto
  --storage-path PATH                       Path whose backing storage drives auto storage and disk scheduler. Default: qBittorrent data path, else /
  --interface IFACE | --netdev IFACE      Network interface to tune. Default: auto
  --link-speed-mbps N                     Link speed used for network sysctls. Default: auto
  --link-speed 1g|10g|25g|2500m           Friendly alias for --link-speed-mbps
  --txqueuelen N                          txqueuelen value. Default: 10000
  --initial-cwnd N                        initcwnd/initrwnd for default routes. Default: 10
  --no-sysctl                             Skip sysctl drop-in generation
  --no-limits                             Skip /etc/security/limits.d drop-in
  --no-ring-buffer                        Skip ethtool ring-buffer tuning
  --no-rss                                Skip RSS channel tuning
  --no-rps                                Skip RPS tuning
  --no-rfs                                Skip RFS/aRFS tuning
  --no-xps                                Skip XPS tuning
  --no-initial-cwnd                       Skip default-route initcwnd/initrwnd
  --no-disk-scheduler                     Skip disk scheduler tuning
  --disk-scheduler-all                     Apply scheduler policy to all eligible physical disks instead of only the storage path leaves
  --no-net-queue-tuning                   Equivalent to --no-ring-buffer --no-rss --no-rps --no-rfs --no-xps

Policy:
  - tuned_: skipped
  - disable_tso_: skipped
  - set_ring_buffer_: best-effort, adapts to driver-reported limits
  - RSS/RPS/RFS/XPS: best-effort with queue/CPU/NUMA awareness where available
  - set_initial_congestion_window_: kept
  - Disk scheduler: path-scoped; HDD mq-deadline, SATA/SAS SSD kyber/mq-deadline, local NVMe none; skips virtual/network/FUSE storage
USAGE
}

tuning::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    apply|install)
      args::parse "$@"
      args::has help && { tuning::usage; return 0; }
      log::init tuning-apply
      tuning::apply_safe_from_parsed
      ;;
    uninstall|remove)
      args::parse "$@"
      args::has help && { tuning::usage; return 0; }
      log::init tuning-uninstall
      tuning::uninstall_from_parsed
      ;;
    status)
      log::init tuning-status
      tuning::status
      ;;
    softnet)
      tuning::softnet_status
      ;;
    help|-h|--help)
      tuning::usage
      ;;
    *)
      ui::error "Unknown tuning command: ${sub}"
      tuning::usage
      return 2
      ;;
  esac
}


tuning::valid_iface_value() {
  local iface="$1"
  [[ "${iface}" == "auto" ]] && return 0
  [[ "${iface}" =~ ^[A-Za-z0-9_.:-]{1,15}$ ]]
}

tuning::iface_arg() {
  local fallback="${1:-auto}" iface
  iface="$(args::get interface "$(args::get netdev "${fallback}")")"
  [[ -n "${iface}" ]] || iface="auto"
  if ! tuning::valid_iface_value "${iface}"; then
    ui::error "Invalid network interface: ${iface}"
    ui::error "Allowed format: auto or ^[A-Za-z0-9_.:-]{1,15}$"
    return 2
  fi
  printf '%s\n' "${iface}"
}

tuning::valid_storage_value() {
  case "$1" in hdd|ssd|sata-ssd|nvme) return 0 ;; *) return 1 ;; esac
}

tuning::valid_bool_value() {
  [[ "$1" =~ ^[01]$ ]]
}

tuning::write_default_kv() {
  local key="$1" value="$2"
  printf '%s=%q\n' "${key}" "${value}"
}


tuning::write_default_raw_kv() {
  local key="$1" value="$2"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s=%s\n' "${key}" "${value}"
}

tuning::sysctl_key_exists() {
  local key="$1" path
  path="/proc/sys/${key//./\/}"
  [[ -e "${path}" ]]
}

tuning::normalize_sysctl_value() {
  local value="$1"
  printf '%s' "${value}" | tr '\t\n' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

tuning::sysctl_current_value() {
  local key="$1" current
  current="$(sysctl -n "${key}" 2>/dev/null || true)"
  tuning::normalize_sysctl_value "${current}"
}

tuning::sysctl_assignment_supported() {
  local key="$1" value="$2" current desired after tmp rc
  tuning::sysctl_key_exists "${key}" || return 1
  if [[ "${SEEDBOX_TUNING_VALIDATE_SYSCTL:-1}" != "1" ]]; then
    return 0
  fi
  current="$(tuning::sysctl_current_value "${key}")"
  desired="$(tuning::normalize_sysctl_value "${value}")"
  tmp="$(mktemp "${TMPDIR:-/tmp}/seedbox-sysctl.XXXXXX")" || return 1
  printf '%s=%s\n' "${key}" "${value}" >"${tmp}"
  # Validate with the same parser/apply path used for the final drop-in. This catches
  # kernels that expose a key but reject a specific value even though the key exists.
  sysctl -p "${tmp}" >/dev/null 2>&1
  rc=$?
  rm -f -- "${tmp}"
  if [[ ${rc} -ne 0 ]]; then
    return 1
  fi
  after="$(tuning::sysctl_current_value "${key}")"
  if [[ "${after}" != "${desired}" ]]; then
    if [[ -n "${current}" && "${current}" != "${after}" ]]; then
      sysctl -w "${key}=${current}" >/dev/null 2>&1 || true
    fi
    return 1
  fi
  # Validation is live because only the kernel can confirm the accepted range.
  # Restore the previous runtime value before loading the generated file.
  if [[ -n "${current}" && "${current}" != "${desired}" ]]; then
    sysctl -w "${key}=${current}" >/dev/null 2>&1 || true
  fi
  return 0
}

tuning::sysctl_out_path() {
  printf '%s\n' "${SEEDBOX_TUNING_SYSCTL_OUT:-${SEEDBOX_TUNING_SYSCTL_FILE:-/etc/sysctl.d/99-seedbox.conf}}"
}

tuning::load_seedbox_sysctl_file() {
  local path="$1" marker="${SEEDBOX_STATE_DIR}/tuning.sysctl-final-apply-warning"
  rm -f -- "${marker}"
  if ! sysctl -e -p "${path}"; then
    printf 'sysctl final apply reported one or more rejected values; continuing because unsupported tunables are non-fatal.\n' >&2
    mkdir -p -- "${SEEDBOX_STATE_DIR}"
    printf '%s\n' "${path}" >"${marker}"
  fi
  return 0
}

tuning::warn_sysctl_issues() {
  local path marker line found=0
  path="$(tuning::sysctl_out_path)"
  marker="${SEEDBOX_STATE_DIR}/tuning.sysctl-final-apply-warning"
  if [[ -r "${path}" ]]; then
    while IFS= read -r line; do
      case "${line}" in
        '# skipped rejected by kernel: '*)
          if [[ ${found} -eq 0 ]]; then
            ui::warn "Some sysctl values were rejected by this kernel and were skipped:"
            found=1
          fi
          ui::warn "  - ${line#'# skipped rejected by kernel: '}"
          ;;
      esac
    done <"${path}"
    if [[ ${found} -eq 1 ]]; then
      ui::warn "Tuning continued. See ${path} for the skipped sysctl comments."
    fi
  fi
  if [[ -e "${marker}" ]]; then
    ui::warn "sysctl reported a non-fatal apply warning. Review the tuning step log and ${path}."
  fi
}

tuning::mem_mib() {
  awk '/MemTotal:/ {printf "%d\n", $2/1024}' /proc/meminfo
}

tuning::parse_link_speed_mbps() {
  local value="$1" lower number multiplier=1
  lower="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  case "${lower}" in
    *g) number="${lower%g}"; multiplier=1000 ;;
    *m) number="${lower%m}" ;;
    *) number="${lower}" ;;
  esac
  if ! validate::positive_int "${number}"; then
    ui::error "Invalid link speed: ${value}"
    return 2
  fi
  printf '%d\n' "$(( number * multiplier ))"
}

tuning::default_iface() {
  ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

tuning::link_mbps() {
  local iface="${1:-}" value=""
  if [[ -n "$(args::get link_speed_mbps)" ]]; then
    tuning::parse_link_speed_mbps "$(args::get link_speed_mbps)"
    return $?
  fi
  if [[ -n "$(args::get link_speed)" ]]; then
    tuning::parse_link_speed_mbps "$(args::get link_speed)"
    return $?
  fi
  if [[ -n "${iface}" && -r "/sys/class/net/${iface}/speed" ]]; then
    value="$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || true)"
    if [[ "${value}" =~ ^[0-9]+$ && "${value}" -gt 0 ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi
  printf '1000\n'
}

tuning::root_block_device() {
  local src pkname name
  src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  [[ -n "${src}" ]] || return 1
  if [[ "${src}" == /dev/* ]]; then
    pkname="$(lsblk -no PKNAME "${src}" 2>/dev/null | head -n1 || true)"
    if [[ -n "${pkname}" ]]; then
      printf '%s\n' "${pkname}"
      return 0
    fi
    name="$(basename -- "${src}")"
    name="${name%%[0-9]*}"
    printf '%s\n' "${name}"
  fi
}

tuning::qbittorrent_data_path_from_state() {
  local path data
  while IFS= read -r path; do
    [[ "$(basename -- "${path}")" == qbittorrent.*.env ]] || continue
    data="$(state::get "${path}" data)"
    [[ -n "${data}" ]] || continue
    printf '%s\n' "${data}"
    return 0
  done < <(state::list_paths 2>/dev/null || true)
  return 1
}

tuning::storage_path() {
  local path
  path="$(args::get storage_path "")"
  [[ -z "${path}" ]] && path="${QB_DATA_DIR:-}"
  [[ -z "${path}" ]] && path="$(tuning::qbittorrent_data_path_from_state 2>/dev/null || true)"
  [[ -z "${path}" ]] && path="/"
  case "${path}" in *$'\n'*|*$'\r'*|'') path="/" ;; esac
  printf '%s\n' "${path}"
}

tuning::storage_class() {
  local requested path detected
  requested="$(args::get storage auto)"
  case "${requested}" in
    hdd|ssd|sata-ssd|sata_ssd|nvme)
      [[ "${requested}" == "sata_ssd" ]] && requested="sata-ssd"
      printf '%s\n' "${requested}"
      return 0
      ;;
    auto|"") ;;
    *) ui::warn "Unknown --storage ${requested}; using auto." ;;
  esac
  path="$(tuning::storage_path)"
  detected="$(storage::host_class_for_path "${path}" 2>/dev/null || true)"
  case "${detected}" in
    hdd|sata-ssd|nvme) printf '%s\n' "${detected}" ;;
    ssd) printf 'sata-ssd\n' ;;
    *) printf 'sata-ssd\n' ;;
  esac
}

tuning::dirty_values() {
  local storage="$1" mem="$2" bg dirty expire writeback swappiness=10
  case "${storage}" in
    hdd)
      expire=1000; writeback=100
      if (( mem <= 512 )); then bg=16777216; dirty=67108864
      elif (( mem <= 1024 )); then bg=33554432; dirty=134217728
      elif (( mem <= 2048 )); then bg=67108864; dirty=268435456
      elif (( mem <= 4096 )); then bg=134217728; dirty=536870912
      elif (( mem <= 8192 )); then bg=268435456; dirty=1073741824
      elif (( mem <= 16384 )); then bg=268435456; dirty=1073741824
      else bg=536870912; dirty=2147483648
      fi
      ;;
    nvme)
      expire=2000; writeback=300
      if (( mem <= 512 )); then bg=33554432; dirty=134217728
      elif (( mem <= 1024 )); then bg=67108864; dirty=268435456
      elif (( mem <= 2048 )); then bg=134217728; dirty=536870912
      elif (( mem <= 4096 )); then bg=268435456; dirty=1073741824
      elif (( mem <= 8192 )); then bg=536870912; dirty=2147483648
      elif (( mem <= 16384 )); then bg=1073741824; dirty=4294967296
      elif (( mem <= 32768 )); then bg=2147483648; dirty=8589934592
      else bg=2147483648; dirty=8589934592
      fi
      ;;
    sata-ssd|ssd|*)
      expire=1500; writeback=200
      if (( mem <= 512 )); then bg=33554432; dirty=134217728
      elif (( mem <= 1024 )); then bg=67108864; dirty=268435456
      elif (( mem <= 2048 )); then bg=134217728; dirty=536870912
      elif (( mem <= 4096 )); then bg=268435456; dirty=1073741824
      elif (( mem <= 8192 )); then bg=536870912; dirty=2147483648
      else bg=1073741824; dirty=4294967296
      fi
      ;;
  esac
  printf '%s %s %s %s %s\n' "${expire}" "${writeback}" "${swappiness}" "${bg}" "${dirty}"
}

tuning::tcp_mem_values() {
  local mem="$1"
  if (( mem <= 512 )); then printf '4096 8192 16384\n'
  elif (( mem <= 1024 )); then printf '8192 16384 32768\n'
  elif (( mem <= 2048 )); then printf '16384 32768 65536\n'
  elif (( mem <= 4096 )); then printf '32768 65536 131072\n'
  elif (( mem <= 8192 )); then printf '65536 131072 262144\n'
  elif (( mem <= 16384 )); then printf '131072 262144 524288\n'
  elif (( mem <= 32768 )); then printf '262144 524288 1048576\n'
  else printf '524288 1048576 2097152\n'
  fi
}

tuning::core_buffer_max() {
  local mem="$1" link="$2" val
  if (( mem <= 512 )); then val=4194304
  elif (( mem <= 1024 )); then val=8388608
  elif (( mem <= 2048 )); then val=16777216
  elif (( mem <= 4096 )); then val=33554432
  elif (( mem <= 32768 )); then val=67108864
  else val=134217728
  fi
  if (( link < 10000 && val > 33554432 )); then val=33554432; fi
  printf '%s\n' "${val}"
}

tuning::tcp_rmem_wmem() {
  local mem="$1" link="$2" max min_r def_r min_w def_w
  if (( mem <= 512 )); then min_r=4096; def_r=131072; max=4194304
  elif (( mem <= 1024 )); then min_r=4096; def_r=131072; max=8388608
  elif (( mem <= 2048 )); then min_r=4096; def_r=131072; max=16777216
  elif (( mem <= 4096 )); then min_r=8192; def_r=131072; max=33554432
  elif (( mem <= 32768 )); then min_r=8192; def_r=262144; max=67108864
  else min_r=8192; def_r=262144; max=134217728
  fi
  if (( link < 10000 && max > 33554432 )); then max=33554432; fi
  min_w=4096; def_w=16384
  printf '%s %s %s|%s %s %s\n' "${min_r}" "${def_r}" "${max}" "${min_w}" "${def_w}" "${max}"
}

tuning::orphan_tw_values() {
  local mem="$1"
  if (( mem <= 1024 )); then printf '8192 32768\n'
  elif (( mem <= 4096 )); then printf '32768 131072\n'
  elif (( mem <= 16384 )); then printf '65536 262144\n'
  elif (( mem <= 65536 )); then printf '131072 524288\n'
  else printf '262144 1048576\n'
  fi
}

tuning::network_budget_values() {
  local link="$1"
  if (( link <= 1000 )); then printf '600 2000 8192\n'
  elif (( link <= 10000 )); then printf '1000 3000 16384\n'
  else printf '2000 4000 32768\n'
  fi
}

tuning::rps_flow_entries() {
  local link="$1"
  if (( link < 10000 )); then printf '65536\n'
  elif (( link < 25000 )); then printf '131072\n'
  else printf '262144\n'
  fi
}

tuning::candidate_sysctls() {
  local iface mem link storage dirty_vals expire writeback swappiness dirty_bg dirty_bytes
  local budget_vals budget budget_usecs backlog tcp_mem corebuf tcpbuf tcp_rmem tcp_wmem orphan_vals orphans tw flow_entries
  iface="$(tuning::iface_arg "$(tuning::default_iface)")" || return $?
  mem="$(tuning::mem_mib)"
  link="$(tuning::link_mbps "${iface}")" || return $?
  storage="$(tuning::storage_class)"
  IFS=' ' read -r expire writeback swappiness dirty_bg dirty_bytes <<<"$(tuning::dirty_values "${storage}" "${mem}")"
  IFS=' ' read -r budget budget_usecs backlog <<<"$(tuning::network_budget_values "${link}")"
  tcp_mem="$(tuning::tcp_mem_values "${mem}")"
  corebuf="$(tuning::core_buffer_max "${mem}" "${link}")"
  tcpbuf="$(tuning::tcp_rmem_wmem "${mem}" "${link}")"
  tcp_rmem="${tcpbuf%%|*}"
  tcp_wmem="${tcpbuf#*|}"
  IFS=' ' read -r orphans tw <<<"$(tuning::orphan_tw_values "${mem}")"
  flow_entries="$(tuning::rps_flow_entries "${link}")"

  cat <<EOF_SYSCTL
fs.file-max=1048576
fs.nr_open=1048576
vm.dirty_expire_centisecs=${expire}
vm.dirty_writeback_centisecs=${writeback}
vm.swappiness=${swappiness}
vm.dirty_background_bytes=${dirty_bg}
vm.dirty_bytes=${dirty_bytes}
net.core.netdev_budget=${budget}
net.core.netdev_budget_usecs=${budget_usecs}
net.core.netdev_max_backlog=${backlog}
net.ipv4.tcp_mem=${tcp_mem}
net.core.rmem_max=${corebuf}
net.core.wmem_max=${corebuf}
net.core.optmem_max=131072
net.ipv4.tcp_base_mss=1024
net.ipv4.tcp_min_snd_mss=536
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.ip_no_pmtu_disc=0
net.ipv4.tcp_mtu_probing=1
net.core.somaxconn=16384
net.ipv4.tcp_max_syn_backlog=16384
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_abort_on_overflow=0
net.ipv4.tcp_max_orphans=${orphans}
net.ipv4.tcp_max_tw_buckets=${tw}
net.ipv4.tcp_early_retrans=3
net.ipv4.tcp_ecn=2
net.ipv4.tcp_ecn_fallback=1
net.ipv4.tcp_rmem=${tcp_rmem}
net.ipv4.tcp_wmem=${tcp_wmem}
net.ipv4.tcp_moderate_rcvbuf=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=131072
vm.vfs_cache_pressure=50
vm.vfs_cache_pressure_denom=100
vm.zone_reclaim_mode=0
net.core.default_qdisc=fq
EOF_SYSCTL

  if ! args::has no_rfs && ! args::has no_net_queue_tuning; then
    printf 'net.core.rps_sock_flow_entries=%s\n' "${flow_entries}"
  fi
  if (( mem <= 512 )); then
    printf 'net.ipv4.tcp_shrink_window=1\n'
  fi
  if [[ -r /proc/sys/net/ipv4/tcp_available_congestion_control ]] && grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
    printf 'net.ipv4.tcp_congestion_control=bbr\n'
  else
    printf '# skipped unavailable congestion control: net.ipv4.tcp_congestion_control=bbr\n'
  fi
}

tuning::render_supported_sysctls() {
  local line key value current
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if [[ "${line}" == \#* ]]; then
      printf '%s\n' "${line}"
      continue
    fi
    key="${line%%=*}"
    value="${line#*=}"
    if ! tuning::sysctl_key_exists "${key}"; then
      printf '# skipped missing key: %s=%s\n' "${key}" "${value}"
    elif tuning::sysctl_assignment_supported "${key}" "${value}"; then
      printf '%s=%s\n' "${key}" "${value}"
    else
      current="$(tuning::sysctl_current_value "${key}")"
      if [[ -n "${current}" ]]; then
        printf '# skipped rejected by kernel: %s=%s (current: %s)\n' "${key}" "${value}" "${current}"
      else
        printf '# skipped rejected by kernel: %s=%s\n' "${key}" "${value}"
      fi
    fi
  done < <(tuning::candidate_sysctls)
}

tuning::write_sysctl() {
  local out iface mem link storage storage_path
  out="$(tuning::sysctl_out_path)"
  iface="$(tuning::iface_arg "$(tuning::default_iface)")" || return $?
  mem="$(tuning::mem_mib)"
  link="$(tuning::link_mbps "${iface}")" || return $?
  storage="$(tuning::storage_class)"
  storage_path="$(tuning::storage_path)"
  {
    printf '# Generated by seedboxctl. Remove with: seedboxctl tuning uninstall\n'
    printf '# detected_mem_mib=%s detected_link_mbps=%s storage=%s interface=%s storage_path=%s\n' "${mem}" "${link}" "${storage}" "${iface:-auto}" "${storage_path}"
    printf '# Only sysctl values accepted by this running kernel are persisted.\n'
    tuning::render_supported_sysctls
  } | fs::write_file "${out}" 0644 root root
  if [[ "${SEEDBOX_TUNING_APPLY_SYSCTL:-1}" == "1" ]]; then
    tuning::load_seedbox_sysctl_file "${out}"
  fi
}

tuning::write_limits() {
  fs::write_file /etc/security/limits.d/99-seedbox.conf 0644 root root <<'EOF_LIMITS'
# Generated by seedboxctl. Remove with: seedboxctl tuning uninstall
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF_LIMITS
}

tuning::write_defaults() {
  local iface link_iface link storage storage_path scheduler_scope txq initcwnd enable_ring enable_rss enable_rps enable_rfs enable_xps enable_initial_cwnd enable_disk_scheduler
  iface="$(tuning::iface_arg auto)" || return $?
  if [[ "${iface}" == "auto" ]]; then
    link_iface="$(tuning::default_iface)"
  else
    link_iface="${iface}"
  fi
  link="$(tuning::link_mbps "${link_iface}")" || return $?
  storage="$(tuning::storage_class)"
  storage_path="$(tuning::storage_path)"
  scheduler_scope="path"
  args::has disk_scheduler_all && scheduler_scope="all"
  txq="$(args::get txqueuelen 10000)"
  initcwnd="$(args::get initial_cwnd 10)"
  validate::positive_int "${link}" || { ui::error "Invalid link speed: ${link}"; return 2; }
  tuning::valid_storage_value "${storage}" || { ui::error "Invalid storage class: ${storage}"; return 2; }
  validate::positive_int "${txq}" || { ui::error "Invalid txqueuelen: ${txq}"; return 2; }
  validate::positive_int "${initcwnd}" || { ui::error "Invalid initial-cwnd: ${initcwnd}"; return 2; }
  enable_ring=1; enable_rss=1; enable_rps=1; enable_rfs=1; enable_xps=1; enable_initial_cwnd=1; enable_disk_scheduler=1
  if args::has no_net_queue_tuning; then enable_ring=0; enable_rss=0; enable_rps=0; enable_rfs=0; enable_xps=0; fi
  args::has no_ring_buffer && enable_ring=0
  args::has no_rss && enable_rss=0
  args::has no_rps && enable_rps=0
  args::has no_rfs && enable_rfs=0
  args::has no_xps && enable_xps=0
  args::has no_initial_cwnd && enable_initial_cwnd=0
  args::has no_disk_scheduler && enable_disk_scheduler=0
  tuning::valid_bool_value "${enable_ring}" || return 2
  tuning::valid_bool_value "${enable_rss}" || return 2
  tuning::valid_bool_value "${enable_rps}" || return 2
  tuning::valid_bool_value "${enable_rfs}" || return 2
  tuning::valid_bool_value "${enable_xps}" || return 2
  tuning::valid_bool_value "${enable_initial_cwnd}" || return 2
  tuning::valid_bool_value "${enable_disk_scheduler}" || return 2
  {
    printf '# Generated by seedboxctl. Remove with: seedboxctl tuning uninstall\n'
    tuning::write_default_raw_kv SEEDBOX_RUNTIME_ROOT "${SEEDBOX_ROOT}"
    tuning::write_default_kv SEEDBOX_TUNING_IFACE "${iface}"
    tuning::write_default_kv SEEDBOX_TUNING_LINK_MBPS "${link}"
    tuning::write_default_kv SEEDBOX_TUNING_STORAGE "${storage}"
    tuning::write_default_raw_kv SEEDBOX_TUNING_PATH "${storage_path}"
    tuning::write_default_kv SEEDBOX_DISK_SCHEDULER_SCOPE "${scheduler_scope}"
    tuning::write_default_kv SEEDBOX_TXQUEUELEN "${txq}"
    tuning::write_default_kv SEEDBOX_INITIAL_CWND "${initcwnd}"
    tuning::write_default_kv SEEDBOX_ENABLE_RING "${enable_ring}"
    tuning::write_default_kv SEEDBOX_ENABLE_RSS "${enable_rss}"
    tuning::write_default_kv SEEDBOX_ENABLE_RPS "${enable_rps}"
    tuning::write_default_kv SEEDBOX_ENABLE_RFS "${enable_rfs}"
    tuning::write_default_kv SEEDBOX_ENABLE_XPS "${enable_xps}"
    tuning::write_default_kv SEEDBOX_ENABLE_INITIAL_CWND "${enable_initial_cwnd}"
    tuning::write_default_kv SEEDBOX_ENABLE_DISK_SCHEDULER "${enable_disk_scheduler}"
  } | fs::write_file /etc/default/seedbox-tuning 0644 root root
}

tuning::write_runtime_script() {
  fs::write_file /usr/local/sbin/seedbox-runtime-tuning 0755 root root <<'EOF_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

seedbox_tuning_known_key() {
  case "$1" in
    SEEDBOX_RUNTIME_ROOT|SEEDBOX_TUNING_IFACE|SEEDBOX_TUNING_LINK_MBPS|SEEDBOX_TUNING_STORAGE|SEEDBOX_TUNING_PATH|SEEDBOX_DISK_SCHEDULER_SCOPE|SEEDBOX_TXQUEUELEN|SEEDBOX_INITIAL_CWND|SEEDBOX_ENABLE_RING|SEEDBOX_ENABLE_RSS|SEEDBOX_ENABLE_RPS|SEEDBOX_ENABLE_RFS|SEEDBOX_ENABLE_XPS|SEEDBOX_ENABLE_INITIAL_CWND|SEEDBOX_ENABLE_DISK_SCHEDULER) return 0 ;;
    *) return 1 ;;
  esac
}

seedbox_tuning_load_defaults() {
  local line key value
  [[ -r /etc/default/seedbox-tuning ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in ''|\#*) continue ;; esac
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    seedbox_tuning_known_key "${key}" || continue
    case "${value}" in *$'\n'*|*$'\r'*) continue ;; esac
    printf -v "${key}" '%s' "${value}"
  done </etc/default/seedbox-tuning
}

seedbox_tuning_load_defaults
: "${SEEDBOX_RUNTIME_ROOT:=/opt/seedbox/Dedicated-Seedbox}"
: "${SEEDBOX_TUNING_IFACE:=auto}"
: "${SEEDBOX_TUNING_LINK_MBPS:=1000}"
: "${SEEDBOX_TUNING_STORAGE:=auto}"
: "${SEEDBOX_TUNING_PATH:=/}"
: "${SEEDBOX_DISK_SCHEDULER_SCOPE:=path}"
: "${SEEDBOX_TXQUEUELEN:=10000}"
: "${SEEDBOX_INITIAL_CWND:=10}"
: "${SEEDBOX_ENABLE_RING:=1}"
: "${SEEDBOX_ENABLE_RSS:=1}"
: "${SEEDBOX_ENABLE_RPS:=1}"
: "${SEEDBOX_ENABLE_RFS:=1}"
: "${SEEDBOX_ENABLE_XPS:=1}"
: "${SEEDBOX_ENABLE_INITIAL_CWND:=1}"
: "${SEEDBOX_ENABLE_DISK_SCHEDULER:=1}"

log() { printf '[seedbox-tuning] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
valid_positive_int() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 )); }
valid_bool() { [[ "$1" =~ ^[01]$ ]]; }
valid_iface() { [[ "$1" == "auto" || "$1" =~ ^[A-Za-z0-9_.:-]{1,15}$ ]]; }
valid_storage() { case "$1" in auto|hdd|ssd|sata-ssd|nvme) return 0 ;; *) return 1 ;; esac; }
valid_scheduler_scope() { case "$1" in path|all) return 0 ;; *) return 1 ;; esac; }

validate_defaults() {
  valid_iface "${SEEDBOX_TUNING_IFACE}" || { log "Invalid SEEDBOX_TUNING_IFACE; using auto"; SEEDBOX_TUNING_IFACE=auto; }
  valid_positive_int "${SEEDBOX_TUNING_LINK_MBPS}" || { log "Invalid SEEDBOX_TUNING_LINK_MBPS; using 1000"; SEEDBOX_TUNING_LINK_MBPS=1000; }
  valid_storage "${SEEDBOX_TUNING_STORAGE}" || { log "Invalid SEEDBOX_TUNING_STORAGE; using auto"; SEEDBOX_TUNING_STORAGE=auto; }
  case "${SEEDBOX_TUNING_PATH}" in *$'\n'*|*$'\r'*|'') log "Invalid SEEDBOX_TUNING_PATH; using /"; SEEDBOX_TUNING_PATH=/ ;; esac
  valid_scheduler_scope "${SEEDBOX_DISK_SCHEDULER_SCOPE}" || { log "Invalid SEEDBOX_DISK_SCHEDULER_SCOPE; using path"; SEEDBOX_DISK_SCHEDULER_SCOPE=path; }
  valid_positive_int "${SEEDBOX_TXQUEUELEN}" || { log "Invalid SEEDBOX_TXQUEUELEN; using 10000"; SEEDBOX_TXQUEUELEN=10000; }
  valid_positive_int "${SEEDBOX_INITIAL_CWND}" || { log "Invalid SEEDBOX_INITIAL_CWND; using 10"; SEEDBOX_INITIAL_CWND=10; }
  valid_bool "${SEEDBOX_ENABLE_RING}" || SEEDBOX_ENABLE_RING=1
  valid_bool "${SEEDBOX_ENABLE_RSS}" || SEEDBOX_ENABLE_RSS=1
  valid_bool "${SEEDBOX_ENABLE_RPS}" || SEEDBOX_ENABLE_RPS=1
  valid_bool "${SEEDBOX_ENABLE_RFS}" || SEEDBOX_ENABLE_RFS=1
  valid_bool "${SEEDBOX_ENABLE_XPS}" || SEEDBOX_ENABLE_XPS=1
  valid_bool "${SEEDBOX_ENABLE_INITIAL_CWND}" || SEEDBOX_ENABLE_INITIAL_CWND=1
  valid_bool "${SEEDBOX_ENABLE_DISK_SCHEDULER}" || SEEDBOX_ENABLE_DISK_SCHEDULER=1
}

validate_defaults

iface_driver() {
  local iface="$1" path
  path="$(readlink -f "/sys/class/net/${iface}/device/driver" 2>/dev/null || true)"
  basename -- "${path:-unknown}"
}

iface_list() {
  local iface
  if [[ "${SEEDBOX_TUNING_IFACE}" != "auto" && -n "${SEEDBOX_TUNING_IFACE}" ]]; then
    printf '%s\n' "${SEEDBOX_TUNING_IFACE}"
    return 0
  fi
  ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 | while IFS= read -r iface; do
    case "${iface}" in
      lo|docker*|br-*|veth*|virbr*|tun*|tap*|wg*|tailscale*|kube*|cni*|flannel*) continue ;;
    esac
    [[ -d "/sys/class/net/${iface}" ]] || continue
    printf '%s\n' "${iface}"
  done
}

link_mbps() {
  local iface="$1" speed=""
  if [[ -r "/sys/class/net/${iface}/speed" ]]; then
    speed="$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || true)"
    if [[ "${speed}" =~ ^[0-9]+$ && "${speed}" -gt 0 ]]; then
      printf '%s\n' "${speed}"
      return 0
    fi
  fi
  printf '%s\n' "${SEEDBOX_TUNING_LINK_MBPS}"
}

physical_core_count() {
  if have python3; then
    python3 - <<'PY'
import os, re
cores=set()
phys=core=None
for line in open('/proc/cpuinfo', 'r', errors='ignore'):
    if line.strip()=='' and core is not None:
        cores.add((phys if phys is not None else len(cores), core))
        phys=core=None
        continue
    if line.startswith('physical id'):
        phys=line.split(':',1)[1].strip()
    elif line.startswith('core id'):
        core=line.split(':',1)[1].strip()
if core is not None:
    cores.add((phys if phys is not None else len(cores), core))
print(len(cores) if cores else (os.cpu_count() or 1))
PY
  else
    nproc 2>/dev/null || printf '1\n'
  fi
}

useful_cpu_count() {
  local iface="$1" driver cpus
  driver="$(iface_driver "${iface}")"
  cpus="$(nproc 2>/dev/null || printf 1)"
  case "${driver}" in
    virtio_net|hv_netvsc|vmxnet3) printf '%s\n' "${cpus}" ;;
    *) physical_core_count ;;
  esac
}

min_int() {
  local a="$1" b="$2"
  (( a < b )) && printf '%s\n' "${a}" || printf '%s\n' "${b}"
}

rss_cap_for_speed() {
  local speed="$1"
  if (( speed <= 1000 )); then printf '4\n'
  elif (( speed <= 10000 )); then printf '8\n'
  else printf '16\n'
  fi
}

max_combined_channels() {
  local iface="$1"
  have ethtool || return 1
  ethtool -l "${iface}" 2>/dev/null | awk '
    /Pre-set maximums:/ {section="max"; next}
    /Current hardware settings:/ {section="current"; next}
    section=="max" && $1=="Combined:" && $2 ~ /^[0-9]+$/ {print $2; found=1; exit}
    END {if (!found) exit 1}
  '
}

queue_count() {
  local iface="$1" type="$2"
  find "/sys/class/net/${iface}/queues" -maxdepth 1 -type d -name "${type}-*" 2>/dev/null | wc -l
}

local_cpulist() {
  local iface="$1" node online
  node="$(cat "/sys/class/net/${iface}/device/numa_node" 2>/dev/null || printf -- '-1')"
  if [[ "${node}" =~ ^[0-9]+$ && "${node}" -ge 0 && -r "/sys/devices/system/node/node${node}/cpulist" ]]; then
    cat "/sys/devices/system/node/node${node}/cpulist"
  elif [[ -r /sys/devices/system/cpu/online ]]; then
    cat /sys/devices/system/cpu/online
  else
    printf '0\n'
  fi
}

cpulist_to_mask() {
  local cpulist="$1"
  if have python3; then
    python3 - "${cpulist}" <<'PY'
import sys
s=sys.argv[1]
cpus=[]
for part in s.split(','):
    if not part: continue
    if '-' in part:
        a,b=part.split('-',1); cpus.extend(range(int(a), int(b)+1))
    else:
        cpus.append(int(part))
if not cpus:
    print('0'); raise SystemExit
maxcpu=max(cpus)
groups=[]
for g in range(maxcpu//32 + 1):
    word=0
    for c in cpus:
        if c//32 == g:
            word |= 1 << (c%32)
    groups.append(f'{word:08x}')
print(','.join(reversed(groups)).lstrip('0') or '0')
PY
  else
    printf 'ffffffff\n'
  fi
}

queue_mask() {
  local cpulist="$1" qidx="$2" qcount="$3"
  if have python3; then
    python3 - "${cpulist}" "${qidx}" "${qcount}" <<'PY'
import sys
s=sys.argv[1]; qidx=int(sys.argv[2]); qcount=max(1,int(sys.argv[3]))
cpus=[]
for part in s.split(','):
    if not part: continue
    if '-' in part:
        a,b=part.split('-',1); cpus.extend(range(int(a), int(b)+1))
    else:
        cpus.append(int(part))
cpus=sorted(set(cpus))
if not cpus:
    cpus=[0]
selected=[]
if qcount >= len(cpus):
    if qidx < len(cpus): selected=[cpus[qidx]]
else:
    for pos,cpu in enumerate(cpus):
        if (pos * qcount) // len(cpus) == qidx:
            selected.append(cpu)
if not selected:
    selected=[cpus[qidx % len(cpus)]]
maxcpu=max(selected)
groups=[]
for g in range(maxcpu//32 + 1):
    word=0
    for c in selected:
        if c//32 == g:
            word |= 1 << (c%32)
    groups.append(f'{word:08x}')
print(','.join(reversed(groups)).lstrip('0') or '0')
PY
  else
    printf 'ffffffff\n'
  fi
}

set_ring_buffer() {
  local iface="$1" speed target rxmax txmax rxcur txcur rx tx
  have ethtool || return 0
  speed="$(link_mbps "${iface}")"
  if (( speed <= 1000 )); then target=1024
  elif (( speed <= 10000 )); then target=4096
  else target=8192
  fi
  rxmax="$(ethtool -g "${iface}" 2>/dev/null | awk '/Pre-set maximums:/ {s="max"; next} /Current hardware settings:/ {s="cur"; next} s=="max" && $1=="RX:" && $2 ~ /^[0-9]+$/ {print $2; exit}')"
  txmax="$(ethtool -g "${iface}" 2>/dev/null | awk '/Pre-set maximums:/ {s="max"; next} /Current hardware settings:/ {s="cur"; next} s=="max" && $1=="TX:" && $2 ~ /^[0-9]+$/ {print $2; exit}')"
  [[ "${rxmax}" =~ ^[0-9]+$ ]] || rxmax=0
  [[ "${txmax}" =~ ^[0-9]+$ ]] || txmax=0
  rx="$(min_int "${rxmax}" "${target}")"
  tx="$(min_int "${txmax}" "${target}")"
  if (( rx > 0 )); then ethtool -G "${iface}" rx "${rx}" 2>/dev/null || true; fi
  if (( tx > 0 )); then ethtool -G "${iface}" tx "${tx}" 2>/dev/null || true; fi
  log "${iface}: ring target=${target} rx=${rx}/${rxmax} tx=${tx}/${txmax}"
}

set_rss() {
  local iface="$1" speed cap maxch useful desired
  have ethtool || return 0
  maxch="$(max_combined_channels "${iface}" || printf 0)"
  [[ "${maxch}" =~ ^[0-9]+$ ]] || maxch=0
  (( maxch > 1 )) || return 0
  speed="$(link_mbps "${iface}")"
  cap="$(rss_cap_for_speed "${speed}")"
  useful="$(useful_cpu_count "${iface}")"
  desired="$(min_int "${useful}" "${cap}")"
  desired="$(min_int "${desired}" "${maxch}")"
  (( desired < 1 )) && desired=1
  ethtool -L "${iface}" combined "${desired}" 2>/dev/null || \
    ethtool -L "${iface}" rx "${desired}" tx "${desired}" 2>/dev/null || true
  log "${iface}: RSS desired queues=${desired} max_combined=${maxch} useful_cpus=${useful} speed=${speed}M"
}

set_rps_rfs() {
  local iface="$1" rxq useful cpulist mask enable_rps=0 q flow_entries flow_cnt qdir
  rxq="$(queue_count "${iface}" rx)"
  useful="$(useful_cpu_count "${iface}")"
  cpulist="$(local_cpulist "${iface}")"
  mask="$(cpulist_to_mask "${cpulist}")"
  if (( rxq > 0 && rxq < useful )); then enable_rps=1; fi

  if (( enable_rps == 0 )); then
    for qdir in "/sys/class/net/${iface}/queues"/rx-*; do
      [[ -w "${qdir}/rps_cpus" ]] && printf '0' >"${qdir}/rps_cpus" || true
      [[ -w "${qdir}/rps_flow_cnt" ]] && printf '0' >"${qdir}/rps_flow_cnt" || true
    done
    log "${iface}: RPS disabled; hardware RX queues appear sufficient (${rxq}/${useful})."
    return 0
  fi

  for qdir in "/sys/class/net/${iface}/queues"/rx-*; do
    [[ -d "${qdir}" ]] || continue
    [[ -w "${qdir}/rps_cpus" ]] && printf '%s' "${mask}" >"${qdir}/rps_cpus" || true
  done
  log "${iface}: RPS enabled mask=${mask} rx_queues=${rxq} useful_cpus=${useful} local_cpus=${cpulist}"

  if [[ "${SEEDBOX_ENABLE_RFS}" == "1" ]]; then
    flow_entries="$(cat /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || printf 65536)"
    [[ "${flow_entries}" =~ ^[0-9]+$ ]] || flow_entries=65536
    (( rxq < 1 )) && rxq=1
    flow_cnt=$(( flow_entries / rxq ))
    (( flow_cnt < 1 )) && flow_cnt=1
    ethtool -K "${iface}" ntuple on 2>/dev/null || true
    for qdir in "/sys/class/net/${iface}/queues"/rx-*; do
      [[ -w "${qdir}/rps_flow_cnt" ]] && printf '%s' "${flow_cnt}" >"${qdir}/rps_flow_cnt" || true
    done
    log "${iface}: RFS/aRFS best-effort enabled flow_entries=${flow_entries} flow_cnt_per_rxq=${flow_cnt}"
  fi
}

set_xps() {
  local iface="$1" txq cpulist qdir idx mask
  txq="$(queue_count "${iface}" tx)"
  (( txq > 0 )) || return 0
  cpulist="$(local_cpulist "${iface}")"
  idx=0
  for qdir in "/sys/class/net/${iface}/queues"/tx-*; do
    [[ -d "${qdir}" ]] || continue
    mask="$(queue_mask "${cpulist}" "${idx}" "${txq}")"
    [[ -w "${qdir}/xps_cpus" ]] && printf '%s' "${mask}" >"${qdir}/xps_cpus" || true
    idx=$((idx + 1))
  done
  log "${iface}: XPS configured tx_queues=${txq} local_cpus=${cpulist}"
}

set_txqueuelen() {
  local iface="$1"
  ip link set dev "${iface}" txqueuelen "${SEEDBOX_TXQUEUELEN}" 2>/dev/null || true
}

set_initial_cwnd() {
  local route
  ip route show default 2>/dev/null | while IFS= read -r route; do
    [[ -n "${route}" ]] || continue
    local old_ifs="${IFS}"
    IFS=' '
    read -r -a parts <<<"${route}"
    IFS="${old_ifs}"
    ip route replace "${parts[@]}" initcwnd "${SEEDBOX_INITIAL_CWND}" initrwnd "${SEEDBOX_INITIAL_CWND}" 2>/dev/null || true
  done
}

load_storage_helper() {
  [[ -n "${SEEDBOX_STORAGE_HELPER_LOADED:-}" ]] && return 0
  local helper="${SEEDBOX_RUNTIME_ROOT}/lib/core/storage.bash"
  if [[ -r "${helper}" ]]; then
    # shellcheck source=/dev/null
    source "${helper}"
    SEEDBOX_STORAGE_HELPER_LOADED=1
    return 0
  fi
  return 1
}

fallback_block_class() {
  local dev="$1"
  if [[ "${dev}" == nvme* ]]; then printf 'nvme\n'; return 0; fi
  if [[ -r "/sys/block/${dev}/queue/rotational" && "$(cat "/sys/block/${dev}/queue/rotational" 2>/dev/null)" == "1" ]]; then
    printf 'hdd\n'
  else
    printf 'sata-ssd\n'
  fi
}

scheduler_candidate_devices() {
  local scheduler_file dev
  if [[ "${SEEDBOX_DISK_SCHEDULER_SCOPE}" == "all" ]]; then
    if load_storage_helper && declare -F storage::scheduler_all_devices >/dev/null; then
      storage::scheduler_all_devices || true
      return 0
    fi
    for scheduler_file in /sys/block/*/queue/scheduler; do
      [[ -e "${scheduler_file}" ]] || continue
      dev="$(basename -- "$(dirname -- "$(dirname -- "${scheduler_file}")")")"
      case "${dev}" in loop*|ram*|sr*|fd*|dm-*|md*) continue ;; esac
      printf '%s\n' "${dev}"
    done
    return 0
  fi

  if load_storage_helper && declare -F storage::scheduler_leaf_devices_for_path >/dev/null; then
    storage::scheduler_leaf_devices_for_path "${SEEDBOX_TUNING_PATH}" || true
  else
    log "storage helper unavailable; disk scheduler skipped for path-scoped mode"
  fi
}

scheduler_class_for_device() {
  local dev="$1" klass
  if load_storage_helper && declare -F storage::scheduler_class_for_device >/dev/null; then
    klass="$(storage::scheduler_class_for_device "${dev}" 2>/dev/null || true)"
    [[ -n "${klass}" ]] && { printf '%s\n' "${klass}"; return 0; }
  fi
  fallback_block_class "${dev}"
}

choose_and_set_scheduler() {
  local dev="$1" scheduler_file available klass candidate
  scheduler_file="/sys/block/${dev}/queue/scheduler"
  [[ -w "${scheduler_file}" ]] || return 0
  available="$(cat "${scheduler_file}" 2>/dev/null || true)"
  klass="$(scheduler_class_for_device "${dev}" 2>/dev/null || printf 'unknown\n')"

  case "${klass}" in
    virtual)
      log "${dev}: scheduler unchanged (virtual/cloud block device)"
      return 0
      ;;
    unknown)
      log "${dev}: scheduler unchanged (unknown block class)"
      return 0
      ;;
    hdd)
      for candidate in mq-deadline deadline; do
        [[ "${available}" == *"${candidate}"* ]] || continue
        printf '%s' "${candidate}" >"${scheduler_file}" 2>/dev/null || true
        log "${dev}: scheduler=${candidate} class=hdd"
        return 0
      done
      ;;
    nvme)
      if [[ "${available}" == *none* ]]; then
        printf 'none' >"${scheduler_file}" 2>/dev/null || true
        log "${dev}: scheduler=none class=nvme"
      fi
      return 0
      ;;
    sata-ssd|ssd)
      for candidate in kyber mq-deadline; do
        [[ "${available}" == *"${candidate}"* ]] || continue
        printf '%s' "${candidate}" >"${scheduler_file}" 2>/dev/null || true
        log "${dev}: scheduler=${candidate} class=sata-ssd"
        return 0
      done
      ;;
  esac
  log "${dev}: scheduler unchanged; no preferred scheduler available for class=${klass}"
}

set_disk_scheduler() {
  local dev
  scheduler_candidate_devices | awk 'NF && !seen[$0]++' | while IFS= read -r dev; do
    [[ -n "${dev}" ]] || continue
    choose_and_set_scheduler "${dev}" || true
  done
}

apply_netdev() {
  local iface="$1"
  [[ -d "/sys/class/net/${iface}" ]] || return 0
  set_txqueuelen "${iface}"
  [[ "${SEEDBOX_ENABLE_RING}" == "1" ]] && set_ring_buffer "${iface}" || true
  [[ "${SEEDBOX_ENABLE_RSS}" == "1" ]] && set_rss "${iface}" || true
  if [[ "${SEEDBOX_ENABLE_RPS}" == "1" ]]; then
    set_rps_rfs "${iface}" || true
  fi
  [[ "${SEEDBOX_ENABLE_XPS}" == "1" ]] && set_xps "${iface}" || true
}

apply_all() {
  local iface
  if have ip; then
    while IFS= read -r iface; do
      [[ -n "${iface}" ]] || continue
      apply_netdev "${iface}"
    done < <(iface_list)
  fi
  [[ "${SEEDBOX_ENABLE_INITIAL_CWND}" == "1" ]] && set_initial_cwnd || true
  [[ "${SEEDBOX_ENABLE_DISK_SCHEDULER}" == "1" ]] && set_disk_scheduler || true
}

case "${1:-apply}" in
  apply) apply_all ;;
  *) echo "Usage: seedbox-runtime-tuning apply" >&2; exit 2 ;;
esac
EOF_SCRIPT
}

tuning::write_boot_service() {
  systemd::write_unit seedbox-safe-tuning.service <<'EOF_UNIT'
[Unit]
Description=Apply seedbox runtime NIC and disk tuning
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/seedbox-runtime-tuning apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_UNIT
  systemctl enable --now seedbox-safe-tuning.service
}

tuning::ensure_packages() {
  apt::ensure_base
  apt::ensure_packages ethtool util-linux python3
}

tuning::write_state() {
  state::write tuning safe <<EOF_STATE
component=tuning
mode=adaptive
storage=$(tuning::storage_class)
storage_path=$(tuning::storage_path)
service=seedbox-safe-tuning.service
sysctl=/etc/sysctl.d/99-seedbox.conf
limits=/etc/security/limits.d/99-seedbox.conf
defaults=/etc/default/seedbox-tuning
runtime_script=/usr/local/sbin/seedbox-runtime-tuning
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

tuning::apply_safe_from_parsed() {
  local iface
  detect::assert_root
  iface="$(tuning::iface_arg auto)" || return $?
  ui::heading "Applying adaptive seedbox tuning"
  ui::kv "Storage" "$(tuning::storage_class)"
  ui::kv "Storage path" "$(tuning::storage_path)"
  ui::kv "Interface" "${iface}"
  ui::log_location
  printf '\n'

  runner::must tuning.packages "Install tuning dependencies" "" tuning::ensure_packages || return $?
  if ! args::has no_sysctl; then
    runner::must tuning.sysctl "Write/apply sysctl config" "" tuning::write_sysctl || return $?
    tuning::warn_sysctl_issues
  else
    ui::warn "Skipping sysctl tuning by request."
  fi
  if ! args::has no_limits; then
    runner::must tuning.limits "Write file-open limits" "" tuning::write_limits || return $?
  else
    ui::warn "Skipping limits tuning by request."
  fi
  runner::must tuning.defaults "Write runtime tuning defaults" "" tuning::write_defaults || return $?
  runner::must tuning.runtime "Write runtime tuning script" "" tuning::write_runtime_script || return $?
  runner::run tuning.boot "Apply boot-time/runtime tuning" "seedbox-safe-tuning.service" tuning::write_boot_service || true
  runner::must tuning.state "Save tuning state" "" tuning::write_state || return $?
  ui::success "Seedbox tuning applied."
}

tuning::uninstall_from_parsed() {
  detect::assert_root
  systemd::stop_disable seedbox-safe-tuning.service || true
  rm -f /etc/systemd/system/seedbox-safe-tuning.service \
        /usr/local/sbin/seedbox-runtime-tuning \
        /usr/local/sbin/seedbox-safe-tuning \
        /etc/default/seedbox-tuning \
        /etc/sysctl.d/99-seedbox.conf \
        /etc/security/limits.d/99-seedbox.conf
  systemctl daemon-reload 2>/dev/null || true
  state::remove tuning safe
  ui::success "Seedbox tuning files removed. A reboot may be needed to fully revert runtime values."
}

tuning::softnet_status() {
  if [[ -r /proc/net/softnet_stat ]]; then
    awk '{drop+=strtonum("0x"$2); sq+=strtonum("0x"$3)} END{printf "softnet_dropped=%d time_squeezed=%d\n", drop, sq}' /proc/net/softnet_stat 2>/dev/null || \
      python3 - <<'PY'
drop=sq=0
for line in open('/proc/net/softnet_stat'):
    f=line.split()
    if len(f) >= 3:
        drop += int(f[1], 16)
        sq += int(f[2], 16)
print(f"softnet_dropped={drop} time_squeezed={sq}")
PY
  else
    ui::warn "/proc/net/softnet_stat is not readable."
  fi
}

tuning::status() {
  ui::heading "Seedbox tuning status"
  [[ -r /etc/default/seedbox-tuning ]] && { printf '\nDefaults:\n'; cat /etc/default/seedbox-tuning; } || ui::warn "No /etc/default/seedbox-tuning found."
  [[ -r /etc/sysctl.d/99-seedbox.conf ]] && { printf '\nSysctl:\n'; cat /etc/sysctl.d/99-seedbox.conf; } || ui::warn "No seedbox sysctl file found."
  printf '\nSoftnet:\n'
  tuning::softnet_status || true
  printf '\nService:\n'
  systemctl status seedbox-safe-tuning.service --no-pager -l 2>/dev/null || true
}
