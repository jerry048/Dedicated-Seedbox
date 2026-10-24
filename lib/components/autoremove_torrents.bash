# autoremove-torrents lifecycle using pipx and systemd timer.

if [[ -n "${SEEDBOX_COMPONENT_AUTOREMOVE_TORRENTS_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_COMPONENT_AUTOREMOVE_TORRENTS_SOURCED=1

declare -g ART_ENABLED=no ART_START_TIMER=no ART_ENABLE_RUNTIME=no

autoremove_torrents::usage() {
  if ui::zh; then
    cat <<'USAGE'
用法：
  seedboxctl autoremove-torrents install --user USER [--enable-autoremove] [OPTIONS]
  seedboxctl autoremove-torrents upgrade --user USER
  seedboxctl autoremove-torrents uninstall --user USER [--purge] [--yes]
  seedboxctl autoremove-torrents status [--user USER] [--json] [--check]
  seedboxctl autoremove-torrents logs [--user USER] [OPTIONS]

安装会在目标用户 HOME 下使用 pipx，避免在 Debian/Ubuntu 上使用全局 pip。
默认生成的是安全配置模板；启用自动删除前请先编辑配置。
重新安装会保留定时器启用状态，优先遵循 systemd 中的手动修改。
USAGE
  else
    cat <<'USAGE'
Usage:
  seedboxctl autoremove-torrents install --user USER [--enable-autoremove] [OPTIONS]
  seedboxctl autoremove-torrents upgrade --user USER
  seedboxctl autoremove-torrents uninstall --user USER [--purge] [--yes]
  seedboxctl autoremove-torrents status [--user USER] [--json] [--check]
  seedboxctl autoremove-torrents logs [--user USER] [OPTIONS]

Install uses pipx under the target user's home, avoiding global pip on Debian/Ubuntu.
The default generated config is a safe template; edit it before enabling automatic removal.
Reinstallation preserves timer enablement, preferring manual systemd changes over saved state.
USAGE
  fi
}

autoremove_torrents::cli() {
  local sub="${1:-help}"
  [[ $# -gt 0 ]] && shift || true
  case "${sub}" in
    install)
      args::parse_for art-install "$@" || return $?
      args::has help && {
        autoremove_torrents::usage
        return 0
      }
      log::init autoremove-install
      autoremove_torrents::install_from_parsed
      ;;
    upgrade)
      args::parse_for art-upgrade "$@" || return $?
      args::has help && {
        autoremove_torrents::usage
        return 0
      }
      log::init autoremove-upgrade
      autoremove_torrents::upgrade_from_parsed
      ;;
    uninstall | remove)
      args::parse_for art-remove "$@" || return $?
      args::has help && {
        autoremove_torrents::usage
        return 0
      }
      log::init autoremove-uninstall
      autoremove_torrents::uninstall_from_parsed
      ;;
    status)
      args::parse_for art-status "$@" || return $?
      args::has help && {
        autoremove_torrents::usage
        return 0
      }
      autoremove_torrents::status_from_parsed
      ;;
    logs) logs::cli autoremove-torrents "$@" ;;
    help | -h | --help)
      args::parse_for none "$@" || return $?
      autoremove_torrents::usage
      ;;
    *)
      ui::error "$(ui::tr "未知 autoremove-torrents 命令：${sub}" "Unknown autoremove-torrents command: ${sub}")"
      autoremove_torrents::usage
      return 2
      ;;
  esac
}

autoremove_torrents::load_args() {
  ART_USER="$(args::get user)"
  [[ -n "${ART_USER}" ]] || {
    ui::error "$(ui::tr "需要 --user" "--user is required")"
    return 2
  }
  validate::die_username "${ART_USER}" || return 2
  ART_HOME="$(user::home "${ART_USER}" 2>/dev/null || true)"
  ART_CONFIG_DIR="${ART_HOME}/.config/autoremove-torrents"
  ART_CONFIG="${ART_CONFIG_DIR}/config.yml"
  ART_BIN="${ART_HOME}/.local/bin/autoremove-torrents"
  ART_SERVICE="seedbox-autoremove-torrents-${ART_USER}.service"
  ART_TIMER="seedbox-autoremove-torrents-${ART_USER}.timer"
  autoremove_torrents::resolve_timer_state
}

autoremove_torrents::resolve_timer_state() {
  local path enabled=""
  ART_ENABLED=no ART_START_TIMER=no ART_ENABLE_RUNTIME=no
  path="$(state::path autoremove-torrents "${ART_USER}")"
  if [[ -r "${path}" ]]; then
    case "$(state::get "${path}" enabled)" in yes | 1) ART_ENABLED=yes ;; esac
    case "$(state::get "${path}" enabled_runtime)" in yes | 1) ART_ENABLE_RUNTIME=yes ;; esac
  fi
  if command -v systemctl >/dev/null 2>&1; then
    enabled="$(systemctl is-enabled "${ART_TIMER}" 2>/dev/null || true)"
    case "${enabled}" in
      enabled)
        ART_ENABLED=yes
        ART_ENABLE_RUNTIME=no
        ;;
      enabled-runtime)
        ART_ENABLED=yes
        ART_ENABLE_RUNTIME=yes
        ;;
      disabled | static | indirect | linked | linked-runtime)
        ART_ENABLED=no
        ART_ENABLE_RUNTIME=no
        ;;
      masked | masked-runtime)
        ui::error "The autoremove timer is masked; unmask it explicitly before reinstalling."
        return 2
        ;;
      *) ;; # No unit/manager: use saved consent, never enable by default.
    esac
    if systemctl is-active --quiet "${ART_TIMER}" 2>/dev/null; then ART_START_TIMER=yes; fi
  fi
  if args::has enable_autoremove; then
    ART_ENABLED=yes
    ART_START_TIMER=yes
    ART_ENABLE_RUNTIME=no
  fi
}

autoremove_torrents::preflight() {
  detect::assert_root || return $?
  detect::assert_supported_os || return $?
  user::exists "${ART_USER}" || {
    ui::error "$(ui::tr "用户不存在：${ART_USER}" "User does not exist: ${ART_USER}")"
    return 1
  }
  ART_HOME="$(user::home "${ART_USER}")" || return $?
  fs::assert_no_symlink_components "${ART_CONFIG}" || return $?
}

autoremove_torrents::install_packages() {
  apt::update || return $?
  apt::ensure_packages python3 python3-venv pipx util-linux || return $?
}

autoremove_torrents::pipx_install() {
  user::run "${ART_USER}" python3 -m pipx install --force autoremove-torrents
}

autoremove_torrents::write_config() {
  fs::ensure_user_dir "${ART_USER}" "${ART_CONFIG_DIR}" || return $?
  fs::assert_no_symlink_components "${ART_CONFIG}" || return $?
  if [[ -e "${ART_CONFIG}" ]] && args::has force; then fs::backup_as "${ART_USER}" "${ART_CONFIG}" || return $?; fi
  if [[ ! -e "${ART_CONFIG}" ]] || args::has force; then
    fs::write_file_as "${ART_USER}" "${ART_CONFIG}" 0600 <<EOF_CONFIG
# autoremove-torrents config template generated by seedboxctl.
# Edit before enabling the timer. Documentation: https://autoremove-torrents.readthedocs.io/
#
# Example skeleton:
# my_task:
#   client: qbittorrent
#   host: http://127.0.0.1:8080
#   username: "${ART_USER}"
#   password: "CHANGE_ME"
#   strategies:
#     my_strategy:
#       categories:
#         - freeleech
#       remove: seeding_time > 604800
EOF_CONFIG
  fi
}

autoremove_torrents::write_units() {
  systemd::write_unit "${ART_SERVICE}" <<EOF_SERVICE || return $?
[Unit]
Description=autoremove-torrents for ${ART_USER}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${ART_USER}
Group=${ART_USER}
Environment=HOME=${ART_HOME}
ExecStart=${ART_BIN} --conf=${ART_CONFIG}
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  systemd::write_unit "${ART_TIMER}" <<EOF_TIMER || return $?
[Unit]
Description=Run autoremove-torrents for ${ART_USER} periodically

[Timer]
OnBootSec=10min
OnUnitActiveSec=10min
Persistent=true
Unit=${ART_SERVICE}

[Install]
WantedBy=timers.target
EOF_TIMER

  if [[ "${ART_ENABLED}" == yes ]]; then
    local -a enable_args=(enable)
    [[ "${ART_ENABLE_RUNTIME}" != yes ]] || enable_args+=(--runtime)
    [[ "${ART_START_TIMER}" != yes ]] || enable_args+=(--now)
    systemctl "${enable_args[@]}" "${ART_TIMER}"
  else
    systemctl disable "${ART_TIMER}"
  fi
}

autoremove_torrents::write_state() {
  state::write autoremove-torrents "${ART_USER}" <<EOF_STATE
component=autoremove-torrents
user=${ART_USER}
binary=${ART_BIN}
config=${ART_CONFIG}
service=${ART_SERVICE}
timer=${ART_TIMER}
enabled=${ART_ENABLED}
enabled_runtime=${ART_ENABLE_RUNTIME}
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
EOF_STATE
}

autoremove_torrents::install_from_parsed() {
  autoremove_torrents::load_args || return $?
  ui::heading "$(ui::tr "正在安装 autoremove-torrents" "Installing autoremove-torrents")"
  ui::kv "$(ui::tr "用户" "User")" "${ART_USER}"
  ui::log_location
  printf '\n'
  runner::must art.preflight "$(ui::tr "安装前检查" "Preflight checks")" "" autoremove_torrents::preflight || return $?
  runner::must art.packages "$(ui::tr "安装 Python/pipx 软件包" "Install Python/pipx packages")" "" autoremove_torrents::install_packages || return $?
  runner::must art.pipx "$(ui::tr "使用 pipx 安装 autoremove-torrents" "Install autoremove-torrents with pipx")" "" autoremove_torrents::pipx_install || return $?
  runner::must art.config "$(ui::tr "写入安全配置模板" "Write safe config template")" "" autoremove_torrents::write_config || return $?
  runner::must art.units "$(ui::tr "写入 systemd 服务/定时器" "Write systemd service/timer")" "${ART_SERVICE}" autoremove_torrents::write_units || return $?
  runner::must art.state "$(ui::tr "保存 autoremove-torrents 状态" "Save autoremove-torrents state")" "" autoremove_torrents::write_state || return $?
  ui::success "$(ui::tr "autoremove-torrents 已安装。配置：${ART_CONFIG}" "autoremove-torrents installed. Config: ${ART_CONFIG}")"
  if [[ "${ART_ENABLED}" != yes ]]; then
    ui::warn "$(ui::tr "定时器已安装但未启用。编辑配置后执行：systemctl enable --now ${ART_TIMER}" "Timer is installed but disabled. Enable after editing config: systemctl enable --now ${ART_TIMER}")"
    ui::pending "$(ui::tr "自动清理默认未启用；检查配置后，再按需要启用 ${ART_TIMER}。" "Automatic removal is disabled by default; review the config before enabling ${ART_TIMER} if wanted.")"
  fi
}

autoremove_torrents::read_state() {
  local user="$1" path
  path="$(state::path autoremove-torrents "${user}")"
  [[ -r "${path}" ]] || {
    ui::error "$(ui::tr "未找到 ${user} 的 autoremove-torrents 状态。" "No autoremove-torrents state found for ${user}.")"
    return 1
  }
  ART_USER="${user}"
  ART_BIN="$(state::get "${path}" binary)"
  ART_CONFIG="$(state::get "${path}" config)"
  ART_SERVICE="$(state::get "${path}" service)"
  ART_TIMER="$(state::get "${path}" timer)"
  ART_ENABLED="$(state::get "${path}" enabled)"
  case "${ART_ENABLED}" in yes | 1) ART_ENABLED=yes ;; *) ART_ENABLED=no ;; esac
  ART_ENABLE_RUNTIME="$(state::get "${path}" enabled_runtime)"
  case "${ART_ENABLE_RUNTIME}" in yes | 1) ART_ENABLE_RUNTIME=yes ;; *) ART_ENABLE_RUNTIME=no ;; esac
  ART_HOME="$(user::home "${user}")" || return $?
  ART_CONFIG_DIR="$(dirname -- "${ART_CONFIG}")"
}

autoremove_torrents::upgrade_from_parsed() {
  local user
  user="$(args::get user)"
  [[ -n "${user}" ]] || {
    ui::error "$(ui::tr "需要 --user" "--user is required")"
    return 2
  }
  autoremove_torrents::read_state "${user}" || return $?
  ui::heading "$(ui::tr "正在为 ${ART_USER} 升级 autoremove-torrents" "Upgrading autoremove-torrents for ${ART_USER}")"
  ui::log_location
  printf '\n'
  runner::must art.upgrade "$(ui::tr "使用 pipx 升级 autoremove-torrents" "Upgrade autoremove-torrents with pipx")" "" user::run "${ART_USER}" python3 -m pipx upgrade autoremove-torrents || return $?
  ui::success "$(ui::tr "已为 ${ART_USER} 升级 autoremove-torrents。" "autoremove-torrents upgraded for ${ART_USER}.")"
}

autoremove_torrents::uninstall_from_parsed() {
  local user
  detect::assert_root || return $?
  user="$(args::get user)"
  [[ -n "${user}" ]] || {
    ui::error "$(ui::tr "需要 --user" "--user is required")"
    return 2
  }
  validate::die_username "${user}" || return 2
  autoremove_torrents::read_state "${user}" || return $?
  [[ "${ART_SERVICE}" == "seedbox-autoremove-torrents-${user}.service" && "${ART_TIMER}" == "seedbox-autoremove-torrents-${user}.timer" && "${ART_CONFIG}" == "${ART_CONFIG_DIR}/config.yml" ]] || {
    ui::error "Invalid autoremove-torrents uninstall state."
    return 2
  }
  if args::has purge; then
    args::has yes || {
      ui::error "$(ui::tr "使用 --purge 时必须同时传入 --yes。" "Use --yes with --purge.")"
      return 1
    }
    fs::safety check-files "${ART_CONFIG_DIR}" --owner "${ART_USER}" config.yml || return $?
    ui::warn "$(ui::tr "只删除 ${ART_CONFIG}；保留父目录和其他文件。" "Remove only ${ART_CONFIG}; keep its parent directory and other files.")"
  fi
  systemctl stop "${ART_TIMER}" "${ART_SERVICE}" || return $?
  if args::has purge; then
    fs::safety remove-files "${ART_CONFIG_DIR}" --owner "${ART_USER}" config.yml || return $?
  fi
  user::run "${ART_USER}" python3 -m pipx uninstall autoremove-torrents || return $?
  systemctl disable "${ART_TIMER}" || return $?
  rm -f -- "/etc/systemd/system/${ART_SERVICE}" "/etc/systemd/system/${ART_TIMER}" || return $?
  systemctl daemon-reload || return $?
  state::remove autoremove-torrents "${ART_USER}" || return $?
  ui::success "$(ui::tr "已为 ${ART_USER} 卸载 autoremove-torrents。" "autoremove-torrents uninstalled for ${ART_USER}.")"
}

autoremove_torrents::status_from_parsed() {
  status::component autoremove-torrents
}
