
if [[ -n "${SEEDBOX_PROFILE_SHARED_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_PROFILE_SHARED_SOURCED=1

profiles::shared_usage() {
  cat <<'USAGE'
Usage:
  seedboxctl install --profile shared [--rootless] [qBittorrent options]
  seedboxctl qbittorrent add-user --profile shared [--rootless] [qBittorrent options]
  seedboxctl qbittorrent install-self [qBittorrent options]

Shared profile behavior:
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
Use --qb-tuning-profile PROFILE to choose auto, legacy, or a 1g/10g storage profile.
USAGE
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
  (( found == 1 ))
}

profiles::shared_install() {
  args::parse "$@"
  args::has help && { profiles::shared_usage; return 0; }
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
