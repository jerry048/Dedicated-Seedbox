# Failure diagnosis helpers. Pattern-based; intentionally conservative.

if [[ -n "${SEEDBOX_CORE_DIAGNOSE_SOURCED:-}" ]]; then
  return 0
fi
readonly SEEDBOX_CORE_DIAGNOSE_SOURCED=1

diagnose::from_log() {
  local log_file="$1" unit="${2:-}"
  [[ -r "${log_file}" ]] || return 0

  local cause=""
  if grep -Eqi 'Could not get lock|Unable to acquire the dpkg frontend lock|is another process using it' "${log_file}"; then
    cause="APT/dpkg is locked, usually by another apt process or unattended-upgrades."
  elif grep -Eqi 'Temporary failure resolving|Could not resolve|Name or service not known' "${log_file}"; then
    cause="DNS resolution failed while downloading or using apt. Check resolver/network connectivity."
  elif grep -Eqi 'Failed to fetch|Connection timed out|Network is unreachable|Connection refused' "${log_file}"; then
    cause="A network fetch failed. Check connectivity, proxy/firewall settings, and whether the URL is reachable."
  elif grep -Eqi '404 Not Found|ERROR 404|The requested URL returned error: 404' "${log_file}"; then
    cause="A requested artifact was not found. The selected version/architecture pair may not exist."
  elif grep -Eqi 'Permission denied|Operation not permitted' "${log_file}"; then
    cause="A permission check failed. Ensure the command is run as root and target files are writable."
  elif grep -Eqi 'command not found|No such file or directory' "${log_file}"; then
    cause="A required command or file was missing. Review the step log for the missing executable/path."
  elif grep -Eqi 'externally-managed-environment' "${log_file}"; then
    cause="Python refused a global pip install because this distro manages Python packages externally. Use pipx or a venv."
  elif grep -Eqi 'Address already in use|bind.*failed|port.*in use' "${log_file}"; then
    cause="A port appears to be occupied by another process."
  elif grep -Eqi 'Could not create AF_NETLINK socket|Address family not supported by protocol' "${log_file}"; then
    cause="The service sandbox blocked an address family qBittorrent needs. Update the systemd unit to allow AF_NETLINK, then daemon-reload and restart the service."
  elif grep -Eqi 'checksum.*failed|sha256sum.*FAILED|computed checksum did NOT match' "${log_file}"; then
    cause="Downloaded artifact checksum verification failed. Do not run the artifact until the manifest is corrected."
  elif grep -Eqi 'WebUI password-hash format|Cannot rewrite qBittorrent config without an existing WebUI password hash' "${log_file}"; then
    cause="qBittorrent config update needs the WebUI password to regenerate the target version's password hash. Re-run with --password-stdin or --password-file."
  elif grep -Eqi 'sysctl: setting key .*Invalid argument|Invalid argument' "${log_file}"; then
    cause="A sysctl value was rejected by the kernel. Review the generated /etc/sysctl.d/99-seedbox.conf values for this kernel/distro."
  fi

  if [[ -n "${cause}" ]]; then
    ui::error "Cause: ${cause}"
  else
    ui::error "Cause: not automatically identified. Review the step log below."
  fi

  ui::error "Step log: ${log_file}"
  if [[ -n "${unit}" ]]; then
    ui::error "Service logs: $(systemd::journal_cmd "${unit}")"
  fi
}
