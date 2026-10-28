# Dedicated-Seedbox V2.1.4

[简体中文](README.zh-CN.md) · [Advanced reference](docs/reference.md)

Install and manage a Debian/Ubuntu seedbox with `seedboxctl`. Supports Debian 11+ and Ubuntu 20.04+ on amd64 and ARM64. Dedicated hosts need root access; shared/rootless accounts can install qBittorrent without sudo.

1. [Quick start](#quick-start)
2. [Upgrade and uninstall](#upgrade-and-uninstall)
3. [Troubleshooting](#troubleshooting)

## Quick start

Replace `REPLACE_WITH_A_STRONG_PASSWORD` and the example usernames with your own values. Command-line passwords may appear in shell history and process listings; prefer `--password-file FILE` with a private file (`chmod 600 FILE`) when needed.

Choose only one password input method: `--password`, `--password-file`, or `--password-stdin`. With `--password-stdin`, use a pipe or file redirection; terminal input is rejected.

### Dedicated server or VPS

Run as root on a host/full VM you control. This installs **qBittorrent 5.3.0 + libtorrent 2.1.2**, host tuning, and **BBRw**:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) \
  --user jerry048 \
  --password 'REPLACE_WITH_A_STRONG_PASSWORD' \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --components qbittorrent,tuning,bbr \
  --bbr-algo bbrw
```

Main options (full list in the [CLI overview](docs/reference.md#cli-overview)):

| Option                                                 | Description                                                                                       |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `--user USER`                                          | Linux account that owns the instance.                                                             |
| `--password PASSWORD`                                  | WebUI password; quote the value as shown above.                                                   |
| `--password-stdin`, `--password-file FILE`             | Preferred password input.                                                                         |
| `--components COMPONENT[,COMPONENT...]`                | Default `qbittorrent,tuning`; add `deluge`, `autobrr`, `vertex`, `autoremove-torrents`, or `bbr`. |
| `--qb-version VERSION`, `--libtorrent-version VERSION` | Static pair from the manifest (see below).                                                        |
| `--cache N`                                            | qBittorrent cache in MiB. Default `3072`.                                                         |
| `--web-port PORT`, `--incoming-port PORT`              | Defaults `8080` and `45000`.                                                                      |
| `--bbr-algo ALGO`                                      | BBR variant (see below).                                                                          |

Available qBittorrent/libtorrent pairs:

| qBittorrent                                 | libtorrent         |
| ------------------------------------------- | ------------------ |
| `4.1.9.1`                                   | `1.1.14`           |
| `4.2.5`, `4.3.9`                            | `1.2.20`           |
| `4.4.5`, `4.5.5`, `4.6.7`, `5.0.5`, `5.1.4` | `1.2.20`, `2.0.15` |
| `5.2.4`                                     | `1.2.20`, `2.0.15` |
| `5.3.0`                                     | `1.2.20`, `2.1.2`  |

BBR variants (`--bbr-algo`): `bbrv3`, `bbrx`, `bbrx_old`, `bbrw`, `bbr_brutal`, `bbrw_brutal`.

The dedicated-server example includes `bbrw`; change `--bbr-algo` to select another variant. No BBRv3 package is configured for Ubuntu 20.04.

### Shared/rootless account

Run as the intended Unix user, **without root or sudo**. This installs qBittorrent only:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) \
  --rootless \
  --webui-username jerry048 \
  --password 'REPLACE_WITH_A_STRONG_PASSWORD' \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2
```

Use the WebUI URL printed by the installer; its default port is **8080**. Keep WebUI access restricted to trusted networks and review its security settings before exposing it publicly. After installation, use `seedboxctl` (or `~/.local/bin/seedboxctl` for rootless accounts).

Already installed? Use **upgrade**, not a fresh install over an existing config. For optional apps, custom ports, storage choices, and other versions, see the [reference](docs/reference.md#components).

### Optional Deluge

Deluge **2.2.0** supports patched libtorrent **1.2.20** or **2.0.15**. Debian 12+/Ubuntu 22.04+, root and systemd are required. This selects Deluge instead of qBittorrent:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) \
  --components deluge \
  --user delugeuser \
  --password 'REPLACE_WITH_A_STRONG_PASSWORD' \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15
```

Omitting version options selects legacy **1.3.15 / 1.1.14**, supported on Debian 11+/Ubuntu 20.04+ with root and systemd. libtorrent 2.x rejects disk-cache options. See the [version, security and private-runtime guide](Torrent%20Clients/Deluge/README.md).

Open `http://SERVER_IP:8112` for WebUI access and restrict the port to trusted sources; daemon RPC stays on loopback. Deluge is not included in the default or rootless profiles. See the guide for [lifecycle commands](Torrent%20Clients/Deluge/README.md#upgrade-and-uninstall).

## Upgrade and uninstall

Back up important configuration before upgrading. Normal qBittorrent upgrades preserve existing settings and compatible credentials, and retain a config snapshot for recovery.

### Upgrade qBittorrent

For a static install:

```bash
sudo seedboxctl qbittorrent upgrade \
  --user jerry048 \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2
```

For a distro-package install:

```bash
sudo seedboxctl qbittorrent upgrade \
  --user jerry048 \
  --source distro
```

**Rootless static installs:** use the static upgrade command without `sudo` and `--user jerry048`; only manage your own instance. Distro-package operations require root. A failed distro upgrade may require manual package/config recovery; package dependencies cannot be automatically rolled back. See [qBittorrent configuration and upgrade details](docs/reference.md#qbittorrent), especially when downgrading or upgrading from qBittorrent 4.1.

### Uninstall while keeping configuration and downloads

```bash
sudo seedboxctl qbittorrent uninstall --user jerry048
```

### Remove qBittorrent configuration, but keep downloads

Only use this when you deliberately want to remove the instance's `qBittorrent.conf`:

```bash
sudo seedboxctl qbittorrent uninstall \
  --user jerry048 \
  --purge \
  --yes
```

Downloaded data, torrent/session metadata, and recovery snapshots are retained. Rootless users omit `sudo` and `--user jerry048` here too.

Other components have different purge behavior—Docker/Vertex purge can delete application data. Read the [component instructions](docs/reference.md#components) before using `--purge --yes` on them.

## Troubleshooting

Start with a status check:

```bash
seedboxctl status
```

Status is read-only. It reports managed services, processes, containers, timers, and configuration without starting or repairing anything. “Running” is not a WebUI or torrent-health test. For scripts, use `seedboxctl status --json --check`; see [status states and exit codes](docs/reference.md#status).

For a root-managed qBittorrent instance:

```bash
sudo seedboxctl qbittorrent logs --user jerry048
```

For a rootless instance:

```bash
seedboxctl qbittorrent logs
```

For Deluge, use `sudo seedboxctl deluge status --user delugeuser --check` and `sudo seedboxctl deluge logs --user delugeuser`. Status checks both services; service logs include both daemon and WebUI journals. Add `--source installer` for build/install logs.

- **Command not found:** rootless users can run `~/.local/bin/seedboxctl` directly.
- **WebUI unavailable:** check the printed address, service status, firewall, and whether another process owns the port.
- **Install/download failure:** inspect the failed step's log for APT locks, DNS/network errors, permissions, or checksum mismatches. Do not bypass integrity checks just to make an installation continue.
- **Recent installer failure:** `seedboxctl logs installer` shows the latest run; `seedboxctl logs installer --list` lists retained runs. For component sources and live following, see [log viewing](docs/reference.md#logs).
- **Upgrade/recovery failure:** keep the reported backups and snapshots. Do not repeatedly reinstall or overwrite the existing config; follow the recovery error and [detailed guidance](docs/reference.md#qbittorrent).
- **Installer display and permissions:** installer messages are localized. Rootless permission errors are not an instruction to rerun with sudo.

When asking for help, include the failed command and the relevant installer-step or service logs. Review/redact sensitive information before sharing. Full [log paths and state locations](docs/reference.md#paths-logs-and-state) are in the reference.

Detailed documentation: [CLI and aliases](docs/reference.md#cli-overview) · [qBittorrent options](docs/reference.md#qbittorrent) · [tuning](docs/reference.md#host-tuning) · [optional components](docs/reference.md#components).
