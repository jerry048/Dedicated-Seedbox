# Advanced reference

[Main guide](../README.md) · [简体中文](reference.zh-CN.md)

Detailed command options, component setup, tuning values, file locations, and recovery behavior for Dedicated-Seedbox V2.1.0. For the everyday install, upgrade, uninstall, and diagnostic commands, start with the [main guide](../README.md).

---

## Contents

- [Supported environments](#supported-environments)
- [Installation examples and legacy aliases](#installation-examples)
- [CLI overview](#cli-overview)
- [Status and monitoring](#status)
- [Log viewing](#logs)
- [Components](#components)
- [Paths, logs, and state](#paths-logs-and-state)
- [Upgrade and uninstall](#upgrade-and-uninstall)
- [Troubleshooting](#troubleshooting)

---

## Supported environments

`seedboxctl` performs runtime detection before making changes.

| Item              | Support                                                                                                                      |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| OS                | Debian 11 or newer; Ubuntu 20.04 or newer.                                                                                   |
| Architecture      | `amd64` / `x86_64` and `arm64` / `aarch64`                                                                                   |
| Init system       | systemd is required for host/system services. Rootless mode can fall back to `screen` or daemon mode.                        |
| Package manager   | APT-based Debian/Ubuntu hosts for root/admin installs.                                                                       |
| Rootless installs | Supported for qBittorrent only. Rootless mode does not run APT, create users, tune the host, install Docker, or install BBR. |

Host-level components such as tuning, Docker, Vertex, and BBR should be run only on a host or full VM that you control.
Deluge additionally requires Debian 12+/Ubuntu 22.04+, root and systemd; only amd64 has execution coverage. Deluge is not part of the default install; selecting its unsupported legacy runtime still emits a security warning.

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

Run the dedicated example as root; do not use root/sudo for the rootless example. Create a private password file first and replace its path in the examples.

#### Legacy wrapper aliases

| Short option     | Canonical option or meaning                                                       |
| ---------------- | --------------------------------------------------------------------------------- |
| `-u USER`        | `--user USER`; rootless legacy usage sets the WebUI username                      |
| `-p PASSWORD`    | `--password PASSWORD`; prefer a password file or stdin                            |
| `-c N`           | `--cache N` (MiB)                                                                 |
| `-q VERSION`     | `--qb-version VERSION`                                                            |
| `-l VERSION`     | `--libtorrent-version VERSION`                                                    |
| `-b`, `-v`, `-r` | Add autobrr, Vertex, or autoremove-torrents to `--components`                     |
| `-3`, `-x`       | `--bbr-algo bbrv3`, `--bbr-algo bbrx`; installer trust options are still required |
| `-o`             | Prompt for custom ports                                                           |
| `-T`             | `--no-tuning`                                                                     |
| `-L LANG`        | `--lang LANG`                                                                     |
| `-h`             | `--help`                                                                          |

After `Install.sh` runs, use `seedboxctl` for lifecycle commands. Long options are canonical in the examples below; aliases remain supported.

---

## CLI overview

Syntax notation: uppercase words are metavariables, `[...]` is optional, and `{a|b}` means choose one. Syntax summaries are not runnable shell commands. A global `--lang LANG` may follow `seedboxctl` in every command.

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

Use built-in help for component-specific flags:

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

`seedboxctl status` is a read-only inventory of installer-managed state visible to the current Unix account. It does not create log/state directories, chmod files, install dependencies, start services, read application credentials, or contact external hosts. No state directory means no managed installations, not an invitation to create one. Root sees system installer state; non-root accounts see their own state by default. It does not discover other users' private installations or automatically impersonate a user to access their systemd session.

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

All component status commands use the same collector and support `--json` and `--check`. `--user USER` filters qBittorrent, autobrr, or autoremove-torrents; `--vertex-name NAME` filters Vertex. With no filter, root lists all matching state records; non-root user-owned component queries default to the current account. Run user-systemd queries as the instance owner; an inaccessible manager is `unknown`, not proof that the service stopped.

### What is observed

Deluge supports `--user USER`, `--json` and `--check` through the same read-only collector. Both recorded daemon/WebUI units must run for `check_ok=true`. `service` remains the daemon unit, `reason` identifies failures, and different unit enablement is `mixed`. Its saved component is `deluge-instance`; JSON fields and exit codes remain shared. This is not an authenticated application-health test.

| Component           | Runtime observation                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| qBittorrent         | Exact recorded system/user unit, or matching executable path and real/effective Unix UID for daemon/screen modes. An open port alone is never sufficient.                             |
| autobrr             | Recorded systemd service state and result.                                                                                                                                            |
| autoremove-torrents | Live timer enablement/activity and last job result. A disabled timer without a recorded job failure is intentional, not an error. An idle oneshot job is normal between runs.         |
| Docker              | Local system daemon at `/var/run/docker.sock`, plus system service state. Remote Docker contexts and host/TLS overrides are ignored.                                                  |
| Vertex              | Saved full container ID, name, `/vertex` bind mount, running state, and Docker healthcheck when present. Legacy/mismatched identities are not silently adopted.                       |
| Tuning              | Existing defaults/helper files and the boot unit's last oneshot result. Successful application is not a permanently running daemon or verification of every live kernel value.        |
| BBR                 | Currently selected and kernel-registered congestion control; a module may be built in. Recorded generic-kernel fallback is shown as `pending-reboot` until installation is completed. |

Human output labels ports as recorded. Versions and WebUI usernames also come from saved state, not fresh application interrogation. Local manager queries have a four-second timeout (plus a one-second forced-termination grace); missing tools, permission failures, timeouts, and incomplete responses are reported as unverified rather than healthy. Multiple instances require multiple queries. Reports can change during concurrent installation or shutdown.

### JSON and exit codes

Global JSON uses an `instances` array with string fields `component`, `user`, `webui_user`, `rootless`, `service`, `service_mode`, `web_port`, `status`, `id`, `kind`, `runtime_state`, `enabled`, `recorded_version`, `last_job_result`, and `reason`, plus boolean `check_ok`. `status` is `active`, `inactive`, or `unknown`. Missing string metadata is empty; unavailable enablement is `unknown`. JSON goes to stdout; fatal collection errors go to stderr.

Component JSON uses the same `instances` envelope as global status. Scripts consuming the old flat qBittorrent-specific object should read `.instances[0]` instead. Component names use saved values, such as `qbittorrent-instance` and `docker-engine`; `id` identifies the state record within the component.

`runtime_state` explains the observation: for example `running`, `stopped`, `failed`, `missing`, `unknown`, `identity-mismatch`, `waiting`, `disabled`, `applied`, `selected`, or `pending-reboot`. Use `check_ok` rather than treating every non-running configuration or timer as broken. It is not an authentication, connectivity, or performance health guarantee.

| Exit | Normal report                                                                                                        | With `--check`                                                                                                 |
| ---- | -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `0`  | Report generated, including stopped/missing instances or an empty inventory.                                         | Every selected record meets its component-specific expectations. An intentionally disabled timer can pass.     |
| `1`  | Cannot safely read/enumerate the state directory. Individual unreadable/malformed records are reported as `unknown`. | At least one unmet/unverifiable expectation, pending setup/reboot, empty selection, or fatal collection error. |
| `2`  | Invalid command, option, or selection syntax.                                                                        | Invalid command, option, or selection syntax.                                                                  |

`--check` is accepted only by status commands. It never fixes a problem. Inspect the reported reason and relevant component logs before changing anything.

## Logs

`seedboxctl logs COMPONENT` and `seedboxctl COMPONENT logs` are equivalent read-only viewers. They never initialize/chmod state or log directories, start services, install tools, or repair permissions. Root must specify `--user USER` for qBittorrent, autobrr, and autoremove-torrents runtime logs; non-root users default to their own account. Vertex requires `--vertex-name NAME` when multiple managed instances exist. Only existing installer-managed runtime state is selected; retained installer logs can be read after uninstall or failed installation without state.

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

| Source           | Selection                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auto` (default) | qBittorrent system/user installations use their exact service journal; daemon/screen installations use their application file. An unavailable qBittorrent journal falls back to the application file with an explanation, unless a time filter was requested. Other components use their service/container source; BBR uses installer logs.                                                                     |
| `service`        | Exact service journal for qBittorrent, autobrr, Docker, or tuning. autoremove-torrents includes both job and timer journals, including historical executions. Vertex reads the verified saved container ID's stdout/stderr from the local Docker engine. BBR has no dedicated daemon source.                                                                                                                    |
| `application`    | qBittorrent's application file. The managed home/XDG layout supplies the default path; explicit `[Application] FileLogger\Path` and disabled `FileLogger\Enabled` are respected. Supported QSettings quoting/backslash/hex escapes are decoded without requiring Python; ambiguous, unsupported, or unsafe paths are refused instead of guessed. Previously discarded daemon/screen stdout cannot be recovered. |
| `installer`      | Latest retained run matching the component, or a selected run/step. Combined installation runs match their recorded component step IDs.                                                                                                                                                                                                                                                                         |
| `all`            | Read each supported source in order; missing/inaccessible requested sources make the result a partial failure. No live multiplexing.                                                                                                                                                                                                                                                                            |

`--lines N` accepts 1–10000 and defaults to 200 **per source**. `--since TIME` passes a time expression to journalctl/Docker; use an absolute timestamp for portability because their relative-time syntax differs. It is rejected for ordinary files and `--source all`. `--list` lists source availability without log contents; `--source installer --list` lists runs instead. Empty readable logs succeed; successful journal access does not prove that entries were retained for that unit. The viewer does not modify retention or enable application logging.

`--follow` streams one source until interrupted; it cannot be combined with `--list` or `--source all`. File following stays on the validated open descriptor, including across a rename; it does not open a replacement file or follow a replacement symlink. Rerun the command after log rotation to select the new file. Manager discovery and non-follow queries are time-bounded, but explicit following is not. Ctrl+C cleans up the viewer's stream processes. File access requires Bash, coreutils, `/proc`, and `timeout`; following additionally needs `setsid`. Missing tools are reported, not installed.

### Installer runs and steps

Deluge supports `logs --user USER` with the same selection and permissions rules as qBittorrent. `auto`/`service` reads both daemon and WebUI journals in one query, including with `--follow`; `all` adds installer logs. There is no Deluge application-file source. `deluge.*` step IDs match build/install/upgrade logs, including combined profile runs.

`seedboxctl logs installer` reads the latest run in the invoking account's log scope. `--list` prints run IDs, actions, filename timestamps, and recorded failed step IDs; newest selection uses file modification time. Run IDs are basenames **without `.log`**. To inspect one run, use `seedboxctl logs installer --run RUN_ID`; add `--list` to list its recorded completed/failed steps or `--step STEP_ID` to read one step. For example, substitute an ID from the listing into `seedboxctl logs installer --run RUN_ID --step qb.upgrade.start`. Step files are selected from the run's recorded paths, not by assuming that similarly timestamped directories belong together. In-progress steps without a recorded result/path may not yet be selectable. No failures are invented when a run has no recorded failed step.

Component `--source installer` and `--source all` are **component-scoped, not instance/user-filtered**: historical logs do not consistently record the target Unix user. `--user` still selects runtime sources, but does not narrow installer runs. Root's default log scope is `/var/log/seedbox`; non-root scope is `~/.local/state/seedbox/logs`; `SEEDBOX_LOG_BASE` overrides that scope. The intentional `latest.log` link is checked for containment; unrelated/unsafe links are not followed. Discovery is bounded to eight seconds and 1024 candidate runs, with four-MiB summary limits; use an explicit run ID to narrow a large history. Unreadable/unsafe runs are reported and skipped during discovery, never opened through a symlink.

### Permissions, output, and exit codes

Application files are read with the instance owner's privileges, even when root invokes the command. Unsafe paths, symlinks, FIFOs, and other nonregular files are refused; file identity is checked before content is read. User-systemd journals must be queried as the instance owner; root does not automatically impersonate their session. Docker always uses `/var/run/docker.sock`, ignoring remote host/context/TLS overrides. Vertex identity/name/data-mount verification must succeed before container log access; an unhealthy or stopped verified container can still have useful logs.

Log content goes to stdout; source labels, failure hints, and warnings go to stderr. Docker's application stdout and stderr are combined as log content. There is no pager or viewer-added color. Logs may contain passwords, tokens, private paths, or addresses: review before sharing; **there is no automatic-redaction guarantee**. Source labels are separate from content, so piping stdout produces raw entries rather than an annotated report.

Exit `0` means the selected source was read (including an empty accessible log); `1` means unavailable/denied/timed-out sources, no matching run, ambiguous selection, or a partial explicit multi-source failure; `2` means invalid options or unsupported combinations. Interrupting a follow session can return the conventional signal-related status. This viewer does not produce JSON, bundles, remote logs, or automatic repairs.

## Components

### Deluge

Optional **1.3.15 / libtorrent 1.1.14** (default) or **2.2.0 / libtorrent 1.2.20 or 2.0.15**. Use `--components deluge --deluge-version 2.2.0 --deluge-libtorrent-version 2.0.15`, or the same version flags with `seedboxctl deluge add-user --user USER --password-stdin`. Deluge 2.2.0 defaults to libtorrent 2.0.15; 1.3.15 emits an informational legacy security warning without requiring an acceptance flag. Root/systemd and Debian 12+/Ubuntu 22.04+ are required. Default loopback-only ports: WebUI `8112`, RPC `58846`; incoming TCP/UDP `45000`. Cache defaults to `256` MiB for libtorrent 1.x; libtorrent 2.x rejects explicit cache options and records `cache_mib=n/a`. For combined installs, use `--deluge-*` names; generic client ports, cache and `--libtorrent-version` belong to qBittorrent. Set distinct incoming ports explicitly.

The [Deluge guide](../Torrent%20Clients/Deluge/README.md) covers security, SSH access, patched native builds, config formats, migration, pair/settings-preserving `upgrade`, config-only `uninstall --purge --yes`, and two-service monitoring. Runtimes stay under `/opt/deluge-1.3.15` or `/opt/deluge-2.2.0-lt-{1.2.20,2.0.15}`; state uses `/var/lib/seedbox/state/deluge.USER.env`, and logs use `/var/log/seedbox`. Major-version/ABI switches are refused before service shutdown and require manual migration or a new Unix account. Uninstall/purge retain downloads, session metadata, plugins, snapshots and shared runtimes. Deluge is not included in the default qBittorrent or rootless profiles.

### qBittorrent

Install a root-managed instance for a Linux user with distro packages:

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

Install a rootless instance for the current user:

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

Common qBittorrent options:

`seedboxctl` rejects unknown options, missing values, and options unsupported by the selected command/components instead of silently ignoring them. Legacy option aliases remain supported.

| Option                                     | Description                                                                                                                                                                                                                              |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--password-stdin`                         | Read the WebUI password from stdin. Recommended.                                                                                                                                                                                         |
| `--password-file FILE`                     | Read the WebUI password from a file.                                                                                                                                                                                                     |
| `--password PASSWORD`                      | Pass the WebUI password as an argument. Convenient, but less safe.                                                                                                                                                                       |
| `--cache N`                                | qBittorrent cache size in MiB. Default: `3072`.                                                                                                                                                                                          |
| `--qb-tuning-profile PROFILE`              | Config-tuning profile: `auto`, `legacy`, `1g-hdd`, `1g-hdd-raid0`, `1g-ssd`, `1g-nvme`, `1g-ceph`, `over1g-hdd`, `over1g-hdd-raid0`, `over1g-ssd`, `over1g-nvme`, or `over1g-ceph`. Old `10g-*` names remain aliases.                    |
| `--storage TYPE`, `--storage-path PATH`    | Shared storage detection overrides for qBittorrent and host tuning. Types: `auto`, `hdd`, `hdd-raid0`, `ssd`, `nvme`, `ceph` (`sata-ssd` is also accepted). The path selects backing storage for tuning; it does not relocate downloads. |
| `--interface IFACE`, `--link-speed-mbps N` | Shared interface/bandwidth overrides. `--netdev` and `--link-speed 2.5g` are also accepted. Use bandwidth overrides for provider shaping.                                                                                                |
| `--web-port PORT`                          | WebUI port. Default: `8080`. Aliases: `--qb-web-port`, `--qb-port`.                                                                                                                                                                      |
| `--incoming-port PORT`                     | Incoming BitTorrent port. Default: `45000`. Alias: `--qb-incoming-port`.                                                                                                                                                                 |
| `--source distro`                          | Install/use the OS `qbittorrent-nox` package. Root/admin mode only.                                                                                                                                                                      |
| `--source static`                          | Use a bundled or downloaded static `qbittorrent-nox` build.                                                                                                                                                                              |
| `--source existing`                        | Use an existing `qbittorrent-nox` from `PATH`, `~/bin`, or `~/.local/bin`.                                                                                                                                                               |
| `--qb-version VERSION`                     | qBittorrent version for static source.                                                                                                                                                                                                   |
| `--libtorrent-version VERSION`             | libtorrent version for static source.                                                                                                                                                                                                    |
| `--service-mode MODE`                      | `system`, `user`, `screen`, `daemon`, `auto`, or `prompt`.                                                                                                                                                                               |
| `--webui-username NAME`                    | Set WebUI username separately from the Unix user.                                                                                                                                                                                        |
| `--allow-unverified-downloads`             | Permit downloads without SHA-256 verification. Avoid for production unless you have reviewed the artifact source.                                                                                                                        |

List available qBittorrent sources and static manifest entries:

```bash
seedboxctl list qbittorrent
```

Static qBittorrent versions are selected from `manifests/qbittorrent.tsv`. If `--qb-version` or `--libtorrent-version` is missing, or if the supplied pair is not listed for the current architecture, an interactive install prints the manifest choices and asks you to select one. Non-interactive installs, such as CI/cron/no-TTY sessions, print the valid choices and exit so you can rerun with a valid manifest pair. `--source distro` and `--source existing` do not use the manifest and do not show the version menu.

Static binary resolution order after a manifest pair is selected:

1. A matching bundled binary under `Torrent Clients/qBittorrent/ARCH/`.
2. A URL from `manifests/qbittorrent.tsv`.

Both sources must match the exact manifest pair and SHA-256. There is no derived-URL or unverified static-qBittorrent fallback; `--allow-unverified-downloads` does not bypass this requirement.

#### qBittorrent config tuning profiles

`--qb-tuning-profile auto` is the default. qBittorrent and host tuning use the **same confirmed storage path/type, interface, and bandwidth**. The selection is made once per install/apply command and reused by both components. Defaults follow **explicit flags → saved choices → detection**. With an interactive terminal, the installer always asks for confirmation; press Enter to accept or type an override. Without a terminal, these defaults are used automatically without consuming piped password input. Upgrades restore the instance's saved hardware choices, including provider bandwidth caps. If the saved interface no longer exists, it warns and detects the routed interface again. Use `--storage auto`, `--interface auto`, or `--link-speed auto` to redetect individual values. A saved tuning path remains selected until you explicitly change it; it does not follow later WebUI download-directory edits automatically.

Up to and including **1000 Mbps** selects `1g-*`; **anything faster** selects `over1g-*`, including 2.5G, 5G, 10G, and faster links. Old `10g-*` arguments/stored profile names remain compatible aliases. An explicit qBittorrent profile overrides automatic profile selection, not the shared host settings. Use `legacy` to retain the older qBittorrent heuristic.

Detection prefers the active interface selected by IPv4/IPv6 routing, not the fastest unrelated NIC. It reads interface speed, tries ethtool and lower interfaces when necessary, and falls back to 1000 Mbps with a warning if speed is unknown. Physical link speed cannot reveal provider bandwidth caps. Storage detection follows the chosen path through partitions/device-mapper/MD, uses kernel device names for LVM, and excludes ZFS log/cache/spare/special devices from data-tier classification. Remote/FUSE storage uses the Ceph-compatible profile with a warning, not a claim that it is actually Ceph. Unknown storage defaults to HDD with a warning. Complex pools, hardware RAID, and multiple download mounts still need confirmation or an explicit override.

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

For qBittorrent 4.5.5+, disk queue size is one quarter of total system RAM, rounded up to a power of two in MiB, capped at **512 MiB for HDD/HDD RAID0** or **1024 MiB for SSD/NVMe/Ceph**. This is a per-instance limit based on total RAM, not currently free RAM. `legacy` does not apply these explicit disk queue or request limits.

Additional version-gated settings are applied only where they belong:

| Gate                                                 | Settings written                                                                                                                           |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| libtorrent 2.x                                       | `Session\HashingThreadsCount`; `Session\DiskIOType` for NVMe/Ceph profiles.                                                                |
| qBittorrent 4.4.5+                                   | `Session\ConnectionSpeed=500`                                                                                                              |
| qBittorrent 4.5.5+                                   | `Session\DiskQueueSize` and `Session\RequestQueueSize`                                                                                     |
| qBittorrent 5.0.1+ with libtorrent 2.x Ceph profiles | `Session\DiskIOType=SimplePreadPwrite`; older libtorrent-2 qBittorrent releases use `Posix` because `SimplePreadPwrite` did not exist yet. |

Status and logs:

```bash
sudo seedboxctl qbittorrent status --user jerry048
sudo seedboxctl qbittorrent status \
  --user jerry048 \
  --json
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

Reapplying tuning preserves the previous runtime choices in `/etc/default/seedbox-tuning`: hardware selection, window/queue values, scheduler scope and opt-outs. Explicit flags override saved choices. `--no-sysctl` and `--no-limits` also persist for subsequent applies, but do not remove previously generated drop-ins or undo existing live settings. To re-enable an opted-out setting, edit its `SEEDBOX_ENABLE_*` value to `1` in `/etc/default/seedbox-tuning` before reapplying.

Network processing uses the same `1g` / `over1g` boundary as qBittorrent:

| Setting                        | Up to 1G | Above 1G (including 10G+) |
| ------------------------------ | -------: | ------------------------: |
| `net.core.netdev_budget`       |     2000 |                      5000 |
| `net.core.netdev_budget_usecs` |     2000 |                      4000 |
| `net.core.netdev_max_backlog`  |    16384 |                     32768 |

`net.ipv4.tcp_mem` uses 10% / 25% / 50% of total system RAM, expressed in the running kernel's page size and rounded up only to the next whole page, not a power of two. These are limits/pressure thresholds, not reserved memory. For example, 16 GiB RAM with 4 KiB pages gives `419431 1048576 2097152` (approximately 1.6 / 4 / 8 GiB). `net.ipv4.tcp_limit_output_bytes` is 3276800 bytes.

Host tuning uses the expanded `net.ipv4.ip_local_port_range=1024 65535`. Managed qBittorrent WebUI/incoming and Deluge WebUI/RPC/incoming ports inside that range are merged into `net.ipv4.ip_local_reserved_ports`, so outgoing connections cannot take them first. Existing reservations are preserved; only ports the installer added are removed when their instance is removed. Both clients' install, upgrade and uninstall refresh reservations when host tuning is active. Rootless users cannot change the host sysctl: after a rootless port change, an administrator must rerun `seedboxctl tuning apply` (which reads visible rootless state records) to reserve the new ports.

Dirty-page policy uses `vm.dirty_background_ratio=5` for HDD or `10` for SSD/NVMe, and `vm.dirty_ratio=30` for all storage classes. Kernel dirty ratios apply to dirtyable memory, not total installed RAM. Writeback/expiry intervals depend on storage type.

For links up to 1G, NIC ring targets are RX 1024 / TX 2048, bounded by driver maxima. Default-route `initcwnd` and `initrwnd` default to 25 packets; override both with `--initial-cwnd N`.

CPU tuning requests the `performance` governor, `performance` energy preference, energy-performance bias `0` (performance), and Intel P-state `min_perf_pct=100` where supported and writable. Missing/unsupported controls (common in VMs) are skipped non-fatally. This may increase power consumption and heat; it does not override hypervisor scheduling or force frequencies on drivers without a percentage control. Use `seedboxctl tuning apply --no-cpu-tuning` to skip CPU policy changes. The boot service reapplies the selected policy; existing power-management daemons may conflict with it.

Race-focused disk read-ahead uses the following starting values at **all NIC speeds**:

| Storage               | Read-ahead |
| --------------------- | ---------: |
| HDD                   |    256 KiB |
| HDD RAID0             |    512 KiB |
| SATA SSD / local NVMe |    128 KiB |
| Remote/FUSE / ZFS     |  Unchanged |

This is a best-effort boot-persistent setting on the download/tuning path's filesystem-facing block device (MD/LVM included), not every physical leaf. A partition uses its parent disk's control, which also affects other partitions on that disk. `--disk-scheduler-all` does not broaden read-ahead scope. Use `seedboxctl tuning apply --no-read-ahead` to skip it. These are race-oriented baselines, not benchmark-proven optima. Patched libtorrent 1.2.20 already performs up to 2 MiB of piece-bounded cache prefetch and normally suppresses Linux file read-ahead for upload reads; this kernel setting is not a replacement for libtorrent's cache or send buffers.

Useful tuning options:

```text
--storage auto|hdd|hdd-raid0|ssd|sata-ssd|nvme|ceph
--storage-path PATH
--interface IFACE
--netdev IFACE
--link-speed-mbps N
--link-speed 1g|10g|25g|2500m
--txqueuelen N
--initial-cwnd N
--no-sysctl
--no-limits
--no-cpu-tuning
--no-read-ahead
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
sudo seedboxctl bbr install \
  --bbr-algo bbrx \
  --bbr-script-sha256 SHA256
```

Supported algorithms:

```text
bbrv3
bbrx
bbrx_old
bbrw
bbr_brutal
bbrw_brutal
```

`bbrx_old` preserves the legacy BBRx algorithm, including its STARTUP-exit bug, 10-bit gain truncation, and original pacing cycle, with the modern kernel compatibility layer. It registers as `bbrx_old`, builds as `tcp_bbrx_old`, and has an independent DKMS package (`bbrx_old/0.1.0`), so it can coexist with unchanged `bbrx`. Legacy `-x` still selects `bbrx`.

```bash
sudo seedboxctl bbr install \
  --bbr-algo bbrx_old \
  --bbr-raw-base 'file:///path/to/reviewed/Trove/BBR-Install/BBR'
sudo seedboxctl bbr uninstall --bbr-algo bbrx_old
```

While `bbrx_old` is unpublished, the verified bundled installer is selected automatically, and an explicit local/published raw-base containing the variant is required. If you override the installer too, it must support `bbrx_old`. Pin reviewed remote sources to commits.

Pin and verify the external BBR installer:

```bash
sudo seedboxctl bbr install \
  --bbr-algo bbrx \
  --bbr-script-url 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBRInstall.sh' \
  --bbr-raw-base 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBR' \
  --bbr-script-sha256 SHA256
```

Check or remove BBR-managed state:

```bash
sudo seedboxctl bbr status
sudo seedboxctl bbr uninstall --bbr-algo bbrx
```

`bbrv3` uses a kernel package path and may require a reboot. For DKMS-based variants, if headers for the running kernel are missing locally and cannot be installed with `apt install linux-headers-$(uname -r)`, Seedbox automatically installs the distribution generic kernel image and headers, records a pending BBR state, and asks you to reboot into the generic kernel before rerunning BBR installation. DKMS/kernel changes are high risk; test on a disposable VPS first.

Runtime restrictions and installer verification run before header/kernel package changes. Containers/WSL are refused unless explicitly overridden with `--force-runtime`. Replace hash placeholders with a reviewed installer SHA-256; `--allow-unverified-bbr-installer` is a separate, deliberate opt-in, not implied by `--yes`. Standalone work parents must have trusted root-owned ancestors; root-owned sticky parents such as `/tmp` are supported.

### Docker

Install Docker:

```bash
sudo seedboxctl docker install --docker-source official
```

Alternative distro packages:

```bash
sudo seedboxctl docker install --docker-source distro
```

Saved Docker state records the installation source that succeeded. If the official installer falls back successfully to distro packages, `source=distro` is recorded instead of the originally requested `official`.

Status and uninstall:

```bash
sudo seedboxctl docker status
sudo seedboxctl docker uninstall
sudo seedboxctl docker uninstall \
  --purge \
  --yes
```

Docker purge requires `--yes` **before** any stop/disable/package changes. It queries the local system daemon at `/var/run/docker.sock` for its actual `DockerRootDir`, ignoring remote contexts/`DOCKER_HOST`; it never guesses a default path. If discovery fails, start the daemon and retry. A private interrupted-purge record allows retry after package removal. Python 3 validates the absolute path, Docker layout, symlinked ancestors and mount points before deletion; broad/shared/unrecognized paths and mounted trees are refused. Stop containers/unmount their storage first. Standalone containerd packages and data (including custom roots) are deliberately retained, because other runtimes may share them. Stop, package and deletion failures propagate and retain installer state.

### Lifecycle safety and compatibility

- Existing qBittorrent configuration is refused on fresh install unless `--force` is supplied. A private `.pre-install.TIME.*` backup is created before replacement. Upgrade migration preserves settings. Existing user directories and download directories are never chowned/chmodded; repair permissions manually if the target user cannot use them. Symlinked config/launcher paths are refused.
- Static qBittorrent installs require an exact manifest qBittorrent/libtorrent pair and matching SHA-256 for local and downloaded binaries. Missing bundles may be downloaded for that exact pair; another library is never substituted. Installation uses a temporary binary and atomic rename. Purge runs as the instance user and deletes only `qBittorrent.conf`; no Python dependency is added for classic rootless purge. Failed cron reads never replace the crontab.
- autobrr and autoremove-torrents config writes run as their service user. Forced replacements retain private backups. Selective purge verifies directory/file ownership and retains the parent and all unrelated data.
- BBR installer downloads and custom local scripts require `--bbr-script-sha256` or explicit `--allow-unverified-bbr-installer`. A supplied hash mismatch is fatal, never a reason to fall back. Eligible unverified-default transport failures may use the bundled installer with its embedded hash. This hash authenticates only that installer, not raw-base DKMS sources or package checksums. Pin both sources to reviewed commits for reproducibility. While `bbrx_old` is unpublished, select an explicit local/published `--bbr-raw-base`; its verified bundled installer is selected automatically. The bundled installer requires Ubuntu 22.04+ or supported Debian. Checksum package names must be `.deb` basenames; paths are refused. DKMS/module removal failures retain recovery state.
- Official Docker migration requires `--allow-docker-package-removal` before removing installed conflicting packages (including `containerd`/`runc`). `--yes` does not grant this consent. No installer data deletion is performed by migration, but package scripts and workload disruption remain possible. Docker purge continues to preserve standalone containerd packages/data.
- Root runtime destinations, command-link parents, and persisted tuning helper paths must be root-owned and not group/other-writable throughout their ancestor chain. Non-root runtime installation under the current user's home remains supported. Privileged purge pins validated objects and rejects untrusted parents; this is not a guarantee against another privileged writer or concurrent mount changes.

`Install.sh` forwards `--force`, `--yes`, and `--allow-docker-package-removal`. Configuration backups, failed Vertex data and old containers are retained for manual review, not automatically pruned.

### Vertex

Install Vertex in Docker:

```bash
sudo seedboxctl vertex install \
  --vertex-port 3000 \
  --vertex-data-dir /root/vertex
```

Python 3 is required for Vertex filesystem safety, including installs without credentials. If it is missing or unusable, installation through APT is offered **before any Vertex Docker/image/data changes**. The default answer is No; declining or failing installation aborts. Without an interactive terminal, install Python first or explicitly consent with `--yes`. Confirmation uses the terminal, not a piped password stream.

Ordinary upgrades never repair/merge missing files automatically. `upgrade --repair-data --yes` explicitly requests missing-file repair and requires a data snapshot. Upgrades stop the old container, copy data to a private sibling snapshot, disable the retained old container's restart policy, and activate the replacement. Snapshot failure restores the previous running state. Health/state-write failures restore data before restarting the old container; failed replacement data is renamed aside, never deleted. Snapshot/rename recovery requires an unmounted data tree and enough space for the copy. Container backups, state backups and snapshots remain after success. `--no-data-snapshot` explicitly forfeits data rollback; after a failed replacement the old container remains stopped with automatic restart disabled for manual recovery. An existing managed install requires `--force` to replace; unrelated same-named containers are never removed automatically. Health checks establish liveness, not database compatibility or application correctness.

Credential updates change only username/password, keep a private `setting.json.pre-credentials.*` backup, and atomically replace the JSON using a mode-`0600` temporary file. Invalid, unreadable, non-object or symlinked existing settings are rejected instead of replaced with an empty object. The generated password file is removed only after a successful update. Normal upgrades do not rewrite credentials.

Install/upgrade readiness requires a local HTTP response and a final check that the verified container is still running; a published Docker port alone is insufficient. This uses the already-required Python 3, ignores proxy settings, and does not follow redirects. It does not test authentication or database compatibility. Read-only `status --check` remains a manager-state check and makes no HTTP requests.

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
sudo seedboxctl vertex uninstall \
  --purge \
  --yes
```

For a custom container name, pass the same `--vertex-name` used at installation. Status selects the exact name and shows logs from that container, not similarly named containers:

```bash
sudo seedboxctl vertex status --vertex-name my-vertex
sudo seedboxctl vertex upgrade --vertex-name my-vertex
sudo seedboxctl vertex uninstall --vertex-name my-vertex
```

Container state records the full Docker container ID and expected `/vertex` bind mount. Lifecycle changes refuse stale IDs or mismatched mounts, even if names match. Older state without `container_id` requires manual review: compare `docker inspect NAME` with the recorded data directory and add the reviewed full ID to the private state file before retrying. Never copy the ID of an unrelated replacement. Initialization must stop and remove its own uniquely named container before data is merged; failures retain the template/container for manual recovery.

Vertex recursive purge requires a matching `.seedbox-managed` ownership marker. With Python 3 available, newly created/empty data directories are marked before initialization; existing populated directories are never silently claimed. Legacy/unmarked data is kept and purge is refused before container removal; use ordinary uninstall, then review/remove that data manually. Broad/home roots, symlinked paths and mounted trees are refused. `--yes` and validation precede container changes, and container-removal/deletion failures retain state for retry. Safe purge requires Python 3 but never installs it implicitly.

### autobrr

Install autobrr for a user:

```bash
sudo seedboxctl autobrr install \
  --user jerry048 \
  --autobrr-port 7474
```

On reinstallation, an explicit `--autobrr-port` updates only the root `port` setting and restarts autobrr; other settings are preserved without `--force`. Omitting the option retains the current config port. Configs with multiline root strings require a manual port edit rather than risking an unsafe text replacement. `--force` deliberately regenerates the full config.

Status, uninstall:

```bash

sudo seedboxctl autobrr status --user jerry048
sudo seedboxctl autobrr uninstall --user jerry048
sudo seedboxctl autobrr uninstall \
  --user jerry048 \
  --purge \
  --yes
```

For standard GitHub release assets, `seedboxctl` attempts to resolve and verify the matching checksums file. For custom URLs, provide `--autobrr-sha256` or explicitly pass `--allow-unverified-downloads` after reviewing the artifact.

autobrr purge removes only the recorded `config.toml` and default `autobrr.db`, `autobrr.db-shm`, `autobrr.db-wal` files beside it. It never recursively deletes the parent directory. Other files/backups and externally configured databases are preserved for manual review. autoremove-torrents purge similarly removes only the recorded `config.yml`. Both require Python 3 for path/type validation and `--yes` before stopping anything; stop/delete failures keep startup files and state.

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
sudo seedboxctl autoremove-torrents install \
  --user jerry048 \
  --enable-autoremove
```

Reinstallation preserves the timer's enablement. The live systemd state takes precedence over saved installer state, so manual `systemctl enable`/`disable` changes are respected; saved state is the fallback if the unit/manager cannot be queried. An enabled-but-stopped timer is not started just because you reinstall. `--enable-autoremove` explicitly enables and starts it. Fresh installs remain disabled by default. Masked timers require explicit manual unmasking before reinstallation; they are not silently overwritten. The effective enabled state is saved, and normal upgrades still leave timer units untouched.

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

Runtime replacement accepts only an empty destination or a known minimal runtime containing exclusively manifest-listed files/directories; mixed checkouts/shared directories, symlinks, broad/home roots and mounted paths are refused. Older minimal runtimes may omit optional manifest files. Temporary and previous-runtime names are allocated uniquely; pre-existing `.old` or `.tmp.PID` siblings are never removed. The previous managed runtime is retained as `DESTINATION.previous.RANDOM` for recovery/manual cleanup. Unsafe destinations abort rather than falling back to another runtime.

Both bundled and standalone BBR installers treat `BBR_WORK_DIR` as a **parent** for a new mode-`0700` `bbr-install.*` child, never as the build/deletion target itself. `BBR_CLEAN_WORK_DIR=1` removes only that exact child after path, mount and device/inode checks; `0` retains it. `auto` cleans automatic workspaces and keeps children under an explicitly selected parent. Existing parent contents are never deleted.

Overall status:

```bash
seedboxctl status
seedboxctl status --json
```

---

## Upgrade and uninstall

### qBittorrent

Upgrade distro package based install:

```bash
sudo seedboxctl qbittorrent upgrade \
  --user jerry048 \
  --source distro
```

Omitting `--service-mode` retains the saved startup mode. Supplying it (or `--install-method`) migrates to a valid mode for that instance: root-managed instances support `system`, `screen`, `daemon`; rootless instances support `user`, `screen`, `daemon`, `auto`, `prompt`. The old startup mechanism is disabled when switching, with rollback attempted if startup or health checks fail.

Rootless upgrade/uninstall requires `flock`. Maintenance holds an exclusive lock shared with generated cron restart helpers, removes the managed cron entry before stopping, and drains older in-flight helpers. Scheduling is restored only after successful upgrade or safe rollback; failures may leave cron suspended for manual recovery. A failed config restore never restarts the old instance. Distro upgrades explicitly refresh APT and install the current `qbittorrent-nox` candidate after stopping and snapshotting the config. Package/dependency changes cannot be automatically rolled back: a failed distro upgrade leaves the instance stopped with the config snapshot retained for manual package/config recovery.

**Configuration preservation:** upgrades merge the current config rather than replace it with the installer template. Existing WebUI settings (including ports, username, save paths, limits, queueing, authentication/security settings and custom tuning) take precedence over stale installer state; explicit CLI flags override the corresponding settings. Known legacy/modern key names and value formats are translated for the target version, including the 5.3 WebUI section change. Missing installer defaults are added. Existing tuning values are retained unless you explicitly supply a tuning profile or hardware option to retune the managed fields. `--cache` explicitly updates both disk cache and the generated process memory limit; without it, these independent controls retain their existing values, including automatic/disabled disk-cache values.

The installer rereads settings after the old process stops, so shutdown-flushed changes are preserved. A mode-`0600` snapshot named `qBittorrent.conf.pre-upgrade.*` is retained beside the config for recovery, including after successful upgrades. Compatible password hashes are retained; crossing the 4.1 password-hash boundary requires a password argument. Older targets cannot implement every newer feature: unknown keys are retained but may be ignored by the target, and conversions that cannot be safely represented (for example active proxy profiles below 4.6, some HTTPS certificate-format changes, or unsupported enum values) fail rather than silently weaken settings. Keep the snapshot when downgrading. Rootless config migration requires Python 3, including for 4.1 targets.

Daemon/screen lifecycle operations wait for the matching user's old process to exit after graceful termination, before rewriting config, starting a replacement, or purging config. The default wait is 30 seconds; set `SEEDBOX_QB_STOP_TIMEOUT` to a positive number of seconds for slower storage. A timeout aborts rather than force-kills the process. Rollback also refuses to overwrite config or restart the old instance if the replacement cannot be stopped. Systemd-managed instances use synchronous `systemctl stop`.

The installer creates missing `.local`, `.local/share`, `.local/share/qBittorrent`, and `.cache` directories as the target user with private permissions. Existing directories are checked for access, not chowned/chmodded; manually repair incompatible existing permissions. Symlinked runtime directories are rejected.

Upgrade static install:

```bash
sudo seedboxctl qbittorrent upgrade \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  < /path/to/password.txt
```

Non-destructive uninstall:

```bash
sudo seedboxctl qbittorrent uninstall --user jerry048
```

This stops and removes startup files but keeps qBittorrent config and downloads.

Remove qBittorrent configuration, preserving downloads:

```bash
sudo seedboxctl qbittorrent uninstall \
  --user jerry048 \
  --purge \
  --yes
```

`--purge` removes only the `qBittorrent.conf` path recorded in instance state, not a hard-coded home path. It never deletes download directories (default or custom), the config parent directory, or other files beside the config. Recovery snapshots/backups and torrent/session metadata are retained; remove those manually if no longer needed. Unsafe, symlinked or non-regular config targets are refused. Validation and confirmation happen before stopping/uninstalling; a config deletion failure retains startup files and instance state for retry.

Rootless uninstall:

```bash
seedboxctl qbittorrent uninstall
seedboxctl qbittorrent uninstall \
  --purge \
  --yes
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

Use `--purge --yes` only when you intentionally want to remove component data/configuration. qBittorrent is configuration-only and always preserves downloads; other components have different purge semantics.

---

## Troubleshooting

### Installer language and progress

Use `--lang zh-CN` immediately after `seedboxctl` (or on `Install.sh`) for Simplified Chinese. Installer-owned prompts, help, progress labels, status explanations, log-viewer metadata and recovery guidance are localized as whole messages. Command names, option values, account names, paths, versions, state keys, JSON fields/values and installer log markers remain literal. Captured application, package-manager and diagnostic log contents are not rewritten or translated. The bundled BBR installer supports `--lang zh-CN`, English and Traditional Chinese.

Steps use separate start/result lines rather than byte-padded columns, so Chinese and narrow terminals do not depend on character-width guesses. Each attempted step shows its elapsed time. In an interactive terminal, long steps print a “still running” message every five seconds; this is activity feedback, **not a progress percentage or estimated completion time**. Redirected output stays line-based without heartbeat chatter. Set `SEEDBOX_PROGRESS=never` to disable heartbeat messages; missing `setsid` also disables this optional display feature, not installation. The step itself stays in the parent shell so its configuration variables are preserved. Progress helpers close inherited maintenance/secret-input descriptors and are stopped when the step ends.

Automatic color uses the actual output stream, honors `NO_COLOR`, and remains optional. Text labels still distinguish information, success, warnings and failures without color. `SEEDBOX_COLOR=never` disables installer colors; `always` is an explicit override when the terminal supports them. Raw logs remain plain stored content; the log viewer does not add color to `[INFO]`/`[ERROR]`.

Mutation commands that have initialized an installer log finish with one operation summary: attempted-step successes/failures, warnings, pending follow-up and the retained log path. Failed attempts that were handled by a fallback remain visible in the counts; unattempted steps are not invented, and successful package preparation is not reported as an active BBR module before the required reboot. A summary does not automatically restart a failed instance, repair permissions or alter the operation's exit code. Read-only status/log/help commands do not create logs or append operation summaries.

### What to do after an error

Failure hints separate a possible cause from a safe next action and the exact step/service log to inspect. For rootless qBittorrent, a permission failure means **stay with the instance owner account**, identify the blocked path and ask the provider/administrator to correct access if necessary—not “retry everything with sudo.” If the installer already runs as root, inspect read-only mounts, ownership and the specific service isolation policy instead of applying blanket `chmod 777`, recursive `chown` or disabling all sandboxing.

If configuration recovery fails, keep the instance stopped and retain its snapshots. First identify the binary/package version and compare the matching saved configuration; restore a compatible pair before restarting through the original startup mechanism. Distro package/dependency changes cannot be automatically rolled back. Vertex recovery likewise requires checking the verified old/new container and data-snapshot state before restarting or deleting anything. “Manual recovery required” is not permission to overwrite the installation or discard the retained copies.

Start with:

```bash
seedboxctl status
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

Failed installer steps inspect their logs for common error patterns, including APT locks, DNS/network failures, missing commands, permission errors, occupied ports, checksum mismatches, and qBittorrent password-hash format changes. This is a best-effort hint, not a full health check. Review the reported step log and the affected service's logs; include the failed command and relevant log excerpts when asking for help, after redacting sensitive information.
