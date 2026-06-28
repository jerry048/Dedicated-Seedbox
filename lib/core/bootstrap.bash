if [[ -n "${SEEDBOX_CORE_BOOTSTRAP_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_BOOTSTRAP_SOURCED=1

: "${SEEDBOX_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

source "${SEEDBOX_ROOT}/lib/core/log.bash"
source "${SEEDBOX_ROOT}/lib/core/args.bash"
source "${SEEDBOX_ROOT}/lib/core/validate.bash"
source "${SEEDBOX_ROOT}/lib/core/detect.bash"
source "${SEEDBOX_ROOT}/lib/core/fs.bash"
source "${SEEDBOX_ROOT}/lib/core/state.bash"
source "${SEEDBOX_ROOT}/lib/core/download.bash"
source "${SEEDBOX_ROOT}/lib/core/apt.bash"
source "${SEEDBOX_ROOT}/lib/core/user.bash"
source "${SEEDBOX_ROOT}/lib/core/ports.bash"
source "${SEEDBOX_ROOT}/lib/core/systemd.bash"
source "${SEEDBOX_ROOT}/lib/core/secrets.bash"
source "${SEEDBOX_ROOT}/lib/core/diagnose.bash"
source "${SEEDBOX_ROOT}/lib/core/runner.bash"
source "${SEEDBOX_ROOT}/lib/core/public_ip.bash"

for _seedbox_component in "${SEEDBOX_ROOT}"/lib/components/*.bash; do
  [[ -r "${_seedbox_component}" ]] && source "${_seedbox_component}"
done
unset _seedbox_component

for _seedbox_profile in "${SEEDBOX_ROOT}"/lib/profiles/*.bash; do
  [[ -r "${_seedbox_profile}" ]] && source "${_seedbox_profile}"
done
unset _seedbox_profile

source "${SEEDBOX_ROOT}/lib/core/status.bash"

seedbox::version() {
  printf 'seedboxctl V2.0.0\n'
}

seedbox::usage() {
  if ui::zh; then
    cat <<'USAGE'
seedboxctl - Dedicated-Seedbox V2.0.0

用法：
  seedboxctl [--lang en|zh-CN] install --profile dedicated|shared [选项]
  seedboxctl [--lang en|zh-CN] qbittorrent add-user|install-self|upgrade|uninstall|status|logs [选项]
  seedboxctl autobrr install|upgrade|uninstall|status [选项]
  seedboxctl autoremove-torrents install|upgrade|uninstall|status [选项]
  seedboxctl vertex install|upgrade|uninstall|status [选项]
  seedboxctl tuning apply|uninstall|status [选项]
  seedboxctl bbr install|uninstall|status [选项]
  seedboxctl status [--json]
  seedboxctl logs qbittorrent --user 用户名
  seedboxctl doctor [--bundle]
  seedboxctl list qbittorrent
  seedboxctl version

示例：
  seedboxctl --lang zh-CN install --profile dedicated --components qbittorrent \
    --user jerry048 --password-stdin --cache 3072 \
    --qb-version 5.0.3 --libtorrent-version v2.0.11 \
    --web-port 8080 --incoming-port 45000 --source static

  seedboxctl qbittorrent add-user --user alice --password-stdin \
    --source distro --web-port 8081 --incoming-port 45001

  seedboxctl qbittorrent install-self --password-stdin \
    --source static --qb-version 5.0.3 --libtorrent-version v2.0.11 \
    --web-port 8080 --incoming-port 45000 --service-mode auto

  seedboxctl qbittorrent upgrade --user alice --source distro
  seedboxctl qbittorrent uninstall --user alice
  seedboxctl doctor --bundle
USAGE
  else
    cat <<'USAGE'
seedboxctl - Dedicated-Seedbox V2.0.0

Usage:
  seedboxctl [--lang en|zh-CN] install --profile dedicated|shared [options]
  seedboxctl [--lang en|zh-CN] qbittorrent add-user|install-self|upgrade|uninstall|status|logs [options]
  seedboxctl autobrr install|upgrade|uninstall|status [options]
  seedboxctl autoremove-torrents install|upgrade|uninstall|status [options]
  seedboxctl vertex install|upgrade|uninstall|status [options]
  seedboxctl tuning apply|uninstall|status [options]
  seedboxctl bbr install|uninstall|status [options]
  seedboxctl status [--json]
  seedboxctl logs qbittorrent --user USER
  seedboxctl doctor [--bundle]
  seedboxctl list qbittorrent
  seedboxctl bbr install --bbr-algo bbrx
  seedboxctl version

Examples:
  seedboxctl install --profile dedicated --components qbittorrent \
    --user jerry048 --password-stdin --cache 3072 \
    --qb-version 5.0.3 --libtorrent-version v2.0.11 \
    --web-port 8080 --incoming-port 45000 --source static

  seedboxctl qbittorrent add-user --user alice --password-stdin \
    --source distro --web-port 8081 --incoming-port 45001

  seedboxctl qbittorrent install-self --password-stdin \
    --source static --qb-version 5.0.3 --libtorrent-version v2.0.11 \
    --web-port 8080 --incoming-port 45000 --service-mode auto

  seedboxctl qbittorrent upgrade --user alice --source distro
  seedboxctl qbittorrent uninstall --user alice
  seedboxctl doctor --bundle
USAGE
  fi
}

seedbox::install() {
  args::parse "$@"
  args::has help && { seedbox::usage; return 0; }
  local profile
  profile="$(args::get profile dedicated)"
  case "${profile}" in
    dedicated) profiles::dedicated_install "$@" ;;
    shared) profiles::shared_install "$@" ;;
    *) ui::error "$(ui::tr "未知 profile：${profile}" "Unknown profile: ${profile}")"; return 2 ;;
  esac
}

seedbox::list() {
  local what="${1:-}"
  case "${what}" in
    qbittorrent|qb) qbittorrent::list_available ;;
    *) ui::error "$(ui::tr "未知列表目标：${what:-missing}" "Unknown list target: ${what:-missing}")"; return 2 ;;
  esac
}

seedbox::apply_global_options() {
  local -a remaining=()
  while (($#)); do
    case "$1" in
      --lang)
        if (($# < 2)); then
          ui::error "$(ui::tr "选项 --lang 需要一个值" "Option --lang requires a value")"
          return 2
        fi
        ui::set_lang "$2" || return $?
        shift 2
        ;;
      --lang=*)
        ui::set_lang "${1#*=}" || return $?
        shift
        ;;
      *)
        remaining+=("$1")
        shift
        ;;
    esac
  done
  SEEDBOX_BOOTSTRAP_ARGS=("${remaining[@]}")
}

seedbox::bootstrap() {
  local -a SEEDBOX_BOOTSTRAP_ARGS=()
  seedbox::apply_global_options "$@" || return $?
  set -- "${SEEDBOX_BOOTSTRAP_ARGS[@]}"
  local cmd="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${cmd}" in
    install) seedbox::install "$@" ;;
    qbittorrent|qb) qbittorrent::cli "$@" ;;
    autobrr)
      if declare -F autobrr::cli >/dev/null; then autobrr::cli "$@"; else ui::error "$(ui::tr "当前运行环境中没有 autobrr 组件。" "autobrr component is not installed in this runtime.")"; return 2; fi ;;
    autoremove-torrents|autoremove_torrents)
      if declare -F autoremove_torrents::cli >/dev/null; then autoremove_torrents::cli "$@"; else ui::error "$(ui::tr "当前运行环境中没有 autoremove-torrents 组件。" "autoremove-torrents component is not installed in this runtime.")"; return 2; fi ;;
    vertex)
      if declare -F vertex::cli >/dev/null; then vertex::cli "$@"; else ui::error "$(ui::tr "当前运行环境中没有 Vertex 组件。" "vertex component is not installed in this runtime.")"; return 2; fi ;;
    docker)
      if declare -F docker::cli >/dev/null; then docker::cli "$@"; else ui::error "$(ui::tr "当前运行环境中没有 Docker 组件。" "docker component is not installed in this runtime.")"; return 2; fi ;;
    tuning)
      if declare -F tuning::cli >/dev/null; then tuning::cli "$@"; else ui::error "$(ui::tr "当前运行环境中没有 tuning 组件。" "tuning component is not installed in this runtime.")"; return 2; fi ;;
    bbr)
      if declare -F bbr::cli >/dev/null; then bbr::cli "$@"; else ui::error "$(ui::tr "当前运行环境中没有 BBR 组件。" "bbr component is not installed in this runtime.")"; return 2; fi ;;
    status) log::init status; status::all "$@" ;;
    logs) status::logs "$@" ;;
    doctor) doctor::run "$@" ;;
    list) seedbox::list "$@" ;;
    version|--version|-V) seedbox::version ;;
    help|--help|-h) seedbox::usage ;;
    *) ui::error "$(ui::tr "未知命令：${cmd}" "Unknown command: ${cmd}")"; seedbox::usage; return 2 ;;
  esac
}
