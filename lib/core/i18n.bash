# Installer-owned messages. Command names, paths and machine fields stay literal.
if [[ -n "${SEEDBOX_CORE_I18N_SOURCED:-}" ]]; then return 0; fi
readonly SEEDBOX_CORE_I18N_SOURCED=1
declare -gA UI_ZH_MESSAGES=()
declare -ga UI_ZH_TEMPLATES=() UI_I18N_ARGS=()

ui::match_message() {
  local template="$1" rest="$2" prefix delimiter value
  UI_I18N_ARGS=()
  while [[ "${template}" == *'%s'* ]]; do
    prefix="${template%%'%s'*}"
    [[ "${rest}" == "${prefix}"* ]] || return 1
    rest="${rest#"${prefix}"}" template="${template#*'%s'}"
    if [[ "${template}" == *'%s'* ]]; then
      delimiter="${template%%'%s'*}"
      [[ -n "${delimiter}" && "${rest}" == *"${delimiter}"* ]] || return 1
      value="${rest%%"${delimiter}"*}"
      rest="${rest#"${value}"}"
    else
      [[ "${rest}" == *"${template}" ]] || return 1
      value="${rest%"${template}"}" rest="${template}"
    fi
    UI_I18N_ARGS+=("${value}")
  done
  [[ "${rest}" == "${template}" ]]
}

ui::catalogue() {
  local text="$1" translated template
  [[ -n "${text}" ]] || return 1
  translated="${UI_ZH_MESSAGES["${text}"]:-}"
  if [[ -n "${translated}" ]]; then
    printf '%s' "${translated}"
    return 0
  fi
  for template in "${UI_ZH_TEMPLATES[@]}"; do
    ui::match_message "${template}" "${text}" || continue
    printf -- "${UI_ZH_MESSAGES[${template}]}" "${UI_I18N_ARGS[@]}"
    return 0
  done
  return 1
}

while IFS=$'\t' read -r _ui_en _ui_zh; do
  [[ -n "${_ui_en}" ]] || continue
  UI_ZH_MESSAGES["${_ui_en}"]="${_ui_zh}"
  [[ "${_ui_en}" != *'%s'* ]] || UI_ZH_TEMPLATES+=("${_ui_en}")
done <<'MESSAGES'
Invalid recorded Deluge service identities	记录中的 Deluge 服务身份无效
Invalid recorded Deluge service identities.	记录中的 Deluge 服务身份无效，已拒绝读取日志。
Deluge daemon and WebUI services are running; application health is not checked	Deluge 守护进程和 WebUI 服务均在运行；未检查应用健康状态
Invalid autobrr config port: %s	autobrr 配置中的端口无效：%s
Invalid explicitly supplied autobrr SHA-256.	提供的 autobrr SHA-256 校验值格式不正确，请核对后重试。
Invalid autobrr uninstall state.	autobrr 的卸载记录不完整或不可信，已停止操作；请先核对实例记录。
The autoremove timer is masked; unmask it explicitly before reinstalling.	自动清理定时器已被屏蔽。请先确认屏蔽原因，再手动解除屏蔽后重新安装。
Invalid autoremove-torrents uninstall state.	autoremove-torrents 的卸载记录不完整或不可信，已停止操作。
BBR requires a host/full VM; use --force-runtime only after reviewing the risk.	BBR 需要在实体主机或完整虚拟机中安装。只有确认内核边界和风险后，才可使用 --force-runtime。
BBR refuses container/WSL package changes without --force-runtime.	默认禁止在容器或 WSL 中修改内核软件包；--force-runtime 仅适用于已评估风险的特殊环境。
bash is required	缺少 bash，无法运行安装器。
sha256sum is required	缺少 sha256sum，无法校验安装文件。
Invalid explicitly supplied BBR installer SHA-256.	提供的 BBR 安装器 SHA-256 校验值格式不正确，请核对后重试。
Unpublished bbrx_old requires an explicit local or published --bbr-raw-base.	bbrx_old 尚未发布，请用 --bbr-raw-base 指定包含该版本的已审核本地目录或远程地址。
The bundled BBR installer supports Debian 11/12/13 and Ubuntu 20.04/22.04/24.04/26.04 only.	随附的 BBR 安装器仅支持 Debian 11/12/13 和 Ubuntu 20.04/22.04/24.04/26.04。
No bundled BBRv3 kernel package is configured for Ubuntu 20.04; choose a DKMS variant.	随附安装器未配置 Ubuntu 20.04 的 BBRv3 内核软件包；请选择 DKMS 变体。
BBRv3 target kernel was not reported or could not be verified; status will remain unverified.	未收到或无法验证 BBRv3 目标内核信息；状态检查将保持未验证。
Could not restore the previous congestion-control selection.	无法恢复之前选择的拥塞控制算法。
Use --bbr-script-sha256 or explicitly --allow-unverified-bbr-installer.	请提供 --bbr-script-sha256 校验值；只有审核过安装器且愿意承担风险时，才使用 --allow-unverified-bbr-installer。
BBR installer URL uses a moving main branch. Pin --bbr-script-url and --bbr-raw-base to a commit for production.	BBR 安装器地址指向会持续变化的 main 分支。生产环境请将 --bbr-script-url 和 --bbr-raw-base 固定到已审核的提交。
Selected installer does not support bbrx_old.	所选安装器不支持 bbrx_old，请换用包含该变体的安装器。
Downloaded BBR installer does not advertise Simplified Chinese; using zh-TW for the BBR subprocess only.	下载的 BBR 安装器未声明支持简体中文；仅对该子进程使用其繁体中文界面，不影响主安装器的语言。
Downloaded BBR installer does not support --lang; continuing without it.	下载的 BBR 安装器不支持 --lang，将按其默认语言运行。
Downloaded BBR installer does not support --upgrade-system; continuing without it.	下载的 BBR 安装器不支持 --upgrade-system，本次不向其传递该选项。
Downloaded BBR installer does not support --no-clear; continuing without it.	下载的 BBR 安装器不支持 --no-clear，本次不向其传递该选项。
Detected running-kernel headers for %s.	已找到当前内核 %s 对应的头文件。
Running-kernel headers are missing: linux-headers-%s. Trying apt first.	缺少当前内核的头文件 linux-headers-%s，正在尝试通过 APT 安装。
Installed running-kernel headers for %s.	已安装当前内核 %s 对应的头文件。
linux-headers-%s was installed or attempted, but /lib/modules/%s/build is still not usable for DKMS.	已尝试安装 linux-headers-%s，但 /lib/modules/%s/build 仍无法用于 DKMS 构建。
apt could not install linux-headers-%s.	APT 未能安装 linux-headers-%s。
Could not resolve a distribution generic kernel image/header package for this OS/architecture.	找不到适用于当前系统和架构的发行版通用内核及头文件软件包。
Could not resolve generic kernel package names.	无法确定通用内核软件包名称，已停止安装。
Installing generic kernel image and headers automatically: %s %s	正在自动安装发行版通用内核及头文件：%s %s
update-grub failed; check bootloader configuration before rebooting.	update-grub 执行失败。请先检查引导配置，确认系统仍可正常启动后再重启。
Create private BBR workspace	创建 BBR 专用临时工作目录
A generic kernel image and headers were installed because headers for the running kernel were unavailable. Reboot into the new generic kernel, then rerun the BBR install for %s.	当前内核缺少可用头文件，已改装发行版通用内核及头文件。下一步：确认引导配置正常，重启进入新内核，再重新安装 %s。
Generic kernel/header fallback completed for %s; BBR module installation is pending until after reboot.	%s 的通用内核准备工作已完成；BBR 模块尚未安装，需要重启进入新内核后继续。
BBRv3 kernel package installation requires a reboot before it can become active.	BBRv3 内核软件包需要在重启并进入该内核后才会生效。
BBR installation flow completed for %s.	%s 的安装流程已执行完成；是否已生效请以状态检查及重启提示为准。
Private BBR workspace retained for review: %s	已保留 BBR 临时工作目录，便于检查和恢复：%s
No BBR state found. Pass --bbr-algo to remove a DKMS variant.	未找到 BBR 安装记录。如需移除某个 DKMS 变体，请用 --bbr-algo 明确指定。
BBRv3 installed a kernel package. This command removes Seedbox-managed sysctl files only.	BBRv3 安装的是内核软件包；本命令只移除 Seedbox 管理的内核参数配置，不会卸载内核。
Boot a known-good distro kernel, inspect dpkg -l 'linux-image*' 'linux-headers*' | grep -i bbr, then purge the specific BBR kernel packages manually.	请先启动到确认可用的发行版内核，再运行 dpkg -l 'linux-image*' 'linux-headers*' | grep -i bbr 核对包名，最后仅卸载已确认的 BBR 内核软件包；不要卸载正在运行的内核。
Seedbox-managed BBR configuration removed. A reboot may be required to fully revert kernel state.	已移除 Seedbox 管理的 BBR 配置；可能需要重启才能完全恢复内核运行状态。
Conflicting packages: %s. Explicitly pass --allow-docker-package-removal (not --yes).	发现冲突软件包：%s。确认移除不会影响其他容器工作负载后，需显式使用 --allow-docker-package-removal；--yes 不代表同意此操作。
Missing or invalid installed Docker source.	Docker 安装来源记录缺失或无效，无法保存安装状态。
Cannot determine the local Docker data root. Start the system daemon and retry; no default-directory deletion will be attempted.	无法确认本机 Docker 的实际数据目录。请先恢复系统 Docker 服务后再重试；不会猜测并删除默认目录。
Cannot prove dockerd is stopped; refusing data deletion.	无法确认 dockerd 已完全停止，已拒绝删除数据。请先检查 Docker 服务及残留进程。
Stop/disable local Docker service and socket	停止并禁用本机 Docker 服务及套接字
Invalid service mode '%s' for this instance (rootless=%s).	启动方式“%s”不适用于当前实例（rootless=%s），请按实例权限选择启动方式。
Rootless mode runs as Unix user %s; using '%s' as the qBittorrent WebUI username.	普通用户模式将以系统账号 %s 运行，qBittorrent 网页管理界面的用户名为“%s”。
Could not determine a safe current Unix username.	无法确认当前系统账号名称，已停止操作；请以目标普通用户登录后重试。
Rootless qBittorrent cannot use --service-mode system. Use user, screen, daemon, auto, or prompt.	普通用户模式不能创建系统级服务。请选择 user、screen、daemon、auto 或 prompt 启动方式。
Rootless mode cannot install distro packages; using an existing qbittorrent-nox from PATH.	普通用户模式不能安装系统软件包，将尝试使用 PATH 中已有的 qbittorrent-nox。
%s service mode is only for rootless/shared-user installs.	%s 启动方式仅适用于普通用户或共享环境安装。
Existing qBittorrent config: use upgrade, or --force for a backed-up replacement.	已存在 qBittorrent 配置。保留设置请使用 upgrade；只有确定需要备份后替换配置时，才使用 --force。
qBittorrent instance for %s already exists. Use upgrade/status/uninstall, or --force to overwrite.	系统账号 %s 已有 qBittorrent 实例。请使用 upgrade、status 或 uninstall 管理；确需覆盖时再使用 --force。
Rootless static install requires curl or wget when the selected qbittorrent-nox binary is not bundled in this release tree.	当前安装目录未附带所选 qbittorrent-nox 文件。普通用户模式需要 curl 或 wget 才能下载，请先确认至少有一个工具可用。
Rootless install/upgrade requires python3 for password hashes and safe config migration.	本次普通用户安装或升级需要 python3 来处理密码及安全迁移配置。请先让服务商或管理员提供 python3，再以原账号重试。
screen is not installed. Use --service-mode daemon or --service-mode auto.	未安装 screen。可改用 --service-mode daemon 或 --service-mode auto，无需为此使用 sudo。
--source existing selected but qbittorrent-nox is not in PATH.	已选择 --source existing，但 PATH 中找不到 qbittorrent-nox。请先修正可执行文件路径。
Could not determine current user's home directory.	无法确定当前账号的主目录，请检查登录环境中的 HOME 设置。
Existing config requires --force.	检测到已有配置。请优先使用升级命令；确认需要备份后替换时才使用 --force。
Pre-install config backup	安装前配置备份
Could not read qBittorrent binary version.	无法读取 qBittorrent 可执行文件的版本，请确认文件可以正常运行。
Unrecognized qBittorrent binary version; refusing to guess its config format.	无法识别 qBittorrent 版本，已停止操作，避免按错误格式改写配置。
qbittorrent-nox package installed but binary was not found.	软件包安装步骤已结束，但仍找不到 qbittorrent-nox 可执行文件，请检查软件包状态及路径。
qbittorrent-nox was not found in PATH, ~/bin, or ~/.local/bin.	在 PATH、~/bin 和 ~/.local/bin 中均未找到 qbittorrent-nox。
Exact manifest URL and SHA-256 are required.	静态版本必须使用清单中准确匹配的下载地址及 SHA-256 校验值，不能跳过校验或替换版本组合。
Cannot rewrite qBittorrent config without an existing WebUI password hash. Re-run upgrade with --password-stdin or --password-file.	现有配置缺少可用的 WebUI 密码校验信息，不能安全改写。请通过 --password-stdin 或 --password-file 提供原密码后重新升级。
This qBittorrent upgrade/downgrade changes the WebUI password-hash format. Re-run with --password-stdin or --password-file so the config can be regenerated safely.	目标版本使用不同的 WebUI 密码校验格式。请通过 --password-stdin 或 --password-file 提供密码，再重新执行升级或降级；不会擅自重置密码。
Could not determine total RAM for qBittorrent disk queue sizing.	无法读取系统总内存，不能安全计算 qBittorrent 磁盘队列大小。
Could not resolve qBittorrent tuning profile '%s'; falling back to legacy tuning values.	无法识别 qBittorrent 调优方案“%s”，将使用兼容的旧版调优值。
crontab is not available; qBittorrent was started but automatic restart fallback was not installed.	qBittorrent 已启动，但系统没有可用的 crontab，未设置自动拉起任务。
flock is required for safe automatic restart.	缺少 flock，无法安全启用自动拉起任务；请先提供该工具，避免与维护操作相互干扰。
Choose qBittorrent startup method:	请选择 qBittorrent 的启动方式：
Please choose a valid installation method.	请输入列表中的有效启动方式编号。
systemctl --user is not available in this session.	当前登录会话无法使用用户级 systemd 服务。
User systemd services may stop after logout unless the provider enables lingering or keeps the user manager active.	用户级服务可能在退出登录后停止。若需持续运行，请让服务商启用登录后驻留，或保持用户服务管理器运行。
screen is not installed.	未安装 screen，无法使用该启动方式。
Falling back to daemon mode.	将改用后台进程方式启动。
WebUI	WebUI 地址
Back up existing config	备份现有配置
Invalid SEEDBOX_QB_STOP_TIMEOUT: %s	SEEDBOX_QB_STOP_TIMEOUT 的值无效：%s
qBittorrent did not exit within %ss. Refusing to rewrite its config, restart another instance, or purge its config.	qBittorrent 在 %s 秒内未退出。为防止配置冲突或数据损失，已停止配置改写、重复启动及配置清理；请先检查仍在运行的实例。
Invalid qBittorrent startup mode: %s	记录的 qBittorrent 启动方式无效：%s
Invalid effective WebUI port.	当前生效配置中的 WebUI 端口无效，请先核对配置。
Invalid effective incoming port.	当前生效配置中的入站连接端口无效，请先核对配置。
Invalid effective cache size.	当前生效配置中的缓存大小无效，请先核对配置。
Invalid effective WebUI username.	当前生效配置中的 WebUI 用户名无效，请先核对配置。
flock is required for safe rootless maintenance.	普通用户实例的安全维护需要 flock。请先提供该工具，再以实例所属账号重试。
Another qBittorrent maintenance/restart is active.	已有 qBittorrent 维护或自动拉起任务正在执行。请等待其结束，不要删除锁文件或同时启动另一个实例。
A previous restart helper is still active; cron remains suspended.	旧的自动拉起任务仍未退出，定时启动已保持暂停。请先检查该任务，再决定如何恢复自动启动。
--user is required when running upgrade as root.	以 root 升级时必须用 --user 指定实例所属的系统账号。
Migrate/preserve qBittorrent config	迁移配置并保留现有设置
Configure/start upgraded qBittorrent	配置并启动升级后的 qBittorrent
Upgrade failed. Restoring the previous binary, config and startup mode.	升级失败，正在尝试恢复原可执行文件、配置及启动方式。
Could not stop the replacement instance. Config and startup recovery require manual intervention; the pre-upgrade snapshot was kept.	未能停止新实例，已保留升级前快照。下一步先查看服务日志并确认实际运行的进程；在完全停止前，不要覆盖配置或启动旧实例。
Could not disable replacement startup; manual recovery required.	未能禁用新实例的自动启动。请先检查其 systemd 服务或定时启动任务，确认不会再次自动启动后，再恢复旧实例。
Config recovery failed; instance remains stopped. Recover %s manually.	配置恢复失败，实例保持停止。请先保留当前文件并核对备份 %s；确认可执行文件版本匹配后恢复该备份，再按原启动方式启动，勿直接覆盖重装。
Distro package changes cannot be automatically rolled back. Config snapshot retained; instance remains stopped for package/config recovery: %s	发行版软件包及依赖不能自动回滚，实例保持停止。请先核对 APT 中的实际版本，再恢复与该版本匹配的配置；已保留快照：%s
Could not restore automatic restart.	自动拉起任务未能恢复。请先确认实例可以正常运行，再检查并恢复原定时启动设置。
Could not restart the previous instance; manual recovery is required.	旧实例未能重新启动。请先查看原服务或应用日志，核对可执行文件与配置版本；不要连续重装，也不要另起重复实例。
Pre-upgrade config snapshot	升级前配置快照
--purge requires --yes in non-interactive mode.	非交互环境中，清理配置必须同时提供 --purge 和 --yes，以明确确认删除范围。
--user is required when running uninstall as root.	以 root 卸载时必须用 --user 指定实例所属的系统账号。
Some sysctl values were rejected by this kernel and were skipped:	以下内核参数不被当前内核接受，已跳过，不影响其余可用参数：
Tuning continued. See %s for the skipped sysctl comments.	其余调优已继续执行。被跳过的参数及说明可在 %s 中查看。
sysctl reported a non-fatal apply warning. Review the tuning step log and %s.	应用内核参数时出现非致命警告。请核对本次调优的步骤日志及 %s，确认哪些设置未生效。
Could not determine kernel page size for TCP memory tuning.	无法读取内核页大小，不能安全计算 TCP 内存阈值。
Invalid RAM or kernel page size for TCP memory tuning.	系统内存或内核页大小无效，已停止计算 TCP 内存阈值。
Invalid saved %s	已保存的 %s 设置无效，请先核对该值。
/proc/net/softnet_stat is not readable.	无法读取 /proc/net/softnet_stat，当前环境可能未开放此网络统计信息。
Vertex already exists; use upgrade or --force for a backed-up replacement.	Vertex 实例已存在。保留现有设置请使用 upgrade；确需备份后替换时才使用 --force。
Unmanaged/mismatched Vertex instance: review manually.	该 Vertex 实例不属于当前安装记录，或身份信息不匹配。请先核对容器 ID 和数据挂载，不要直接覆盖或删除。
Vertex state has no verified container ID. Review the container and record its full container_id in state before retrying.	旧版记录没有已验证的容器 ID。请先用 docker inspect 核对容器及数据挂载，再将确认过的完整 container_id 写入状态记录后重试；不要仅凭名称认领容器。
Stale Vertex container identity; refusing same-named replacement.	保存的 Vertex 容器身份已失效，已拒绝操作同名替代容器。请先核对实际容器 ID 和挂载目录。
Unconfirmed initialization container ID; retain %s and inspect %s.	无法确认初始化容器的身份。请保留 %s，并检查容器 %s；确认其已停止前，不要合并或删除初始化数据。
Incomplete Vertex data: use upgrade --repair-data --yes (snapshot required).	Vertex 数据不完整。请先备份，确认修复范围后使用 upgrade --repair-data --yes；修复必须保留数据快照。
Initialization failed; template/container retained for manual recovery: %s	初始化失败，已保留初始化目录及容器。请先查看容器日志并确认其已停止，再处理保留数据：%s
Invalid Vertex password hash; settings were not changed.	Vertex 密码校验值无效，未修改现有设置。
No Vertex snapshot: a failed new image may migrate data; the old container will NOT restart automatically.	本次没有数据快照。新镜像即使启动失败，也可能已迁移数据，因此不会自动重启旧容器。请先确认数据版本兼容性。
Vertex replacement failed; recovery status=%s. Snapshot: %s; previous container: %s.	Vertex 替换失败，恢复结果：%s。请先检查新旧容器日志，保留快照 %s 和原容器 %s；确认恢复结果及数据版本后再启动，勿删除保留副本。
Retained container backup	保留的原容器
Retained data snapshot	保留的数据快照
Failed replacement data retained: %s	已保留替换失败时的数据，便于检查和恢复：%s
Pull Vertex image	拉取 Vertex 镜像
Activate/recover Vertex	切换 Vertex 实例并准备失败恢复
Incomplete data: use --repair-data --yes.	Vertex 数据不完整。请先备份并检查缺失内容，确认后再使用 --repair-data --yes 修复。
Repair requires --yes and a data snapshot.	数据修复必须使用 --yes 明确确认，并保留数据快照。
Activate/recover Vertex upgrade	切换升级后的 Vertex 并准备失败恢复
Invalid Vertex uninstall state.	Vertex 的卸载记录不完整或不可信，已停止操作。
Unknown option: --%s	无法识别选项 --%s，请查看该命令的 --help。
Unknown option context: %s	无法识别命令的参数范围：%s
Option --%s is not supported by %s.	当前命令不接受 --%s（参数范围：%s），请查看该命令的 --help。
Unexpected arguments: %s	此命令不接受这些位置参数：%s
Flag --%s does not take a value.	--%s 是开关选项，不需要填写值。
Invalid SHA-256.	SHA-256 校验值格式不正确，请核对后重试。
Python 3 is required for safe purge validation; no changes were made. Install python3 and retry.	安全清理需要 Python 3 执行路径及文件身份检查；尚未做出任何更改。请先安装 python3，再重试原命令。
Saved interface %s is no longer available; detecting the routed interface.	已保存的网卡 %s 已不存在，正在重新检测实际路由使用的网卡。
Log query requires timeout; no dependencies installed.	日志查询需要 timeout；不会自动安装依赖，请先提供该工具。
Log source unavailable, denied, interrupted, or timed out (exit %s).	日志来源不可用、权限不足、查询被中断或已超时（退出码 %s）。请查看上方具体信息。
Following requires setsid; no dependencies installed.	实时跟踪需要 setsid；不会自动安装依赖，请先提供该工具。
Log stream exited before initialization.	日志跟踪进程在初始化完成前已退出。
Could not establish a bounded log-stream session.	未能在规定时间内建立日志跟踪会话，已停止查询。
Log stream ended unsuccessfully (exit %s).	日志跟踪异常结束（退出码 %s）。
Managed state directory is missing, unreadable, or unsafe.	受管实例的状态目录不存在、无法读取或未通过安全检查；不会创建或修复目录。
Cannot enumerate managed instances.	无法读取受管实例列表，请检查状态目录的访问权限。
Expected one managed instance; found %s. Select --user USER or --vertex-name NAME where applicable.	需要选择一个受管实例，目前匹配 %s 个。用户实例请用 --user USER，Vertex 请用 --vertex-name NAME 明确选择。
Managed state is malformed, unreadable, or unsafe.	实例状态记录格式错误、无法读取或未通过安全检查，已停止查询。
State component identity does not match.	状态记录中的组件身份与请求不符，已停止查询。
Invalid recorded qBittorrent startup mode.	状态记录中的 qBittorrent 启动方式无效。
Invalid recorded Unix account identity.	状态记录中的系统账号身份无效。
Instance is outside the current Unix account scope.	该实例不属于当前系统账号可查询的范围。
This component has no supported application-file source.	此组件尚不支持直接读取应用日志文件，请选择其他可用来源。
BBR has no dedicated daemon journal; use --source installer.	BBR 没有独立的常驻服务日志，请使用 --source installer 查看安装记录。
Query user journals as the instance owner; no automatic impersonation.	请以实例所属账号查看用户级服务日志；不会自动切换到其他用户的会话。
Daemon/screen stdout was not retained; trying the application file is possible.	后台进程或 screen 的终端输出未被保存，可以尝试查看应用自身的日志文件。
Invalid recorded service unit.	记录的服务单元名称无效，已停止查询。
Container identity cannot be verified: %s	无法验证容器身份：%s
Installer log directory is missing, unreadable, or unsafe.	安装器日志目录不存在、无法读取或未通过安全检查；不会创建或修复目录。
Untrusted installer log directory.	安装器日志目录的所有权或权限不可信，已拒绝读取。
Ignoring an unsafe or dangling latest.log link.	latest.log 链接不安全或目标已不存在，已忽略该链接，将检查有效的保留记录。
Cannot enumerate installer logs.	无法读取安装器日志列表，请检查日志目录的访问权限。
Installer log discovery exceeded its time/run budget; use --run RUN_ID.	安装记录过多或检索时间过长，请使用 --run RUN_ID 指定要查看的运行记录。
Installer discovery timed out.	检索安装记录超时，请使用 --run RUN_ID 缩小范围后重试。
No matching retained installer run found.	未找到匹配的安装器运行记录，记录可能尚未生成或已被移除。
Selected step has no recorded log in this run.	所选步骤在本次运行中没有已记录的日志路径；步骤尚未结束时可能暂不可选。
Installer source: %s (current account scope; component runs are not filtered by instance user).	安装器日志：%s（当前账号的日志范围；按组件筛选，不按实例所属用户筛选）。
Failed step: %s (use --run %s --step %s).	失败步骤：%s。查看详情请使用 --run %s --step %s。
Application source: %s	应用日志：%s
Service source: %s	服务或容器日志：%s
Installer runs are component-scoped; instance selectors do not filter historical runs.	安装器历史按组件筛选；实例选择参数不会按目标用户或容器名过滤历史记录。
--since is not supported for application files.	普通应用日志文件不支持 --since 时间筛选。
Primary %s source unavailable.	首选日志来源 %s 不可用。
Trying the qBittorrent application log.	正在尝试读取 qBittorrent 自身的应用日志。
--yes is not supported by read-only log queries.	日志查询只读，不接受 --yes。
--lines must be 1–10000.	--lines 必须是 1 到 10000 之间的整数。
Invalid log source.	日志来源无效，请使用 auto、service、application、installer 或 all。
Invalid --since value.	--since 的时间值无效，请提供有效且不含控制字符的时间表达式。
--follow requires one source and cannot be combined with --list or --source all.	--follow 只能跟踪一个来源，不能与 --list 或 --source all 同用。
--since requires a journal/Docker source, not files or --source all.	--since 仅适用于服务 journal 或 Docker 日志，不支持普通文件或 --source all。
Invalid --%s selector.	--%s 的选择值无效，请使用列表中合法的名称或 ID。
--run/--step require an installer source.	--run 和 --step 只适用于安装器日志来源。
--list cannot be combined with --step, --lines, or --since.	--list 只列出可用记录，不能与 --step、--lines 或 --since 同用。
installer only supports the installer source.	installer 目标只支持安装器日志来源。
Application-file logs are supported only for qBittorrent.	目前只有 qBittorrent 支持直接读取应用日志文件。
BBR has no dedicated daemon log; use --source installer.	BBR 没有独立的常驻服务日志，请使用 --source installer 查看安装记录。
--user is required for user-owned logs when running as root.	以 root 查询用户实例的运行日志时，必须用 --user 指定所属账号。
Cannot query another Unix account.	普通用户不能查询其他系统账号的实例。
Invalid Vertex name.	Vertex 容器名称无效，请核对 --vertex-name。
Recorded unit is missing	记录中的服务单元已不存在。
Unit load state: %s	服务单元的加载状态为 %s。
Unit result: %s	服务单元的执行结果为 %s。
Last oneshot execution succeeded; live tuning values are not revalidated	上次一次性调优任务执行成功；本次未逐项复核内核的实时参数。
Managed systemd service is running	受管 systemd 服务正在运行。
Managed unit is inactive	受管服务当前未运行。
Unit substate: %s	服务单元的详细状态为 %s。
Invalid recorded process identity	记录中的进程身份信息无效。
Recorded Unix account is unavailable	记录中的系统账号不存在或无法查询。
Recorded executable is missing, inaccessible, or cannot be resolved	记录中的可执行文件不存在、无法访问或无法确定实际路径。
Process information is unavailable	当前环境无法读取进程信息。
Process scan timed out	检查进程信息超时。
Matching process is suspended (PID %s)	匹配的进程已被暂停（PID %s）。
Executable and Unix UID match (PID %s); application health is not checked	可执行文件及实际、有效 UID 均匹配（PID %s）；未验证应用功能是否正常。
Some process identities could not be inspected	部分进程身份无法检查，不能可靠判断实例是否运行。
No process matches the recorded executable and Unix UID	未找到同时匹配记录中可执行文件及系统账号 UID 的进程。
Timer job unit is missing or cannot be queried	定时任务对应的服务单元不存在或无法查询。
Last timer job result: %s	定时任务最近一次执行结果为 %s。
Timer unit failed	定时器运行失败。
Timer unit is masked	定时器已被屏蔽，不能启动。
Timer is active; an idle job service is normal	定时器正在等待触发；两次执行之间任务服务处于空闲状态是正常现象。
Timer is intentionally disabled; last job has no recorded failure	定时器已主动禁用，最近的任务记录未显示失败。
Timer is not active	定时器当前未运行。
Timer state cannot be verified: %s	无法验证定时器状态，观察到的值为 %s。
Local system Docker daemon is reachable; unit state: %s	可以连接本机系统 Docker；服务单元状态为 %s。
Local system Docker daemon is unavailable, denied, or timed out; unit state: %s	本机系统 Docker 无法连接、权限不足或查询超时；服务单元状态为 %s。
Invalid recorded container identity	记录中的容器身份信息无效。
Local Docker engine is unavailable, denied, or timed out	本机 Docker 引擎无法连接、权限不足或查询超时。
Incomplete Docker container inventory	Docker 返回的容器列表不完整，无法可靠判断。
Legacy state has no verified container ID; manual review required	旧版记录缺少已验证的容器 ID，请先人工核对，不会自动认领同名容器。
An unrelated same-named container replaced the saved identity	当前同名容器的 ID 与安装记录不符，可能已被其他容器替代。
Saved container ID/name is absent	找不到记录中的容器 ID 与名称组合。
Saved container could not be inspected	无法读取记录中容器的详细信息。
Container ID, name, or /vertex bind mount does not match saved state	容器 ID、名称或 /vertex 数据绑定挂载与安装记录不符。
Incomplete Docker container state	Docker 返回的容器状态不完整。
Container is paused	容器已暂停。
Docker reports an unhealthy container	Docker 健康检查报告容器异常。
Docker healthcheck is still starting	Docker 健康检查仍处于启动阶段。
Saved container is running; Docker health: %s (not an application test)	记录中的容器正在运行，Docker 健康状态为 %s；这不代表应用功能已通过测试。
Container exited successfully	容器已正常退出。
Container state: %s; exit code: %s	容器状态为 %s，退出码为 %s。
Tuning configuration path cannot be inspected safely	调优配置路径未通过安全检查。
Tuning defaults or boot helper is missing/unreadable	调优默认配置或开机执行脚本缺失，或无法读取。
Kernel fallback recorded; reboot into it and rerun module installation as appropriate	已记录通用内核回退操作；请重启进入该内核，再按提示继续安装模块。
Invalid recorded BBR algorithm	记录中的 BBR 算法名称无效。
Current congestion control cannot be read	无法读取当前选择的拥塞控制算法。
Available congestion controls cannot be read	无法读取当前内核支持的拥塞控制算法列表。
Kernel congestion control is %s; registered in the running kernel (module or built-in)	当前内核已选择 %s，且该算法已注册（可能以内建或模块方式提供）。
%s is available but the kernel currently selects %s	%s 已可用，但当前内核选择的是 %s。
%s is not registered in the running kernel; selected: %s	当前内核未注册 %s，目前选择的是 %s。
State file is malformed, unreadable, oversized, or symlinked	状态文件格式错误、不可读、过大，或路径中包含符号链接。
Recorded instance is outside the current Unix user's scope	记录中的实例不属于当前系统账号可查询的范围。
User systemd status must be queried as the instance owner	请以实例所属账号查询用户级 systemd 状态，不会自动切换用户会话。
Unrecognized recorded startup mode	无法识别记录中的启动方式。
Interrupted Docker purge is recorded; review manually	发现未完成的 Docker 清理记录，请先检查保留状态，再决定是否重试。
Unsupported or mismatched state record	状态记录不受支持，或组件身份不匹配。
No matching installer-managed state record	未找到匹配的安装器受管实例记录。
Invalid Vertex container name.	Vertex 容器名称无效。
Existing home has the wrong owner: %s	已有主目录的所有者与目标账号不符：%s。请先让管理员核对归属，不会自动更改现有目录的所有权。
qBittorrent upgrade completed for %s. Existing settings were merged into the target config format.	已为 %s 完成 qBittorrent 升级，原有设置已迁移到目标版本的配置格式。
Invalid qBittorrent tuning profile: %s. Valid profiles: %s	qBittorrent 调优方案“%s”无效。可用方案：%s
Cause: %s	可能原因：%s
Cause: not automatically identified. Review the step log below.	未能自动判断原因。请先查看下方步骤日志中的具体错误。
Next action: %s	下一步：%s
Step log: %s	步骤日志：%s
Service logs: %s	查看服务日志：%s
Log/config file missing, unreadable, replaced, or unsafe.	日志或配置文件不存在、无法读取、已被替换，或未通过安全检查。
Malformed application config section.	应用配置的分区格式不正确，无法安全读取日志设置。
Custom QSettings log path cannot be decoded safely.	自定义日志路径的 QSettings 编码无法可靠解析，不会猜测路径。
qBittorrent application file logging is disabled.	qBittorrent 的文件日志已关闭；本命令不会自动开启日志。
Invalid recorded unit	状态记录中的服务单元名称无效。
Incomplete service-manager response	服务管理器返回的信息不完整，无法可靠判断。
Incomplete service execution result	服务管理器未返回完整的执行结果。
Service manager unavailable, denied, or timed out (exit %s)	服务管理器不可用、权限不足或查询超时（退出码 %s）。
No reliable runtime observation	尚未获得可信的运行状态信息。
Cannot safely read the state directory; no changes made.	状态目录无法读取或未通过安全检查，未做出任何更改。
Cannot enumerate the state directory; no changes made.	无法读取状态目录中的记录，未做出任何更改。
No managed installations found in the current state scope.	当前账号的状态范围内没有受管安装记录。
Symlinked path refused: %s	路径中包含符号链接，已拒绝操作：%s
Untrusted privileged path: %s	特权操作路径的所有权或权限不可信：%s
No qBittorrent version was supplied.	尚未指定 qBittorrent 版本。
No libtorrent version was supplied.	尚未指定 libtorrent 版本。
Operation summary	本次操作结果
Operation	操作
Step results	步骤统计
Warnings encountered	过程警告
Follow-up	待办事项
Inspect last failed step	查看最近失败步骤
MESSAGES
unset _ui_en _ui_zh
