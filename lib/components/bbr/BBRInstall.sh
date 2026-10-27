#!/usr/bin/env bash
# BBR installer for Debian/Ubuntu.
#
# Debian 13 / trixie compatibility note:
# systemd-sysctl no longer reads /etc/sysctl.conf on Debian 13.  Local sysctl
# configuration is written to /etc/sysctl.d/*.conf instead.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="${0##*/}"
DEFAULT_RAW_BASE="https://raw.githubusercontent.com/jerry048/Trove/refs/heads/main/BBR-Install/BBR"

# Environment overrides for advanced users / tests.
RAW_BASE="${RAW_BASE:-$DEFAULT_RAW_BASE}"
SYSCTL_DROPIN="${BBR_SYSCTL_DROPIN:-/etc/sysctl.d/90-bbr-congestion-control.conf}"
SYSCTL_LEGACY_FILE="${BBR_SYSCTL_LEGACY_FILE:-/etc/sysctl.conf}"
MODULES_LOAD_DROPIN="${BBR_MODULES_LOAD_DROPIN:-/etc/modules-load.d/90-bbr-congestion-control.conf}"
FORCE_UNSUPPORTED_RUNTIME="${BBR_FORCE_UNSUPPORTED_RUNTIME:-0}"
WORK_DIR="${BBR_WORK_DIR:-}"
CLEAN_WORK_DIR="${BBR_CLEAN_WORK_DIR:-auto}"
ALGO="${BBR_ALGO:-}"
KERNEL_MIN_VERSION="${BBR_KERNEL_MIN_VERSION:-5.4}"
KERNEL_MAX_VERSION="${BBR_KERNEL_MAX_VERSION:-7.1.999}"
LANG_CODE="${BBR_LANG:-en}"
SHOW_HELP=0

SUPPORTED_ALGOS=("bbrv3" "bbrx" "bbrw" "bbr_brutal" "bbrw_brutal" "bbrx_old")
WORK_DIR_CREATED=""
WORK_DIR_IS_AUTO=0
WORK_DIR_ID=""

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_INFO=$'\e[92m'
  COLOR_NOTE=$'\e[94m'
  COLOR_WARN=$'\e[93m'
  COLOR_FAIL=$'\e[91m'
  COLOR_RESET=$'\e[0m'
else
  COLOR_INFO=""
  COLOR_NOTE=""
  COLOR_WARN=""
  COLOR_FAIL=""
  COLOR_RESET=""
fi

info() { printf '%s%s%s\n' "$COLOR_INFO" "$(bbr_message "$*")" "$COLOR_RESET"; }
note() { printf '%s%s%s\n' "$COLOR_NOTE" "$(bbr_message "$*")" "$COLOR_RESET"; }
warn() { printf '%s%s%s\n' "$COLOR_WARN" "$(bbr_message "$*")" "$COLOR_RESET" >&2; }
fail() { printf '%s%s%s\n' "$COLOR_FAIL" "$(bbr_message "$*")" "$COLOR_RESET" >&2; }
die() {
  fail "$*"
  exit 1
}

normalize_lang() {
  case "${1:-en}" in
    en | en-US | en_US | en-us | en_us) printf '%s' "en" ;;
    zh-CN | zh_CN | zh-cn | zh_cn | zh-Hans | zh_Hans | zh-hans | zh_hans | cn | simplified | simplified-chinese) printf '%s' "zh-CN" ;;
    zh | zh-TW | zh_TW | zh-tw | zh_tw | zh-Hant | zh_Hant | zh-hant | zh_hant | tw | traditional | traditional-chinese) printf '%s' "zh-TW" ;;
    *) return 1 ;;
  esac
}

set_language() {
  local requested="${1:-en}" normalized
  if ! normalized="$(normalize_lang "$requested")"; then
    die "Error: unsupported language: $requested (supported: en, zh-CN, zh-TW)"
  fi
  LANG_CODE="$normalized"
}

declare -A BBR_CN_MESSAGES=()
declare -a BBR_CN_TEMPLATES=()
bbr_message() {
  local text="$1" template rest prefix delimiter value translated
  local -a values=()
  [[ "$LANG_CODE" == zh-CN ]] || {
    printf '%s' "$text"
    return
  }
  [[ -n "$text" ]] || return 0
  translated="${BBR_CN_MESSAGES["$text"]:-}"
  if [[ -n "$translated" ]]; then
    printf '%s' "$translated"
    return
  fi
  for template in "${BBR_CN_TEMPLATES[@]}"; do
    local pattern="$template"
    rest="$text" values=()
    while [[ "$pattern" == *'%s'* ]]; do
      prefix="${pattern%%'%s'*}"
      [[ "$rest" == "$prefix"* ]] || break
      rest="${rest#"$prefix"}" pattern="${pattern#*'%s'}"
      if [[ "$pattern" == *'%s'* ]]; then
        delimiter="${pattern%%'%s'*}"
        [[ -n "$delimiter" && "$rest" == *"$delimiter"* ]] || break
        value="${rest%%"$delimiter"*}" rest="${rest#"$value"}"
      else
        [[ "$rest" == *"$pattern" ]] || break
        value="${rest%"$pattern"}" rest="$pattern"
      fi
      values+=("$value")
    done
    if [[ "$rest" == "$pattern" && "$pattern" != *'%s'* ]]; then
      printf -- "${BBR_CN_MESSAGES[$template]}" "${values[@]}"
      return
    fi
  done
  printf '%s' "$text"
}
while IFS=$'\t' read -r _bbr_en _bbr_cn; do
  BBR_CN_MESSAGES["$_bbr_en"]="$_bbr_cn"
  [[ "$_bbr_en" != *'%s'* ]] || BBR_CN_TEMPLATES+=("$_bbr_en")
done <<'BBR_MESSAGES'
Error: --algo requires a value.	错误：--algo 需要指定算法。
Error: --raw-base requires a value.	错误：--raw-base 需要指定下载源地址。
Error: --lang requires a value.	错误：--lang 需要指定语言。
Error: unknown argument: %s	错误：无法识别参数 %s，请查看 --help。
Error: unsupported congestion-control algorithm: %s	错误：不支持的拥塞控制算法：%s
Error: non-interactive mode requires --algo or BBR_ALGO.	错误：非交互环境必须用 --algo 或 BBR_ALGO 指定算法。
Select the congestion-control algorithm to install:	请选择要安装的拥塞控制算法：
Enter selection number: 	请输入编号：
Error: invalid selection.	错误：请输入列表中的有效编号。
Error: this script must be run as root.	错误：内核及 DKMS 安装必须由 root 在实体主机或完整虚拟机中执行。
Error: required command not found: %s	错误：缺少必需的命令：%s
Updating APT package indexes...	正在更新 APT 软件包索引……
Error: could not identify the OS distribution. This script supports Debian/Ubuntu only.	错误：无法识别系统发行版，本安装器仅支持 Debian 和 Ubuntu。
Error: this script supports Debian 11/12/13 only. Current version: %s	错误：本安装器仅支持 Debian 11、12、13；当前版本为 %s。
Error: this script supports Ubuntu 20.04/22.04/24.04/26.04 only. Current version: %s	错误：本安装器仅支持 Ubuntu 20.04、22.04、24.04、26.04；当前版本为 %s。
Error: this script supports Debian/Ubuntu only. Current system: %s (%s)	错误：本安装器仅支持 Debian 和 Ubuntu；当前系统为 %s（%s）。
Warning: --force-runtime was used; skipping runtime safety checks.	注意：已使用 --force-runtime，将跳过运行环境限制检查，请确认已了解内核共享风险。
Error: container environment detected (%s). Installing kernel/DKMS modules requires the host or a full VM.	错误：检测到容器环境（%s）。内核及 DKMS 模块必须在宿主机或完整虚拟机中安装。
Error: WSL environment detected. WSL is not suitable for this kind of kernel/DKMS module installation.	错误：检测到 WSL 环境，不适合安装这类内核或 DKMS 模块。
Warning: could not identify the virtualization environment; make sure this is the host or a full VM before continuing.	注意：无法识别虚拟化环境。继续前，请确认当前是实体主机或完整虚拟机。
System information:	系统信息：
  Distribution: %s %s %s	  发行版：%s %s %s
  Architecture: %s	  架构：%s
  Kernel:       %s	  内核：%s
  Runtime:      %s/%s	  运行环境：%s/%s
Installing download tools...	正在安装下载工具……
Error: failed to install curl/wget.	错误：未能安装 curl 或 wget。
Error: download failed or file is empty: %s	错误：下载失败或文件为空：%s
Backed up: %s -> %s	已备份：%s → %s
Commented out conflicting local sysctl setting: %s	已注释本机冲突的内核参数配置：%s
Error: invalid congestion-control algorithm name: %s	错误：拥塞控制算法名称无效：%s
Wrote sysctl configuration: %s	已写入内核参数配置：%s
Switched the current session to congestion-control algorithm: %s	当前运行的内核已切换为拥塞控制算法 %s。
Warning: persistent configuration was written, but the current kernel could not switch to %s yet. It will be retried after reboot or after the matching module is loaded.	注意：已保存持久配置，但当前内核尚未能切换到 %s。请在重启或加载对应模块后再次检查。
Wrote module autoload configuration: %s	已写入模块自动加载配置：%s
Removed old module autoload configuration: %s	已移除原模块自动加载配置：%s
Error: no bbrv3 package directory found for %s %s %s.	错误：找不到适用于 %s %s %s 的 bbrv3 软件包目录。
Error: bbrv3 ARM64 prebuilt kernel packages currently support Debian 13 only. Current system: %s %s, architecture: %s	错误：bbrv3 的 ARM64 预编译内核目前只支持 Debian 13；当前系统为 %s %s，架构为 %s。
Error: bbrv3 prebuilt kernel packages currently support amd64/x86_64 and arm64/aarch64 only. Current architecture: %s	错误：bbrv3 预编译内核目前只支持 amd64/x86_64 和 arm64/aarch64；当前架构为 %s。
Error: no bbrv3 package directory candidates were found for this system.	错误：找不到适用于当前系统的 bbrv3 候选软件包目录。
Downloading bbrv3 Debian kernel packages...	正在下载 bbrv3 的 Debian 格式内核软件包……
Trying bbrv3 package directory: bbrv3/%s	正在检查 bbrv3 软件包目录：bbrv3/%s
Error: could not download bbrv3 SHA256SUMS from any candidate directory: %s	错误：所有候选目录均无法下载 bbrv3 的 SHA256SUMS 校验清单：%s
Selected bbrv3 package directory: bbrv3/%s	已选择 bbrv3 软件包目录：bbrv3/%s
Error: could not identify linux-headers/linux-image packages from SHA256SUMS.	错误：无法从 SHA256SUMS 中确定 linux-headers 和 linux-image 软件包。
Error: could not create the checksum file list.	错误：无法生成待校验文件列表。
Error: SHA256 verification failed.	错误：SHA-256 校验失败；请勿安装或运行下载文件。
Invalid BBRv3 kernel package name	BBRv3 内核软件包名称无效。
Invalid BBRv3 kernel release	BBRv3 内核版本标识无效。
Unsafe BBR kernel result directory	BBR 内核结果目录不安全。
BBRv3 kernel result could not be verified	无法验证 BBRv3 内核结果。
bbrv3 kernel packages downloaded and verified.	bbrv3 内核软件包已下载并通过校验。
Installing bbrv3 kernel packages...	正在安装 bbrv3 内核软件包……
bbrv3 kernel packages were installed successfully. Reboot to enter the bbrv3 kernel.	bbrv3 内核软件包已安装。请确认引导配置正常后重启，并进入新内核。
After reboot, verify with: uname -r && sysctl net.ipv4.tcp_congestion_control	重启后检查：uname -r && sysctl net.ipv4.tcp_congestion_control
Error: could not parse the current kernel version: %s	错误：无法解析当前内核版本：%s
Error: DKMS modules support kernel versions [%s - 7.1.x] only. Current kernel: %s	错误：DKMS 模块仅支持 [%s - 7.1.x] 范围内的内核，当前内核为 %s。
Installing build dependencies: %s	正在安装构建依赖：%s
Error: no generic kernel/header packages found for %s %s. Manually install headers matching the current kernel.	错误：找不到适用于 %s %s 的通用内核及头文件软件包；请先提供与当前内核匹配的头文件。
Error: could not resolve generic kernel/header package names.	错误：无法确定通用内核及头文件的软件包名称。
Warning: headers for the running kernel were not found or are not usable: linux-headers-%s	注意：当前内核的头文件不存在或不可用：linux-headers-%s
You can install the distribution generic kernel image and headers instead:	可以改装发行版的通用内核及头文件：
  Kernel image: %s	  内核镜像：%s
  Kernel headers: %s	  内核头文件：%s
After installation, reboot into the new kernel and rerun this script before the DKMS module can be built and installed.	安装后必须重启进入新内核，再重新运行本脚本，才能继续构建并安装 DKMS 模块。
Automatically installing generic kernel image and headers: %s %s	正在自动安装通用内核及头文件：%s %s
Error: failed to install generic kernel/headers: %s %s	错误：未能安装通用内核及头文件：%s %s
Warning: update-grub failed; check the bootloader configuration.	注意：update-grub 执行失败，请检查引导配置，确认可正常启动后再重启。
Generic kernel image and headers were installed.	通用内核及头文件已安装。
Reboot now, then rerun this script.	请确认引导配置正常后重启进入新内核，再重新运行本脚本。
After reboot, verify with: uname -r && ls -l /lib/modules/$(uname -r)/build	重启后检查：uname -r && ls -l /lib/modules/$(uname -r)/build
Rerun example: ./%s --algo %s	重新运行示例：./%s --algo %s
Detected current kernel headers: %s	已找到当前内核的头文件：%s
Installing current kernel headers: linux-headers-%s	正在安装当前内核的头文件：linux-headers-%s
Current kernel header check passed: %s	当前内核头文件检查通过：%s
Warning: linux-headers-%s was installed or attempted, but %s is not usable for DKMS.	注意：已尝试安装 linux-headers-%s，但 %s 仍无法用于 DKMS 构建。
Warning: could not find or install the running kernel headers package: linux-headers-%s.	注意：找不到或无法安装当前内核的头文件软件包 linux-headers-%s。
Found an existing %s DKMS module; removing old versions...	发现已有的 %s DKMS 模块，正在移除旧版本……
Error: failed to remove %s/%s.	错误：未能移除 %s/%s。
System support check passed.	系统环境检查通过。
Downloading %s congestion-control module source...	正在下载 %s 拥塞控制模块源码……
Source download completed.	源码下载完成。
Building and installing the %s congestion-control module...	正在构建并安装 %s 拥塞控制模块……
Error: DKMS could not add the kernel module.	错误：DKMS 未能添加内核模块。
Error: DKMS module build failed.	错误：DKMS 模块构建失败，请检查构建日志及当前内核头文件。
Error: DKMS could not install the kernel module.	错误：DKMS 未能安装内核模块。
Error: failed to load module: %s	错误：无法加载模块 %s，请检查模块日志及当前内核版本。
%s congestion-control module was installed and loaded successfully. You can usually try it without rebooting.	%s 拥塞控制模块已安装并加载，通常无需重启即可检查是否生效。
Error: module did not appear in /proc/modules: %s	错误：/proc/modules 中未找到模块 %s。
Checking system support...	正在检查系统环境……
Could not clean private BBR workspace: %s	无法清理 BBR 临时工作目录，已保留：%s
Refusing cleanup of changed/symlinked/mounted BBR workspace: %s	BBR 临时工作目录已改变、包含符号链接或涉及挂载点，已拒绝清理：%s
Invalid BBR_CLEAN_WORK_DIR: %s	BBR_CLEAN_WORK_DIR 的值无效：%s
Unsafe/symlinked BBR work parent: %s	BBR 工作目录的上级路径不安全或包含符号链接：%s
Unsafe BBR work ancestor: %s	BBR 工作目录的上级路径未通过安全检查：%s
Untrusted BBR work ancestor: %s	BBR 工作目录的上级路径权限或归属不可信：%s
Unsafe package checksum filename	校验清单中的软件包文件名不安全，已停止下载。
Ambiguous package checksums	软件包校验清单存在歧义，无法确定唯一的内核及头文件软件包。
Error: unsupported language: %s (supported: en, zh-CN, zh-TW)	错误：不支持的语言：%s（可选 en、zh-CN、zh-TW）。
BBR_MESSAGES
unset _bbr_en _bbr_cn

l10n() {
  local zh_tw="$1" en="$2"
  if [[ "$LANG_CODE" == "zh-CN" ]]; then
    bbr_message "$en"
  elif [[ "$LANG_CODE" == "zh-TW" ]]; then
    printf '%s' "$zh_tw"
  else
    printf '%s' "$en"
  fi
}

set_language "$LANG_CODE"

join_words() {
  local item output=""
  for item in "$@"; do
    output="${output:+$output }$item"
  done
  printf '%s' "$output"
}

separator() {
  local cols
  cols="$(tput cols 2>/dev/null || printf '80')"
  printf '\n%*s\n' "$cols" '' | tr ' ' '='
}

usage() {
  local algos
  algos="$(join_words "${SUPPORTED_ALGOS[@]}")"

  if [[ "$LANG_CODE" == "zh-CN" ]]; then
    cat <<USAGE
用法：$SCRIPT_NAME [OPTIONS]

选项：
  --algo ALGO           选择要安装的算法：$algos
  --raw-base URL        指定下载源地址，也可使用 RAW_BASE=...
  --lang LANG           界面语言：en（默认）、zh-CN、zh-TW，也可使用 BBR_LANG=...
  --force-runtime       在容器或 WSL 中跳过环境限制；请先评估内核共享风险
  -h, --help            显示帮助

环境变量：
  BBR_LANG=en|zh-CN|zh-TW, BBR_ALGO, RAW_BASE,
  BBR_SYSCTL_DROPIN, BBR_SYSCTL_LEGACY_FILE,
  BBR_MODULES_LOAD_DROPIN, BBR_FORCE_UNSUPPORTED_RUNTIME=1,
  BBR_WORK_DIR, BBR_CLEAN_WORK_DIR=0,
  BBR_KERNEL_MIN_VERSION, BBR_KERNEL_MAX_VERSION, NO_COLOR=1
USAGE
  elif [[ "$LANG_CODE" == "zh-TW" ]]; then
    cat <<USAGE
用法: $SCRIPT_NAME [OPTIONS]

選項:
  --algo ALGO           安裝下列其中一種演算法: $algos
  --raw-base URL        覆寫下載來源基底 URL；也可使用 RAW_BASE=...
  --lang LANG           輸出語言: en（預設）、zh-TW；也可使用 BBR_LANG=...
  --force-runtime       在容器/WSL 等不支援的環境中仍繼續執行
  -h, --help            顯示此說明

環境變數覆寫:
  BBR_LANG=en|zh-TW, BBR_ALGO, RAW_BASE,
  BBR_SYSCTL_DROPIN, BBR_SYSCTL_LEGACY_FILE,
  BBR_MODULES_LOAD_DROPIN, BBR_FORCE_UNSUPPORTED_RUNTIME=1,
  BBR_WORK_DIR, BBR_CLEAN_WORK_DIR=0,
  BBR_KERNEL_MIN_VERSION, BBR_KERNEL_MAX_VERSION, NO_COLOR=1
USAGE
  else
    cat <<USAGE
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --algo ALGO           Install one of: $algos
  --raw-base URL        Override source base URL. Can also use RAW_BASE=...
  --lang LANG           Output language: en (default), zh-CN, zh-TW. Can also use BBR_LANG=...
  --force-runtime       Continue in unsupported runtimes such as containers/WSL
  -h, --help            Show this help

Environment overrides:
  BBR_LANG=en|zh-CN|zh-TW, BBR_ALGO, RAW_BASE,
  BBR_SYSCTL_DROPIN, BBR_SYSCTL_LEGACY_FILE,
  BBR_MODULES_LOAD_DROPIN, BBR_FORCE_UNSUPPORTED_RUNTIME=1,
  BBR_WORK_DIR, BBR_CLEAN_WORK_DIR=0,
  BBR_KERNEL_MIN_VERSION, BBR_KERNEL_MAX_VERSION, NO_COLOR=1
USAGE
  fi
}

work_path_safe() {
  local path="$1" target rest
  [[ "$path" == /* && "$path" != *$'\n'* && "$path" != *$'\r'* && "$(realpath -ms -- "$path")" == "$path" && "$(realpath -m -- "$path")" == "$path" ]] || return 1
  while IFS=' ' read -r _ _ _ _ target rest; do
    printf -v target '%b' "$target"
    [[ "$target" != "$path" && "$target" != "$path/"* ]] || return 1
  done </proc/self/mountinfo
}

cleanup() {
  if [[ -z "$WORK_DIR_CREATED" || ! -d "$WORK_DIR_CREATED" ]]; then
    return 0
  fi

  if [[ "$CLEAN_WORK_DIR" == "1" || ("$CLEAN_WORK_DIR" == "auto" && "$WORK_DIR_IS_AUTO" == "1") ]]; then
    if [[ -n "$WORK_DIR_ID" && "${WORK_DIR_CREATED##*/}" == bbr-install.* ]] && work_path_safe "$WORK_DIR_CREATED" && [[ "$(stat -c '%d:%i' -- "$WORK_DIR_CREATED")" == "$WORK_DIR_ID" ]]; then
      rm -rf --one-file-system -- "$WORK_DIR_CREATED" || {
        warn "Could not clean private BBR workspace: $WORK_DIR_CREATED"
        return 1
      }
    else
      warn "Refusing cleanup of changed/symlinked/mounted BBR workspace: $WORK_DIR_CREATED"
      return 1
    fi
  fi
}
trap cleanup EXIT

parse_args() {
  while (($#)); do
    case "$1" in
      --algo)
        shift
        [[ $# -gt 0 ]] || die "$(l10n "錯誤：--algo 需要參數。" "Error: --algo requires a value.")"
        ALGO="$1"
        ;;
      --algo=*)
        ALGO="${1#*=}"
        ;;
      --raw-base)
        shift
        [[ $# -gt 0 ]] || die "$(l10n "錯誤：--raw-base 需要參數。" "Error: --raw-base requires a value.")"
        RAW_BASE="${1%/}"
        ;;
      --raw-base=*)
        RAW_BASE="${1#*=}"
        RAW_BASE="${RAW_BASE%/}"
        ;;
      --lang)
        shift
        [[ $# -gt 0 ]] || die "$(l10n "錯誤：--lang 需要參數。" "Error: --lang requires a value.")"
        set_language "$1"
        ;;
      --lang=*)
        set_language "${1#*=}"
        ;;
      --force-runtime)
        FORCE_UNSUPPORTED_RUNTIME=1
        ;;
      -h | --help)
        SHOW_HELP=1
        ;;
      *)
        die "$(l10n "錯誤：未知參數：$1" "Error: unknown argument: $1")"
        ;;
    esac
    shift
  done
}

is_supported_algo() {
  local candidate="$1"
  local algo
  for algo in "${SUPPORTED_ALGOS[@]}"; do
    [[ "$candidate" == "$algo" ]] && return 0
  done
  return 1
}

choose_algo() {
  if [[ -n "$ALGO" ]]; then
    is_supported_algo "$ALGO" || die "$(l10n "錯誤：不支援的擁塞控制演算法：$ALGO" "Error: unsupported congestion-control algorithm: $ALGO")"
    return 0
  fi

  [[ -t 0 ]] || die "$(l10n "錯誤：非互動模式請使用 --algo 或 BBR_ALGO 指定演算法。" "Error: non-interactive mode requires --algo or BBR_ALGO.")"

  info "$(l10n "請選擇要安裝的擁塞控制演算法：" "Select the congestion-control algorithm to install:")"
  local PS3
  PS3="$(l10n "請輸入編號：" "Enter selection number: ")"
  select selected_algo in "${SUPPORTED_ALGOS[@]}"; do
    if is_supported_algo "${selected_algo:-}"; then
      ALGO="$selected_algo"
      break
    fi
    fail "$(l10n "錯誤：無效的選擇。" "Error: invalid selection.")"
  done
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "$(l10n "錯誤：此腳本必須以 root 執行。" "Error: this script must be run as root.")"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$(l10n "錯誤：缺少必要命令：$1" "Error: required command not found: $1")"
}

apt_update() {
  export DEBIAN_FRONTEND=noninteractive
  info "$(l10n "正在更新 APT 套件索引..." "Updating APT package indexes...")"
  apt-get update >/dev/null
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y --no-install-recommends "$@"
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

parse_major_version() {
  local version="$1"
  if [[ "$version" =~ ^([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

OS_ID=""
OS_NAME=""
OS_VERSION_ID=""
OS_VERSION_MAJOR=""
OS_CODENAME=""
OS_ARCH=""
KERNEL=""
KERNEL_BASE=""
VIRT_KIND="unknown"
VIRT_TYPE="unknown"

collect_system_info() {
  local name="" id="" version_id="" version_codename="" ubuntu_codename=""

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    name="${NAME:-}"
    id="${ID:-}"
    version_id="${VERSION_ID:-}"
    version_codename="${VERSION_CODENAME:-}"
    ubuntu_codename="${UBUNTU_CODENAME:-}"
  elif command -v lsb_release >/dev/null 2>&1; then
    name="$(lsb_release -si 2>/dev/null || true)"
    id="$name"
    version_id="$(lsb_release -sr 2>/dev/null || true)"
    version_codename="$(lsb_release -sc 2>/dev/null || true)"
  elif [[ -r /etc/debian_version ]]; then
    name="Debian"
    id="debian"
    version_id="$(cat /etc/debian_version)"
  else
    die "$(l10n "錯誤：無法識別系統發行版。本腳本僅支援 Debian/Ubuntu。" "Error: could not identify the OS distribution. This script supports Debian/Ubuntu only.")"
  fi

  OS_ID="$(lowercase "$id")"
  OS_NAME="${name:-$OS_ID}"
  OS_VERSION_ID="$version_id"
  OS_VERSION_MAJOR="$(parse_major_version "$OS_VERSION_ID")"
  OS_CODENAME="${version_codename:-$ubuntu_codename}"
  OS_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  KERNEL="$(uname -r)"
  KERNEL_BASE="$(printf '%s' "$KERNEL" | sed -E 's/^([0-9]+(\.[0-9]+){1,2}).*/\1/')"

  if command -v systemd-detect-virt >/dev/null 2>&1; then
    if systemd-detect-virt --quiet --container; then
      VIRT_KIND="container"
      VIRT_TYPE="$(systemd-detect-virt --container 2>/dev/null || printf 'container')"
    elif systemd-detect-virt --quiet --vm; then
      VIRT_KIND="vm"
      VIRT_TYPE="$(systemd-detect-virt --vm 2>/dev/null || printf 'vm')"
    else
      VIRT_KIND="none"
      VIRT_TYPE="none"
    fi
  elif grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    VIRT_KIND="wsl"
    VIRT_TYPE="wsl"
  else
    VIRT_KIND="unknown"
    VIRT_TYPE="unknown"
  fi
}

check_supported_os() {
  case "$OS_ID" in
    debian)
      case "$OS_VERSION_MAJOR" in
        11 | 12 | 13) ;;
        *) die "$(l10n "錯誤：本腳本僅支援 Debian 11/12/13。目前版本：${OS_VERSION_ID:-unknown}" "Error: this script supports Debian 11/12/13 only. Current version: ${OS_VERSION_ID:-unknown}")" ;;
      esac
      ;;
    ubuntu)
      case "$OS_VERSION_ID" in
        20.04* | 22.04* | 24.04* | 26.04*) ;;
        *) die "$(l10n "錯誤：本腳本僅支援 Ubuntu 20.04/22.04/24.04/26.04。目前版本：${OS_VERSION_ID:-unknown}" "Error: this script supports Ubuntu 20.04/22.04/24.04/26.04 only. Current version: ${OS_VERSION_ID:-unknown}")" ;;
      esac
      ;;
    *)
      die "$(l10n "錯誤：本腳本僅支援 Debian/Ubuntu。目前系統：${OS_NAME:-unknown} (${OS_ID:-unknown})" "Error: this script supports Debian/Ubuntu only. Current system: ${OS_NAME:-unknown} (${OS_ID:-unknown})")"
      ;;
  esac
}

check_supported_runtime() {
  if [[ "$FORCE_UNSUPPORTED_RUNTIME" == "1" ]]; then
    warn "$(l10n "警告：已使用 --force-runtime，將略過執行環境限制檢查。" "Warning: --force-runtime was used; skipping runtime safety checks.")"
    return 0
  fi

  case "$VIRT_KIND" in
    container)
      die "$(l10n "錯誤：偵測到容器環境 ($VIRT_TYPE)。安裝核心/DKMS 模組需要宿主機或完整虛擬機。" "Error: container environment detected ($VIRT_TYPE). Installing kernel/DKMS modules requires the host or a full VM.")"
      ;;
    wsl)
      die "$(l10n "錯誤：偵測到 WSL 環境。WSL 不適合安裝這類核心/DKMS 模組。" "Error: WSL environment detected. WSL is not suitable for this kind of kernel/DKMS module installation.")"
      ;;
    unknown)
      warn "$(l10n "警告：無法識別虛擬化環境，繼續前請確認這是宿主機或完整虛擬機。" "Warning: could not identify the virtualization environment; make sure this is the host or a full VM before continuing.")"
      ;;
    *) ;;
  esac
}

print_system_info() {
  separator
  info "$(l10n "系統資訊：" "System information:")"
  note "$(l10n "  發行版：${OS_NAME:-unknown} ${OS_VERSION_ID:-unknown} ${OS_CODENAME:+($OS_CODENAME)}" "  Distribution: ${OS_NAME:-unknown} ${OS_VERSION_ID:-unknown} ${OS_CODENAME:+($OS_CODENAME)}")"
  note "$(l10n "  架構：  ${OS_ARCH:-unknown}" "  Architecture: ${OS_ARCH:-unknown}")"
  note "$(l10n "  核心：  ${KERNEL:-unknown}" "  Kernel:       ${KERNEL:-unknown}")"
  note "$(l10n "  環境：  ${VIRT_KIND:-unknown}/${VIRT_TYPE:-unknown}" "  Runtime:      ${VIRT_KIND:-unknown}/${VIRT_TYPE:-unknown}")"
}

ensure_download_tools() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  info "$(l10n "正在安裝下載工具..." "Installing download tools...")"
  apt_install ca-certificates curl || apt_install ca-certificates wget

  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || die "$(l10n "錯誤：安裝 curl/wget 失敗。" "Error: failed to install curl/wget.")"
}

fetch_optional() {
  local url="$1"
  local output="$2"

  rm -f -- "$output" || return 1
  if [[ "$url" == file://* || "$url" == /* ]]; then
    local source="${url#file://}"
    [[ -f "$source" && ! -L "$source" ]] || return 1
    cp -- "$source" "$output" || return 1
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 --output "$output" "$url" || return 1
  else
    wget -q --tries=3 --timeout=30 -O "$output" "$url" || return 1
  fi

  if [[ ! -s "$output" ]]; then
    rm -f -- "$output"
    return 1
  fi
}

fetch() {
  local url="$1"
  local output="$2"

  fetch_optional "$url" "$output" || die "$(l10n "錯誤：下載失敗或檔案為空：$url" "Error: download failed or file is empty: $url")"
}

validate_work_parent() {
  local parent="${WORK_DIR:-${TMPDIR:-/tmp}}"
  case "$CLEAN_WORK_DIR" in auto | 0 | 1) ;; *) die "Invalid BBR_CLEAN_WORK_DIR: $CLEAN_WORK_DIR" ;; esac
  [[ "$parent" == /* && "$parent" != *$'\n'* && "$parent" != *$'\r'* && "$(realpath -ms -- "$parent")" == "$parent" && "$(realpath -m -- "$parent")" == "$parent" ]] || die "Unsafe/symlinked BBR work parent: $parent"
  local current="$parent" uid mode
  while :; do
    if [[ -e "$current" ]]; then
      [[ -d "$current" && ! -L "$current" ]] || die "Unsafe BBR work ancestor: $current"
      uid="$(stat -c %u -- "$current")" || return $?
      mode="$(stat -c %a -- "$current")" || return $?
      [[ "$uid" == 0 ]] && (((8#$mode & 0022) == 0 || (8#$mode & 01000) != 0)) || die "Untrusted BBR work ancestor: $current"
    fi
    [[ "$current" != / ]] || break
    current="$(dirname -- "$current")" || return $?
  done
}

create_work_dir() {
  local parent
  if [[ -n "$WORK_DIR_CREATED" ]]; then
    return 0
  fi

  parent="${WORK_DIR:-${TMPDIR:-/tmp}}"
  # The selected directory is only a parent; never build in or delete it.
  validate_work_parent || return $?
  mkdir -p -- "$parent" || return $?
  WORK_DIR_CREATED="$(mktemp -d "$parent/bbr-install.XXXXXX")" || return $?
  WORK_DIR_ID="$(stat -c '%d:%i' -- "$WORK_DIR_CREATED")" || return $?
  [[ "$(stat -c %u -- "$WORK_DIR_CREATED")" == 0 && "$(stat -c %a -- "$WORK_DIR_CREATED")" == 700 ]] || return 1
  WORK_DIR_IS_AUTO=1
  [[ -z "$WORK_DIR" ]] || WORK_DIR_IS_AUTO=0
}

backup_file_once() {
  local file="$1"
  local stamp backup
  [[ -f "$file" ]] || return 0
  stamp="$(date +%Y%m%d%H%M%S)"
  backup="${file}.bbrinstall.${stamp}.bak"
  cp -a -- "$file" "$backup"
  note "$(l10n "已備份：$file -> $backup" "Backed up: $file -> $backup")"
}

comment_conflicting_sysctl_key() {
  local file="$1"
  local key_regex='net[./]ipv4[./]tcp_congestion_control'

  [[ -f "$file" ]] || return 0
  [[ "$file" != "$SYSCTL_DROPIN" ]] || return 0

  if grep -Eq "^[[:space:]]*-?[[:space:]]*${key_regex}[[:space:]]*=" "$file"; then
    backup_file_once "$file"
    sed -i -E "s|^([[:space:]]*)(-?[[:space:]]*${key_regex}[[:space:]]*=.*)|\1# BBRInstall disabled conflicting setting: \2|" "$file"
    note "$(l10n "已註解本機衝突的 sysctl 設定：$file" "Commented out conflicting local sysctl setting: $file")"
  fi
}

comment_local_conflicting_sysctls() {
  local sysctl_dir
  sysctl_dir="$(dirname -- "$SYSCTL_DROPIN")"

  comment_conflicting_sysctl_key "$SYSCTL_LEGACY_FILE"

  if [[ -d "$sysctl_dir" ]]; then
    local file
    for file in "$sysctl_dir"/*.conf; do
      [[ -e "$file" ]] || continue
      comment_conflicting_sysctl_key "$file"
    done
  fi
}

configure_sysctl_cc() {
  local cc_algo="$1"
  local sysctl_dir
  sysctl_dir="$(dirname -- "$SYSCTL_DROPIN")"

  [[ "$cc_algo" =~ ^[A-Za-z0-9_]+$ ]] || die "$(l10n "錯誤：不合法的擁塞控制演算法名稱：$cc_algo" "Error: invalid congestion-control algorithm name: $cc_algo")"

  mkdir -p -- "$sysctl_dir"
  comment_local_conflicting_sysctls

  cat >"$SYSCTL_DROPIN" <<EOF_SYSCTL
# Managed by BBRInstall.
# Debian 13/trixie: systemd-sysctl no longer reads /etc/sysctl.conf.
# Keep local kernel parameter overrides in /etc/sysctl.d/*.conf.
net.ipv4.tcp_congestion_control = $cc_algo
EOF_SYSCTL
  chmod 0644 "$SYSCTL_DROPIN"
  note "$(l10n "已寫入 sysctl 設定：$SYSCTL_DROPIN" "Wrote sysctl configuration: $SYSCTL_DROPIN")"

  if sysctl -w "net.ipv4.tcp_congestion_control=$cc_algo" >/dev/null 2>&1; then
    note "$(l10n "目前工作階段已切換擁塞控制演算法為：$cc_algo" "Switched the current session to congestion-control algorithm: $cc_algo")"
  else
    warn "$(l10n "警告：已寫入持久化設定，但目前核心暫時無法切換到 $cc_algo。重新開機或載入對應模組後會再次嘗試生效。" "Warning: persistent configuration was written, but the current kernel could not switch to $cc_algo yet. It will be retried after reboot or after the matching module is loaded.")"
  fi
}

configure_module_autoload() {
  local module_name="$1"
  local modules_dir
  modules_dir="$(dirname -- "$MODULES_LOAD_DROPIN")"

  mkdir -p -- "$modules_dir"
  cat >"$MODULES_LOAD_DROPIN" <<EOF_MODULES
# Managed by BBRInstall.
# Load the DKMS congestion-control module before sysctl.d settings are applied.
$module_name
EOF_MODULES
  chmod 0644 "$MODULES_LOAD_DROPIN"
  note "$(l10n "已寫入模組自動載入設定：$MODULES_LOAD_DROPIN" "Wrote module autoload configuration: $MODULES_LOAD_DROPIN")"
}

remove_managed_module_autoload() {
  if [[ -f "$MODULES_LOAD_DROPIN" ]]; then
    rm -f -- "$MODULES_LOAD_DROPIN"
    note "$(l10n "已移除舊的模組自動載入設定：$MODULES_LOAD_DROPIN" "Removed old module autoload configuration: $MODULES_LOAD_DROPIN")"
  fi
}

resolve_bbrv3_candidate_dirs() {
  # Current bbrv3 packages are grouped by architecture, for example:
  #   bbrv3/x86_64/debian13-amd64
  #   bbrv3/ARM64/debian13-arm64
  # Keep legacy top-level paths as fallbacks so older mirrors continue to work.
  case "$OS_ARCH" in
    amd64 | x86_64)
      case "$OS_ID:$OS_VERSION_MAJOR" in
        debian:11) printf '%s\n' "x86_64/debian11-amd64" "debian11-amd64" ;;
        debian:12) printf '%s\n' "x86_64/debian12-amd64" "debian12-amd64" ;;
        debian:13) printf '%s\n' "x86_64/debian13-amd64" "debian13-amd64" ;;
        ubuntu:22) printf '%s\n' "x86_64/ubuntu2204-generic" "ubuntu2204-generic" ;;
        ubuntu:24) printf '%s\n' "x86_64/ubuntu2404-generic" "ubuntu2404-generic" ;;
        ubuntu:26) printf '%s\n' "x86_64/ubuntu2604-generic" "ubuntu2604-generic" ;;
        *) die "$(l10n "錯誤：找不到適用於 ${OS_NAME:-$OS_ID} ${OS_VERSION_ID:-unknown} $OS_ARCH 的 bbrv3 套件目錄。" "Error: no bbrv3 package directory found for ${OS_NAME:-$OS_ID} ${OS_VERSION_ID:-unknown} $OS_ARCH.")" ;;
      esac
      ;;
    arm64 | aarch64)
      case "$OS_ID:$OS_VERSION_MAJOR" in
        debian:13) printf '%s\n' "ARM64/debian13-arm64" "debian13-arm64" ;;
        *) die "$(l10n "錯誤：bbrv3 ARM64 預編譯核心套件目前僅支援 Debian 13。目前系統：${OS_NAME:-$OS_ID} ${OS_VERSION_ID:-unknown}，架構：$OS_ARCH" "Error: bbrv3 ARM64 prebuilt kernel packages currently support Debian 13 only. Current system: ${OS_NAME:-$OS_ID} ${OS_VERSION_ID:-unknown}, architecture: $OS_ARCH")" ;;
      esac
      ;;
    *)
      die "$(l10n "錯誤：bbrv3 預編譯核心套件目前僅支援 amd64/x86_64 與 arm64/aarch64。目前架構：$OS_ARCH" "Error: bbrv3 prebuilt kernel packages currently support amd64/x86_64 and arm64/aarch64 only. Current architecture: $OS_ARCH")"
      ;;
  esac
}

extract_checksum_filename() {
  # Only package basenames are accepted; never paths from a checksum file.
  awk 'NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-fA-F]/ {exit 1}
	     {name=$2; sub(/^\*/, "", name); sub(/^\.\//, "", name);
	      if (name !~ /^linux-(headers|image)-[A-Za-z0-9][A-Za-z0-9.+:~_-]*\.deb$/ || index(name,"..")) exit 1;
	      print name}' "$1"
}

write_selected_sha256sums() {
  local checksum_file="$1"
  local output_file="$2"
  shift 2
  local wanted_csv="," wanted_file
  for wanted_file in "$@"; do
    wanted_csv+="${wanted_file},"
  done

  awk -v wanted="$wanted_csv" '
		{
			file=$2
			sub(/^\*/, "", file)
			sub(/^\.\//, "", file)
			if (index(wanted, "," file ",") > 0) {
				print $1 "  " file
			}
		}
	' "$checksum_file" >"$output_file"
}

install_bbrv3_deb() {
  local pkg_dir pkg_base selected_pkg_dir work headers_deb image_deb sha_selected kernel_release
  local -a pkg_candidates=()

  ensure_download_tools
  create_work_dir
  work="$WORK_DIR_CREATED/bbrv3"
  mkdir -p -- "$work"
  cd "$work"

  mapfile -t pkg_candidates < <(resolve_bbrv3_candidate_dirs)
  [[ ${#pkg_candidates[@]} -gt 0 ]] || die "$(l10n "錯誤：找不到適用於目前系統的 bbrv3 套件目錄候選。" "Error: no bbrv3 package directory candidates were found for this system.")"

  separator
  info "$(l10n "正在下載 bbrv3 Debian 核心套件..." "Downloading bbrv3 Debian kernel packages...")"
  for pkg_dir in "${pkg_candidates[@]}"; do
    pkg_base="$RAW_BASE/bbrv3/$pkg_dir"
    note "$(l10n "嘗試 bbrv3 套件目錄：bbrv3/$pkg_dir" "Trying bbrv3 package directory: bbrv3/$pkg_dir")"
    if fetch_optional "$pkg_base/SHA256SUMS" "SHA256SUMS"; then
      selected_pkg_dir="$pkg_dir"
      break
    fi
  done

  [[ -n "${selected_pkg_dir:-}" ]] || die "$(l10n "錯誤：無法從任何候選目錄下載 bbrv3 SHA256SUMS：$(join_words "${pkg_candidates[@]}")" "Error: could not download bbrv3 SHA256SUMS from any candidate directory: $(join_words "${pkg_candidates[@]}")")"
  pkg_base="$RAW_BASE/bbrv3/$selected_pkg_dir"
  note "$(l10n "已選擇 bbrv3 套件目錄：bbrv3/$selected_pkg_dir" "Selected bbrv3 package directory: bbrv3/$selected_pkg_dir")"

  local package_names
  package_names="$(extract_checksum_filename SHA256SUMS)" || die "Unsafe package checksum filename"
  [[ "$(grep -c '^linux-headers-' <<<"$package_names")" == 1 && "$(grep -c '^linux-image-' <<<"$package_names")" == 1 ]] || die "Ambiguous package checksums"
  headers_deb="$(grep '^linux-headers-' <<<"$package_names")"
  image_deb="$(grep '^linux-image-' <<<"$package_names")"

  [[ -n "$headers_deb" && -n "$image_deb" ]] || die "$(l10n "錯誤：無法從 SHA256SUMS 辨識 linux-headers/linux-image 套件。" "Error: could not identify linux-headers/linux-image packages from SHA256SUMS.")"

  fetch "$pkg_base/$headers_deb" "$headers_deb"
  fetch "$pkg_base/$image_deb" "$image_deb"

  sha_selected="SHA256SUMS.selected"
  write_selected_sha256sums "SHA256SUMS" "$sha_selected" "$headers_deb" "$image_deb"
  [[ -s "$sha_selected" ]] || die "$(l10n "錯誤：無法產生待校驗檔案清單。" "Error: could not create the checksum file list.")"

  sha256sum -c "$sha_selected" >/dev/null || die "$(l10n "錯誤：SHA256 校驗失敗。" "Error: SHA256 verification failed.")"
  note "$(l10n "bbrv3 核心套件已下載並完成校驗。" "bbrv3 kernel packages downloaded and verified.")"

  kernel_release="$(dpkg-deb --field "$image_deb" Package)" || return $?
  [[ "$kernel_release" == linux-image-* ]] || die "Invalid BBRv3 kernel package name"
  kernel_release="${kernel_release#linux-image-}"
  kernel_release="${kernel_release#unsigned-}"
  [[ "$kernel_release" =~ ^[A-Za-z0-9][A-Za-z0-9.+_~-]*$ && ${#kernel_release} -le 255 ]] || die "Invalid BBRv3 kernel release"

  separator
  info "$(l10n "正在安裝 bbrv3 核心套件..." "Installing bbrv3 kernel packages...")"
  apt-get install -y "./$image_deb" "./$headers_deb"

  if command -v update-grub >/dev/null 2>&1; then
    update-grub >/dev/null
  fi

  remove_managed_module_autoload
  # BBRv3 kernel packages expose the congestion control as bbr.
  configure_sysctl_cc "bbr"

  if [[ -n "${BBR_KERNEL_RESULT_FILE:-}" ]]; then
    local result_parent result_tmp
    result_parent="$(dirname -- "$BBR_KERNEL_RESULT_FILE")" || return $?
    work_path_safe "$result_parent" && [[ -d "$result_parent" && "$(stat -c '%u:%a' -- "$result_parent")" == 0:700 ]] || die "Unsafe BBR kernel result directory"
    [[ -f "/boot/vmlinuz-$kernel_release" && ! -L "$BBR_KERNEL_RESULT_FILE" ]] || die "BBRv3 kernel result could not be verified"
    result_tmp="$(mktemp "$result_parent/.bbr-kernel.XXXXXX")" || return $?
    if ! printf '%s\n' "$kernel_release" >"$result_tmp" || ! mv -Tf -- "$result_tmp" "$BBR_KERNEL_RESULT_FILE"; then
      rm -f -- "$result_tmp"
      return 1
    fi
  fi

  separator
  info "$(l10n "bbrv3 核心套件已成功安裝。請重新開機以進入 bbrv3 核心。" "bbrv3 kernel packages were installed successfully. Reboot to enter the bbrv3 kernel.")"
  note "$(l10n "重新開機後可使用：uname -r && sysctl net.ipv4.tcp_congestion_control" "After reboot, verify with: uname -r && sysctl net.ipv4.tcp_congestion_control")"
}

check_kernel_for_dkms() {
  [[ "$KERNEL_BASE" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "$(l10n "錯誤：無法解析目前核心版本：$KERNEL" "Error: could not parse the current kernel version: $KERNEL")"

  if ! dpkg --compare-versions "$KERNEL_BASE" ge "$KERNEL_MIN_VERSION" \
    || ! dpkg --compare-versions "$KERNEL_BASE" le "$KERNEL_MAX_VERSION"; then
    die "$(l10n "錯誤：DKMS 模組僅支援核心版本 [$KERNEL_MIN_VERSION - 7.1.x]。目前核心：$KERNEL" "Error: DKMS modules support kernel versions [$KERNEL_MIN_VERSION - 7.1.x] only. Current kernel: $KERNEL")"
  fi
}

ensure_build_prereqs() {
  local packages=()

  command -v dkms >/dev/null 2>&1 || packages+=(dkms)
  command -v make >/dev/null 2>&1 || packages+=(build-essential)
  command -v gcc >/dev/null 2>&1 || packages+=(build-essential)
  command -v modprobe >/dev/null 2>&1 || packages+=(kmod)
  command -v sha256sum >/dev/null 2>&1 || packages+=(coreutils)

  if ((${#packages[@]})); then
    info "$(l10n "正在安裝建置相依套件：$(join_words "${packages[@]}")" "Installing build dependencies: $(join_words "${packages[@]}")")"
    apt_install "${packages[@]}"
  fi
}

resolve_generic_kernel_packages() {
  case "$OS_ID" in
    debian)
      case "$OS_ARCH" in
        amd64 | x86_64)
          printf '%s\n' "linux-image-amd64" "linux-headers-amd64"
          ;;
        arm64 | aarch64)
          printf '%s\n' "linux-image-arm64" "linux-headers-arm64"
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    ubuntu)
      printf '%s\n' "linux-image-generic" "linux-headers-generic"
      ;;
    *)
      return 1
      ;;
  esac
}

install_generic_kernel_and_exit() {
  local image_pkg headers_pkg generic_output
  local -a generic_packages=()

  if ! generic_output="$(resolve_generic_kernel_packages)"; then
    die "$(l10n "錯誤：找不到適用於 ${OS_NAME:-$OS_ID} ${OS_ARCH:-unknown} 的通用核心/標頭檔套件。請手動安裝與目前核心相符的 headers 套件。" "Error: no generic kernel/header packages found for ${OS_NAME:-$OS_ID} ${OS_ARCH:-unknown}. Manually install headers matching the current kernel.")"
  fi
  mapfile -t generic_packages <<<"$generic_output"

  image_pkg="${generic_packages[0]:-}"
  headers_pkg="${generic_packages[1]:-}"
  [[ -n "$image_pkg" && -n "$headers_pkg" ]] || die "$(l10n "錯誤：無法解析通用核心/標頭檔套件名稱。" "Error: could not resolve generic kernel/header package names.")"

  separator
  warn "$(l10n "警告：找不到或無法使用目前執行中核心的標頭檔：linux-headers-${KERNEL}" "Warning: headers for the running kernel were not found or are not usable: linux-headers-${KERNEL}")"
  note "$(l10n "可改為安裝發行版通用核心映像與標頭檔：" "You can install the distribution generic kernel image and headers instead:")"
  note "$(l10n "  核心映像：$image_pkg" "  Kernel image: $image_pkg")"
  note "$(l10n "  核心標頭檔：$headers_pkg" "  Kernel headers: $headers_pkg")"
  warn "$(l10n "安裝後必須重新開機進入新核心，然後重新執行本腳本，DKMS 模組才能繼續編譯安裝。" "After installation, reboot into the new kernel and rerun this script before the DKMS module can be built and installed.")"

  info "$(l10n "正在自動安裝通用核心映像與標頭檔：$image_pkg $headers_pkg" "Automatically installing generic kernel image and headers: $image_pkg $headers_pkg")"
  apt_install "$image_pkg" "$headers_pkg" || die "$(l10n "錯誤：安裝通用核心/標頭檔失敗：$image_pkg $headers_pkg" "Error: failed to install generic kernel/headers: $image_pkg $headers_pkg")"
  if command -v update-grub >/dev/null 2>&1; then
    update-grub >/dev/null || warn "$(l10n "警告：update-grub 執行失敗，請確認開機載入器設定。" "Warning: update-grub failed; check the bootloader configuration.")"
  fi
  separator
  info "$(l10n "通用核心映像與標頭檔已安裝。" "Generic kernel image and headers were installed.")"
  note "$(l10n "請現在重新開機，然後重新執行本腳本。" "Reboot now, then rerun this script.")"
  note "$(l10n "重新開機後可使用：uname -r && ls -l /lib/modules/\$(uname -r)/build" "After reboot, verify with: uname -r && ls -l /lib/modules/\$(uname -r)/build")"
  note "$(l10n "重新執行範例：./$SCRIPT_NAME --algo $ALGO" "Rerun example: ./$SCRIPT_NAME --algo $ALGO")"
  exit 0
}

ensure_kernel_headers() {
  local build_dir headers_dir
  build_dir="/lib/modules/${KERNEL}/build"
  headers_dir="/usr/src/linux-headers-${KERNEL}"

  if [[ ! -e "$build_dir" && -d "$headers_dir" ]]; then
    mkdir -p -- "/lib/modules/${KERNEL}"
    ln -s -- "$headers_dir" "$build_dir"
  fi

  if [[ -e "$build_dir/Makefile" ]]; then
    note "$(l10n "偵測到目前核心標頭檔：$build_dir" "Detected current kernel headers: $build_dir")"
    return 0
  fi

  info "$(l10n "正在安裝目前核心標頭檔：linux-headers-${KERNEL}" "Installing current kernel headers: linux-headers-${KERNEL}")"
  if apt_install "linux-headers-${KERNEL}"; then
    if [[ ! -e "$build_dir" && -d "$headers_dir" ]]; then
      mkdir -p -- "/lib/modules/${KERNEL}"
      ln -s -- "$headers_dir" "$build_dir"
    fi

    if [[ -e "$build_dir/Makefile" ]]; then
      note "$(l10n "目前核心標頭檔檢查通過：$build_dir" "Current kernel header check passed: $build_dir")"
      return 0
    fi

    warn "$(l10n "警告：linux-headers-${KERNEL} 已安裝/已嘗試安裝，但 $build_dir 無法供 DKMS 使用。" "Warning: linux-headers-${KERNEL} was installed or attempted, but $build_dir is not usable for DKMS.")"
  else
    warn "$(l10n "警告：找不到或無法安裝目前執行中核心的標頭檔套件：linux-headers-${KERNEL}。" "Warning: could not find or install the running kernel headers package: linux-headers-${KERNEL}.")"
  fi

  install_generic_kernel_and_exit
}

remove_existing_dkms_module() {
  local module="$1"
  local installed_ver_dir installed_ver

  [[ -d "/var/lib/dkms/$module" ]] || return 0

  info "$(l10n "偵測到現有的 $module DKMS 模組，正在移除舊版本..." "Found an existing $module DKMS module; removing old versions...")"
  for installed_ver_dir in "/var/lib/dkms/$module"/*; do
    [[ -d "$installed_ver_dir" ]] || continue
    installed_ver="$(basename -- "$installed_ver_dir")"
    dkms remove -m "$module" -v "$installed_ver" --all >/dev/null || die "$(l10n "錯誤：移除 $module/$installed_ver 失敗。" "Error: failed to remove $module/$installed_ver.")"
  done
}

download_dkms_source() {
  local src_dir="$1"
  mkdir -p -- "$src_dir"

  fetch "$RAW_BASE/$ALGO/tcp_$ALGO.c" "$src_dir/tcp_$ALGO.c"
  fetch "$RAW_BASE/$ALGO/dkms.conf" "$src_dir/dkms.conf"
  fetch "$RAW_BASE/$ALGO/Makefile" "$src_dir/Makefile"
}

install_dkms_bbr() {
  local module_name module_version src_dir dkms_src_dir
  module_name="tcp_${ALGO}"
  module_version="$KERNEL_BASE"
  [[ "$ALGO" != "bbrx_old" ]] || module_version="0.1.0"

  check_kernel_for_dkms
  ensure_build_prereqs
  ensure_kernel_headers
  ensure_download_tools
  note "$(l10n "系統支援檢查通過。" "System support check passed.")"

  create_work_dir
  src_dir="$WORK_DIR_CREATED/src"

  separator
  info "$(l10n "正在下載 $ALGO 擁塞控制模組原始碼..." "Downloading $ALGO congestion-control module source...")"
  download_dkms_source "$src_dir"
  note "$(l10n "原始碼下載完成。" "Source download completed.")"

  separator
  info "$(l10n "正在編譯並安裝 $ALGO 擁塞控制模組..." "Building and installing the $ALGO congestion-control module...")"
  remove_existing_dkms_module "$ALGO"

  dkms_src_dir="/usr/src/${ALGO}-${module_version}"
  rm -rf -- "$dkms_src_dir"
  mkdir -p -- "$dkms_src_dir"
  cp -a "$src_dir/." "$dkms_src_dir/"

  if ! dkms add -m "$ALGO" -v "$module_version" >/dev/null; then
    dkms remove -m "$ALGO" -v "$module_version" --all >/dev/null 2>&1 || true
    die "$(l10n "錯誤：DKMS 無法新增核心模組。" "Error: DKMS could not add the kernel module.")"
  fi

  if ! dkms build -m "$ALGO" -v "$module_version" >/dev/null; then
    dkms remove -m "$ALGO" -v "$module_version" --all >/dev/null 2>&1 || true
    die "$(l10n "錯誤：建置 DKMS 模組失敗。" "Error: DKMS module build failed.")"
  fi

  if ! dkms install -m "$ALGO" -v "$module_version" >/dev/null; then
    dkms remove -m "$ALGO" -v "$module_version" --all >/dev/null 2>&1 || true
    die "$(l10n "錯誤：DKMS 無法安裝核心模組。" "Error: DKMS could not install the kernel module.")"
  fi

  depmod -a "$KERNEL" >/dev/null 2>&1 || true

  if ! modprobe "$module_name"; then
    dkms remove -m "$ALGO" -v "$module_version" --all >/dev/null 2>&1 || true
    die "$(l10n "錯誤：載入模組失敗：$module_name" "Error: failed to load module: $module_name")"
  fi

  separator
  if grep -q "^${module_name}[[:space:]]" /proc/modules; then
    info "$(l10n "$ALGO 擁塞控制模組已成功安裝並載入。通常不需重新開機即可嘗試生效。" "$ALGO congestion-control module was installed and loaded successfully. You can usually try it without rebooting.")"
  else
    dkms remove -m "$ALGO" -v "$module_version" --all >/dev/null 2>&1 || true
    die "$(l10n "錯誤：模組未出現在 /proc/modules：$module_name" "Error: module did not appear in /proc/modules: $module_name")"
  fi

  configure_module_autoload "$module_name"
  configure_sysctl_cc "$ALGO"
}

main() {
  parse_args "$@"

  if [[ "$SHOW_HELP" == "1" ]]; then
    usage
    exit 0
  fi

  if [[ -t 1 && -n "${TERM:-}" ]]; then
    clear
  fi

  choose_algo
  require_root
  require_command apt-get
  require_command dpkg
  require_command uname
  require_command awk
  require_command sed
  require_command grep
  require_command sha256sum
  require_command realpath
  require_command stat
  require_command mktemp
  validate_work_parent

  collect_system_info
  print_system_info

  separator
  info "$(l10n "正在檢查系統支援狀態..." "Checking system support...")"
  check_supported_os
  check_supported_runtime
  apt_update

  if [[ "$ALGO" == "bbrv3" ]]; then
    note "$(l10n "系統支援檢查通過。" "System support check passed.")"
    install_bbrv3_deb
  else
    install_dkms_bbr
  fi
}

main "$@"
