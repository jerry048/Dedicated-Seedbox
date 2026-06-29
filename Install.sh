#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LANG_CODE="${SEEDBOX_LANG:-en}"

normalize_lang() {
  local value="${1:-en}"
  value="${value,,}"
  value="${value//_/-}"
  case "${value}" in
    en|en-us|english) printf 'en\n' ;;
    zh|zh-cn|zh-hans|cn|sc|simplified|simplified-chinese|chinese) printf 'zh-CN\n' ;;
    *) return 1 ;;
  esac
}

set_language() {
  local normalized
  normalized="$(normalize_lang "${1:-en}")" || die "Unsupported language: ${1:-} (supported: en, zh-CN)"
  LANG_CODE="${normalized}"
  export SEEDBOX_LANG="${LANG_CODE}"
}

is_zh() { [[ "${LANG_CODE}" == "zh-CN" ]]; }
tr_msg() { if is_zh; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

die() {
  printf '%s: %s\n' "$(tr_msg '错误' 'Error')" "$*" >&2
  exit 1
}

warn() { printf '%s\n' "$(tr_msg "警告：$1" "Warning: $1")" >&2; }
note() { printf '%s\n' "$*" >&2; }

usage() {
  if is_zh; then
    cat <<'USAGE'
用法：
  ./Install.sh -u 用户名 [选项]
  ./Install.sh --rootless [选项]

兼容旧版脚本的短选项：
  -u 用户名                  Linux 用户名；rootless 模式下作为 WebUI 用户名
  -p 密码                    qBittorrent WebUI 密码
  -c 缓存_MiB                qBittorrent 缓存大小，单位 MiB
  -q QB版本                  安装静态版 qBittorrent，例如 5.0.3
  -l LIBTORRENT版本          静态版 libtorrent，例如 v2.0.11
  -b                         安装 autobrr（需要 root）
  -v                         安装 Vertex（需要 root）
  -r                         安装 autoremove-torrents（需要 root）
  -x                         安装 BBRx（需要 root）
  -3                         安装 BBRv3（需要 root）
  -o                         交互式设置端口
  -T, --no-tuning            跳过系统调优
  --storage-path 路径        系统调优使用该路径背后的存储；默认使用 qBittorrent 下载目录
  --disk-scheduler-all       对所有合格物理盘应用调度器策略，而不是只处理下载路径背后的磁盘
  -L, --lang en|zh-CN        设置安装界面语言
  -h, --help                 显示帮助

新版长选项：
  --rootless, --shared       以当前普通用户安装 rootless qBittorrent；请不要配合 sudo 使用
  --install-rootless         --rootless 的别名
  --profile dedicated|shared 选择 seedboxctl profile；默认 root 为 dedicated，rootless 为 shared
  --user 用户名              等同于 -u
  --webui-username 用户名    设置 qBittorrent WebUI 用户名；rootless 时可不同于 Unix 用户
  --password 密码            等同于 -p
  --password-stdin           从标准输入读取 qBittorrent WebUI 密码
  --source distro|static|existing
  --qb-tuning-profile PROFILE  qBittorrent 配置调优：auto、legacy、1g-hdd、10g-nvme 等
  --qb-version 版本          等同于 -q
  --libtorrent-version 版本  等同于 -l
  --web-port 端口
  --incoming-port 端口
  --service-mode auto|prompt|user|screen|daemon|system
  --autobrr-port 端口
  --vertex-port 端口
  --components 组件列表
  --bbr-algo bbrv3|bbrx|bbrw|bbr_brutal|bbrw_brutal
  --bbr-script-url URL
  --bbr-script-sha256 SHA256
  --bbr-raw-base URL
  --bbr-lang LANG
  --allow-unverified-downloads
  --allow-unverified-bbr-installer
  --force-runtime

PATH 安装：
  以 root 运行时，Install.sh 默认把发布目录安装到 /opt/seedbox/Dedicated-Seedbox，并把命令链接到 /usr/local/bin/seedboxctl。
  以普通用户运行时，默认安装到 ~/.local/share/seedbox/Dedicated-Seedbox，并链接到 ~/.local/bin/seedboxctl。
  当通过 bash <(wget ... Install.sh) 远程运行时，Install.sh 会先下载最小运行时（Install.sh、bin、lib、manifests）。
  可用 SEEDBOX_INSTALL_TREE=0 跳过目录安装；可用 SEEDBOXCTL_INSTALL_PATH=0 跳过命令链接。
  也可用 SEEDBOX_INSTALL_DIR=/path 或 SEEDBOXCTL_INSTALL_DIR=/path 修改安装位置。
  可用 SEEDBOX_RUNTIME_REPO=owner/repo、SEEDBOX_RUNTIME_REF=branch-or-commit 或 SEEDBOX_RUNTIME_RAW_BASE=URL 修改运行时下载源。

Rootless 说明：
  rootless 模式只安装 qBittorrent，不会运行 APT、创建 Linux 用户、写入系统 systemd、调优，
  也不会安装 BBR、Docker、Vertex、autobrr 或 autoremove-torrents。qBittorrent 会作为当前 Unix 用户运行。

qBittorrent 版本选择：
  只有 --source static 会使用 manifests/qbittorrent.tsv。未提供 qBittorrent/libtorrent 版本，
  或提供的组合不在清单中时，交互式会话会根据清单列出可选组合让你选择；非交互式会话会
  打印有效组合并退出，让你重新传入明确版本。

qBittorrent 配置调优：
  --qb-tuning-profile 默认是 auto，会根据网卡速率和下载目录所在存储自动选择 1G/10G + HDD/RAID0/SSD/NVMe/Ceph。
  指定 legacy 可保留旧版启发式调优。

示例：
  sudo ./Install.sh -u alice -p 'password' -c 3072 -q 5.0.3 -l v2.0.11
  sudo ./Install.sh --lang zh-CN -u alice -p 'password' -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -3
  ./Install.sh --rootless -u alice -p 'password' -c 3072 -q 5.0.3 -l v2.0.11 --service-mode auto
USAGE
  else
    cat <<'USAGE'
Usage:
  ./Install.sh -u USER [options]
  ./Install.sh --rootless [options]

Legacy-compatible short options:
  -u USER                    Linux user; in rootless mode, WebUI username
  -p PASSWORD                qBittorrent WebUI password
  -c CACHE_MIB               qBittorrent cache size in MiB
  -q QB_VERSION              Install qBittorrent static build, for example 5.0.3
  -l LIBTORRENT_VERSION      Static libtorrent version, for example v2.0.11
  -b                         Install autobrr; root required
  -v                         Install Vertex; root required
  -r                         Install autoremove-torrents; root required
  -x                         Install BBRx; root required
  -3                         Install BBRv3; root required
  -o                         Prompt for custom ports
  -T, --no-tuning            Disable tuning
  --storage-path PATH        Use PATH backing storage for host tuning; default is qBittorrent download path
  --disk-scheduler-all       Apply scheduler policy to all eligible physical disks, not only download-path disks
  -L, --lang en|zh-CN        Installer language
  -h, --help                 Show help

Additional options:
  --rootless, --shared       Install rootless qBittorrent as the current non-root user; do not use sudo
  --install-rootless         Alias for --rootless
  --profile dedicated|shared Select seedboxctl profile; defaults to dedicated for root, shared for rootless
  --user USER                Same as -u
  --webui-username USER      qBittorrent WebUI username; useful in rootless mode
  --password PASSWORD        Same as -p
  --password-stdin           Read qBittorrent WebUI password from stdin
  --source distro|static|existing
  --qb-tuning-profile PROFILE qBittorrent config tuning: auto, legacy, 1g-hdd, 10g-nvme, etc.
  --qb-version VERSION       Same as -q
  --libtorrent-version VER   Same as -l
  --web-port PORT
  --incoming-port PORT
  --service-mode auto|prompt|user|screen|daemon|system
  --autobrr-port PORT
  --vertex-port PORT
  --components CSV
  --bbr-algo bbrv3|bbrx|bbrw|bbr_brutal|bbrw_brutal
  --bbr-script-url URL
  --bbr-script-sha256 SHA256
  --bbr-raw-base URL
  --bbr-lang LANG
  --allow-unverified-downloads
  --allow-unverified-bbr-installer
  --force-runtime

PATH install:
  When run as root, Install.sh installs the release tree to /opt/seedbox/Dedicated-Seedbox and links /usr/local/bin/seedboxctl.
  When run as a normal user, it installs to ~/.local/share/seedbox/Dedicated-Seedbox and links ~/.local/bin/seedboxctl.
  When run through bash <(wget ... Install.sh), Install.sh first downloads the minimal runtime: Install.sh, bin, lib, and manifests.
  Set SEEDBOX_INSTALL_TREE=0 to skip tree installation; set SEEDBOXCTL_INSTALL_PATH=0 to skip the command link.
  Use SEEDBOX_INSTALL_DIR=/path or SEEDBOXCTL_INSTALL_DIR=/path to change the install locations.
  Use SEEDBOX_RUNTIME_REPO=owner/repo, SEEDBOX_RUNTIME_REF=branch-or-commit, or SEEDBOX_RUNTIME_RAW_BASE=URL to change the runtime source.

Rootless notes:
  Rootless mode installs qBittorrent only. It does not run APT, create Linux users, write system
  systemd units, tune the host, or install BBR, Docker, Vertex, autobrr, or autoremove-torrents.
  qBittorrent runs as the current Unix user.

qBittorrent version selection:
  Only --source static uses manifests/qbittorrent.tsv. If qBittorrent/libtorrent versions are missing
  or the supplied pair is not in the manifest, an interactive session lists valid manifest choices and
  asks you to select one. A non-interactive session prints valid choices and exits so you can rerun with
  explicit versions.

qBittorrent config tuning:
  --qb-tuning-profile defaults to auto, which chooses a 1G/10G + HDD/RAID0/SSD/NVMe/Ceph profile from NIC speed and download-path storage.
  Use legacy to keep the older heuristic tuning.

Examples:
  sudo ./Install.sh -u alice -p 'password' -c 3072 -q 5.0.3 -l v2.0.11
  sudo ./Install.sh --lang zh-CN -u alice -p 'password' -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -3
  ./Install.sh --rootless -u alice -p 'password' -c 3072 -q 5.0.3 -l v2.0.11 --service-mode auto
USAGE
  fi
}

csv_contains() {
  local csv=",$1," item="$2"
  csv="${csv// /}"
  [[ "${csv}" == *",${item},"* ]]
}

csv_add() {
  local csv="$1" item="$2"
  if [[ -z "${csv}" ]]; then
    printf '%s\n' "${item}"
  elif csv_contains "${csv}" "${item}"; then
    printf '%s\n' "${csv}"
  else
    printf '%s,%s\n' "${csv}" "${item}"
  fi
}

csv_remove() {
  local csv="$1" remove="$2" item output=""
  IFS=',' read -r -a parts <<<"${csv}"
  for item in "${parts[@]}"; do
    item="${item// /}"
    [[ -z "${item}" || "${item}" == "${remove}" ]] && continue
    output="$(csv_add "${output}" "${item}")"
  done
  printf '%s\n' "${output}"
}

csv_only_qbittorrent() {
  local csv="$1" item
  IFS=',' read -r -a parts <<<"${csv}"
  for item in "${parts[@]}"; do
    item="${item// /}"
    [[ -z "${item}" ]] && continue
    [[ "${item}" == "qbittorrent" ]] || return 1
  done
  return 0
}

require_value() {
  local option="$1" value="${2:-}"
  [[ -n "${value}" ]] || die "${option} $(tr_msg '需要一个参数' 'requires a value')"
}

normalize_qb_version() {
  local value="$1"
  value="${value#qBittorrent-}"
  value="${value#qbittorrent-}"
  printf '%s\n' "${value}"
}

normalize_libtorrent_version() {
  local value="$1"
  value="${value#libtorrent-}"
  printf '%s\n' "${value}"
}

tty_available() {
  { : </dev/tty >/dev/tty; } 2>/dev/null
}

read_value() {
  local label="$1" value
  if tty_available; then
    printf '%s: ' "${label}" >/dev/tty
    IFS= read -r value </dev/tty
  elif [[ -t 0 ]]; then
    printf '%s: ' "${label}" >&2
    IFS= read -r value
  else
    die "$(tr_msg "非交互式运行时不能提示输入：${label}" "Cannot prompt for ${label} in non-interactive mode")"
  fi
  printf '%s\n' "${value}"
}

read_secret() {
  local label="$1" value
  if tty_available; then
    printf '%s: ' "${label}" >/dev/tty
    stty -echo </dev/tty 2>/dev/null || true
    IFS= read -r value </dev/tty
    stty echo </dev/tty 2>/dev/null || true
    printf '\n' >/dev/tty
  elif [[ -t 0 ]]; then
    printf '%s: ' "${label}" >&2
    stty -echo 2>/dev/null || true
    IFS= read -r value
    stty echo 2>/dev/null || true
    printf '\n' >&2
  else
    die "$(tr_msg '非交互式运行时不能提示输入密码；请使用 -p 或 --password-stdin。' 'Cannot prompt for a password in non-interactive mode; use -p or --password-stdin.')"
  fi
  printf '%s\n' "${value}"
}

read_port() {
  local label="$1" value
  while true; do
    value="$(read_value "${label}")"
    if [[ "${value}" =~ ^[0-9]+$ && "${value}" -ge 1024 && "${value}" -le 65535 ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
    printf '%s\n' "$(tr_msg '请输入 1024 到 65535 之间的端口。' 'Please enter a port between 1024 and 65535.')" >&2
  done
}

script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P
}

path_is_same() {
  local a="$1" b="$2"
  if command -v realpath >/dev/null 2>&1; then
    [[ "$(realpath -m -- "${a}")" == "$(realpath -m -- "${b}")" ]]
  else
    [[ "${a}" == "${b}" ]]
  fi
}

default_release_prefix() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    printf '/opt/seedbox/Dedicated-Seedbox\n'
  else
    local data_home="${XDG_DATA_HOME:-${HOME:-}/.local/share}"
    [[ -n "${data_home}" ]] || die "$(tr_msg '无法确定用户数据目录；请设置 HOME 或 SEEDBOX_INSTALL_DIR。' 'Could not determine a user data directory; set HOME or SEEDBOX_INSTALL_DIR.')"
    printf '%s/seedbox/Dedicated-Seedbox\n' "${data_home}"
  fi
}

runtime_files() {
  cat <<'FILES'
Install.sh
bin/seedboxctl
lib/components/autobrr.bash
lib/components/autoremove_torrents.bash
lib/components/bbr.bash
lib/components/bbr/BBRInstall.sh
lib/components/docker.bash
lib/components/qbittorrent.bash
lib/components/tuning.bash
lib/components/vertex.bash
lib/core/apt.bash
lib/core/args.bash
lib/core/bootstrap.bash
lib/core/detect.bash
lib/core/diagnose.bash
lib/core/download.bash
lib/core/fs.bash
lib/core/log.bash
lib/core/ports.bash
lib/core/public_ip.bash
lib/core/runner.bash
lib/core/secrets.bash
lib/core/state.bash
lib/core/storage.bash
lib/core/status.bash
lib/core/systemd.bash
lib/core/user.bash
lib/core/validate.bash
lib/profiles/dedicated.bash
lib/profiles/shared.bash
manifests/qbittorrent.tsv
FILES
}

runtime_tree_complete() {
  local root="$1" file
  [[ -n "${root}" && -d "${root}" ]] || return 1
  while IFS= read -r file; do
    [[ -r "${root}/${file}" ]] || return 1
  done < <(runtime_files)
}

runtime_install_mode() {
  case "$1" in
    Install.sh|bin/seedboxctl|lib/components/bbr/BBRInstall.sh) printf '0755\n' ;;
    *) printf '0644\n' ;;
  esac
}

copy_minimal_runtime_tree() {
  local src_dir="$1" dest_dir="$2" file mode target_dir
  while IFS= read -r file; do
    [[ -r "${src_dir}/${file}" ]] || {
      warn "$(tr_msg "本地运行时缺少 ${file}" "local runtime is missing ${file}")"
      return 1
    }
    target_dir="$(dirname -- "${dest_dir}/${file}")"
    install -d -m 0755 -- "${target_dir}" || return $?
    mode="$(runtime_install_mode "${file}")"
    install -m "${mode}" -- "${src_dir}/${file}" "${dest_dir}/${file}" || return $?
  done < <(runtime_files)
}

runtime_raw_base() {
  local base="${SEEDBOX_RUNTIME_RAW_BASE:-}"
  if [[ -z "${base}" ]]; then
    local repo="${SEEDBOX_RUNTIME_REPO:-jerry048/Dedicated-Seedbox}"
    local ref="${SEEDBOX_RUNTIME_REF:-main}"
    base="https://raw.githubusercontent.com/${repo}/${ref}"
  fi
  printf '%s\n' "${base%/}"
}

runtime_fetch() {
  local url="$1" dest="$2" tmp dir local_path
  dir="$(dirname -- "${dest}")"
  install -d -m 0755 -- "${dir}" || return $?
  tmp="$(mktemp "${dir}/.runtime-download.XXXXXX")"

  if [[ "${url}" == file://* ]]; then
    local_path="${url#file://}"
    if ! cp -f -- "${local_path}" "${tmp}"; then
      rm -f -- "${tmp}"
      return 1
    fi
  elif [[ "${url}" != *://* && -r "${url}" ]]; then
    if ! cp -f -- "${url}" "${tmp}"; then
      rm -f -- "${tmp}"
      return 1
    fi
  elif [[ "${url}" != *://* ]]; then
    rm -f -- "${tmp}"
    return 1
  elif command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 -o "${tmp}" "${url}"; then
      rm -f -- "${tmp}"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -qO "${tmp}" "${url}"; then
      rm -f -- "${tmp}"
      return 1
    fi
  else
    rm -f -- "${tmp}"
    die "$(tr_msg '需要 curl 或 wget 来下载最小运行时。' 'curl or wget is required to download the minimal runtime.')"
  fi

  mv -f -- "${tmp}" "${dest}"
}

download_minimal_runtime() {
  local dest parent tmp base file url mode install_enabled
  install_enabled="${SEEDBOX_INSTALL_TREE:-1}"
  case "${install_enabled,,}" in
    0|false|no|off)
      die "$(tr_msg '远程 Install.sh 需要安装最小运行时；请不要设置 SEEDBOX_INSTALL_TREE=0，或改为在完整仓库目录中运行。' 'Remote Install.sh needs to install the minimal runtime; do not set SEEDBOX_INSTALL_TREE=0, or run from a complete repository checkout.')"
      ;;
  esac

  dest="${SEEDBOX_INSTALL_DIR:-${SEEDBOX_INSTALL_PREFIX:-}}"
  [[ -n "${dest}" ]] || dest="$(default_release_prefix)"
  parent="$(dirname -- "${dest}")"
  install -d -m 0755 -- "${parent}" || die "$(tr_msg "无法创建运行时目录父目录 ${parent}" "could not create runtime parent ${parent}")"

  tmp="${dest}.tmp.$$"
  rm -rf -- "${tmp}"
  install -d -m 0755 -- "${tmp}" || die "$(tr_msg "无法创建临时运行时目录 ${tmp}" "could not create temporary runtime directory ${tmp}")"

  base="$(runtime_raw_base)"
  note "$(tr_msg "正在下载最小运行时：${base}" "Downloading minimal runtime: ${base}")"
  while IFS= read -r file; do
    url="${base}/${file}"
    if ! runtime_fetch "${url}" "${tmp}/${file}"; then
      rm -rf -- "${tmp}"
      die "$(tr_msg "下载最小运行时失败：${url}" "failed to download minimal runtime file: ${url}")"
    fi
    mode="$(runtime_install_mode "${file}")"
    chmod "${mode}" "${tmp}/${file}" 2>/dev/null || true
  done < <(runtime_files)

  runtime_tree_complete "${tmp}" || {
    rm -rf -- "${tmp}"
    die "$(tr_msg '下载的最小运行时不完整。' 'downloaded minimal runtime is incomplete.')"
  }

  rm -rf -- "${dest}.old"
  if [[ -e "${dest}" ]]; then
    mv -- "${dest}" "${dest}.old" || {
      rm -rf -- "${tmp}"
      die "$(tr_msg "无法替换 ${dest}" "could not replace ${dest}")"
    }
  fi
  if ! mv -- "${tmp}" "${dest}"; then
    [[ -e "${dest}.old" ]] && mv -- "${dest}.old" "${dest}" 2>/dev/null || true
    rm -rf -- "${tmp}"
    die "$(tr_msg "无法启用 ${dest}" "could not activate ${dest}")"
  fi
  rm -rf -- "${dest}.old"
  note "$(tr_msg "已安装最小运行时：${dest}" "Installed minimal runtime: ${dest}")"
  printf '%s\n' "${dest}"
}

stage_release_tree() {
  local src_dir="$1" dest install_enabled tmp parent
  install_enabled="${SEEDBOX_INSTALL_TREE:-1}"
  case "${install_enabled,,}" in
    0|false|no|off)
      printf '%s\n' "${src_dir}"
      return 0
      ;;
  esac

  dest="${SEEDBOX_INSTALL_DIR:-${SEEDBOX_INSTALL_PREFIX:-}}"
  [[ -n "${dest}" ]] || dest="$(default_release_prefix)"

  if path_is_same "${src_dir}" "${dest}"; then
    printf '%s\n' "${src_dir}"
    return 0
  fi

  parent="$(dirname -- "${dest}")"
  if ! install -d -m 0755 -- "${parent}"; then
    warn "$(tr_msg "无法创建发布目录父目录 ${parent}；将直接使用 ${src_dir}" "could not create release parent ${parent}; using ${src_dir} directly")"
    printf '%s\n' "${src_dir}"
    return 0
  fi

  tmp="${dest}.tmp.$$"
  rm -rf -- "${tmp}"
  install -d -m 0755 -- "${tmp}"
  if ! copy_minimal_runtime_tree "${src_dir}" "${tmp}"; then
    rm -rf -- "${tmp}"
    warn "$(tr_msg "最小运行时安装失败；将直接使用 ${src_dir}" "minimal-runtime installation failed; using ${src_dir} directly")"
    printf '%s\n' "${src_dir}"
    return 0
  fi
  rm -rf -- "${dest}.old"
  if [[ -e "${dest}" ]]; then
    mv -- "${dest}" "${dest}.old" || {
      rm -rf -- "${tmp}"
      warn "$(tr_msg "无法替换 ${dest}；将直接使用 ${src_dir}" "could not replace ${dest}; using ${src_dir} directly")"
      printf '%s\n' "${src_dir}"
      return 0
    }
  fi
  if ! mv -- "${tmp}" "${dest}"; then
    [[ -e "${dest}.old" ]] && mv -- "${dest}.old" "${dest}" 2>/dev/null || true
    rm -rf -- "${tmp}"
    warn "$(tr_msg "无法启用 ${dest}；将直接使用 ${src_dir}" "could not activate ${dest}; using ${src_dir} directly")"
    printf '%s\n' "${src_dir}"
    return 0
  fi
  rm -rf -- "${dest}.old"
  note "$(tr_msg "已安装发布目录：${dest}" "Installed release tree: ${dest}")"
  printf '%s\n' "${dest}"
}

find_seedboxctl() {
  local script_root release_dir candidate
  script_root="$(script_dir)"

  if [[ -n "${SEEDBOXCTL:-}" ]]; then
    [[ -x "${SEEDBOXCTL}" ]] || die "SEEDBOXCTL is set but not executable: ${SEEDBOXCTL}"
    printf '%s\n' "${SEEDBOXCTL}"
    return 0
  fi

  if runtime_tree_complete "${script_root}"; then
    release_dir="$(stage_release_tree "${script_root}")"
  else
    release_dir="$(download_minimal_runtime)"
  fi
  for candidate in \
    "${release_dir}/bin/seedboxctl" \
    "${script_root}/bin/seedboxctl" \
    "${script_root}/../Dedicated-Seedbox/bin/seedboxctl" \
    "${HOME:-}/.local/share/seedbox/Dedicated-Seedbox/bin/seedboxctl" \
    "${HOME:-}/.local/bin/seedboxctl" \
    "/opt/seedbox/Dedicated-Seedbox/bin/seedboxctl" \
    "/usr/local/bin/seedboxctl"; do
    [[ -n "${candidate}" && -x "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return 0
  done
  die "$(tr_msg '找不到 seedboxctl。请在 Dedicated-Seedbox 目录中运行，或设置 SEEDBOXCTL=/path/to/seedboxctl。' 'seedboxctl was not found. Run this script from the Dedicated-Seedbox directory or set SEEDBOXCTL=/path/to/seedboxctl.')"
}

install_seedboxctl_command() {
  local seedboxctl="$1"
  local install_enabled="${SEEDBOXCTL_INSTALL_PATH:-1}"
  local default_install_dir install_dir target resolved target_dir

  case "${install_enabled,,}" in
    0|false|no|off) return 0 ;;
  esac

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    default_install_dir="/usr/local/bin"
  else
    default_install_dir="${HOME}/.local/bin"
  fi

  install_dir="${SEEDBOXCTL_INSTALL_DIR:-${default_install_dir}}"
  target="${SEEDBOXCTL_COMMAND:-${install_dir}/seedboxctl}"
  target_dir="$(dirname -- "${target}")"

  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath -- "${seedboxctl}")"
  else
    resolved="${seedboxctl}"
  fi

  if ! install -d -m 0755 -- "${target_dir}"; then
    printf '%s\n' "$(tr_msg "警告：无法创建 PATH 目录 ${target_dir}；将继续使用 ${seedboxctl}。" "Warning: could not create PATH directory ${target_dir}; continuing with ${seedboxctl}.")" >&2
    return 0
  fi

  if [[ -e "${target}" && ! -L "${target}" ]]; then
    if [[ "${SEEDBOXCTL_INSTALL_PATH_FORCE:-0}" != "1" ]]; then
      printf '%s\n' "$(tr_msg "警告：${target} 已存在且不是符号链接，未覆盖。可设置 SEEDBOXCTL_INSTALL_PATH_FORCE=1 强制覆盖。" "Warning: ${target} exists and is not a symlink; not overwriting it. Set SEEDBOXCTL_INSTALL_PATH_FORCE=1 to replace it.")" >&2
      return 0
    fi
    rm -f -- "${target}"
  fi

  if ln -sfn -- "${resolved}" "${target}"; then
    printf '%s\n' "$(tr_msg "已安装命令：${target} -> ${resolved}" "Installed command: ${target} -> ${resolved}")" >&2
    case ":${PATH:-}:" in
      *":${target_dir}:"*) ;;
      *)
        if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
          printf '%s\n' "$(tr_msg "提示：${target_dir} 不在当前 PATH 中；可重新登录，或执行：export PATH=\"${target_dir}:\$PATH\"" "Note: ${target_dir} is not in PATH yet; log in again or run: export PATH=\"${target_dir}:\$PATH\"")" >&2
        fi
        ;;
    esac
  else
    printf '%s\n' "$(tr_msg "警告：无法创建 ${target}；将继续使用 ${seedboxctl}。" "Warning: could not create ${target}; continuing with ${seedboxctl}.")" >&2
  fi
}

set_static_qb() {
  local qb="$1"
  qb_version="$(normalize_qb_version "${qb}")"
  qbit_requested=1
  [[ -n "${source:-}" ]] || source="static"
  components="$(csv_add "${components}" qbittorrent)"
}

set_static_lib() {
  local lib="$1"
  lib_version="$(normalize_libtorrent_version "${lib}")"
  qbit_requested=1
  [[ -n "${source:-}" ]] || source="static"
  components="$(csv_add "${components}" qbittorrent)"
}

handle_short_option_with_value() {
  local opt="$1" value="$2"
  case "${opt}" in
    u) username="${value}" ;;
    p) password="${value}" ;;
    c) cache="${value}" ;;
    q) set_static_qb "${value}" ;;
    l) set_static_lib "${value}" ;;
    L) set_language "${value}" ;;
    *) die "Unknown option: -${opt}" ;;
  esac
}

main() {
  local username="" password="" cache="3072" qb_version="" lib_version="" qb_tuning_profile=""
  local components="tuning" custom_ports=0 qb_port="" qb_incoming_port="" autobrr_port="" vertex_port=""
  local bbr_algo="" bbr_script_url="" bbr_script_sha256="${SEEDBOX_BBR_SCRIPT_SHA256:-}" bbr_raw_base="${SEEDBOX_BBR_RAW_BASE:-}" bbr_lang=""
  local tuning_enabled=1 qbit_requested=0 password_stdin=0 source="" allow_unverified=0 allow_unverified_bbr=0 force_runtime=0 components_overridden=0
  local upgrade_system=0 no_clear=0 rootless=0 service_mode="" webui_username="" profile="" root_only_requested=0
  local storage_path="" disk_scheduler_all=0

  set_language "${LANG_CODE}"

  while (($#)); do
    case "$1" in
      --lang) require_value "$1" "${2:-}"; set_language "$2"; shift 2 ;;
      --lang=*) set_language "${1#*=}"; shift ;;
      -L) require_value "$1" "${2:-}"; set_language "$2"; shift 2 ;;
      -u|--user) require_value "$1" "${2:-}"; username="$2"; shift 2 ;;
      --user=*) username="${1#*=}"; shift ;;
      -p|--password) require_value "$1" "${2:-}"; password="$2"; shift 2 ;;
      --password=*) password="${1#*=}"; shift ;;
      -c|--cache) require_value "$1" "${2:-}"; cache="$2"; shift 2 ;;
      --cache=*) cache="${1#*=}"; shift ;;
      -q|--qb-version|--qbittorrent-version) require_value "$1" "${2:-}"; set_static_qb "$2"; shift 2 ;;
      --qb-version=*|--qbittorrent-version=*) set_static_qb "${1#*=}"; shift ;;
      -l|--libtorrent-version) require_value "$1" "${2:-}"; set_static_lib "$2"; shift 2 ;;
      --libtorrent-version=*) set_static_lib "${1#*=}"; shift ;;
      -u?*) username="${1#-u}"; shift ;;
      -p?*) password="${1#-p}"; shift ;;
      -c?*) cache="${1#-c}"; shift ;;
      -q?*) set_static_qb "${1#-q}"; shift ;;
      -l?*) set_static_lib "${1#-l}"; shift ;;
      -L?*) set_language "${1#-L}"; shift ;;
      -r) root_only_requested=1; components="$(csv_add "${components}" autoremove-torrents)"; shift ;;
      -b) root_only_requested=1; components="$(csv_add "${components}" autobrr)"; shift ;;
      -v) root_only_requested=1; components="$(csv_add "${components}" vertex)"; shift ;;
      -x) root_only_requested=1; bbr_algo="bbrx"; components="$(csv_add "${components}" bbr)"; shift ;;
      -3) root_only_requested=1; bbr_algo="bbrv3"; components="$(csv_add "${components}" bbr)"; shift ;;
      -o) custom_ports=1; shift ;;
      -T|--no-tuning) tuning_enabled=0; components="$(csv_remove "${components}" tuning)"; shift ;;
      --storage-path) require_value "$1" "${2:-}"; root_only_requested=1; storage_path="$2"; components="$(csv_add "${components}" tuning)"; shift 2 ;;
      --storage-path=*) root_only_requested=1; storage_path="${1#*=}"; components="$(csv_add "${components}" tuning)"; shift ;;
      --disk-scheduler-all) root_only_requested=1; disk_scheduler_all=1; components="$(csv_add "${components}" tuning)"; shift ;;
      --rootless|--shared|--install-rootless|--install-self) rootless=1; qbit_requested=1; shift ;;
      --profile) require_value "$1" "${2:-}"; profile="$2"; shift 2 ;;
      --profile=*) profile="${1#*=}"; shift ;;
      --webui-username|--webui-user) require_value "$1" "${2:-}"; webui_username="$2"; shift 2 ;;
      --webui-username=*|--webui-user=*) webui_username="${1#*=}"; shift ;;
      --service-mode) require_value "$1" "${2:-}"; service_mode="$2"; shift 2 ;;
      --service-mode=*) service_mode="${1#*=}"; shift ;;
      --password-stdin) password_stdin=1; shift ;;
      --source) require_value "$1" "${2:-}"; source="$2"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift 2 ;;
      --source=*) source="${1#*=}"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift ;;
      --qb-tuning-profile|--qb-profile) require_value "$1" "${2:-}"; qb_tuning_profile="$2"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift 2 ;;
      --qb-tuning-profile=*|--qb-profile=*) qb_tuning_profile="${1#*=}"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift ;;
      --web-port) require_value "$1" "${2:-}"; qb_port="$2"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift 2 ;;
      --web-port=*) qb_port="${1#*=}"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift ;;
      --incoming-port) require_value "$1" "${2:-}"; qb_incoming_port="$2"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift 2 ;;
      --incoming-port=*) qb_incoming_port="${1#*=}"; qbit_requested=1; components="$(csv_add "${components}" qbittorrent)"; shift ;;
      --autobrr-port) require_value "$1" "${2:-}"; root_only_requested=1; autobrr_port="$2"; components="$(csv_add "${components}" autobrr)"; shift 2 ;;
      --autobrr-port=*) root_only_requested=1; autobrr_port="${1#*=}"; components="$(csv_add "${components}" autobrr)"; shift ;;
      --vertex-port) require_value "$1" "${2:-}"; root_only_requested=1; vertex_port="$2"; components="$(csv_add "${components}" vertex)"; shift 2 ;;
      --vertex-port=*) root_only_requested=1; vertex_port="${1#*=}"; components="$(csv_add "${components}" vertex)"; shift ;;
      --components) require_value "$1" "${2:-}"; components="$2"; components_overridden=1; shift 2 ;;
      --components=*) components="${1#*=}"; components_overridden=1; shift ;;
      --bbr-algo) require_value "$1" "${2:-}"; root_only_requested=1; bbr_algo="$2"; components="$(csv_add "${components}" bbr)"; shift 2 ;;
      --bbr-algo=*) root_only_requested=1; bbr_algo="${1#*=}"; components="$(csv_add "${components}" bbr)"; shift ;;
      --bbr-script-url) require_value "$1" "${2:-}"; bbr_script_url="$2"; shift 2 ;;
      --bbr-script-url=*) bbr_script_url="${1#*=}"; shift ;;
      --bbr-script-sha256) require_value "$1" "${2:-}"; bbr_script_sha256="$2"; shift 2 ;;
      --bbr-script-sha256=*) bbr_script_sha256="${1#*=}"; shift ;;
      --bbr-raw-base) require_value "$1" "${2:-}"; bbr_raw_base="$2"; shift 2 ;;
      --bbr-raw-base=*) bbr_raw_base="${1#*=}"; shift ;;
      --bbr-lang) require_value "$1" "${2:-}"; bbr_lang="$2"; shift 2 ;;
      --bbr-lang=*) bbr_lang="${1#*=}"; shift ;;
      --allow-unverified-downloads) allow_unverified=1; shift ;;
      --allow-unverified-bbr-installer) allow_unverified_bbr=1; shift ;;
      --force-runtime) force_runtime=1; shift ;;
      --upgrade-system) upgrade_system=1; shift ;;
      --no-clear) no_clear=1; shift ;;
      -h|--help) usage; exit 0 ;;
      -[!-]*)
        local cluster="${1#-}" opt value
        shift
        while [[ -n "${cluster}" ]]; do
          opt="${cluster:0:1}"
          cluster="${cluster:1}"
          case "${opt}" in
            u|p|c|q|l|L)
              if [[ -n "${cluster}" ]]; then
                value="${cluster}"
                cluster=""
              else
                [[ $# -gt 0 ]] || die "-${opt} $(tr_msg '需要一个参数' 'requires a value')"
                value="$1"
                shift
              fi
              handle_short_option_with_value "${opt}" "${value}"
              ;;
            r) root_only_requested=1; components="$(csv_add "${components}" autoremove-torrents)" ;;
            b) root_only_requested=1; components="$(csv_add "${components}" autobrr)" ;;
            v) root_only_requested=1; components="$(csv_add "${components}" vertex)" ;;
            x) root_only_requested=1; bbr_algo="bbrx"; components="$(csv_add "${components}" bbr)" ;;
            3) root_only_requested=1; bbr_algo="bbrv3"; components="$(csv_add "${components}" bbr)" ;;
            o) custom_ports=1 ;;
            T) tuning_enabled=0; components="$(csv_remove "${components}" tuning)" ;;
            h) usage; exit 0 ;;
            *) die "Unknown option: -${opt}" ;;
          esac
        done
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  profile="${profile,,}"
  case "${profile}" in
    ""|dedicated|shared) ;;
    *) die "$(tr_msg "不支持的 profile：${profile}" "Unsupported profile: ${profile}")" ;;
  esac

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    rootless=1
  fi

  if (( rootless )); then
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      die "$(tr_msg 'rootless qBittorrent 不能以 root/sudo 运行。请切换到目标普通用户后执行；如需 root/admin 安装，请使用：sudo seedboxctl qbittorrent add-user --user USER --password-stdin，或 sudo seedboxctl install --profile dedicated --components qbittorrent --user USER --password-stdin。' 'Rootless qBittorrent cannot be run as root/sudo. Run it as the target normal user. For root/admin install, use: sudo seedboxctl qbittorrent add-user --user USER --password-stdin, or sudo seedboxctl install --profile dedicated --components qbittorrent --user USER --password-stdin.')"
    fi
    if (( root_only_requested )); then
      die "$(tr_msg 'rootless Install.sh 只支持 qBittorrent；请去掉 -b/-v/-r/-x/-3 或 BBR/Vertex/autobrr 相关参数。' 'rootless Install.sh supports qBittorrent only; remove -b/-v/-r/-x/-3 or BBR/Vertex/autobrr options.')"
    fi
    if (( components_overridden )); then
      csv_only_qbittorrent "${components}" || die "$(tr_msg 'rootless Install.sh 只支持 --components qbittorrent。' 'rootless Install.sh supports only --components qbittorrent.')"
    fi
    components="qbittorrent"
    profile="shared"
    qbit_requested=1
    tuning_enabled=0
    webui_username="${webui_username:-${username}}"
    username=""
    if [[ -z "${source}" ]]; then
      source="static"
    fi
  elif [[ "${profile}" == "shared" ]]; then
    if (( root_only_requested )); then
      die "$(tr_msg 'shared profile 只支持 qBittorrent；请去掉 root-only 组件参数。' 'shared profile supports qBittorrent only; remove root-only component options.')"
    fi
    if (( components_overridden )); then
      csv_only_qbittorrent "${components}" || die "$(tr_msg 'shared profile 只支持 --components qbittorrent。' 'shared profile supports only --components qbittorrent.')"
    else
      components="qbittorrent"
    fi
    qbit_requested=1
  else
    profile="dedicated"
  fi

  if (( tuning_enabled == 0 && components_overridden == 0 && rootless == 0 )); then
    components="$(csv_remove "${components}" tuning)"
  fi
  [[ -n "${components}" ]] || die "$(tr_msg '没有选择任何组件' 'no components selected')"

  if (( rootless == 0 )) && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "$(tr_msg '非 root 运行时只能使用 --rootless。' 'Non-root runs must use --rootless.')"
  fi

  local needs_user=0
  if (( rootless == 0 )) && { csv_contains "${components}" qbittorrent || csv_contains "${components}" autobrr || csv_contains "${components}" autoremove-torrents; }; then
    needs_user=1
  fi

  if (( needs_user )) && [[ -z "${username}" ]]; then
    username="$(read_value "$(tr_msg '用户名' 'Username')")"
  fi
  if (( needs_user )); then
    [[ -n "${username}" ]] || die "$(tr_msg '必须提供用户名' 'username is required')"
  fi
  [[ "${cache}" =~ ^[0-9]+$ ]] || die "$(tr_msg '缓存必须是数字' 'cache must be a number')"

  if csv_contains "${components}" qbittorrent; then
    # Install.sh is the legacy-compatible installer, so qBittorrent installs default
    # to manifest-backed static builds. Pass --source distro or --source existing to opt out.
    [[ -n "${source}" ]] || source="static"
    if [[ "${password_stdin}" -eq 0 && -z "${password}" ]]; then
      password="$(read_secret "$(tr_msg 'qBittorrent WebUI 密码' 'qBittorrent WebUI password')")"
    fi
  fi

  if (( custom_ports )); then
    if csv_contains "${components}" qbittorrent; then
      qb_port="${qb_port:-$(read_port "$(tr_msg 'qBittorrent WebUI 端口' 'qBittorrent WebUI port')")}" 
      qb_incoming_port="${qb_incoming_port:-$(read_port "$(tr_msg 'qBittorrent 传入连接端口' 'qBittorrent incoming port')")}" 
    fi
    if csv_contains "${components}" autobrr; then
      autobrr_port="${autobrr_port:-$(read_port "$(tr_msg 'autobrr WebUI 端口' 'autobrr WebUI port')")}" 
    fi
    if csv_contains "${components}" vertex; then
      vertex_port="${vertex_port:-$(read_port "$(tr_msg 'Vertex WebUI 端口' 'Vertex WebUI port')")}" 
    fi
  fi

  local seedboxctl cmd=()
  seedboxctl="$(find_seedboxctl)"
  install_seedboxctl_command "${seedboxctl}"
  cmd=("${seedboxctl}" --lang "${LANG_CODE}" install --profile "${profile}" --components "${components}")
  (( rootless )) && cmd+=(--rootless)
  [[ -n "${username}" ]] && cmd+=(--user "${username}")
  [[ -n "${webui_username}" ]] && cmd+=(--webui-username "${webui_username}")

  if csv_contains "${components}" qbittorrent; then
    cmd+=(--cache "${cache}")
    [[ -n "${source}" ]] && cmd+=(--source "${source}")
    [[ -n "${qb_tuning_profile}" ]] && cmd+=(--qb-tuning-profile "${qb_tuning_profile}")
    [[ -n "${qb_version}" ]] && cmd+=(--qb-version "${qb_version}")
    [[ -n "${lib_version}" ]] && cmd+=(--libtorrent-version "${lib_version}")
    [[ -n "${qb_port}" ]] && cmd+=(--web-port "${qb_port}")
    [[ -n "${qb_incoming_port}" ]] && cmd+=(--incoming-port "${qb_incoming_port}")
    [[ -n "${service_mode}" ]] && cmd+=(--service-mode "${service_mode}")
    (( allow_unverified )) && cmd+=(--allow-unverified-downloads)
  fi

  if csv_contains "${components}" tuning; then
    [[ -n "${storage_path}" ]] && cmd+=(--storage-path "${storage_path}")
    (( disk_scheduler_all )) && cmd+=(--disk-scheduler-all)
  fi

  [[ -n "${autobrr_port}" ]] && cmd+=(--autobrr-port "${autobrr_port}")
  [[ -n "${vertex_port}" ]] && cmd+=(--vertex-port "${vertex_port}")

  if [[ -n "${bbr_algo}" ]]; then
    cmd+=(--bbr-algo "${bbr_algo}")
    [[ -n "${bbr_script_url}" ]] && cmd+=(--bbr-script-url "${bbr_script_url}")
    [[ -n "${bbr_script_sha256}" ]] && cmd+=(--bbr-script-sha256 "${bbr_script_sha256}")
    [[ -n "${bbr_raw_base}" ]] && cmd+=(--bbr-raw-base "${bbr_raw_base}")
    [[ -n "${bbr_lang}" ]] && cmd+=(--bbr-lang "${bbr_lang}")
    (( allow_unverified_bbr )) && cmd+=(--allow-unverified-bbr-installer)
    (( force_runtime )) && cmd+=(--force-runtime)
    (( upgrade_system )) && cmd+=(--upgrade-system)
    (( no_clear )) && cmd+=(--no-clear)
  fi

  if (( password_stdin )); then
    "${cmd[@]}" --password-stdin
  elif [[ -n "${password}" ]]; then
    printf '%s' "${password}" | "${cmd[@]}" --password-stdin
  else
    "${cmd[@]}"
  fi
}

main "$@"
