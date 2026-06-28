
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
  --service-mode auto     Try user systemd service, then screen, then daemon/crontab fallback. Default.
  --service-mode prompt   Ask interactively: Local User Service, Screen, or Daemon.
  --service-mode user     Force systemctl --user service.
  --service-mode screen   Force screen session plus crontab restart.
  --service-mode daemon   Force qbittorrent-nox -d plus crontab restart.

Use --webui-username NAME when the qBittorrent WebUI username should differ from the Unix user.
Use --qb-tuning-profile PROFILE to choose auto, legacy, or a 1g/10g storage profile.
USAGE
}

profiles::shared_install() {
  args::parse "$@"
  args::has help && { profiles::shared_usage; return 0; }
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    ARGS[rootless]=1
  fi
  log::init install-shared
  ui::heading "Shared seedbox qBittorrent install"
  ui::log_location
  qbittorrent::install_from_parsed || return $?
}
