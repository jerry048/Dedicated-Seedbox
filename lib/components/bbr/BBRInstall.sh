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
KERNEL_MIN_VERSION="${BBR_KERNEL_MIN_VERSION:-5.10}"
KERNEL_MAX_VERSION="${BBR_KERNEL_MAX_VERSION:-7.1.999}"
LANG_CODE="${BBR_LANG:-en}"
SHOW_HELP=0

SUPPORTED_ALGOS=("bbrv3" "bbrx" "bbrw" "bbr_brutal" "bbrw_brutal")
WORK_DIR_CREATED=""
WORK_DIR_IS_AUTO=0

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

info() { printf '%s%s%s\n' "$COLOR_INFO" "$*" "$COLOR_RESET"; }
note() { printf '%s%s%s\n' "$COLOR_NOTE" "$*" "$COLOR_RESET"; }
warn() { printf '%s%s%s\n' "$COLOR_WARN" "$*" "$COLOR_RESET" >&2; }
fail() { printf '%s%s%s\n' "$COLOR_FAIL" "$*" "$COLOR_RESET" >&2; }
die() { fail "$*"; exit 1; }

normalize_lang() {
	case "${1:-en}" in
		en|en-US|en_US|en-us|en_us) printf '%s' "en" ;;
		zh|zh-TW|zh_TW|zh-tw|zh_tw|zh-Hant|zh_Hant|zh-hant|zh_hant|tw|traditional|traditional-chinese) printf '%s' "zh-TW" ;;
		*) return 1 ;;
	esac
}

set_language() {
	local requested="${1:-en}" normalized
	if ! normalized="$(normalize_lang "$requested")"; then
		die "Error: unsupported language: $requested (supported: en, zh-TW)"
	fi
	LANG_CODE="$normalized"
}

l10n() {
	local zh_tw="$1" en="$2"
	if [[ "$LANG_CODE" == "zh-TW" ]]; then
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

	if [[ "$LANG_CODE" == "zh-TW" ]]; then
		cat <<USAGE
用法: $SCRIPT_NAME [選項]

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
Usage: $SCRIPT_NAME [options]

Options:
  --algo ALGO           Install one of: $algos
  --raw-base URL        Override source base URL. Can also use RAW_BASE=...
  --lang LANG           Output language: en (default), zh-TW. Can also use BBR_LANG=...
  --force-runtime       Continue in unsupported runtimes such as containers/WSL
  -h, --help            Show this help

Environment overrides:
  BBR_LANG=en|zh-TW, BBR_ALGO, RAW_BASE,
  BBR_SYSCTL_DROPIN, BBR_SYSCTL_LEGACY_FILE,
  BBR_MODULES_LOAD_DROPIN, BBR_FORCE_UNSUPPORTED_RUNTIME=1,
  BBR_WORK_DIR, BBR_CLEAN_WORK_DIR=0,
  BBR_KERNEL_MIN_VERSION, BBR_KERNEL_MAX_VERSION, NO_COLOR=1
USAGE
	fi
}

cleanup() {
	if [[ -z "$WORK_DIR_CREATED" || ! -d "$WORK_DIR_CREATED" ]]; then
		return 0
	fi

	if [[ "$CLEAN_WORK_DIR" == "1" || ( "$CLEAN_WORK_DIR" == "auto" && "$WORK_DIR_IS_AUTO" == "1" ) ]]; then
		rm -rf -- "$WORK_DIR_CREATED"
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
			-h|--help)
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
				11|12|13) ;;
				*) die "$(l10n "錯誤：本腳本僅支援 Debian 11/12/13。目前版本：${OS_VERSION_ID:-unknown}" "Error: this script supports Debian 11/12/13 only. Current version: ${OS_VERSION_ID:-unknown}")" ;;
			esac
			;;
		ubuntu)
			case "$OS_VERSION_ID" in
				22.04*|24.04*|26.04*) ;;
				*) die "$(l10n "錯誤：本腳本僅支援 Ubuntu 22.04/24.04/26.04。目前版本：${OS_VERSION_ID:-unknown}" "Error: this script supports Ubuntu 22.04/24.04/26.04 only. Current version: ${OS_VERSION_ID:-unknown}")" ;;
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

	rm -f -- "$output"
	if command -v curl >/dev/null 2>&1; then
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

create_work_dir() {
	if [[ -n "$WORK_DIR_CREATED" ]]; then
		return 0
	fi

	if [[ -n "$WORK_DIR" ]]; then
		mkdir -p -- "$WORK_DIR"
		WORK_DIR_CREATED="$WORK_DIR"
		WORK_DIR_IS_AUTO=0
	else
		WORK_DIR_CREATED="$(mktemp -d -t bbr-install.XXXXXX)"
		WORK_DIR_IS_AUTO=1
	fi
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

	cat > "$SYSCTL_DROPIN" <<EOF_SYSCTL
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
	cat > "$MODULES_LOAD_DROPIN" <<EOF_MODULES
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
		amd64|x86_64)
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
		arm64|aarch64)
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
	awk '{print $2}' "$1" | sed -e 's#^\*##' -e 's#^\./##'
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
	' "$checksum_file" > "$output_file"
}

install_bbrv3_deb() {
	local pkg_dir pkg_base selected_pkg_dir work headers_deb image_deb sha_selected
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

	headers_deb="$(extract_checksum_filename SHA256SUMS | grep -E '^linux-headers-.*\.deb$' | head -n 1 || true)"
	image_deb="$(extract_checksum_filename SHA256SUMS | grep -E '^linux-image-.*\.deb$' | head -n 1 || true)"

	[[ -n "$headers_deb" && -n "$image_deb" ]] || die "$(l10n "錯誤：無法從 SHA256SUMS 辨識 linux-headers/linux-image 套件。" "Error: could not identify linux-headers/linux-image packages from SHA256SUMS.")"

	fetch "$pkg_base/$headers_deb" "$headers_deb"
	fetch "$pkg_base/$image_deb" "$image_deb"

	sha_selected="SHA256SUMS.selected"
	write_selected_sha256sums "SHA256SUMS" "$sha_selected" "$headers_deb" "$image_deb"
	[[ -s "$sha_selected" ]] || die "$(l10n "錯誤：無法產生待校驗檔案清單。" "Error: could not create the checksum file list.")"

	sha256sum -c "$sha_selected" >/dev/null || die "$(l10n "錯誤：SHA256 校驗失敗。" "Error: SHA256 verification failed.")"
	note "$(l10n "bbrv3 核心套件已下載並完成校驗。" "bbrv3 kernel packages downloaded and verified.")"

	separator
	info "$(l10n "正在安裝 bbrv3 核心套件..." "Installing bbrv3 kernel packages...")"
	apt-get install -y "./$image_deb" "./$headers_deb"

	if command -v update-grub >/dev/null 2>&1; then
		update-grub >/dev/null
	fi

	remove_managed_module_autoload
	# BBRv3 kernel packages expose the congestion control as bbr.
	configure_sysctl_cc "bbr"

	separator
	info "$(l10n "bbrv3 核心套件已成功安裝。請重新開機以進入 bbrv3 核心。" "bbrv3 kernel packages were installed successfully. Reboot to enter the bbrv3 kernel.")"
	note "$(l10n "重新開機後可使用：uname -r && sysctl net.ipv4.tcp_congestion_control" "After reboot, verify with: uname -r && sysctl net.ipv4.tcp_congestion_control")"
}

check_kernel_for_dkms() {
	[[ "$KERNEL_BASE" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "$(l10n "錯誤：無法解析目前核心版本：$KERNEL" "Error: could not parse the current kernel version: $KERNEL")"

	if ! dpkg --compare-versions "$KERNEL_BASE" ge "$KERNEL_MIN_VERSION" || \
	   ! dpkg --compare-versions "$KERNEL_BASE" le "$KERNEL_MAX_VERSION"; then
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
				amd64|x86_64)
					printf '%s\n' "linux-image-amd64" "linux-headers-amd64"
					;;
				arm64|aarch64)
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
	mapfile -t generic_packages <<< "$generic_output"

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
