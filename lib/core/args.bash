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
    help|yes|dry_run|json|bundle|purge|force|rootless|no_cron|allow_unverified_downloads|allow_unverified_bbr_installer|password_stdin|set_system_password|no_tuning|no_bbr|debug|enable_autoremove|host_network|force_runtime|upgrade_system|no_clear|no_rss|no_rps|no_rfs|no_xps|no_ring_buffer|no_initial_cwnd|no_disk_scheduler|no_net_queue_tuning|no_sysctl|no_limits|no_cron)
      return 0 ;;
    *) return 1 ;;
  esac
}

args::normalize_key() {
  local key="$1"
  key="${key#--}"
  key="${key//-/_}"
  printf '%s\n' "${key}"
}

args::parse() {
  args::reset
  while (($#)); do
    case "$1" in
      --)
        shift
        while (($#)); do POSITIONAL+=("$1"); shift; done
        ;;
      --*=*)
        local raw="${1%%=*}" val="${1#*=}" key
        key="$(args::normalize_key "${raw}")"
        ARGS["${key}"]="${val}"
        shift
        ;;
      --*)
        local key
        key="$(args::normalize_key "$1")"
        if args::is_flag "${key}"; then
          ARGS["${key}"]=1
          shift
        else
          if (($# < 2)); then
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
