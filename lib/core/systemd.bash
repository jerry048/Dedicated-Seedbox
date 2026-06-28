# systemd helpers.

if [[ -n "${SEEDBOX_CORE_SYSTEMD_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_SYSTEMD_SOURCED=1

systemd::require() {
  if ! detect::has_systemd; then
    ui::error "systemd was not detected. Use --service-mode screen or --service-mode daemon for qBittorrent, or run on a systemd host."
    return 1
  fi
}

systemd::daemon_reload() {
  systemctl daemon-reload
}

systemd::enable_now() {
  local unit="$1"
  systemctl enable --now "${unit}"
}

systemd::restart() {
  local unit="$1"
  systemctl restart "${unit}"
}

systemd::stop_disable() {
  local unit="$1"
  systemctl stop "${unit}" 2>/dev/null || true
  systemctl disable "${unit}" 2>/dev/null || true
}

systemd::is_active() {
  local unit="$1"
  systemctl is-active --quiet "${unit}"
}

systemd::journal_cmd() {
  local unit="$1"
  printf 'journalctl -u %s -n 200 --no-pager\n' "${unit}"
}

systemd::write_unit() {
  local unit="$1"
  fs::write_file "/etc/systemd/system/${unit}" 0644 root root
  systemd::daemon_reload
}
