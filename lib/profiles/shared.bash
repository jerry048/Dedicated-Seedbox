if [[ -n "${SEEDBOX_PROFILE_SHARED_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_PROFILE_SHARED_SOURCED=1

profiles::shared_usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl install --profile shared [--rootless] [OPTIONS]
  seedboxctl qbittorrent install-self [OPTIONS]

共享环境说明：
  OPTIONS 使用 qBittorrent 的选项；qbittorrent add-user --profile shared 仍可作为兼容写法。
  以 root 运行时，--user 指定目标系统账号，由安装器创建并管理该实例。
  以普通账号运行时，自动采用无需 root 的安装方式，实例属于当前账号。

普通用户实例的启动方式：
  请直接以目标普通账号运行，不要使用 sudo 或 root。
  --service-mode auto     默认依次尝试用户级 systemd、screen、后台进程及定时拉起任务。
  --service-mode prompt   交互选择用户级服务、screen 会话或后台进程。
  --service-mode user     仅使用 systemctl --user 管理的服务。
  --service-mode screen   使用 screen 会话，并通过定时任务自动拉起。
  --service-mode daemon   使用 qbittorrent-nox -d 后台进程，并通过定时任务自动拉起。

WebUI 用户名与系统账号不同时，请使用 --webui-username NAME。
--qb-tuning-profile PROFILE 可选 auto、legacy 或 1g/over1g 存储调优方案。
有交互终端时会展示检测结果供确认；无终端时自动采用检测结果或显式参数。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl install --profile shared [--rootless] [OPTIONS]
  seedboxctl qbittorrent install-self [OPTIONS]

Shared profile behavior:
  OPTIONS are qBittorrent options; qbittorrent add-user --profile shared remains an alias.
  As root, --user is the target Linux account and seedboxctl creates/administers that instance.
  As a normal user, rootless mode is selected automatically and the instance runs as the current Unix user.

Rootless startup modes:
  Rootless mode must be run as the target non-root Unix user; do not use sudo/root.
  --service-mode auto     Try user systemd service, then screen, then daemon/crontab fallback. Default.
  --service-mode prompt   Ask interactively: Local User Service, Screen, or Daemon.
  --service-mode user     Force systemctl --user service.
  --service-mode screen   Force screen session plus crontab restart.
  --service-mode daemon   Force qbittorrent-nox -d plus crontab restart.

Use --webui-username NAME when the qBittorrent WebUI username should differ from the Unix user.
Use --qb-tuning-profile PROFILE to choose auto, legacy, or a 1g/over1g storage profile.
Shared detection prompts with defaults when a terminal is available; otherwise it runs automatically.
USAGE
  fi
}

profiles::shared_components_are_qbittorrent_only() {
  local csv="$1" item found=0
  IFS=',' read -r -a _shared_csv_parts <<<"${csv}"
  for item in "${_shared_csv_parts[@]}"; do
    item="${item// /}"
    [[ -z "${item}" ]] && continue
    [[ "${item}" == "qbittorrent" ]] || return 1
    found=1
  done
  ((found == 1))
}

profiles::shared_install() {
  args::parse_for install "$@" || return $?
  args::has help && {
    profiles::shared_usage
    return 0
  }
  if ((${#POSITIONAL[@]} > 0)); then
    ui::error "$(ui::tr "shared install 不接受位置参数：$(args::format_positionals)" "shared install does not accept positional arguments: $(args::format_positionals)")"
    return 2
  fi
  if ! profiles::shared_components_are_qbittorrent_only "$(args::get components qbittorrent)"; then
    ui::error "$(ui::tr "shared profile 只支持 qBittorrent。" "shared profile only supports qBittorrent.")"
    ui::error "$(ui::tr "安装 Vertex 请使用：seedboxctl vertex install ..." "To install Vertex, use: seedboxctl vertex install ...")"
    return 2
  fi
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    ARGS[rootless]=1
  fi
  log::init install-shared
  ui::heading "Shared seedbox qBittorrent install"
  ui::log_location
  qbittorrent::install_from_parsed || return $?
}
