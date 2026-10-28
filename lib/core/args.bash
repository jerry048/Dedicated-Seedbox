# Small long-option parser shared by seedboxctl commands.

if [[ -n "${SEEDBOX_CORE_ARGS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_ARGS_SOURCED=1

declare -gA ARGS=()
declare -ga POSITIONAL=()

args::reset() {
  ARGS=()
  POSITIONAL=()
}

args::is_flag() {
  case "$1" in
    help | yes | json | check | follow | list | purge | force | rootless | no_cron | allow_unverified_downloads | allow_unverified_bbr_installer | allow_docker_package_removal | repair_data | no_data_snapshot | password_stdin | set_system_password | no_tuning | no_bbr | enable_autoremove | host_network | force_runtime | upgrade_system | no_clear | no_rss | no_rps | no_rfs | no_xps | no_ring_buffer | no_initial_cwnd | no_disk_scheduler | disk_scheduler_all | no_net_queue_tuning | no_cpu_tuning | no_read_ahead | no_sysctl | no_limits)
      return 0
      ;;
    *) return 1 ;;
  esac
}

args::normalize_key() {
  local key="$1"
  key="${key#--}"
  key="${key//-/_}"
  printf '%s\n' "${key}"
}

args::known_key() {
  args::is_flag "$1" && return 0
  case "$1" in
    deluge_version | deluge_libtorrent_version | deluge_web_port | deluge_rpc_port | deluge_incoming_port | deluge_cache_mib | rpc_port | jobs | source_dir) return 0 ;;
    profile | components | user | password | password_file | cache | cache_mib | web_port | qb_web_port | qb_port | incoming_port | qb_incoming_port | listen_port | qb_version | libtorrent_version | source | service_mode | install_method | qb_tuning_profile | qb_profile | qbtuning_profile | webui_username | webui_user | web_user | storage | storage_path | interface | netdev | link_speed | link_speed_mbps | txqueuelen | initial_cwnd | autobrr_port | autobrr_url | autobrr_sha256 | vertex_name | vertex_port | vertex_data_dir | vertex_image | timezone | docker_source | bbr_algo | algo | bbr_script_url | bbr_script_sha256 | bbr_raw_base | bbr_lang | lines | since | run | step) return 0 ;;
    *)
      ui::error "Unknown option: --${1//_/-}"
      return 2
      ;;
  esac
}

# Keep command allowlists separate from parsing so combined installs can accept
# the union of their selected components' options, without accepting ignored keys.
args::options_for() {
  local context="$1" hardware qb tuning bbr
  hardware="storage storage_path interface netdev link_speed link_speed_mbps"
  qb="user password password_file password_stdin cache cache_mib web_port qb_web_port qb_port incoming_port qb_incoming_port listen_port qb_version libtorrent_version source service_mode install_method qb_tuning_profile qb_profile qbtuning_profile webui_username webui_user web_user allow_unverified_downloads no_cron ${hardware}"
  tuning="${hardware} txqueuelen initial_cwnd no_sysctl no_limits no_cpu_tuning no_read_ahead no_ring_buffer no_rss no_rps no_rfs no_xps no_initial_cwnd no_disk_scheduler disk_scheduler_all no_net_queue_tuning"
  bbr="bbr_algo algo bbr_script_url bbr_script_sha256 bbr_raw_base bbr_lang allow_unverified_bbr_installer force_runtime upgrade_system no_clear"
  case "${context}" in
    deluge-build | deluge-upgrade)
      printf '%s' 'jobs source_dir deluge_version deluge_libtorrent_version libtorrent_version'
      [[ "${context}" != deluge-upgrade ]] || printf ' user deluge_cache_mib cache_mib'
      ;;
    deluge-install) printf '%s' 'user password password_file password_stdin jobs source_dir deluge_version deluge_libtorrent_version libtorrent_version deluge_web_port deluge_rpc_port deluge_incoming_port deluge_cache_mib web_port rpc_port incoming_port cache_mib' ;;
    deluge-status) printf '%s' 'user json check' ;;
    deluge-remove) printf '%s' 'user purge yes' ;;
    qb-install) printf '%s' "${qb} rootless profile force set_system_password" ;;
    qb-upgrade) printf '%s' "${qb}" ;;
    qb-status | autobrr-status | art-status) printf '%s' 'user json check' ;;
    qb-logs | logs-user) printf '%s' 'user lines follow since source list run step' ;;
    logs-vertex) printf '%s' 'vertex_name lines follow since source list run step' ;;
    logs) printf '%s' 'lines follow since source list run step' ;;
    qb-remove | autobrr-remove | art-remove) printf '%s' 'user purge yes' ;;
    autobrr-install) printf '%s' 'user autobrr_port autobrr_url autobrr_sha256 allow_unverified_downloads force' ;;
    autobrr-upgrade) printf '%s' 'user autobrr_url autobrr_sha256 allow_unverified_downloads' ;;
    art-upgrade) printf '%s' user ;;
    art-install) printf '%s' 'user enable_autoremove force' ;;
    vertex-install) printf '%s' 'vertex_name vertex_port vertex_data_dir vertex_image timezone host_network user password password_file password_stdin docker_source allow_docker_package_removal force' ;;
    vertex-upgrade) printf '%s' 'vertex_name vertex_image repair_data no_data_snapshot' ;;
    vertex-remove) printf '%s' 'vertex_name purge yes' ;;
    vertex-status) printf '%s' 'vertex_name json check' ;;
    docker-install) printf '%s' 'docker_source allow_docker_package_removal' ;;
    docker-remove) printf '%s' 'purge yes' ;;
    tuning-apply) printf '%s' "${tuning}" ;;
    bbr-install) printf '%s' "${bbr}" ;;
    bbr-remove) printf '%s' 'bbr_algo algo' ;;
    status) printf '%s' 'json check' ;;
    install)
      local components component
      components="$(args::get components "$([[ "$(args::get profile dedicated)" == shared ]] && printf qbittorrent || printf qbittorrent,tuning)")"
      printf '%s' 'profile components no_tuning no_bbr'
      while IFS= read -r component; do
        case "${component// /}" in
          deluge) printf ' %s' "$(args::options_for deluge-install)" ;;
          qbittorrent) printf ' %s' "$(args::options_for qb-install)" ;;
          tuning) printf ' %s' "${tuning}" ;;
          autobrr) printf ' %s' "$(args::options_for autobrr-install)" ;;
          autoremove-torrents) printf ' %s' "$(args::options_for art-install)" ;;
          vertex) printf ' %s' "$(args::options_for vertex-install)" ;;
          bbr) printf ' %s' "${bbr}" ;;
        esac
      done < <(printf '%s\n' "${components//,/$'\n'}")
      # Supplying an algorithm implicitly selects BBR in the dedicated profile.
      if args::has bbr_algo || args::has algo; then printf ' %s' "${bbr}"; fi
      ;;
    none | tuning-remove) ;;
    *)
      ui::error "Unknown option context: ${context}"
      return 2
      ;;
  esac
}

args::parse_for() {
  local context="$1" allowed key
  shift
  args::parse "$@" || return $?
  allowed=" help yes $(args::options_for "${context}") " || return $?
  for key in "${!ARGS[@]}"; do
    if [[ "${allowed}" != *" ${key} "* ]]; then
      ui::error "Option --${key//_/-} is not supported by ${context}."
      return 2
    fi
  done
  if [[ "${context}" != install ]] && ((${#POSITIONAL[@]})); then
    ui::error "Unexpected arguments: $(args::format_positionals)"
    return 2
  fi
  args::has help || args::validate_password_input || return $?
  return 0
}

args::validate_password_input() {
  local count=0 key
  for key in password password_file password_stdin; do
    if args::has "${key}"; then count=$((count + 1)); fi
  done
  if ((count > 1)); then
    ui::error "$(ui::tr '密码输入方式冲突：--password、--password-file 和 --password-stdin 只能选一种。' 'Conflicting password inputs: choose only one of --password, --password-file, or --password-stdin.')"
    return 2
  fi
  if args::has password && [[ -z "$(args::get password)" ]]; then
    ui::error "$(ui::tr '密码不能为空。' 'Password must not be empty.')"
    return 2
  fi
  if args::has password_file && [[ -z "$(args::get password_file)" ]]; then
    ui::error "$(ui::tr '密码文件路径不能为空。' 'Password file path must not be empty.')"
    return 2
  fi
  if args::has password_stdin && [[ -t 0 ]]; then
    ui::error "$(ui::tr '--password-stdin 需要管道或文件重定向，不能直接从终端读取；也可改用 --password-file。' '--password-stdin requires a pipe or file redirection, not a terminal; alternatively use --password-file.')"
    return 2
  fi
  return 0
}

args::parse() {
  args::reset
  while (($#)); do
    case "$1" in
      --)
        shift
        while (($#)); do
          POSITIONAL+=("$1")
          shift
        done
        ;;
      --*=*)
        local raw="${1%%=*}" val="${1#*=}" key
        key="$(args::normalize_key "${raw}")"
        args::known_key "${key}" || return $?
        if args::is_flag "${key}"; then
          ui::error "Flag --${key//_/-} does not take a value."
          return 2
        fi
        ARGS["${key}"]="${val}"
        shift
        ;;
      --*)
        local key
        key="$(args::normalize_key "$1")"
        args::known_key "${key}" || return $?
        if args::is_flag "${key}"; then
          ARGS["${key}"]=1
          shift
        else
          if (($# < 2)) || [[ "$2" == --* || "$2" == -h ]]; then
            ui::error "$(ui::tr "选项 --${key//_/-} 需要一个值" "Option --${key//_/-} requires a value")"
            return 2
          fi
          ARGS["${key}"]="$2"
          shift 2
        fi
        ;;
      -h)
        ARGS[help]=1
        shift
        ;;
      *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
  done
}

args::get() {
  local key="$1" default="${2:-}"
  key="${key//-/_}"
  if [[ -v ARGS["${key}"] ]]; then
    printf '%s\n' "${ARGS[${key}]}"
  else
    printf '%s\n' "${default}"
  fi
}

args::has() {
  local key="$1"
  key="${key//-/_}"
  [[ -v ARGS["${key}"] ]]
}

args::format_positionals() {
  local item first=1
  for item in "${POSITIONAL[@]}"; do
    if ((first)); then
      first=0
    else
      printf ' '
    fi
    printf '%q' "${item}"
  done
}

args::copy_value_alias() {
  local canonical="$1" alias="$2"
  canonical="${canonical//-/_}"
  alias="${alias//-/_}"
  if [[ ! -v ARGS["${canonical}"] && -v ARGS["${alias}"] ]]; then
    ARGS["${canonical}"]="${ARGS[${alias}]}"
  fi
}

args::csv_contains() {
  local csv="$1" wanted="$2" item
  IFS=',' read -r -a _args_csv_parts <<<"${csv}"
  for item in "${_args_csv_parts[@]}"; do
    item="${item// /}"
    [[ "${item}" == "${wanted}" ]] && return 0
  done
  return 1
}

args::require() {
  local missing=0 key
  for key in "$@"; do
    if [[ -z "$(args::get "${key}")" ]]; then
      ui::error "$(ui::tr "缺少必需选项：--${key//_/-}" "Missing required option: --${key//_/-}")"
      missing=1
    fi
  done
  [[ ${missing} -eq 0 ]]
}
