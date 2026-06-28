# Dedicated-Seedbox V2.0.0

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-blue)](#supported-environments)
[![Mode](https://img.shields.io/badge/modes-dedicated%20%7C%20shared%20%7C%20rootless-informational)](#profiles)

Simplified Chinese: [README.zh-CN.md](README.zh-CN.md)

`Dedicated-Seedbox` is the shared backend for building and managing Debian/Ubuntu seedbox installations. It provides a single CLI, `seedboxctl`, for qBittorrent instances, host tuning, BBR variants, Docker/Vertex, autobrr, autoremove-torrents, status reporting, logs, and diagnostics.

The project is designed to be used in two ways:

- **Dedicated servers or VPS hosts** where you have root access and can manage users, systemd services, APT packages, kernel/network tuning, Docker, and BBR.
- **Shared or rootless seedbox accounts** where you only control your own Unix account and want to run qBittorrent without `sudo`.

---

## Contents

- [Features](#features)
- [Supported environments](#supported-environments)
- [Quick start](#quick-start)
- [CLI overview](#cli-overview)
- [Components](#components)
- [Paths, logs, and state](#paths-logs-and-state)
- [Upgrade and uninstall](#upgrade-and-uninstall)
- [Troubleshooting](#troubleshooting)

---

## Supported environments

`seedboxctl` performs runtime detection before making changes.

| Item | Support |
| --- | --- |
| OS | Debian 11 or newer; Ubuntu 20.04 or newer. |
| Architecture | `amd64` / `x86_64` and `arm64` / `aarch64` |
| Init system | systemd is required for host/system services. Rootless mode can fall back to `screen` or daemon mode. |
| Package manager | APT-based Debian/Ubuntu hosts for root/admin installs. |
| Rootless installs | Supported for qBittorrent only. Rootless mode does not run APT, create users, tune the host, install Docker, or install BBR. |

Host-level components such as tuning, Docker, Vertex, and BBR should be run only on a host or full VM that you control.

---

## Quick start

### For Dedicated Seedbox

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) \
  -u jerry048 \
  -p 'change-this-password' \
  -c 3072 \
  -q 5.2.2 -l v2.0.13 \
  -b -v -r \
  -x

seedboxctl version
```
### For Shared Seedbox
```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --rootless \
  -u jerry048 \
  -p 'change-this-password' \
  -c 3072 \
  -q 5.2.2 -l v2.0.13 \
  --service-mode auto

~/.local/bin/seedboxctl version
```
#### Options
	1. -u: username 
	2. -p: password
	3. -c: Cache size for torrent client
	4. -q: qBittorrent versions
	5. -l: libtorrent versions
	6. -b: Install autobrr
	7. -v: Install vertex
	8. -r: Install autoremove-torrents
	9. -3: Enable BBR V3
	10.-x: Enable BBRx
	11. Customize ports

##### After `Install.sh` runs, you can call the script via `seedboxctl`

---

## CLI overview

```bash
seedboxctl install --profile dedicated|shared [options]
seedboxctl qbittorrent add-user|install-self|upgrade|uninstall|status|logs [options]
seedboxctl autobrr install|upgrade|uninstall|status [options]
seedboxctl autoremove-torrents install|upgrade|uninstall|status [options]
seedboxctl vertex install|upgrade|uninstall|status [options]
seedboxctl docker install|uninstall|status [options]
seedboxctl tuning apply|uninstall|status [options]
seedboxctl bbr install|uninstall|status [options]
seedboxctl status [--json]
seedboxctl logs qbittorrent --user USER
seedboxctl doctor [--bundle]
seedboxctl list qbittorrent
seedboxctl version
```

Use built-in help for component-specific flags:

```bash
seedboxctl help
seedboxctl qbittorrent help
seedboxctl tuning help
seedboxctl bbr help
seedboxctl autobrr help
seedboxctl autoremove-torrents help
seedboxctl vertex help
seedboxctl docker help
```

---

## Components

### qBittorrent

Install a root-managed instance for a Linux user with distro packages :

```bash
printf '%s' 'change-this-password' | sudo seedboxctl qbittorrent add-user \
  --user jerry048 \
  --password-stdin \
  --source distro \
  --cache 3072 \
  --web-port 8080 \
  --incoming-port 45000
```

Install a rootless instance for the current user:

```bash
printf '%s' 'change-this-password' | seedboxctl qbittorrent install-self \
  --password-stdin \
  --webui-username jerry048 \
  --source static \
  --qb-version 5.2.2 \
  --libtorrent-version v2.0.13 \
  --cache 3072 \
  --web-port 8080 \
  --incoming-port 45000 \
  --service-mode auto
```

Common qBittorrent options:

| Option | Description |
| --- | --- |
| `--password-stdin` | Read the WebUI password from stdin. Recommended. |
| `--password-file FILE` | Read the WebUI password from a file. |
| `--password PASSWORD` | Pass the WebUI password as an argument. Convenient, but less safe. |
| `--cache MIB` | qBittorrent cache size in MiB. Default: `3072`. |
| `--qb-tuning-profile PROFILE` | Config-tuning profile: `auto`, `legacy`, `1g-hdd`, `1g-hdd-raid0`, `1g-ssd`, `1g-nvme`, `1g-ceph`, `10g-hdd`, `10g-hdd-raid0`, `10g-ssd`, `10g-nvme`, or `10g-ceph`. |
| `--web-port PORT` | WebUI port. Default: `8080`. Aliases: `--qb-web-port`, `--qb-port`. |
| `--incoming-port PORT` | Incoming BitTorrent port. Default: `45000`. Alias: `--qb-incoming-port`. |
| `--source distro` | Install/use the OS `qbittorrent-nox` package. Root/admin mode only. |
| `--source static` | Use a bundled or downloaded static `qbittorrent-nox` build. |
| `--source existing` | Use an existing `qbittorrent-nox` from `PATH`, `~/bin`, or `~/.local/bin`. |
| `--qb-version VERSION` | qBittorrent version for static source. |
| `--libtorrent-version VERSION` | libtorrent version for static source. |
| `--service-mode MODE` | `system`, `user`, `screen`, `daemon`, `auto`, or `prompt`. |
| `--webui-username NAME` | Set WebUI username separately from the Unix user. |
| `--allow-unverified-downloads` | Permit downloads without SHA-256 verification. Avoid for production unless you have reviewed the artifact source. |

List available qBittorrent sources and static manifest entries:

```bash
seedboxctl list qbittorrent
```

Static qBittorrent versions are selected from `manifests/qbittorrent.tsv`. If `--qb-version` or `--libtorrent-version` is missing, or if the supplied pair is not listed for the current architecture, an interactive install prints the manifest choices and asks you to select one. Non-interactive installs, such as CI/cron/no-TTY sessions, print the valid choices and exit so you can rerun with a valid manifest pair. `--source distro` and `--source existing` do not use the manifest and do not show the version menu.

Static binary resolution order after a manifest pair is selected:

1. A matching bundled binary under `Torrent Clients/qBittorrent/<arch>/`.
2. A URL from `manifests/qbittorrent.tsv`.
3. A default raw GitHub URL derived from the selected qBittorrent/libtorrent version and architecture.

Downloaded static binaries require a SHA-256 checksum unless `--allow-unverified-downloads` is explicitly passed.

#### qBittorrent config tuning profiles

`--qb-tuning-profile auto` is the default. It detects the highest non-loopback NIC speed and the storage backing the download path, then maps to one of the table profiles. Use `--qb-tuning-profile legacy` to keep the older automatic heuristic, or pass a profile explicitly:

| Profile | Async I/O threads | Send buffer low | Send buffer watermark | Factor |
| --- | ---: | ---: | ---: | ---: |
| `1g-hdd` | 4 | 1024 | 4096 | 150 |
| `1g-hdd-raid0` | 8 | 1024 | 8192 | 150 |
| `1g-ssd` | 12 | 1024 | 8192 | 200 |
| `1g-nvme` | 16 | 1024 | 16384 | 200 |
| `1g-ceph` | 8 | 1024 | 16384 | 200 |
| `10g-hdd` | 4 | 1024 | 16384 | 150 |
| `10g-hdd-raid0` | 8 | 1024 | 16384 | 150 |
| `10g-ssd` | 16 | 2048 | 32768 | 200 |
| `10g-nvme` | 32 | 2048 | 32768 | 200 |
| `10g-ceph` | 16 | 2048 | 32768 | 200 |

Additional version-gated settings are applied only where they belong:

| Gate | Settings written |
| --- | --- |
| libtorrent 2.x | `Session\HashingThreadsCount`; `Session\DiskIOType` for NVMe/Ceph profiles.
| qBittorrent 4.4.5+ | `Session\ConnectionSpeed=500` |
| qBittorrent 4.5.5+ | `Session\DiskQueueSize` and `Session\RequestQueueSize`|
| qBittorrent 5.0.1+ with libtorrent 2.x Ceph profiles | `Session\DiskIOType=SimplePreadPwrite`; older libtorrent-2 qBittorrent releases use `Posix` because `SimplePreadPwrite` did not exist yet. |

Status and logs:

```bash
sudo seedboxctl qbittorrent status --user jerry048
sudo seedboxctl qbittorrent status --user jerry048 --json
sudo seedboxctl qbittorrent logs --user jerry048
sudo journalctl -u seedbox-qbittorrent-jerry048.service -n 200 --no-pager
```

Rootless status and logs:

```bash
seedboxctl qbittorrent status
seedboxctl qbittorrent logs
systemctl --user status seedbox-qbittorrent.service --no-pager
journalctl --user -u seedbox-qbittorrent.service -n 200 --no-pager
```

### Host tuning

Apply adaptive seedbox tuning:

```bash
sudo seedboxctl tuning apply
```

Useful tuning options:

```text
--storage auto|hdd|ssd|sata-ssd|nvme
--interface IFACE
--netdev IFACE
--link-speed-mbps N
--link-speed 1g|10g|25g|2500m
--txqueuelen N
--initial-cwnd N
--no-sysctl
--no-limits
--no-ring-buffer
--no-rss
--no-rps
--no-rfs
--no-xps
--no-initial-cwnd
--no-disk-scheduler
--no-net-queue-tuning
```

Tuning writes managed drop-ins instead of editing broad system files directly:

```text
/etc/sysctl.d/99-seedbox.conf
/etc/security/limits.d/99-seedbox.conf
/etc/default/seedbox-tuning
/usr/local/sbin/seedbox-runtime-tuning
/etc/systemd/system/seedbox-safe-tuning.service
```

Check or remove tuning:

```bash
sudo seedboxctl tuning status
sudo seedboxctl tuning uninstall
```

A reboot may be required to fully revert runtime kernel/network values after uninstall.

### BBR variants

##### Read more about the BBR variants at [here](https://github.com/jerry048/Trove/blob/main/BBR-Install/BBR/README.md)

Install a BBR algorithm:

```bash
sudo seedboxctl bbr install --bbr-algo bbrx
```

Supported algorithms:

```text
bbrv3
bbrx
bbrw
bbr_brutal
bbrw_brutal
```

Pin and verify the external BBR installer:

```bash
sudo seedboxctl bbr install \
  --bbr-algo bbrx \
  --bbr-script-url 'https://raw.githubusercontent.com/jerry048/Trove/<commit>/BBR-Install/BBRInstall.sh' \
  --bbr-raw-base 'https://raw.githubusercontent.com/jerry048/Trove/<commit>/BBR-Install/BBR' \
  --bbr-script-sha256 '<sha256>'
```

Check or remove BBR-managed state:

```bash
sudo seedboxctl bbr status
sudo seedboxctl bbr uninstall --bbr-algo bbrx
```

`bbrv3` uses a kernel package path and may require a reboot. For DKMS-based variants, if headers for the running kernel are missing locally and cannot be installed with `apt install linux-headers-$(uname -r)`, Seedbox automatically installs the distribution generic kernel image and headers, records a pending BBR state, and asks you to reboot into the generic kernel before rerunning BBR installation. DKMS/kernel changes are high risk; test on a disposable VPS first.

### Docker

Install Docker:

```bash
sudo seedboxctl docker install --docker-source official
```

Alternative distro packages:

```bash
sudo seedboxctl docker install --docker-source distro
```

Status and uninstall:

```bash
sudo seedboxctl docker status
sudo seedboxctl docker uninstall
sudo seedboxctl docker uninstall --purge --yes
```

### Vertex

Install Vertex in Docker:

```bash
sudo seedboxctl vertex install \
  --vertex-port 3000 \
  --vertex-data-dir /root/vertex
```

Defaults:

```text
image: lswl/vertex:stable
data:  /root/vertex
port:  3000
```

Use host networking only when you intentionally want Docker host networking:

```bash
sudo seedboxctl vertex install --host-network
```

Status, uninstall:

```bash

sudo seedboxctl vertex status
sudo seedboxctl vertex uninstall
sudo seedboxctl vertex uninstall --purge --yes
```

### autobrr

Install autobrr for a user:

```bash
sudo seedboxctl autobrr install \
  --user jerry048 \
  --autobrr-port 7474
```

Status, uninstall:

```bash

sudo seedboxctl autobrr status --user jerry048
sudo seedboxctl autobrr uninstall --user jerry048
sudo seedboxctl autobrr uninstall --user jerry048 --purge --yes
```

For standard GitHub release assets, `seedboxctl` attempts to resolve and verify the matching checksums file. For custom URLs, provide `--autobrr-sha256` or explicitly pass `--allow-unverified-downloads` after reviewing the artifact.

### autoremove-torrents

Install under a target user's home with `pipx`:

```bash
sudo seedboxctl autoremove-torrents install --user jerry048
```

The generated config is a safe starter template. Edit it before enabling automatic removal:

```bash
sudo -e /home/jerry048/.config/autoremove-torrents/config.yml
sudo systemctl enable --now seedbox-autoremove-torrents-jerry048.timer
```

Install and enable the timer immediately:

```bash
sudo seedboxctl autoremove-torrents install --user jerry048 --enable-autoremove
```

Upgrade, status, uninstall:

```bash
sudo seedboxctl autoremove-torrents upgrade --user jerry048
sudo seedboxctl autoremove-torrents status --user jerry048
sudo seedboxctl autoremove-torrents uninstall --user jerry048
sudo seedboxctl autoremove-torrents uninstall --user jerry048 --purge --yes
```

---

## Paths, logs, and state

### Root/admin mode

```text
/opt/seedbox/Dedicated-Seedbox/                  # default minimal runtime
/opt/seedbox/qbittorrent/                        # static qBittorrent binaries
/var/log/seedbox/                                # action logs
/var/log/seedbox/steps/                          # per-step command logs
/var/log/seedbox/latest.log                      # latest log symlink
/var/lib/seedbox/state/                          # component state files
/home/<user>/.config/qBittorrent/qBittorrent.conf
/home/<user>/qbittorrent/Downloads
/etc/systemd/system/seedbox-qbittorrent-<user>.service
```

### Rootless mode

```text
~/.local/share/seedbox/Dedicated-Seedbox/        # default minimal runtime
~/.local/share/seedbox/qbittorrent/              # static qBittorrent binaries
~/.local/state/seedbox/logs/                     # action logs
~/.local/state/seedbox/logs/steps/               # per-step command logs
~/.local/state/seedbox/state/                    # state files
~/.config/qBittorrent/qBittorrent.conf
~/.config/systemd/user/seedbox-qbittorrent.service
~/qbittorrent/Downloads
~/bin/qbittorrent-nox                            # convenience symlink for static installs
~/.local/bin/seedbox-qbittorrent-restart         # screen/daemon restart helper when used
```

Overall status:

```bash
seedboxctl status
seedboxctl status --json
```

Diagnostic summary:

```bash
seedboxctl doctor
seedboxctl doctor --bundle
```

---

## Upgrade and uninstall

### qBittorrent

Upgrade distro package based install:

```bash
sudo seedboxctl qbittorrent upgrade --user jerry048 --source distro
```

Upgrade static install:

```bash
printf '%s' 'change-this-password' | sudo seedboxctl qbittorrent upgrade \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.2.2 \
  --libtorrent-version v2.0.13
```

Non-destructive uninstall:

```bash
sudo seedboxctl qbittorrent uninstall --user jerry048
```

This stops and removes startup files but keeps qBittorrent config and downloads.

Purge qBittorrent config/data:

```bash
sudo seedboxctl qbittorrent uninstall --user jerry048 --purge --yes
```

Rootless uninstall:

```bash
seedboxctl qbittorrent uninstall
seedboxctl qbittorrent uninstall --purge --yes
```

### Optional components

```bash
sudo seedboxctl autobrr upgrade --user jerry048
sudo seedboxctl autoremove-torrents upgrade --user jerry048
sudo seedboxctl vertex upgrade

sudo seedboxctl autobrr uninstall --user jerry048
sudo seedboxctl autoremove-torrents uninstall --user jerry048
sudo seedboxctl vertex uninstall
sudo seedboxctl docker uninstall
sudo seedboxctl tuning uninstall
sudo seedboxctl bbr uninstall --bbr-algo bbrx
```

Use `--purge --yes` only when you intentionally want to remove component data/configuration.

---

## Troubleshooting

Start with:

```bash
seedboxctl doctor
seedboxctl status
```

Create a diagnostic bundle:

```bash
seedboxctl doctor --bundle
```

Root/admin logs:

```text
/var/log/seedbox/latest.log
/var/log/seedbox/steps/
/var/lib/seedbox/state/
```

Rootless logs:

```text
~/.local/state/seedbox/logs/latest.log
~/.local/state/seedbox/logs/steps/
~/.local/state/seedbox/state/
```

qBittorrent system service:

```bash
sudo systemctl status seedbox-qbittorrent-jerry048.service --no-pager
sudo journalctl -u seedbox-qbittorrent-jerry048.service -n 200 --no-pager
```

qBittorrent rootless user service:

```bash
systemctl --user status seedbox-qbittorrent.service --no-pager
journalctl --user -u seedbox-qbittorrent.service -n 200 --no-pager
```

qBittorrent screen fallback:

```bash
screen -ls
screen -r seedbox-qbittorrent
```

Common causes detected by `doctor` and step logs include APT locks, DNS failures, failed downloads, missing commands, permission errors, occupied ports, checksum mismatches, and qBittorrent password-hash family changes during upgrade/downgrade.
