# Failure diagnosis helpers. Pattern-based; intentionally conservative.

if [[ -n "${SEEDBOX_CORE_DIAGNOSE_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_DIAGNOSE_SOURCED=1

diagnose::from_log() {
  local log_file="$1" unit="${2:-}" step="${3:-}" next='' cause='' journal
  [[ -r "${log_file}" ]] || return 0

  if grep -Eqi 'Could not get lock|Unable to acquire the dpkg frontend lock|is another process using it' "${log_file}"; then
    cause="$(ui::tr 'APT/dpkg 正被其他软件包任务占用，常见原因是自动更新尚未结束。' 'APT/dpkg is locked, usually by another apt process or unattended-upgrades.')"
    next="$(ui::tr '等待现有软件包任务结束后重试。不要删除锁文件，也不要同时启动另一个 APT 任务。' 'Wait for the current package operation to finish, then retry. Do not delete lock files or start another APT operation concurrently.')"
  elif grep -Eqi 'Temporary failure resolving|Could not resolve|Name or service not known' "${log_file}"; then
    cause="$(ui::tr '下载或使用 APT 时域名解析失败。' 'DNS resolution failed while downloading or using apt.')"
    next="$(ui::tr '先检查本机 DNS 和网络连接，确认日志中的主机名可以解析后，再重试原命令。' 'Check local DNS/network connectivity and resolve the hostname shown in the step log before retrying the original command.')"
  elif grep -Eqi 'Failed to fetch|Connection timed out|Network is unreachable|Connection refused' "${log_file}"; then
    cause="$(ui::tr '网络下载失败，可能与连接、代理、防火墙或远程服务有关。' 'A network fetch failed; connectivity, proxy/firewall settings or the remote service may be involved.')"
    next="$(ui::tr '先确认步骤日志中的下载地址可访问，再重试；不要为了继续安装而关闭校验。' 'Check that the URL in the step log is reachable, then retry; do not disable integrity checks to proceed.')"
  elif grep -Eqi '404 Not Found|ERROR 404|The requested URL returned error: 404' "${log_file}"; then
    cause="$(ui::tr '远程文件不存在，所选版本或架构组合可能未发布。' 'A requested artifact was not found; the selected version/architecture pair may not exist.')"
    next="$(ui::tr '核对步骤日志中的地址；静态 qBittorrent 请用 seedboxctl list qbittorrent 查看清单，选择准确匹配的版本组合。' 'Check the logged URL; for static qBittorrent, use seedboxctl list qbittorrent and select an exact listed version pair.')"
  elif grep -Eqi 'Symlinked path refused|Untrusted privileged path|Unsafe .*path|wrong owner' "${log_file}"; then
    cause="$(ui::tr '目标路径、所有权或符号链接未通过安全检查。' 'A path, ownership or symlink safety check failed.')"
    next="$(ui::tr '先核对步骤日志中指出的具体路径及其上级目录。保留现有数据，请管理员确认归属和安装位置；不要用 --force、软链接或递归改权限绕过检查。' 'Inspect the exact path and its ancestors in the step log. Retain existing data and have the administrator verify ownership/install location; do not bypass checks using --force, symlinks or recursive permission changes.')"
  elif grep -Eqi 'Permission denied|Operation not permitted' "${log_file}"; then
    cause="$(ui::tr '访问文件或系统资源时权限不足；也可能受只读挂载或服务隔离策略限制。' 'A permission check failed; filesystem permissions, read-only mounts or service isolation may be involved.')"
    if [[ "${QB_ROOTLESS:-0}" == 1 || ${EUID:-$(id -u)} -ne 0 && ("${step}" == qb.* || -z "${step}") ]]; then
      next="$(ui::tr '请继续使用实例所属的普通账号，不要改用 sudo。先核对日志中的具体路径和归属；无权修复时请联系管理员，不要递归修改共享目录或下载目录的权限。' 'Keep using the instance owner account; do not switch to sudo. Inspect the exact path/ownership in the log and ask the administrator if needed. Do not recursively change shared/download-directory permissions.')"
    elif [[ ${EUID:-$(id -u)} -ne 0 ]]; then
      next="$(ui::tr '此步骤属于主机级操作，需要管理员权限；请让管理员在自己控制的主机上执行。若只安装个人 qBittorrent，应使用普通用户模式，而不是提高整个安装的权限。' 'This is a host-level step; ask the administrator to run it on a host they control. For a personal qBittorrent install, use rootless mode instead of elevating the entire installation.')"
    else
      next="$(ui::tr '当前已是 root。请先检查日志中的具体路径、挂载是否只读，以及相关服务的隔离策略；不要盲目使用 chmod 777、递归 chown 或全局关闭隔离保护。' 'Already running as root: inspect the logged path, read-only mounts and the relevant service isolation policy. Do not apply chmod 777, recursive chown or globally disable isolation.')"
    fi
  elif grep -Eqi 'command not found|No such file or directory' "${log_file}"; then
    cause="$(ui::tr '缺少必需的命令或文件。' 'A required command or file was missing.')"
    next="$(ui::tr '先在步骤日志中确认缺少的是哪个工具或路径，再由有权限的账号补齐依赖；不要用空文件或任意软链接绕过检查。' 'Identify the missing tool/path in the step log, then have an authorized account provide it. Do not bypass checks with empty files or arbitrary symlinks.')"
  elif grep -Eqi 'externally-managed-environment' "${log_file}"; then
    cause="$(ui::tr '发行版保护系统 Python，拒绝向全局环境直接安装 pip 软件包。' 'Python refused a global pip install because this distro manages Python packages externally.')"
    next="$(ui::tr '按组件说明使用 pipx 或虚拟环境，不要使用 --break-system-packages 破坏系统 Python 环境。' 'Use pipx or a virtual environment as documented for the component; do not use --break-system-packages to bypass the distro protection.')"
  elif grep -Eqi 'Address already in use|bind.*failed|port.*in use' "${log_file}"; then
    cause="$(ui::tr '所需端口可能已被其他进程占用。' 'A port appears to be occupied by another process.')"
    next="$(ui::tr '先确认占用端口的进程是否属于已有实例。保留已有服务，或明确选择一个空闲端口后重试；不要直接终止不明进程。' 'Identify the listener and check for an existing instance. Keep that service or explicitly choose a free port before retrying; do not kill an unknown process blindly.')"
  elif grep -Eqi 'Could not create AF_NETLINK socket|Address family not supported by protocol' "${log_file}"; then
    cause="$(ui::tr '服务隔离策略可能禁止了 qBittorrent 所需的网络地址族。' 'The service sandbox may have blocked an address family qBittorrent needs.')"
    next="$(ui::tr '核对具体服务单元的 RestrictAddressFamilies 是否允许 AF_NETLINK；仅修正该项后，由服务所属权限范围重新加载并启动，不要整体关闭沙箱。' 'Check that the exact unit permits AF_NETLINK in RestrictAddressFamilies. Correct only that setting, then reload/start in the appropriate system/user scope; do not disable the entire sandbox.')"
  elif grep -Eqi 'checksum.*failed|sha256sum.*FAILED|computed checksum did NOT match' "${log_file}"; then
    cause="$(ui::tr '下载文件的校验和与预期不一致。' 'Downloaded artifact checksum verification failed.')"
    next="$(ui::tr '不要运行该文件或跳过校验。先核对清单、版本组合和下载来源，确认发布方校验值后再重新下载。' 'Do not run the file or bypass verification. Check the manifest, exact version pair and source, confirm the publisher checksum, then download again.')"
  elif grep -Eqi 'WebUI password-hash format|Cannot rewrite qBittorrent config without an existing WebUI password hash' "${log_file}"; then
    cause="$(ui::tr '目标 qBittorrent 版本需要不同的密码校验格式，必须提供 WebUI 密码才能安全迁移。' 'The target qBittorrent version needs a different WebUI password-hash format.')"
    next="$(ui::tr '请使用 --password-stdin 或 --password-file 提供密码，再重试原升级命令；不要公开粘贴密码或手工清空认证设置。' 'Supply the password using --password-stdin or --password-file and retry the original upgrade. Do not post the password or clear authentication settings manually.')"
  elif grep -Eqi 'sysctl: setting key .*Invalid argument' "${log_file}"; then
    cause="$(ui::tr '当前内核拒绝了某个 sysctl 参数值。' 'A sysctl value was rejected by the kernel.')"
    next="$(ui::tr '核对步骤日志中的具体参数及 /etc/sysctl.d/99-seedbox.conf，仅调整不受支持的项；不要据此重置整套内核参数。' 'Check the exact key in the step log and /etc/sysctl.d/99-seedbox.conf; adjust only unsupported values, not the entire kernel configuration.')"
  fi

  if [[ -n "${cause}" ]]; then
    ui::error "Cause: ${cause}"
  else
    ui::error "Cause: not automatically identified. Review the step log below."
    next="$(ui::tr '先查看下方步骤日志中的首个实际错误。若有恢复快照，请先保留；不要连续覆盖重装。' 'Inspect the first concrete error in the step log below. Retain recovery snapshots and avoid repeated overwrite installs.')"
  fi
  ui::info "Next action: ${next}"

  ui::error "Step log: ${log_file}"
  if [[ -n "${unit}" ]]; then
    if [[ "${QB_SERVICE_MODE:-}" == user && ("${QB_ROOTLESS:-0}" == 1 || ${EUID:-$(id -u)} -ne 0) ]]; then
      printf -v journal 'journalctl --user -u %q -n 200 --no-pager' "${unit}"
    else journal="$(systemd::journal_cmd "${unit}")"; fi
    ui::error "Service logs: ${journal}"
  fi
}
