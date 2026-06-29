# Dedicated-Seedbox profile: one primary user with selectable components.

if [[ -n "${SEEDBOX_PROFILE_DEDICATED_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_PROFILE_DEDICATED_SOURCED=1

profiles::dedicated_usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl install --profile dedicated --user 用户名 [选项]

专用服务器选项：
  --components qbittorrent[,autobrr,autoremove-torrents,vertex,tuning,bbr]
  --no-tuning
  --storage-path 路径
  --disk-scheduler-all
  --password-stdin | --password-file 文件 | --password 密码
  --cache MiB
  --qb-tuning-profile PROFILE
  --qb-version 版本 --libtorrent-version 版本
  --source distro|static
  --web-port 端口 --incoming-port 端口
  --allow-unverified-downloads
  --bbr-algo bbrv3|bbrx|bbrw|bbr_brutal|bbrw_brutal
  --bbr-script-url URL --bbr-script-sha256 SHA --bbr-raw-base URL
  --bbr-lang LANG --force-runtime

未指定 --components 时默认安装：
  qbittorrent,tuning

使用 --no-tuning 可以保留默认安装流程，但跳过系统调优。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl install --profile dedicated --user USER [options]

Dedicated options:
  --components qbittorrent[,autobrr,autoremove-torrents,vertex,tuning,bbr]
  --no-tuning
  --storage-path PATH
  --disk-scheduler-all
  --password-stdin | --password-file FILE | --password PASSWORD
  --cache MIB
  --qb-tuning-profile PROFILE
  --qb-version VERSION --libtorrent-version VERSION
  --source distro|static
  --web-port PORT --incoming-port PORT
  --allow-unverified-downloads
  --bbr-algo bbrv3|bbrx|bbrw|bbr_brutal|bbrw_brutal
  --bbr-script-url URL --bbr-script-sha256 SHA --bbr-raw-base URL
  --bbr-lang LANG --force-runtime

Default components when --components is omitted:
  qbittorrent,tuning

Use --no-tuning to keep the default profile but skip tuning.
USAGE
  fi
}

profiles::csv_contains() {
  local csv="$1" wanted="$2" item
  IFS=',' read -r -a _profile_csv_parts <<<"${csv}"
  for item in "${_profile_csv_parts[@]}"; do
    item="${item// /}"
    [[ "${item}" == "${wanted}" ]] && return 0
  done
  return 1
}

profiles::csv_add() {
  local csv="$1" item="$2"
  if [[ -z "${csv}" ]]; then
    printf '%s\n' "${item}"
  elif profiles::csv_contains "${csv}" "${item}"; then
    printf '%s\n' "${csv}"
  else
    printf '%s,%s\n' "${csv}" "${item}"
  fi
}

profiles::csv_remove() {
  local csv="$1" remove="$2" item output=""
  IFS=',' read -r -a _profile_csv_parts <<<"${csv}"
  for item in "${_profile_csv_parts[@]}"; do
    item="${item// /}"
    [[ -z "${item}" || "${item}" == "${remove}" ]] && continue
    output="$(profiles::csv_add "${output}" "${item}")"
  done
  printf '%s\n' "${output}"
}

profiles::validate_dedicated_components() {
  local csv="$1" item valid=0
  IFS=',' read -r -a _profile_csv_parts <<<"${csv}"
  for item in "${_profile_csv_parts[@]}"; do
    item="${item// /}"
    [[ -z "${item}" ]] && continue
    case "${item}" in
      qbittorrent|autobrr|autoremove-torrents|vertex|tuning|bbr)
        valid=1
        ;;
      *)
        ui::error "$(ui::tr "未知安装组件：${item}" "Unknown install component: ${item}")"
        ui::error "$(ui::tr "有效组件：qbittorrent,autobrr,autoremove-torrents,vertex,tuning,bbr" "Valid components: qbittorrent,autobrr,autoremove-torrents,vertex,tuning,bbr")"
        return 2
        ;;
    esac
  done
  if (( valid == 0 )); then
    ui::error "$(ui::tr "没有选择任何组件。" "No install components selected.")"
    return 2
  fi
}

profiles::dedicated_install() {
  args::parse "$@"
  args::has help && { profiles::dedicated_usage; return 0; }
  if ((${#POSITIONAL[@]} > 0)); then
    ui::error "$(ui::tr "dedicated install 不接受位置参数：$(args::format_positionals)" "dedicated install does not accept positional arguments: $(args::format_positionals)")"
    ui::error "$(ui::tr "请使用 --components 指定组件。" "Use --components to choose components.")"
    return 2
  fi
  log::init install-dedicated
  local components password_cache_created=0
  components="$(args::get components qbittorrent,tuning)"
  if args::has password_stdin && [[ -z "${SEEDBOX_PASSWORD_STDIN_CACHE:-}" ]]; then
    SEEDBOX_PASSWORD_STDIN_CACHE="$(mktemp /tmp/seedbox.password.XXXXXX)"
    export SEEDBOX_PASSWORD_STDIN_CACHE
    password_cache_created=1
  fi
  if (( password_cache_created )); then
    trap 'rm -f -- "${SEEDBOX_PASSWORD_STDIN_CACHE:-}"' RETURN
  fi

  if args::has no_tuning; then
    components="$(profiles::csv_remove "${components}" tuning)"
  fi
  if [[ -n "$(args::get bbr_algo)" ]] && ! args::has no_bbr; then
    components="$(profiles::csv_add "${components}" bbr)"
  fi
  profiles::validate_dedicated_components "${components}" || return $?

  ui::heading "$(ui::tr "专用 seedbox 安装" "Dedicated seedbox install")"
  ui::kv "$(ui::tr "组件" "Components")" "${components}"
  ui::log_location

  if args::csv_contains "${components}" qbittorrent; then
    qbittorrent::install_from_parsed || return $?
  fi
  if args::csv_contains "${components}" autoremove-torrents; then
    if declare -F autoremove_torrents::install_from_parsed >/dev/null; then
      autoremove_torrents::install_from_parsed || return $?
    else
      ui::warn "$(ui::tr "当前运行环境中没有 autoremove-torrents 组件。" "autoremove-torrents component is not available in this runtime.")"
    fi
  fi
  if args::csv_contains "${components}" autobrr; then
    if declare -F autobrr::install_from_parsed >/dev/null; then
      autobrr::install_from_parsed || return $?
    else
      ui::warn "$(ui::tr "当前运行环境中没有 autobrr 组件。" "autobrr component is not available in this runtime.")"
    fi
  fi
  if args::csv_contains "${components}" vertex; then
    if declare -F vertex::install_from_parsed >/dev/null; then
      vertex::install_from_parsed || return $?
    else
      ui::warn "$(ui::tr "当前运行环境中没有 Vertex 组件。" "vertex component is not available in this runtime.")"
    fi
  fi
  if args::csv_contains "${components}" tuning; then
    if declare -F tuning::apply_safe_from_parsed >/dev/null; then
      tuning::apply_safe_from_parsed || return $?
    else
      ui::warn "$(ui::tr "当前运行环境中没有 tuning 组件。" "tuning component is not available in this runtime.")"
    fi
  fi
  if args::csv_contains "${components}" bbr; then
    if declare -F bbr::install_from_parsed >/dev/null; then
      bbr::install_from_parsed || return $?
    else
      ui::warn "$(ui::tr "当前运行环境中没有 BBR 组件。" "bbr component is not available in this runtime.")"
    fi
  fi
}
