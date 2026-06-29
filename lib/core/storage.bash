# Shared storage/path detector for qBittorrent profile selection and host tuning.
# Read-only: uses findmnt, lsblk, /sys, /dev/disk/by-id, and optional zpool metadata.

if [[ -n "${SEEDBOX_CORE_STORAGE_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_STORAGE_SOURCED=1

storage::have() { command -v "$1" >/dev/null 2>&1; }

storage::lower() {
  local value="${1:-}"
  printf '%s\n' "${value,,}"
}

storage::existing_path() {
  local path="${1:-/}"
  [[ -n "${path}" ]] || path="/"
  while [[ ! -e "${path}" && "${path}" != "/" ]]; do
    path="$(dirname -- "${path}")"
  done
  printf '%s\n' "${path}"
}

storage::findmnt_field() {
  local path field target
  path="${1:-/}"
  field="$2"
  target="$(storage::existing_path "${path}")"
  storage::have findmnt || return 1
  findmnt -n -T "${target}" -o "${field}" 2>/dev/null | head -n1
}

storage::mount_source() { storage::findmnt_field "${1:-/}" SOURCE; }
storage::mount_fstype() { storage::findmnt_field "${1:-/}" FSTYPE; }

storage::strip_source_suffix() {
  local source="${1:-}"
  # findmnt can render btrfs subvolumes as /dev/sdaX[/subvol].
  source="${source%%\[*}"
  printf '%s\n' "${source}"
}

storage::fstype_is_ceph() {
  local fstype
  fstype="$(storage::lower "${1:-}")"
  case "${fstype}" in
    ceph|cephfs|fuse.ceph|rbd|rbd*) return 0 ;;
    *) return 1 ;;
  esac
}

storage::source_is_ceph() {
  local source
  source="$(storage::lower "${1:-}")"
  case "${source}" in
    *ceph*|*rbd*) return 0 ;;
    *) return 1 ;;
  esac
}

storage::fstype_is_network_or_fuse() {
  local fstype
  fstype="$(storage::lower "${1:-}")"
  case "${fstype}" in
    ceph|cephfs|fuse.ceph|rbd|rbd*|\
    nfs|nfs4|cifs|smb|smb2|smb3|smbfs|sshfs|fuse.sshfs|\
    fuse.rclone|fuse.mergerfs|fuse.s3fs|fuse.gcsfuse|fuse.goofys|\
    glusterfs|lustre|davfs|davfs2|fuse.*)
      return 0 ;;
    *) return 1 ;;
  esac
}

storage::path_is_ceph() {
  local path source fstype
  path="${1:-/}"
  source="$(storage::mount_source "${path}" 2>/dev/null || true)"
  fstype="$(storage::mount_fstype "${path}" 2>/dev/null || true)"
  storage::fstype_is_ceph "${fstype}" || storage::source_is_ceph "${source}"
}

storage::path_is_network_or_fuse() {
  local path source fstype source_l
  path="${1:-/}"
  source="$(storage::mount_source "${path}" 2>/dev/null || true)"
  fstype="$(storage::mount_fstype "${path}" 2>/dev/null || true)"
  source_l="$(storage::lower "${source}")"
  if storage::fstype_is_network_or_fuse "${fstype}"; then
    return 0
  fi
  case "${source_l}" in
    *ceph*|*rbd*|*://*|//*) return 0 ;;
    *) return 1 ;;
  esac
}

storage::source_device_for_path() {
  local path source dev
  path="${1:-/}"
  source="$(storage::mount_source "${path}" 2>/dev/null || true)"
  source="$(storage::strip_source_suffix "${source}")"
  [[ -n "${source}" ]] || return 1

  case "${source}" in
    UUID=*|LABEL=*|PARTUUID=*|PARTLABEL=*)
      if storage::have findfs; then
        dev="$(findfs "${source}" 2>/dev/null || true)"
        [[ -n "${dev}" ]] && { printf '%s\n' "${dev}"; return 0; }
      fi
      ;;
    /dev/*)
      dev="$(readlink -f -- "${source}" 2>/dev/null || printf '%s\n' "${source}")"
      [[ -e "${dev}" ]] || return 1
      printf '%s\n' "${dev}"
      return 0
      ;;
  esac
  return 1
}

storage::block_name_from_device() {
  local dev="$1" name
  [[ -n "${dev}" ]] || return 1
  storage::have lsblk || return 1
  name="$(lsblk -dnro NAME -- "${dev}" 2>/dev/null | head -n1 || true)"
  [[ -n "${name}" ]] || return 1
  printf '%s\n' "${name}"
}

storage::block_type() {
  local name="$1"
  storage::have lsblk || return 1
  lsblk -dnro TYPE -- "/dev/${name}" 2>/dev/null | head -n1
}

storage::parent_block_name() {
  local name="$1"
  storage::have lsblk || return 1
  lsblk -dnro PKNAME -- "/dev/${name}" 2>/dev/null | head -n1
}

storage::stack_block_names_from_name() {
  local name="$1" seen="${2:-}" type pk slave_path slave found=0
  [[ -n "${name}" ]] || return 0
  case " ${seen} " in *" ${name} "*) return 0 ;; esac

  printf '%s\n' "${name}"

  if [[ -d "/sys/class/block/${name}/slaves" ]]; then
    for slave_path in "/sys/class/block/${name}/slaves"/*; do
      [[ -e "${slave_path}" ]] || continue
      found=1
      slave="$(basename -- "${slave_path}")"
      storage::stack_block_names_from_name "${slave}" "${seen} ${name}"
    done
  fi

  type="$(storage::block_type "${name}" 2>/dev/null || true)"
  if [[ "${type}" == "part" ]]; then
    pk="$(storage::parent_block_name "${name}" 2>/dev/null || true)"
    [[ -n "${pk}" ]] && storage::stack_block_names_from_name "${pk}" "${seen} ${name}"
  fi
}

storage::leaf_devices_from_name() {
  local name="$1" seen="${2:-}" type pk slave_path slave found=0
  [[ -n "${name}" ]] || return 0
  case " ${seen} " in *" ${name} "*) return 0 ;; esac

  if [[ -d "/sys/class/block/${name}/slaves" ]]; then
    for slave_path in "/sys/class/block/${name}/slaves"/*; do
      [[ -e "${slave_path}" ]] || continue
      found=1
      slave="$(basename -- "${slave_path}")"
      storage::leaf_devices_from_name "${slave}" "${seen} ${name}"
    done
    (( found )) && return 0
  fi

  type="$(storage::block_type "${name}" 2>/dev/null || true)"
  if [[ "${type}" == "part" ]]; then
    pk="$(storage::parent_block_name "${name}" 2>/dev/null || true)"
    if [[ -n "${pk}" ]]; then
      storage::leaf_devices_from_name "${pk}" "${seen} ${name}"
      return 0
    fi
  fi

  [[ -e "/sys/class/block/${name}" ]] || return 0
  printf '%s\n' "${name}"
}

storage::unique_lines() {
  awk 'NF && !seen[$0]++'
}

storage::zfs_leaf_devices_for_path() {
  local path source pool dev name
  path="${1:-/}"
  [[ "$(storage::mount_fstype "${path}" 2>/dev/null || true)" == "zfs" ]] || return 1
  storage::have zpool || return 1
  source="$(storage::mount_source "${path}" 2>/dev/null || true)"
  [[ -n "${source}" ]] || return 1
  pool="${source%%/*}"
  [[ -n "${pool}" ]] || return 1
  zpool status -P "${pool}" 2>/dev/null | awk '$1 ~ /^\/dev\// {print $1}' | while IFS= read -r dev; do
    name="$(storage::block_name_from_device "${dev}" 2>/dev/null || true)"
    [[ -n "${name}" ]] || continue
    storage::leaf_devices_from_name "${name}"
  done | storage::unique_lines
}

storage::leaf_devices_for_path() {
  local path dev name
  path="${1:-/}"
  if storage::path_is_network_or_fuse "${path}"; then
    return 0
  fi
  if [[ "$(storage::mount_fstype "${path}" 2>/dev/null || true)" == "zfs" ]]; then
    storage::zfs_leaf_devices_for_path "${path}" 2>/dev/null && return 0
  fi
  dev="$(storage::source_device_for_path "${path}" 2>/dev/null || true)"
  [[ -n "${dev}" ]] || return 1
  name="$(storage::block_name_from_device "${dev}" 2>/dev/null || true)"
  [[ -n "${name}" ]] || return 1
  storage::leaf_devices_from_name "${name}" | storage::unique_lines
}

storage::stack_block_names_for_path() {
  local path dev name
  path="${1:-/}"
  if [[ "$(storage::mount_fstype "${path}" 2>/dev/null || true)" == "zfs" ]]; then
    storage::zfs_leaf_devices_for_path "${path}" 2>/dev/null && return 0
  fi
  dev="$(storage::source_device_for_path "${path}" 2>/dev/null || true)"
  [[ -n "${dev}" ]] || return 1
  name="$(storage::block_name_from_device "${dev}" 2>/dev/null || true)"
  [[ -n "${name}" ]] || return 1
  storage::stack_block_names_from_name "${name}" | storage::unique_lines
}

storage::md_level_for_name() {
  local name="$1" pk level_path
  [[ -n "${name}" ]] || return 1
  level_path="/sys/class/block/${name}/md/level"
  if [[ -r "${level_path}" ]]; then
    cat "${level_path}"
    return 0
  fi
  if [[ "$(storage::block_type "${name}" 2>/dev/null || true)" == "part" ]]; then
    pk="$(storage::parent_block_name "${name}" 2>/dev/null || true)"
    [[ -n "${pk}" ]] && storage::md_level_for_name "${pk}"
  fi
}

storage::md_levels_for_path() {
  local path name level
  path="${1:-/}"
  storage::stack_block_names_for_path "${path}" 2>/dev/null | while IFS= read -r name; do
    level="$(storage::md_level_for_name "${name}" 2>/dev/null || true)"
    [[ -n "${level}" ]] && printf '%s\n' "${level}"
  done | storage::unique_lines
}

storage::path_has_md_raid0() {
  local path="${1:-/}" level level_l
  while IFS= read -r level; do
    level_l="$(storage::lower "${level}")"
    case "${level_l}" in
      raid0|0|stripe|striped) return 0 ;;
    esac
  done < <(storage::md_levels_for_path "${path}" 2>/dev/null || true)
  return 1
}

storage::device_rotational() {
  local dev="$1" value
  if [[ -r "/sys/block/${dev}/queue/rotational" ]]; then
    value="$(cat "/sys/block/${dev}/queue/rotational" 2>/dev/null || true)"
    [[ "${value}" =~ ^[01]$ ]] && { printf '%s\n' "${value}"; return 0; }
  fi
  if storage::have lsblk; then
    value="$(lsblk -dnro ROTA -- "/dev/${dev}" 2>/dev/null | head -n1 || true)"
    [[ "${value}" =~ ^[01]$ ]] && { printf '%s\n' "${value}"; return 0; }
  fi
  return 1
}

storage::device_transport() {
  local dev="$1"
  storage::have lsblk || return 1
  lsblk -dnro TRAN -- "/dev/${dev}" 2>/dev/null | head -n1
}

storage::device_metadata() {
  local dev="$1" link target
  if storage::have lsblk; then
    lsblk -dnro VENDOR,MODEL,SERIAL -- "/dev/${dev}" 2>/dev/null | head -n1 || true
  fi
  if [[ -d /dev/disk/by-id ]]; then
    for link in /dev/disk/by-id/*; do
      [[ -L "${link}" ]] || continue
      target="$(readlink -f -- "${link}" 2>/dev/null || true)"
      [[ -n "${target}" ]] || continue
      if [[ "$(basename -- "${target}")" == "${dev}" ]]; then
        basename -- "${link}"
      fi
    done
  fi
}

storage::is_virtualized() {
  local info
  if storage::have systemd-detect-virt && systemd-detect-virt --quiet 2>/dev/null; then
    return 0
  fi
  info="$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null || true)"
  info="$(storage::lower "${info}")"
  case "${info}" in
    *kvm*|*qemu*|*vmware*|*virtualbox*|*xen*|*bochs*|*hyper-v*|*microsoft*virtual*|\
    *amazon*ec2*|*google*compute*|*digitalocean*|*openstack*|*parallels*|*bhyve*|*oracle*cloud*)
      return 0 ;;
    *) return 1 ;;
  esac
}

storage::device_is_nvme_interface() {
  local dev="$1" tran
  [[ "${dev}" == nvme* ]] && return 0
  tran="$(storage::device_transport "${dev}" 2>/dev/null || true)"
  [[ "$(storage::lower "${tran}")" == "nvme" ]]
}

storage::device_has_local_nvme_evidence() {
  local dev="$1" meta
  storage::device_is_nvme_interface "${dev}" || return 1
  meta="$(storage::device_metadata "${dev}" 2>/dev/null || true)"
  meta="$(storage::lower "${meta}")"
  case "${meta}" in
    *instance*storage*|*ec2*nvme*instance*|*local*ssd*|*local-nvme*|*nvme*local*|*ephemeral*)
      return 0 ;;
    *) return 1 ;;
  esac
}

storage::device_is_virtual_or_cloud() {
  local dev="$1"
  storage::is_virtualized || return 1
  storage::device_has_local_nvme_evidence "${dev}" && return 1
  return 0
}

storage::device_storage_kind() {
  local dev="$1" rota
  if storage::device_is_nvme_interface "${dev}" && ! storage::device_is_virtual_or_cloud "${dev}"; then
    printf 'nvme\n'
    return 0
  fi
  rota="$(storage::device_rotational "${dev}" 2>/dev/null || true)"
  if [[ "${rota}" == "1" ]]; then
    printf 'hdd\n'
  elif [[ "${rota}" == "0" ]]; then
    printf 'ssd\n'
  else
    return 1
  fi
}

storage::qbittorrent_kind_for_path() {
  local path dev kind saw_hdd=0 saw_ssd=0 saw_nvme=0 count=0
  path="${1:-/}"

  if storage::path_is_ceph "${path}"; then
    printf 'ceph\n'
    return 0
  fi
  if storage::path_is_network_or_fuse "${path}"; then
    # Existing qBittorrent profiles have no generic remote class; ceph is the conservative remote profile.
    printf 'ceph\n'
    return 0
  fi

  while IFS= read -r dev; do
    [[ -n "${dev}" ]] || continue
    kind="$(storage::device_storage_kind "${dev}" 2>/dev/null || true)"
    case "${kind}" in
      hdd) saw_hdd=1; count=$((count + 1)) ;;
      nvme) saw_nvme=1; count=$((count + 1)) ;;
      ssd) saw_ssd=1; count=$((count + 1)) ;;
    esac
  done < <(storage::leaf_devices_for_path "${path}" 2>/dev/null || true)

  (( count > 0 )) || return 1

  if (( saw_hdd && ! saw_ssd && ! saw_nvme )) && storage::path_has_md_raid0 "${path}"; then
    printf 'hdd-raid0\n'
  elif (( saw_hdd )); then
    printf 'hdd\n'
  elif (( saw_nvme && ! saw_ssd )); then
    printf 'nvme\n'
  else
    printf 'ssd\n'
  fi
}

storage::host_class_for_path() {
  local path kind
  path="${1:-/}"
  kind="$(storage::qbittorrent_kind_for_path "${path}" 2>/dev/null || true)"
  case "${kind}" in
    nvme) printf 'nvme\n' ;;
    hdd|hdd-raid0) printf 'hdd\n' ;;
    ssd|ceph) printf 'sata-ssd\n' ;;
    *) printf 'sata-ssd\n' ;;
  esac
}

storage::is_schedulable_block_device() {
  local dev="$1"
  [[ -n "${dev}" ]] || return 1
  case "${dev}" in loop*|ram*|sr*|fd*|dm-*|md*) return 1 ;; esac
  [[ -e "/sys/block/${dev}/queue/scheduler" ]]
}

storage::scheduler_leaf_devices_for_path() {
  local path dev
  path="${1:-/}"
  storage::path_is_network_or_fuse "${path}" && return 0
  while IFS= read -r dev; do
    storage::is_schedulable_block_device "${dev}" || continue
    printf '%s\n' "${dev}"
  done < <(storage::leaf_devices_for_path "${path}" 2>/dev/null || true) | storage::unique_lines
  return 0
}

storage::scheduler_all_devices() {
  local scheduler_file dev
  for scheduler_file in /sys/block/*/queue/scheduler; do
    [[ -e "${scheduler_file}" ]] || continue
    dev="$(basename -- "$(dirname -- "$(dirname -- "${scheduler_file}")")")"
    storage::is_schedulable_block_device "${dev}" || continue
    printf '%s\n' "${dev}"
  done | storage::unique_lines
}

storage::scheduler_class_for_device() {
  local dev="$1" rota
  storage::is_schedulable_block_device "${dev}" || return 1
  if storage::device_is_virtual_or_cloud "${dev}"; then
    printf 'virtual\n'
    return 0
  fi
  if storage::device_is_nvme_interface "${dev}"; then
    printf 'nvme\n'
    return 0
  fi
  rota="$(storage::device_rotational "${dev}" 2>/dev/null || true)"
  if [[ "${rota}" == "1" ]]; then
    printf 'hdd\n'
  elif [[ "${rota}" == "0" ]]; then
    printf 'sata-ssd\n'
  else
    printf 'unknown\n'
  fi
}
