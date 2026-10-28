# Deluge on Debian/Ubuntu

[简体中文](README.zh-CN.md) · [Main guide](../../README.md) · [All options](../../docs/reference.md#deluge)

Deluge is optional and requires **root and systemd**; rootless installation is not supported. It builds a private runtime without replacing system Python or requiring Docker.

| Deluge           | libtorrent             | Minimum OS               | Runtime prefix                |
| ---------------- | ---------------------- | ------------------------ | ----------------------------- |
| 1.3.15 (default) | 1.1.14                 | Debian 11 / Ubuntu 20.04 | `/opt/deluge-1.3.15`          |
| 2.2.0            | 1.2.20                 | Debian 12 / Ubuntu 22.04 | `/opt/deluge-2.2.0-lt-1.2.20` |
| 2.2.0            | 2.0.15 (2.2.0 default) | Debian 12 / Ubuntu 22.04 | `/opt/deluge-2.2.0-lt-2.0.15` |

**Legacy warning:** Deluge 1.3.15 and its Python 2.7/OpenSSL 1.1.1 stack are unsupported. Use them only when required; private installation and pinned downloads do not make them secure or maintained.

## Install

Use the Deluge example in the [main Quick start](../../README.md#quick-start), or run this from a complete repository checkout:

```bash
sudo bash bin/seedboxctl deluge add-user \
  --user delugeuser \
  --password 'REPLACE_WITH_A_STRONG_PASSWORD' \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  --jobs 2
```

- Replace the username and password. A missing Unix account is created; an existing account must be non-root and own its home directory.
- Command-line passwords may appear in shell history and process listings. Alternatively, use `--password-file FILE` with a private, nonempty, single-line UTF-8 password file (`chmod 600 FILE`). Choose only one password input method; `--password-stdin` requires a pipe or file redirection.
- Compilation needs several GiB of disk space and substantial RAM/CPU time. Use `--jobs 1` on small hosts. APT sources must work and pass signature checks; retired Debian 11 security mirrors may need the [Debian archive](https://archive.debian.org/debian-security/).
- For Deluge 2.2.0 with libtorrent 1.2.20, change `--deluge-libtorrent-version` to `1.2.20`; it supports `--deluge-cache-mib 256`. libtorrent 2.x rejects this cache option.
- Omitting both version options selects **1.3.15 / 1.1.14**, not 2.2.0.

## Access

Open **`http://SERVER_IP:8112`** and enter your WebUI password.

| Service    | Default                                | Option                   |
| ---------- | -------------------------------------- | ------------------------ |
| WebUI      | TCP `8112`, binds `0.0.0.0`            | `--deluge-web-port`      |
| Daemon RPC | TCP `58846`, loopback `127.0.0.1` only | `--deluge-rpc-port`      |
| BitTorrent | TCP/UDP `45000`                        | `--deluge-incoming-port` |

The installer does not open firewall ports. Restrict WebUI to trusted clients; for untrusted networks, use an HTTPS reverse proxy or trusted VPN. Keep TLS verification enabled. RPC stays local and uses a separate generated credential.

## Upgrade and uninstall

```bash
sudo seedboxctl deluge upgrade --user delugeuser
sudo seedboxctl deluge upgrade --user delugeuser --deluge-version 2.2.0 --deluge-libtorrent-version 2.0.15
sudo seedboxctl deluge uninstall --user delugeuser
```

- **Upgrade** keeps the current version pair unless you specify a target. It supports **1.3.15 → 2.2.0** and switching **1.2.20 ↔ 2.0.15** within 2.2.0. Ports, paths, WebUI password and compatible ltConfig settings are preserved; no password input is needed.
- The target runtime is built before stopping services. Version switches take a full-profile `.pre-upgrade-*` snapshot, including torrent/session data and plugins. Success requires all saved torrents to load; failure restores the profile/services/state when possible and leaves services stopped for review. Download files and the old runtime are not removed.
- **Uninstall** removes services but keeps configuration, downloads, torrent/session data and the shared runtime.
- Add **`--purge --yes`** only to deliberately remove active settings: `core.conf`, `web.conf`, `hostlist.conf.1.2` or `hostlist.conf`, `auth` and `ltconfig.conf`. Downloads, torrent/session metadata, plugins and recovery snapshots remain.

Automatic downgrade to **1.3.15** is not supported. Disable third-party plugins before switching versions. Unsupported libtorrent controls are removed from active settings but retained in the snapshot. Switching from 2.0.15 to 1.2.20 prompts for a cache size in MiB, with **no default**, before building or stopping services. For non-interactive runs, supply `--deluge-cache-mib N` (alias: `--cache-mib N`); upgrade cache options apply only to this switch. Legacy automatic folder watching needs reconfiguration with Deluge 2's AutoAdd plugin. Back up important data before upgrading.

Upgrades preserve existing WebUI binding. For an old loopback-only profile, stop both services and back up `web.conf` before changing `interface` to `"0.0.0.0"`; preserve its version header, then run `upgrade`. Leave `"127.0.0.1"` to keep local-only access.

## Paths and runtime reuse

| Purpose                             | Location                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------ |
| Configuration/session               | `~delugeuser/.config/deluge`                                                   |
| Downloads                           | `~delugeuser/deluge/download`                                                  |
| Completed/torrent/watch directories | `~delugeuser/deluge/{completed,torrent,watch}`                                 |
| Instance record                     | `/var/lib/seedbox/state/deluge.delugeuser.env`                                 |
| Daemon / WebUI services             | `seedbox-deluged-delugeuser.service` / `seedbox-deluge-web-delugeuser.service` |
| Installer logs                      | `/var/log/seedbox`                                                             |

Matching completed runtimes are checked and reused. To build one before creating instances:

```bash
sudo seedboxctl deluge build-runtime \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  --jobs 2
```

Do not copy compiled runtimes between distributions. Failed/incompatible runtimes are retained, not overwritten: inspect the failure, stop affected services and keep runtime/profile backups before moving the old prefix aside and rebuilding. Runtime replacement affects every instance sharing that prefix; reconcile them with `upgrade` afterward.

Use `--source-dir DIR` for exact local source files listed in the selected runtime's locks; APT dependencies must still be available. Missing files or hash mismatches abort. Build sources, locks and tuning patches are in [`lib/components/deluge/`](../../lib/components/deluge/).

## Troubleshooting

```bash
sudo seedboxctl deluge status --user delugeuser --check
sudo seedboxctl deluge logs --user delugeuser --source service --lines 100
sudo seedboxctl deluge logs --source installer
```

Status checks both services; it is not an authenticated transfer test. Service logs combine both journals. Add `--follow` for live service logs; use `--source installer --list` to find installer runs. See the [monitoring reference](../../docs/reference.md#status) for JSON, exit codes and log options. Review logs for secrets before sharing.
