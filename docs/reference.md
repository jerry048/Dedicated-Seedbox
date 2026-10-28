# Advanced reference

[Main guide](../README.md) · [简体中文](reference.zh-CN.md)

Command options, component setup, tuning values, paths, and recovery behavior for Dedicated-Seedbox V2.1.3. Start with the [main guide](../README.md) for routine work.

---

## Contents

- [Supported environments](#supported-environments)
- [Installation examples and legacy aliases](#installation-examples)
- [CLI overview](#cli-overview)
- [Status and monitoring](#status)
- [Log viewing](#logs)
- [Components](#components)
  - [Deluge](#deluge)
  - [qBittorrent](#qbittorrent)
  - [Host tuning](#host-tuning)
  - [BBR variants](#bbr-variants)
  - [Docker](#docker)
  - [Vertex](#vertex)
  - [autobrr](#autobrr)
  - [autoremove-torrents](#autoremove-torrents)
- [Paths, logs, and state](#paths-logs-and-state)

---

## Supported environments

`seedboxctl` detects the runtime before changing anything.

| Item              | Support                                                                                                                      |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| OS                | Debian 11 or newer; Ubuntu 20.04 or newer.                                                                                   |
| Architecture      | `amd64` / `x86_64` and `arm64` / `aarch64`                                                                                   |
| Init system       | systemd is required for host/system services. Rootless mode can fall back to `screen` or daemon mode.                        |
| Package manager   | APT-based Debian/Ubuntu hosts for root/admin installs.                                                                       |
| Rootless installs | Supported for qBittorrent only. Rootless mode does not run APT, create users, tune the host, install Docker, or install BBR. |

Run tuning, Docker, Vertex, and BBR only on a host or full VM you control.

Deluge needs root and systemd. 1.3.15 supports Debian 11+/Ubuntu 20.04+; 2.2.0 requires Debian 12+/Ubuntu 22.04+. Coverage is amd64 only. Deluge is not installed by default; the unsupported legacy runtime emits a security warning.

---

## Installation examples

### Dedicated seedbox

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) \
  --user jerry048 \
  --password-stdin \
  --cache 3072 \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --components qbittorrent,tuning,autobrr,vertex,autoremove-torrents \
  < /path/to/password.txt

seedboxctl version
```

### Shared/rootless seedbox

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) \
  --rootless \
  --webui-username jerry048 \
  --password-stdin \
  --cache 3072 \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --service-mode auto \
  < /path/to/password.txt

~/.local/bin/seedboxctl version
```

Run the dedicated example as root and the rootless example without root or sudo. Create a private password file first and replace the example path.

`--password`, `--password-file`, and `--password-stdin` are mutually exclusive. `--password-stdin` requires a pipe or file redirection, not a terminal. Invalid combinations fail before installation starts.

#### Legacy wrapper aliases

| Short option     | Canonical option or meaning                                                           |
| ---------------- | ------------------------------------------------------------------------------------- |
| `-u USER`        | `--user USER`; rootless legacy usage sets the WebUI username                          |
| `-p PASSWORD`    | `--password PASSWORD`; prefer a password file or stdin                                |
| `-c N`           | `--cache N` (MiB)                                                                     |
| `-q VERSION`     | `--qb-version VERSION`                                                                |
| `-l VERSION`     | `--libtorrent-version VERSION`                                                        |
| `-b`, `-v`, `-r` | Add autobrr, Vertex, or autoremove-torrents to `--components`                         |
| `-3`, `-x`       | `--bbr-algo bbrv3`, `--bbr-algo bbrx`; uses the verified bundled installer by default |
| `-o`             | Prompt for custom ports                                                               |
| `-T`             | `--no-tuning`                                                                         |
| `-L LANG`        | `--lang LANG`                                                                         |
| `-h`             | `--help`                                                                              |

After `Install.sh`, use `seedboxctl`. Examples use canonical long options; aliases remain supported.

---

## CLI overview

Uppercase words are metavariables; `[...]` is optional and `{a|b}` means choose one. Summaries are not shell commands. Every command accepts a global `--lang LANG` after `seedboxctl`.

```text
seedboxctl install --profile {dedicated|shared} [OPTIONS]
seedboxctl qbittorrent {add-user|install-self|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl deluge {install|add-user|upgrade|uninstall|build-runtime|status|logs} [OPTIONS]
seedboxctl autobrr {install|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl autoremove-torrents {install|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl vertex {install|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl docker {install|uninstall|status|logs} [OPTIONS]
seedboxctl tuning {apply|uninstall|status|logs} [OPTIONS]
seedboxctl bbr {install|uninstall|status|logs} [OPTIONS]
seedboxctl status [--json] [--check]
seedboxctl logs COMPONENT [OPTIONS]
seedboxctl logs installer [--run RUN_ID] [--step STEP_ID] [OPTIONS]
seedboxctl list qbittorrent
seedboxctl version
```

Component-specific flags:

```bash
seedboxctl help
seedboxctl qbittorrent help
seedboxctl deluge help
seedboxctl tuning help
seedboxctl bbr help
seedboxctl autobrr help
seedboxctl autoremove-torrents help
seedboxctl vertex help
seedboxctl docker help
```

---

## Status

`seedboxctl status` reads installer-managed state.

```bash
seedboxctl status
seedboxctl status \
  --json \
  --check
sudo seedboxctl qbittorrent status \
  --user jerry048 \
  --json
sudo seedboxctl autoremove-torrents status \
  --user jerry048 \
  --check
sudo seedboxctl vertex status \
  --vertex-name my-vertex \
  --json
```

JSON variables (`{"instances":[...]}`, one object per record):

| Variable           | Values                                                                                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `component`        | `qbittorrent-instance`, `deluge-instance`, `autobrr`, `autoremove-torrents`, `vertex`, `docker-engine`, `docker-purge`, `tuning`, `bbr`                       |
| `id`               | record identifier within the component                                                                                                                        |
| `user`             | Unix account                                                                                                                                                  |
| `webui_user`       | WebUI login                                                                                                                                                   |
| `rootless`         | `0` or `1`                                                                                                                                                    |
| `service`          | recorded unit or service name                                                                                                                                 |
| `service_mode`     | `system`, `user`, `screen`, `daemon`                                                                                                                          |
| `web_port`         | recorded WebUI port                                                                                                                                           |
| `status`           | `active`, `inactive`, `unknown`                                                                                                                               |
| `kind`             | `service`, `process`, `timer`, `container`, `configuration`, `maintenance`                                                                                    |
| `runtime_state`    | `running`, `stopped`, `failed`, `missing`, `unknown`, `identity-mismatch`, `waiting`, `disabled`, `masked`, `paused`, `applied`, `selected`, `pending-reboot` |
| `enabled`          | unit enablement (`enabled`, `disabled`, `masked`, …); Deluge uses `mixed` when its units differ                                                               |
| `recorded_version` | saved application version                                                                                                                                     |
| `last_job_result`  | last timer/oneshot result                                                                                                                                     |
| `reason`           | failure or observation detail                                                                                                                                 |
| `check_ok`         | `true` or `false`                                                                                                                                             |

`--json` prints JSON. `--check` returns `1` when expectations are unmet or no record matches, `0` otherwise, `2` on invalid syntax. `--user USER` filters qBittorrent, Deluge, autobrr, and autoremove-torrents; `--vertex-name NAME` filters Vertex. `check_ok` is an expectation check, not application health.

## Logs

`seedboxctl logs COMPONENT` and `seedboxctl COMPONENT logs` are equivalent read-only viewers.

```bash
sudo seedboxctl logs qbittorrent \
  --user jerry048 \
  --lines 100
seedboxctl qbittorrent logs \
  --source application \
  --follow
sudo seedboxctl autoremove-torrents logs \
  --user jerry048 \
  --since '2026-10-22 12:00:00'
sudo seedboxctl vertex logs \
  --vertex-name my-vertex \
  --follow
seedboxctl logs installer
seedboxctl logs installer --list
seedboxctl logs --help
```

| Option           | Values                                                         |
| ---------------- | -------------------------------------------------------------- |
| `--source`       | `auto` (default), `service`, `application`, `installer`, `all` |
| `--lines N`      | 1–10000, default 200 per source                                |
| `--since TIME`   | journalctl/Docker time filter; prefer absolute timestamps      |
| `--follow`       | stream one source until interrupted                            |
| `--list`         | list sources, or installer runs/steps                          |
| `--run RUN_ID`   | installer run basename without `.log`                          |
| `--step STEP_ID` | step within a run, for example `qb.upgrade.start`              |

| Source        | Reads                                                                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `auto`        | system/user qBittorrent journal, daemon/screen application file; other components use service/container sources; BBR uses installer logs |
| `service`     | exact systemd journal; autoremove-torrents includes job and timer; Vertex reads the verified container                                   |
| `application` | qBittorrent application file (`[Application] FileLogger\Path`, `FileLogger\Enabled`)                                                     |
| `installer`   | installer run/step logs                                                                                                                  |
| `all`         | all supported sources in order                                                                                                           |

Root must pass `--user USER` for qBittorrent, Deluge, autobrr, and autoremove-torrents; non-root defaults to the current account. Vertex uses `--vertex-name NAME`. Log scope is `/var/log/seedbox` for root and `~/.local/state/seedbox/logs` otherwise; `SEEDBOX_LOG_BASE` overrides it. Logs may contain secrets; review before sharing. Exit: `0` read, `1` unavailable/no match/partial, `2` invalid options.

## Components

### Deluge

```bash
sudo seedboxctl deluge add-user \
  --user delugeuser \
  --password-stdin \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 1.2.20 \
  --deluge-web-port 8112 \
  --deluge-rpc-port 58846 \
  --deluge-incoming-port 45000 \
  --deluge-cache-mib 256 \
  --jobs 2 \
  --source-dir /path/to/sources \
  < /path/to/password.txt
```

| Option                                | Description                                                         |
| ------------------------------------- | ------------------------------------------------------------------- |
| `--user USER`                         | Instance owner; created if missing.                                 |
| `--password-stdin`                    | Read the WebUI password from stdin.                                 |
| `--password-file FILE`                | Read the WebUI password from a file.                                |
| `--password PASSWORD`                 | Pass the password as an argument. Less safe.                        |
| `--deluge-version VERSION`            | `1.3.15` (default) or `2.2.0`.                                      |
| `--deluge-libtorrent-version VERSION` | `1.1.14` with 1.3.15; `1.2.20` or `2.0.15` (default) with 2.2.0.    |
| `--deluge-web-port PORT`              | WebUI port. Default `8112`.                                         |
| `--deluge-rpc-port PORT`              | RPC port. Default `58846`.                                          |
| `--deluge-incoming-port PORT`         | BitTorrent port. Default `45000`.                                   |
| `--deluge-cache-mib N`                | Cache in MiB for libtorrent 1.x; default `256`. Rejected by 2.0.15. |
| `--jobs N`                            | Runtime build jobs. Default `2`.                                    |
| `--source-dir DIR`                    | Verified local sources for an offline build.                        |

Aliases: `--web-port`, `--rpc-port`, `--incoming-port`, `--cache-mib`; `--libtorrent-version` on Deluge-only commands.

Upgrade, status, uninstall:

```bash
sudo seedboxctl deluge upgrade --user delugeuser
sudo seedboxctl deluge status --user delugeuser --check
sudo seedboxctl deluge uninstall --user delugeuser
```

### qBittorrent

#### Static install

Root-managed instance for a Linux user, using a pinned static pair:

```bash
sudo seedboxctl qbittorrent add-user \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --cache 3072 \
  --web-port 8080 \
  --incoming-port 45000 \
  --webui-username jerry048 \
  --service-mode system \
  --qb-tuning-profile auto \
  --storage auto \
  --storage-path /path/to/storage \
  --interface auto \
  --link-speed-mbps 1000 \
  < /path/to/password.txt
```

| Option                                     | Description                                                                                                                                                               |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--user USER`                              | Linux account that owns the instance.                                                                                                                                     |
| `--password-stdin`                         | Read the WebUI password from stdin. Recommended.                                                                                                                          |
| `--password-file FILE`                     | Read the WebUI password from a file.                                                                                                                                      |
| `--password PASSWORD`                      | Pass the WebUI password as an argument. Convenient, less safe.                                                                                                            |
| `--source static`                          | Bundled or downloaded static `qbittorrent-nox` (Install.sh default).                                                                                                      |
| `--qb-version VERSION`                     | qBittorrent version from the manifest.                                                                                                                                    |
| `--libtorrent-version VERSION`             | libtorrent version from the manifest.                                                                                                                                     |
| `--cache N`                                | Cache size in MiB. Default: `3072`.                                                                                                                                       |
| `--web-port PORT`                          | WebUI port. Default: `8080`. Aliases: `--qb-web-port`, `--qb-port`.                                                                                                       |
| `--incoming-port PORT`                     | Incoming BitTorrent port. Default: `45000`. Alias: `--qb-incoming-port`.                                                                                                  |
| `--webui-username NAME`                    | WebUI username, independent of the Unix user.                                                                                                                             |
| `--service-mode MODE`                      | `system`, `user`, `screen`, `daemon`, `auto`, or `prompt`.                                                                                                                |
| `--qb-tuning-profile PROFILE`              | `auto`, `legacy`, or a `1g-*`/`over1g-*` profile.                                                                                                                         |
| `--storage TYPE`, `--storage-path PATH`    | Storage overrides: `auto`, `hdd`, `hdd-raid0`, `ssd`, `nvme`, `ceph` (`sata-ssd` also accepted). The path selects backing storage for tuning; it does not move downloads. |
| `--interface IFACE`, `--link-speed-mbps N` | Interface/bandwidth overrides. `--netdev` and `--link-speed 2.5g` are also accepted.                                                                                      |
| `--allow-unverified-downloads`             | Permit downloads without SHA-256 verification. Avoid in production unless the artifact source is reviewed.                                                                |

#### Other install sources

Distro package:

```bash
sudo seedboxctl qbittorrent add-user \
  --user jerry048 \
  --password-stdin \
  --source distro \
  --cache 3072 \
  --web-port 8080 \
  --incoming-port 45000 \
  < /path/to/password.txt
```

Existing binary:

```bash
seedboxctl qbittorrent add-user \
  --user jerry048 \
  --password-stdin \
  --source existing \
  --web-port 8080 \
  --incoming-port 45000 \
  < /path/to/password.txt
```

`add-user` manages an instance for `--user USER`. `--source distro` uses the OS `qbittorrent-nox` package; `--source existing` uses one from `PATH`, `~/bin`, or `~/.local/bin`. Both skip the static manifest.

#### Rootless

Current user, without root or sudo:

```bash
seedboxctl qbittorrent install-self \
  --password-stdin \
  --webui-username jerry048 \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --cache 3072 \
  --web-port 8080 \
  --incoming-port 45000 \
  --service-mode auto \
  < /path/to/password.txt
```

The options above apply. `--user` is omitted; `--service-mode` defaults to `auto` and also accepts `prompt`.

#### Tuning profile

Override automatic selection with `--qb-tuning-profile PROFILE`.

| Profile            | Async I/O threads | Send buffer low (MiB) | Send buffer watermark (MiB) | Factor | Request limit (4.5.5+) |
| ------------------ | ----------------: | --------------------: | --------------------------: | -----: | ---------------------: |
| `1g-hdd`           |                 4 |                     3 |                          10 |   150% |                   2000 |
| `1g-hdd-raid0`     |                 8 |                     3 |                          16 |   150% |                   4000 |
| `1g-ssd`           |                12 |                     5 |                          20 |   200% |                   4000 |
| `1g-nvme`          |                16 |                     5 |                          20 |   200% |                   8000 |
| `1g-ceph`          |                 8 |                     5 |                          20 |   200% |                   4000 |
| `over1g-hdd`       |                 4 |                     3 |                          16 |   250% |                   4000 |
| `over1g-hdd-raid0` |                 8 |                     3 |                          16 |   250% |                   8000 |
| `over1g-ssd`       |                16 |                     5 |                          32 |   300% |                  10000 |
| `over1g-nvme`      |                32 |                     5 |                          32 |   300% |                  10000 |
| `over1g-ceph`      |                16 |                     5 |                          32 |   250% |                  10000 |

Version-gated settings:

| Gate                                                 | Settings written                                                                                                               |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| libtorrent 2.x                                       | `Session\HashingThreadsCount`; `Session\DiskIOType` for NVMe/Ceph profiles.                                                    |
| qBittorrent 4.4.5+                                   | `Session\ConnectionSpeed=500`                                                                                                  |
| qBittorrent 4.5.5+                                   | `Session\DiskQueueSize` and `Session\RequestQueueSize`                                                                         |
| qBittorrent 5.0.1+ with libtorrent 2.x Ceph profiles | `Session\DiskIOType=SimplePreadPwrite`; older libtorrent-2 releases use `Posix` because `SimplePreadPwrite` did not exist yet. |

#### Configuration preservation

Upgrades merge the current config instead of replacing it with the template.

- Existing WebUI settings—ports, username, save paths, limits, queueing, authentication/security, custom tuning—override stale installer state.
- Explicit CLI flags override individual settings.
- Known legacy/modern key names and value formats are translated, including the 5.3 WebUI section change. Missing defaults are added.
- Tuning persists unless a profile or hardware option retunes the managed fields.
- `--cache` updates both disk cache and process memory limit; without it, each keeps its value, including automatic or disabled cache.

Settings are reread after the old process stops, preserving shutdown-flushed changes. A mode-`0600` `qBittorrent.conf.pre-upgrade.*` snapshot stays beside the config, even after success. Crossing the 4.1 password-hash boundary requires a password argument. Older targets cannot implement every newer feature: unknown keys are kept but may be ignored, and unsafe conversions—active proxy profiles below 4.6, some HTTPS certificate-format changes, unsupported enums—fail rather than weaken settings. Keep the snapshot when downgrading. Rootless migration needs Python 3, including for 4.1 targets.

#### Upgrade static release

```bash
sudo seedboxctl qbittorrent upgrade \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  < /path/to/password.txt
```

Upgrade, status, uninstall:

```bash
sudo seedboxctl qbittorrent upgrade --user jerry048
sudo seedboxctl qbittorrent status --user jerry048
sudo seedboxctl qbittorrent uninstall --user jerry048
```

### Host tuning

```bash
sudo seedboxctl tuning apply \
  --storage auto \
  --storage-path /path/to/storage \
  --interface auto \
  --link-speed-mbps 1000 \
  --txqueuelen 10000 \
  --initial-cwnd 25 \
  --disk-scheduler-all
```

| Option                             | Description                                                    |
| ---------------------------------- | -------------------------------------------------------------- |
| `--storage TYPE`                   | `auto`, `hdd`, `hdd-raid0`, `ssd`, `sata-ssd`, `nvme`, `ceph`. |
| `--storage-path PATH`              | Path used for storage detection.                               |
| `--interface IFACE`                | Interface to tune; alias `--netdev`.                           |
| `--link-speed-mbps N`              | Bandwidth override.                                            |
| `--link-speed 1g\|10g\|25g\|2500m` | Friendly bandwidth alias.                                      |
| `--txqueuelen N`                   | NIC transmit queue length.                                     |
| `--initial-cwnd N`                 | Initial congestion window in packets.                          |
| `--disk-scheduler-all`             | Apply scheduler policy to all eligible disks.                  |
| `--no-sysctl`                      | Skip sysctl settings.                                          |
| `--no-limits`                      | Skip ulimits.                                                  |
| `--no-cpu-tuning`                  | Skip CPU policy.                                               |
| `--no-read-ahead`                  | Skip read-ahead.                                               |
| `--no-ring-buffer`                 | Skip NIC ring tuning.                                          |
| `--no-rss`                         | Skip receive-side scaling.                                     |
| `--no-rps`                         | Skip receive packet steering.                                  |
| `--no-rfs`                         | Skip receive flow steering.                                    |
| `--no-xps`                         | Skip transmit packet steering.                                 |
| `--no-initial-cwnd`                | Skip initial cwnd/initrwnd.                                    |
| `--no-disk-scheduler`              | Skip scheduler policy.                                         |
| `--no-net-queue-tuning`            | Skip all NIC queue tuning.                                     |

Managed drop-ins:

```text
/etc/sysctl.d/99-seedbox.conf
/etc/security/limits.d/99-seedbox.conf
/etc/default/seedbox-tuning
/usr/local/sbin/seedbox-runtime-tuning
/etc/systemd/system/seedbox-safe-tuning.service
```

Check or remove:

```bash
sudo seedboxctl tuning status
sudo seedboxctl tuning uninstall
```

### BBR variants

##### Read more about the BBR variants at [here](https://github.com/jerry048/Trove/blob/main/BBR-Install/BBR/README.md)

All variants default to the SHA-256-verified bundled installer: `sudo seedboxctl bbr install --bbr-algo bbrx`. DKMS variants support Debian 11–13 and Ubuntu 20.04/22.04/24.04/26.04 with kernel 5.4–7.1.x and matching headers. No BBRv3 package is configured for Ubuntu 20.04; availability elsewhere varies by OS/architecture. The options below show how to select a custom installer, which requires a checksum or explicit verification bypass.

Ubuntu 20.04 amd64 validation: all five DKMS variants built and installed with GCC 9.4/DKMS 2.8.1 against `5.4.0-216-generic` and `5.15.0-139-generic`. Both kernels were booted in QEMU; each module passed loading, congestion-control selection, a SHA-256-verified 1 MiB loopback TCP transfer, restoration to Cubic, and unloading. ARM64, Secure Boot, and long-duration/performance testing are not covered by these checks.

Uninstall unloads the module before removing DKMS files; busy modules retain their installation and state. BBRv3 status requires the running kernel to match the recorded `kernel_release`, not just the `bbr` algorithm name. Reinstall older BBRv3 records to capture that release. Custom BBRv3 installers must write the target release to the supplied `BBR_KERNEL_RESULT_FILE`; otherwise status remains unverified.

```bash
sudo seedboxctl bbr install \
  --bbr-algo bbrx \
  --bbr-script-url 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBRInstall.sh' \
  --bbr-raw-base 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBR' \
  --bbr-script-sha256 SHA256 \
  --bbr-lang en \
  --force-runtime \
  --upgrade-system \
  --no-clear
```

| Option                             | Description                                                       |
| ---------------------------------- | ----------------------------------------------------------------- |
| `--bbr-algo ALGO`                  | `bbrv3`, `bbrx`, `bbrx_old`, `bbrw`, `bbr_brutal`, `bbrw_brutal`. |
| `--bbr-script-url URL`             | Installer URL.                                                    |
| `--bbr-script-sha256 SHA256`       | Verify the installer.                                             |
| `--bbr-raw-base URL`               | Source base for DKMS sources.                                     |
| `--bbr-lang LANG`                  | Installer language: `en`, `zh-CN`, `zh-TW`.                       |
| `--allow-unverified-bbr-installer` | Skip installer verification after review.                         |
| `--force-runtime`                  | Allow containers/WSL.                                             |
| `--upgrade-system`                 | Pass `--upgrade-system` to the installer when supported.          |
| `--no-clear`                       | Pass `--no-clear` when supported.                                 |

Check or remove:

```bash
sudo seedboxctl bbr status
sudo seedboxctl bbr uninstall --bbr-algo bbrx
sudo seedboxctl bbr uninstall --bbr-algo bbrx_old
```

### Docker

```bash
sudo seedboxctl docker install \
  --docker-source official \
  --allow-docker-package-removal
```

| Option                           | Description                               |
| -------------------------------- | ----------------------------------------- |
| `--docker-source SOURCE`         | `official` (default) or `distro`.         |
| `--allow-docker-package-removal` | Consent to removing conflicting packages. |

```bash
sudo seedboxctl docker status
sudo seedboxctl docker uninstall
sudo seedboxctl docker uninstall \
  --purge \
  --yes
```

Purge requires `--yes` **before** any stop, disable, or package change.

### Vertex

```bash
sudo seedboxctl vertex install \
  --vertex-name vertex \
  --vertex-port 3000 \
  --vertex-data-dir /root/vertex \
  --vertex-image lswl/vertex:stable \
  --timezone Asia/Shanghai \
  --user WEBUI_USER \
  --password-stdin \
  --docker-source official \
  --allow-docker-package-removal \
  --force \
  --host-network \
  < /path/to/password.txt
```

| Option                           | Description                                             |
| -------------------------------- | ------------------------------------------------------- |
| `--vertex-name NAME`             | Container name. Default `vertex`.                       |
| `--vertex-port PORT`             | Published WebUI port. Default `3000`.                   |
| `--vertex-data-dir DIR`          | Host data directory. Default `/root/vertex`.            |
| `--vertex-image IMAGE`           | Image. Default `lswl/vertex:stable`.                    |
| `--timezone TZ`                  | Container timezone. Default `Asia/Shanghai`.            |
| `--user WEBUI_USER`              | Vertex WebUI username.                                  |
| `--password-stdin`               | Read the WebUI password from stdin.                     |
| `--password-file FILE`           | Read the WebUI password from a file.                    |
| `--password PASSWORD`            | Pass the password as an argument. Less safe.            |
| `--docker-source SOURCE`         | `official` (default) or `distro`.                       |
| `--allow-docker-package-removal` | Consent to removing conflicting packages.               |
| `--force`                        | Replace an existing managed instance.                   |
| `--host-network`                 | Use Docker host networking instead of a published port. |

Defaults:

```text
image: lswl/vertex:stable
data:  /root/vertex
port:  3000
```

Upgrade, status, uninstall:

```bash
sudo seedboxctl vertex upgrade
sudo seedboxctl vertex status
sudo seedboxctl vertex uninstall
sudo seedboxctl vertex uninstall \
  --purge \
  --yes
```

Pass the same `--vertex-name` used at install:

```bash
sudo seedboxctl vertex status --vertex-name my-vertex
sudo seedboxctl vertex upgrade --vertex-name my-vertex
sudo seedboxctl vertex uninstall --vertex-name my-vertex
```

### autobrr

```bash
sudo seedboxctl autobrr install \
  --user jerry048 \
  --autobrr-port 7474 \
  --autobrr-url 'https://github.com/autobrr/autobrr/releases/download/VERSION/autobrr_VERSION_linux_x86_64.tar.gz' \
  --autobrr-sha256 SHA256 \
  --allow-unverified-downloads \
  --force
```

| Option                         | Description                     |
| ------------------------------ | ------------------------------- |
| `--user USER`                  | Service account.                |
| `--autobrr-port PORT`          | WebUI port. Default `7474`.     |
| `--autobrr-url URL`            | Custom release archive.         |
| `--autobrr-sha256 SHA256`      | Verify the archive.             |
| `--allow-unverified-downloads` | Skip verification after review. |
| `--force`                      | Regenerate the full config.     |

Upgrade, status, uninstall:

```bash
sudo seedboxctl autobrr upgrade --user jerry048
sudo seedboxctl autobrr status --user jerry048
sudo seedboxctl autobrr uninstall --user jerry048
sudo seedboxctl autobrr uninstall \
  --user jerry048 \
  --purge \
  --yes
```

Standard GitHub releases resolve and verify the matching checksums file. Custom URLs need `--autobrr-sha256` or, after review, explicit `--allow-unverified-downloads`.

### autoremove-torrents

```bash
sudo seedboxctl autoremove-torrents install \
  --user jerry048 \
  --enable-autoremove \
  --force
```

| Option                | Description                 |
| --------------------- | --------------------------- |
| `--user USER`         | Service account.            |
| `--enable-autoremove` | Enable and start the timer. |
| `--force`             | Replace an existing config. |

The generated config is a safe starter template. Edit it before enabling automatic removal:

```bash
sudo -e /home/jerry048/.config/autoremove-torrents/config.yml
sudo systemctl enable --now seedbox-autoremove-torrents-jerry048.timer
```

Upgrade, status, uninstall:

```bash
sudo seedboxctl autoremove-torrents upgrade --user jerry048
sudo seedboxctl autoremove-torrents status --user jerry048
sudo seedboxctl autoremove-torrents uninstall --user jerry048
sudo seedboxctl autoremove-torrents uninstall \
  --user jerry048 \
  --purge \
  --yes
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
/home/USER/.config/qBittorrent/qBittorrent.conf
/home/USER/qbittorrent/Downloads
/etc/systemd/system/seedbox-qbittorrent-USER.service
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
