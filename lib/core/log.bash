# Logging and user-facing output helpers for seedboxctl.

if [[ -n "${SEEDBOX_CORE_LOG_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_LOG_SOURCED=1

: "${SEEDBOX_LOG_BASE:=}"
: "${SEEDBOX_COLOR:=auto}"

declare -g SEEDBOX_LOG_FILE="${SEEDBOX_LOG_FILE:-}"
declare -g SEEDBOX_STEP_DIR="${SEEDBOX_STEP_DIR:-}"
declare -g SEEDBOX_LOG_INITIALIZED="${SEEDBOX_LOG_INITIALIZED:-0}"
declare -g SEEDBOX_STEP_INDEX=0

declare -g UI_COLOR_CHECKED="${UI_COLOR_CHECKED:-0}"
declare -g UI_COLOR_SUPPORTED="${UI_COLOR_SUPPORTED:-0}"


declare -g SEEDBOX_LANG="${SEEDBOX_LANG:-en}"

ui::normalize_lang() {
  local value="${1:-en}"
  value="${value,,}"
  value="${value//_/-}"
  case "${value}" in
    en|en-us|english) printf 'en\n' ;;
    zh|zh-cn|zh-hans|cn|sc|simplified|simplified-chinese|chinese) printf 'zh-CN\n' ;;
    *) return 1 ;;
  esac
}

ui::set_lang() {
  local normalized
  normalized="$(ui::normalize_lang "${1:-en}")" || {
    printf 'Error: unsupported language: %s (supported: en, zh-CN)\n' "${1:-}" >&2
    return 2
  }
  SEEDBOX_LANG="${normalized}"
  export SEEDBOX_LANG
}

ui::zh() {
  [[ "${SEEDBOX_LANG}" == "zh-CN" ]]
}

ui::tr() {
  local zh="$1" en="$2"
  if ui::zh; then
    printf '%s' "${zh}"
  else
    printf '%s' "${en}"
  fi
}

ui::translate() {
  local text="$*"
  if ! ui::zh; then
    printf '%s' "${text}"
    return 0
  fi

  case "${text}" in
    "OK") printf '完成' ;;
    "FAIL") printf '失败' ;;
    "Installer log") printf '日志' ;;

    "Preflight checks") printf '安装前检查' ;;
    "Install packages") printf '安装软件包' ;;
    "Install/check required packages") printf '安装/检查所需软件包' ;;
    "Install/check upgrade dependencies") printf '安装/检查升级依赖' ;;
    "Create/verify user paths") printf '创建/检查用户路径' ;;
    "Install/locate qBittorrent binary") printf '安装/定位 qBittorrent 二进制' ;;
    "Write qBittorrent config") printf '写入 qBittorrent 配置' ;;
    "Configure/start qBittorrent service") printf '配置/启动 qBittorrent 服务' ;;
    "Healthcheck qBittorrent") printf 'qBittorrent 健康检查' ;;
    "Save instance state") printf '保存实例状态' ;;
    "Prepare config password/hash update") printf '准备配置密码/哈希更新' ;;
    "Install new qBittorrent binary") printf '安装新的 qBittorrent 二进制' ;;
    "Stop qBittorrent") printf '停止 qBittorrent' ;;
    "Rewrite qBittorrent config") printf '重写 qBittorrent 配置' ;;
    "Update systemd service") printf '更新 systemd 服务' ;;
    "Update user systemd service") printf '更新用户 systemd 服务' ;;
    "Start upgraded qBittorrent") printf '启动升级后的 qBittorrent' ;;
    "Healthcheck upgraded qBittorrent") printf '检查升级后的 qBittorrent 健康状态' ;;
    "Update instance state") printf '更新实例状态' ;;
    "Disable systemd service") printf '禁用 systemd 服务' ;;

    "Install tuning dependencies") printf '安装调优依赖' ;;
    "Write/apply sysctl config") printf '写入/应用 sysctl 配置' ;;
    "Write file-open limits") printf '写入文件打开数限制' ;;
    "Write runtime tuning defaults") printf '写入运行时调优默认值' ;;
    "Write runtime tuning script") printf '写入运行时调优脚本' ;;
    "Apply boot-time/runtime tuning") printf '应用启动/运行时调优' ;;
    "Save tuning state") printf '保存调优状态' ;;

    "Remove conflicting Docker packages") printf '删除冲突的 Docker 软件包' ;;
    "Install Docker from official repo") printf '从官方仓库安装 Docker' ;;
    "Install Docker from distro repo") printf '从发行版仓库安装 Docker' ;;
    "Enable/start Docker") printf '启用/启动 Docker' ;;
    "Save Docker state") printf '保存 Docker 状态' ;;
    "Stop Docker") printf '停止 Docker' ;;
    "Disable Docker") printf '禁用 Docker' ;;

    "Preflight BBR installer") printf 'BBR 安装前检查' ;;
    "Prepare DKMS kernel headers") printf '准备 DKMS 内核头文件' ;;
    "Save pending BBR state") printf '保存待完成的 BBR 状态' ;;
    "Download BBR installer") printf '下载 BBR 安装器' ;;
    "Run BBR installer") printf '运行 BBR 安装器' ;;
    "Save BBR state") printf '保存 BBR 状态' ;;
    "Remove DKMS module if present") printf '删除已有 DKMS 模块' ;;

    "Installing Docker") printf '正在安装 Docker' ;;
    "Docker status") printf 'Docker 状态' ;;
    "Uninstalling Docker") printf '正在卸载 Docker' ;;
    "Installing qBittorrent") printf '正在安装 qBittorrent' ;;
    "qBittorrent installed") printf 'qBittorrent 已安装' ;;
    "qBittorrent sources") printf 'qBittorrent 来源' ;;
    "Uninstalling BBR configuration") printf '正在卸载 BBR 配置' ;;
    "Installing BBR congestion-control variant") printf '正在安装 BBR 拥塞控制变体' ;;
    "BBR status") printf 'BBR 状态' ;;
    "Applying adaptive seedbox tuning") printf '正在应用自适应 seedbox 调优' ;;
    "Seedbox tuning status") printf 'Seedbox 调优状态' ;;
    "Seedbox status") printf 'Seedbox 状态' ;;
    "Seedbox doctor") printf 'Seedbox 诊断' ;;
    "Shared seedbox qBittorrent install") printf '共享 seedbox qBittorrent 安装' ;;

    "User") printf '用户' ;;
    "Port") printf '端口' ;;
    "Image") printf '镜像' ;;
    "Data") printf '数据目录' ;;
    "Source") printf '来源' ;;
    "Version") printf '版本' ;;
    "Algorithm") printf '算法' ;;
    "Installer") printf '安装器' ;;
    "Unix user") printf 'Unix 用户' ;;
    "WebUI user") printf 'WebUI 用户' ;;
    "WebUI") printf 'WebUI' ;;
    "Mode") printf '模式' ;;
    "Install mode") printf '安装模式' ;;
    "Service mode") printf '服务模式' ;;
    "WebUI port") printf 'WebUI 端口' ;;
    "Incoming port") printf '传入端口' ;;
    "qBittorrent tuning") printf 'qBittorrent 调优' ;;
    "Config") printf '配置' ;;
    "Service") printf '服务' ;;
    "Screen") printf 'Screen 会话' ;;
    "Restart script") printf '重启脚本' ;;
    "From") printf '从' ;;
    "To") printf '到' ;;
    "State") printf '状态' ;;
    "Active") printf '当前' ;;
    "Available") printf '可用' ;;
    "Storage") printf '存储' ;;
    "Interface") printf '网卡' ;;
    "Log") printf '日志' ;;
    "State dir") printf '状态目录' ;;
    "Doctor bundle") printf '诊断包' ;;

    "Unknown qBittorrent command: "*) printf '未知 qBittorrent 命令：%s' "${text#Unknown qBittorrent command: }" ;;
    "Unknown docker command: "*) printf '未知 Docker 命令：%s' "${text#Unknown docker command: }" ;;
    "Unknown bbr command: "*) printf '未知 BBR 命令：%s' "${text#Unknown bbr command: }" ;;
    "Unknown tuning command: "*) printf '未知 tuning 命令：%s' "${text#Unknown tuning command: }" ;;
    "Unsupported BBR algorithm: "*) printf '不支持的 BBR 算法：%s' "${text#Unsupported BBR algorithm: }" ;;
    "Missing --bbr-algo") printf '缺少 --bbr-algo' ;;
    "Invalid cache size: "*) printf '无效的缓存大小：%s' "${text#Invalid cache size: }" ;;
    "Invalid WebUI port: "*) printf '无效的 WebUI 端口：%s' "${text#Invalid WebUI port: }" ;;
    "Invalid incoming port: "*) printf '无效的传入端口：%s' "${text#Invalid incoming port: }" ;;
    "Invalid WebUI username.") printf '无效的 WebUI 用户名。' ;;
    "Invalid qBittorrent source: "*) printf '无效的 qBittorrent 来源：%s' "${text#Invalid qBittorrent source: }" ;;
    "Invalid rootless service mode: "*) printf '无效的 rootless 服务模式：%s' "${text#Invalid rootless service mode: }" ;;
    "Invalid service mode: "*) printf '无效的服务模式：%s' "${text#Invalid service mode: }" ;;
    "Invalid qBittorrent tuning profile: "*) printf '无效的 qBittorrent 调优 profile：%s' "${text#Invalid qBittorrent tuning profile: }" ;;
    "No qBittorrent state found for user "*)
      local who="${text#No qBittorrent state found for user }"
      who="${who%.}"
      printf '未找到用户 %s 的 qBittorrent 状态。' "${who}"
      ;;
    "No qBittorrent state found for "*)
      local who="${text#No qBittorrent state found for }"
      who="${who%.}"
      printf '未找到 %s 的 qBittorrent 状态。' "${who}"
      ;;
    "Upgrading qBittorrent for "*) printf '正在为 %s 升级 qBittorrent' "${text#Upgrading qBittorrent for }" ;;
    "Uninstalling qBittorrent for "*) printf '正在为 %s 卸载 qBittorrent' "${text#Uninstalling qBittorrent for }" ;;
    "Upgrade failed. Rolling back to previous binary.") printf '升级失败，正在回滚到之前的二进制。' ;;
    "Rootless upgrade can only manage the current Unix user's qBittorrent instance.") printf 'Rootless 升级只能管理当前 Unix 用户的 qBittorrent 实例。' ;;
    "Rootless uninstall can only manage the current Unix user's qBittorrent instance.") printf 'Rootless 卸载只能管理当前 Unix 用户的 qBittorrent 实例。' ;;
    "qBittorrent upgrade completed for "*)
      local who="${text#qBittorrent upgrade completed for }"
      who="${who%. Config file was rewritten for the selected version.}"
      printf '已为 %s 完成 qBittorrent 升级。配置文件已按所选版本重写。' "${who}"
      ;;
    "Uninstalled qBittorrent startup files for "*)
      local who="${text#Uninstalled qBittorrent startup files for }"
      who="${who%. Config/data kept.}"
      printf '已卸载 %s 的 qBittorrent 启动文件。配置/数据已保留。' "${who}"
      ;;

    "APT is required for Docker installation.") printf '安装 Docker 需要 APT。' ;;
    "Could not determine OS codename for Docker repo.") printf '无法确定 Docker 仓库所需的系统代号。' ;;
    "Invalid --docker-source: "*) printf '无效的 --docker-source：%s' "${text#Invalid --docker-source: }" ;;
    "Official Docker repo install failed. Falling back to distro docker.io.") printf '官方 Docker 仓库安装失败，回退到发行版 docker.io。' ;;
    "Docker installed."*) printf 'Docker 已安装。请注意，Docker 发布端口可能绕过 ufw 等主机防火墙工具，除非另行处理。' ;;
    "docker command not found.") printf '未找到 docker 命令。' ;;
    "Use --yes with --purge for Docker.") printf '清理 Docker 时必须同时传入 --yes。' ;;
    "Purge will remove Docker packages"*) printf '清理将删除 Docker 软件包和 Docker 运行时数据：/var/lib/docker /var/lib/containerd' ;;
    "Docker uninstall completed.") printf 'Docker 卸载完成。' ;;

    "APT/dpkg lock is still held after "*) printf 'APT/dpkg 锁等待超时：%s' "${text#APT/dpkg lock is still held after }" ;;
    "apt-get/dpkg-query not found") printf '未找到 apt-get/dpkg-query' ;;
    "Unsupported Debian version: "*) printf '不支持的 Debian 版本：%s' "${text#Unsupported Debian version: }" ;;
    "Supported Debian versions:"*) printf '支持的 Debian 版本：11 或更新版本，包括 12 和 13。' ;;
    "Unsupported Ubuntu version: "*) printf '不支持的 Ubuntu 版本：%s' "${text#Unsupported Ubuntu version: }" ;;
    "Supported Ubuntu versions:"*) printf '支持的 Ubuntu 版本：20.04 或更新版本，包括 24.04 和 26.04。' ;;
    "Unsupported OS: "*) printf '不支持的系统：%s' "${text#Unsupported OS: }" ;;
    "Only modern Debian and Ubuntu are supported.") printf '仅支持较新的 Debian 和 Ubuntu。' ;;
    "Unsupported CPU architecture: "*) printf '不支持的 CPU 架构：%s' "${text#Unsupported CPU architecture: }" ;;
    "Supported architectures:"*) printf '支持的架构：amd64/x86_64 和 arm64/aarch64。' ;;
    "This command must be run as root.") printf '此命令必须以 root 身份运行。' ;;
    "Cause: not automatically identified. Review the step log below.") printf '原因：未能自动识别。请查看下面的步骤日志。' ;;
    "Cause: "*) printf '原因：%s' "${text#Cause: }" ;;
    "Step log: "*) printf '步骤日志：%s' "${text#Step log: }" ;;
    "Service logs: "*) printf '服务日志：%s' "${text#Service logs: }" ;;
    "Download failed: "*) printf '下载失败：%s' "${text#Download failed: }" ;;
    "Neither curl nor wget is installed.") printf '未安装 curl 或 wget。' ;;
    "Downloaded artifact checksum verification failed: "*) printf '下载文件校验失败：%s' "${text#Downloaded artifact checksum verification failed: }" ;;
    "Refusing unverified download: "*) printf '拒绝未校验的下载：%s' "${text#Refusing unverified download: }" ;;
    "Unverified download allowed: "*) printf '已允许未校验下载：%s' "${text#Unverified download allowed: }" ;;
    "Unknown logs component: "*) printf '未知日志组件：%s' "${text#Unknown logs component: }" ;;
    "APT is not available.") printf 'APT 不可用。' ;;
    "Neither curl nor wget is available.") printf 'curl 和 wget 都不可用。' ;;
    "Doctor result: OK") printf '诊断结果：正常' ;;
    "Doctor result: warnings or failures found") printf '诊断结果：发现警告或失败' ;;
    "systemd was not detected."*) printf '未检测到 systemd。qBittorrent 请使用 --service-mode screen 或 --service-mode daemon，或在 systemd 主机上运行。' ;;
    "Could not determine home directory for "*)
      local who="${text#Could not determine home directory for }"
      who="${who%.}"
      printf '无法确定 %s 的 HOME 目录。' "${who}"
      ;;

    "Invalid network interface: "*) printf '无效的网卡：%s' "${text#Invalid network interface: }" ;;
    "Allowed format: auto or"*) printf '允许的格式：auto 或 ^[A-Za-z0-9_.:-]{1,15}$' ;;
    "Invalid link speed: "*) printf '无效的链路速度：%s' "${text#Invalid link speed: }" ;;
    "Invalid storage class: "*) printf '无效的存储类型：%s' "${text#Invalid storage class: }" ;;
    "Invalid txqueuelen: "*) printf '无效的 txqueuelen：%s' "${text#Invalid txqueuelen: }" ;;
    "Invalid initial-cwnd: "*) printf '无效的 initial-cwnd：%s' "${text#Invalid initial-cwnd: }" ;;
    "Skipping sysctl tuning by request.") printf '已按要求跳过 sysctl 调优。' ;;
    "Skipping limits tuning by request.") printf '已按要求跳过 limits 调优。' ;;
    "Seedbox tuning applied.") printf 'Seedbox 调优已应用。' ;;
    "Seedbox tuning files removed."*) printf 'Seedbox 调优文件已删除。可能需要重启才能完全恢复运行时参数。' ;;
    "No /etc/default/seedbox-tuning found.") printf '未找到 /etc/default/seedbox-tuning。' ;;
    "No seedbox sysctl file found.") printf '未找到 seedbox sysctl 文件。' ;;

    *) printf '%s' "${text}" ;;
  esac
}


log::timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log::default_base() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    printf '%s\n' "/var/log/seedbox"
  else
    printf '%s\n' "${HOME}/.local/state/seedbox/logs"
  fi
}

log::init() {
  local action="${1:-run}"
  if [[ "${SEEDBOX_LOG_INITIALIZED}" == "1" ]]; then
    return 0
  fi

  local base stamp safe_action
  base="${SEEDBOX_LOG_BASE:-$(log::default_base)}"
  stamp="$(date '+%Y%m%d-%H%M%S')"
  safe_action="${action//[^a-zA-Z0-9_.-]/-}"

  mkdir -p "${base}/steps"
  chmod 700 "${base}" "${base}/steps" 2>/dev/null || true

  SEEDBOX_LOG_FILE="${base}/${safe_action}-${stamp}.log"
  SEEDBOX_STEP_DIR="${base}/steps/${safe_action}-${stamp}"
  mkdir -p "${SEEDBOX_STEP_DIR}"
  chmod 700 "${SEEDBOX_STEP_DIR}" 2>/dev/null || true
  : >"${SEEDBOX_LOG_FILE}"
  chmod 600 "${SEEDBOX_LOG_FILE}" 2>/dev/null || true
  ln -sfn "${SEEDBOX_LOG_FILE}" "${base}/latest.log" 2>/dev/null || true

  SEEDBOX_LOG_INITIALIZED=1
  log::info "seedboxctl log started: action=${action} pid=$$ user=$(id -un 2>/dev/null || printf unknown)"
}

log::line() {
  local level="$1"; shift
  local msg="$*"
  if [[ -n "${SEEDBOX_LOG_FILE}" ]]; then
    printf '%s [%s] %s\n' "$(log::timestamp)" "${level}" "${msg}" >>"${SEEDBOX_LOG_FILE}"
  fi
}

log::info() { log::line INFO "$@"; }
log::warn() { log::line WARN "$@"; }
log::error() { log::line ERROR "$@"; }

ui::supports_color_uncached() {
  case "${SEEDBOX_COLOR}" in
    always) ;;
    never) return 1 ;;
    auto|"")
      [[ -z "${NO_COLOR:-}" ]] || return 1
      [[ -t 1 ]] || return 1
      ;;
    *)
      # Unknown value: be safe and behave like auto.
      [[ -z "${NO_COLOR:-}" ]] || return 1
      [[ -t 1 ]] || return 1
      ;;
  esac

  [[ -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 1
  command -v tput >/dev/null 2>&1 || return 1

  local colors sample
  colors="$(tput colors 2>/dev/null || printf '0')"
  [[ "${colors}" =~ ^[0-9]+$ && "${colors}" -ge 8 ]] || return 1

  sample="$(tput setaf 1 2>/dev/null || true)"
  [[ "${sample}" != *'%p1'* && "${sample}" != *'%{'* && "${sample}" != *'%t'* ]] || return 1

  return 0
}

ui::supports_color() {
  if [[ "${UI_COLOR_CHECKED}" != "1" ]]; then
    if ui::supports_color_uncached; then
      UI_COLOR_SUPPORTED=1
    else
      UI_COLOR_SUPPORTED=0
    fi
    UI_COLOR_CHECKED=1
  fi

  [[ "${UI_COLOR_SUPPORTED}" == "1" ]]
}

ui::color() {
  local cap="${1:-}"
  [[ -n "${cap}" ]] || return 0
  shift || true

  ui::supports_color || return 0

  case "${cap}" in
    setaf|setab)
      [[ "$#" -eq 1 && "${1}" =~ ^[0-9]+$ ]] || return 0
      ;;
    sgr0|bold|dim|smul|rmul|sitm|ritm|rev)
      [[ "$#" -eq 0 ]] || return 0
      ;;
    *)
      # Do not pass arbitrary capabilities through from callers. This keeps
      # user-facing color output predictable and avoids noisy terminal garbage.
      return 0
      ;;
  esac

  tput "${cap}" "$@" 2>/dev/null || true
}

ui::reset() { ui::color sgr0; }

ui::say() {
  local msg
  msg="$(ui::translate "$*")"
  printf '%s\n' "${msg}"
}

ui::info() {
  local msg
  msg="$(ui::translate "$*")"
  ui::color setaf 6
  printf '%s\n' "${msg}"
  ui::reset
  log::info "${msg}"
}

ui::success() {
  local msg
  msg="$(ui::translate "$*")"
  ui::color setaf 2
  printf '%s\n' "${msg}"
  ui::reset
  log::info "${msg}"
}

ui::warn() {
  local msg
  msg="$(ui::translate "$*")"
  ui::color setaf 3 >&2
  printf '%s\n' "${msg}" >&2
  ui::reset >&2
  log::warn "${msg}"
}

ui::error() {
  local msg
  msg="$(ui::translate "$*")"
  ui::color setaf 1 >&2
  printf '%s\n' "${msg}" >&2
  ui::reset >&2
  log::error "${msg}"
}

ui::heading() {
  local msg="$*"
  msg="$(ui::translate "${msg}")"
  ui::color bold
  printf '\n%s\n' "${msg}"
  ui::reset
  log::info "== ${msg} =="
}

ui::kv() {
  local key="$1" value="$2"
  key="$(ui::translate "${key}")"
  printf '  %-18s %s\n' "${key}:" "${value}"
}

ui::log_location() {
  [[ -n "${SEEDBOX_LOG_FILE}" ]] && ui::kv "$(ui::tr "日志" "Installer log")" "${SEEDBOX_LOG_FILE}"
}
