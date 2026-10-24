# Deluge on modern Debian/Ubuntu

[简体中文](README.zh-CN.md)

The optional `seedboxctl deluge` component supports these private native runtimes:

| Deluge           | libtorrent             | Runtime prefix                |
| ---------------- | ---------------------- | ----------------------------- |
| 1.3.15 (default) | 1.1.14                 | `/opt/deluge-1.3.15`          |
| 2.2.0            | 1.2.20                 | `/opt/deluge-2.2.0-lt-1.2.20` |
| 2.2.0            | 2.0.15 (2.2.0 default) | `/opt/deluge-2.2.0-lt-2.0.15` |

It uses the same lifecycle, instance state, progress, installer logs and monitoring as qBittorrent. It does not replace system Python, install obsolete distribution packages, register global library paths, or require Docker. Deluge is not part of the default profile and does not support rootless installation.

## Legacy security warning

Deluge 1.3.15, Python 2.7, OpenSSL 1.1.1 and the compatible Python packages are unsupported. Pinning them makes the installation reproducible, **not secure or maintained**. Use this only for a workflow that specifically requires Deluge 1.3.15. The torrent engine still handles untrusted network traffic; private installation and systemd restrictions do not remove its vulnerabilities.

For every version, new profiles bind WebUI to **0.0.0.0**, accessible at `http://SERVER_IP:8112` without an SSH tunnel. Daemon RPC remains bound to **127.0.0.1 only**. Restrict WebUI to trusted source addresses with a firewall; it uses HTTP by default, so use an HTTPS reverse proxy or trusted VPN/network where appropriate. Keep certificate verification enabled. Outbound HTTPS uses the host's current CA certificate bundle; only the 1.3.15 runtime uses legacy TLS.

## Install

Requirements: root and a running systemd host. **Deluge 1.3.15** supports **Debian 11+ or Ubuntu 20.04+**; **Deluge 2.2.0** requires **Debian 12+ or Ubuntu 22.04+**. The build targets amd64 and arm64; only amd64 has been execution-tested, and ARM64 remains unverified. Container lifecycle tests use a private service-manager fixture; a separate Debian 13 VPS test covers genuine systemd and public torrent downloads. Reboot persistence, GTK and long-duration seeding are not covered. Compilation needs several GiB of free disk space and substantial RAM/CPU time; reduce `--jobs` to `1` on small machines. The build uses the distribution's current compiler and signed APT repositories for build tools. Legacy sources and wheels are pinned by SHA-256 in `sources.lock`; modern locks are described below.

Older hosts need working, signed APT sources. Retired Debian 11 security packages are available from [Debian's archive](https://archive.debian.org/debian-security/); update the host's repository configuration if its retired security mirror returns 404. The installer does not rewrite APT sources or bypass signature verification. Installer compatibility does not restore upstream security maintenance for the legacy application stack or an end-of-life OS.

Use the [main Quick Start](../../README.md#quick-start), selecting `--components deluge`, or use `seedboxctl` from a complete local checkout as below. A missing Unix account is created; an existing account must be non-root and own its real home directory, including custom homes outside `/home`.

Create a private, nonempty, single-line UTF-8 password file, owned by you with mode `600`. From the repository root:

```bash
sudo bash bin/seedboxctl deluge add-user \
  --user delugeuser \
  --password-stdin \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  --deluge-web-port 8112 \
  --deluge-rpc-port 58846 \
  --deluge-incoming-port 45000 \
  --jobs 2 \
  < /path/to/password.txt
```

Select `--deluge-libtorrent-version 1.2.20` for the other modern pair; it accepts `--deluge-cache-mib 256`. libtorrent 2.x does not support this cache control, rejects the option and records `cache_mib=n/a`. For the legacy pair, select `--deluge-version 1.3.15 --deluge-libtorrent-version 1.1.14`; omitting both versions selects that pair. Legacy install, runtime build and upgrade emit a security warning but do not require an acceptance flag.

The password is not passed in command-line arguments. A separate random RPC credential connects the WebUI to the daemon (`localclient` for 2.2.0). Configuration is created as the instance owner with private permissions and JSON escaping; shell metacharacters and non-ASCII passwords are supported.

`install` and `add-user` are equivalent. The installer refuses existing active settings, conflicting ports, unknown runtimes, foreign units and service drop-ins. It never silently overwrites another installation. New services activate only after build/configuration succeed. Readiness authenticates to the WebUI and verifies the connected daemon reports the selected version. A readiness failure stops and disables both services, retaining configuration and managed state for diagnosis/uninstall. Do not use `--force` to bypass these guards.

The legacy stack is Python 2.7.18, OpenSSL 1.1.1w, Boost 1.69.0, libtorrent 1.1.14, Twisted 20.3.0, pyOpenSSL 21.0.0 and Deluge 1.3.15. `sources.lock` lists all Python dependencies and ltConfig 0.3.1. No GTK desktop is installed. The old bundled `.deb` packages are not used.

Deluge 2.2.0 builds private **CPython 3.11.17** and **Boost 1.83.0**, links Python/libtorrent against host **OpenSSL 3**, and uses ltConfig **2.0.0**. `sources-2.2.0-common.lock` plus `sources-2.2.0-{amd64,arm64}.lock` pin sources and Python wheels by SHA-256. setuptools stays at 80.9.0 for upstream's `pkg_resources` dependency. The hash-locked `deluge-2.2.0-crypto.patch` replaces the removed pyOpenSSL `X509Req` API with `cryptography.x509` certificate generation, without downgrading TLS dependencies.

Both modern libraries use the byte-identical matching qBittorrent-build patches from `Patch/patches/libtorrent/{1.2.20,2.0.15}/patch`, pinned in `patches-2.2.0.lock` and applied with zero fuzz. Modern presets retain effective controls, not obsolete libtorrent 1.1 cache options: disk queue **250 MiB**, tracker-management limit **1600**, backlog **3000**, and global connections **500000**. libtorrent 1.2 uses file pool **5000** and the selected cache; 2.0 uses file pool **100**, **2** hashing threads and **4** AIO threads. Saved overrides remain authoritative on upgrade.

Modern config framing uses `hostlist.conf` file version **3**, `web.conf` file version **2**, and file version **1** for other active JSON settings. Legacy profiles keep `hostlist.conf.1.2` and file version **1**.

For the legacy pair, libtorrent is compiled with the **same 1.1.14 tuning patch used for qBittorrent builds**, copied unchanged from `Patch/patches/libtorrent/1.1.14/patch` into `lib/components/deluge/libtorrent-1.1.14.patch`. Its exact SHA-256 is pinned in `patches.lock`; application uses zero fuzz and fails closed. The patch and lock participate in the runtime fingerprint and are retained in the installed runtime for provenance. Compiled-default checks distinguish patched from stock libraries.

New legacy profiles use 50 ltConfig settings, including a disk queue of **250 MiB** (`262144000` bytes) and a tracker-management limit of **1600**. The patched backlog is **3000**, global connection limit **500000**, checking-memory fallback **128 MiB**, and volatile-cache fallback **128 blocks**. An explicit cache size overrides the patch's automatic-cache fallback. Existing saved settings are not silently rewritten during upgrade.

### Access

Open `http://HOST:8112` using the server address and enter the password from your file. For access outside a trusted network, use the HTTPS URL of your reverse proxy instead. The installer does not open firewall ports or configure a reverse proxy.

An SSH tunnel remains an optional way to access WebUI. On your own computer, replace `HOST` with the server address:

```bash
ssh -N -L 8112:127.0.0.1:8112 USER@HOST
```

With this tunnel, open `http://127.0.0.1:8112` locally. Use `ssh -p PORT` if SSH uses a nonstandard port.

The torrent port is TCP/UDP `45000` by default. Allow the chosen torrent port through the host/provider firewall as needed, and permit WebUI TCP `8112` only from intended clients/proxies. RPC TCP `58846` stays local; the installer does not change firewalls. When host tuning is active, install/upgrade/uninstall refresh reservations for managed Deluge WebUI, RPC and incoming ports together with qBittorrent ports, preserving external reservations and `net.ipv4.ip_local_port_range=1024 65535`.

### Combined installation

```bash
sudo seedboxctl install \
  --profile dedicated \
  --components qbittorrent,deluge,tuning \
  --user delugeuser \
  --password-stdin \
  --source distro \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 1.2.20 \
  --web-port 8080 \
  --incoming-port 45000 \
  --deluge-web-port 8112 \
  --deluge-rpc-port 58846 \
  --deluge-incoming-port 45001 \
  --deluge-cache-mib 256 \
  < /path/to/password.txt
```

Generic `--web-port`, `--incoming-port`, `--cache-mib` and `--libtorrent-version` belong to qBittorrent when both clients are selected. Use the `--deluge-*` names to avoid ambiguity. For Deluge-only commands they are aliases; `--rpc-port` aliases `--deluge-rpc-port`. `--cache`/`-c` remain qBittorrent options. Combined installs share the stdin password without rereading the pipe. Choose distinct ports for every instance; a combined install with both default incoming ports is rejected before either client is installed.

### Paths and services

| Purpose                             | Location                                                                |
| ----------------------------------- | ----------------------------------------------------------------------- |
| Private runtime                     | Version-specific prefix in the table above                              |
| Verified download cache             | `/var/cache/seedbox-deluge-1.3.15` or `/var/cache/seedbox-deluge-2.2.0` |
| Owner's configuration/session       | `~delugeuser/.config/deluge`                                            |
| Downloads                           | `~delugeuser/deluge/download`                                           |
| Completed/torrent/watch directories | `~delugeuser/deluge/{completed,torrent,watch}`                          |
| Root-owned instance record          | `/var/lib/seedbox/state/deluge.delugeuser.env`                          |
| Daemon                              | `seedbox-deluged-delugeuser.service`                                    |
| WebUI                               | `seedbox-deluge-web-delugeuser.service`                                 |
| Installer logs                      | `/var/log/seedbox`                                                      |

For libtorrent 1.x, `--cache-mib` is converted to 16 KiB blocks and applied consistently to core and ltConfig; libtorrent 2.x does not use this cache. The services run as the selected non-root user and stop normally via systemd, not `killall`.

## Runtime reuse and migration

You can compile once before creating instances:

```bash
sudo seedboxctl deluge build-runtime \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  --jobs 2
```

An identical completed runtime is checked and reused. The runtime ID includes the source lock, build/check scripts, host distribution and architecture; do not copy a compiled runtime between distributions. A failed build keeps its build directory and incomplete prefix for inspection. After reviewing the failure and stopping any affected services, move the incomplete runtime aside before retrying; the installer does not recursively erase unknown runtime directories.

A runtime built with different build scripts or patches has a different fingerprint and will not be reused or overwritten. To replace a legacy runtime, stop all Deluge instances sharing it, retain the old runtime and private profile backups, move the old prefix aside, and run `seedboxctl deluge build-runtime` before reconciling instances with `upgrade`. This is a deliberate shared-runtime replacement, not an automatic live upgrade; retain the old runtime for manual recovery.

For offline source builds, place every exact file from `sources.lock` (legacy), or both modern common/host-architecture locks, in one directory and pass `--source-dir DIR`. Files are copied into a root-private workspace and checked before compilation. A missing source or checksum mismatch aborts; there is no integrity bypass. APT still needs the required packages locally or through configured repositories. Runtime assets live in `lib/components/deluge/`, orchestration in `lib/components/deluge.bash`, and owner-side settings operations in `lib/core/delugeconfig.py`; remote bootstrap fetches them with the main runtime.

Existing profiles and old service templates require deliberate migration. Stop and back up the old installation, inspect its ownership, credentials and download paths, and keep session/torrent data intact. The installer does not convert between Deluge major versions or libtorrent ABIs, or import old sessions. Use a new Unix account or plan a manual migration; do not remove your old configuration just to get past the guard.

## Upgrade and uninstall

Upgrades preserve saved network settings. To enable direct WebUI access for an existing loopback-only profile, stop both services and back up the settings; set `interface` to `"0.0.0.0"` in `web.conf`, preserving its version header. Then run `upgrade` below to reconcile the WebUI unit without a forced bind flag. Keeping `interface="127.0.0.1"` intentionally retains local-only WebUI access. RPC binding, credentials and TLS verification do not need to change.

```bash
sudo seedboxctl deluge upgrade --user delugeuser
```

This preserves the **recorded Deluge/libtorrent pair**, validates/reuses its runtime and reconciles services. Legacy instances still emit a security warning, without an acceptance flag. An explicit major-version/ABI switch is refused before stopping services. Services stop before taking a private `.pre-upgrade-*` snapshot of five active settings files. Current ports, download paths, cache, password and ltConfig settings are reread and preserved. No password input is needed: readiness checks local RPC and WebUI reachability. If an upgrade fails after stopping, settings are restored when possible and services remain stopped for review; retain the snapshot and inspect logs before restarting. Runtime replacement across distributions/ABIs is manual and affects all instances sharing that prefix.

To remove services while keeping runtime files, configuration, session state and downloads:

```bash
sudo seedboxctl deluge uninstall --user delugeuser
```

To deliberately remove active configuration too, add `--purge --yes`. Only `core.conf`, `web.conf`, the selected version's hostlist (`hostlist.conf.1.2` or `hostlist.conf`), `auth` and `ltconfig.conf` are removed. Downloads, torrent/session metadata, plugins, recovery snapshots and the shared runtime remain. A fresh install over retained active settings is refused; do not delete settings merely to bypass migration guards. Use the managed `seedboxctl deluge` commands; bundled `.deb` archives are not installation inputs.

## Validation coverage

Deluge **1.3.15 / libtorrent 1.1.14** passed clean native builds on amd64 `debian:11-slim` and `ubuntu:20.04`, including patched defaults, non-root daemon/WebUI, authenticated WebUI access through a non-loopback IP, settings-preserving upgrade, rollback, data-preserving purge, a SHA-256-verified local BitTorrent transfer and graceful restart. System Python was unchanged. Debian 11 used its signed security archive; service control in these container tests used a fixture, not genuine systemd.

Both modern pairs passed clean native builds and lifecycle tests on amd64 `debian:12-slim`, `debian:13-slim`, `ubuntu:22.04` and `ubuntu:26.04`, including all patched defaults, saved settings, transfer/restart, recovery and data-preserving purge. Container service control was simulated.

Debian 13 amd64 validation covers genuine non-root systemd services, WebUI/RPC, journals, restart, pair-preserving upgrade, simultaneous ABI isolation and public Debian ISO downloads. Download hashes matched official SHA-256 and SHA-512 checksums retrieved over verified HTTPS; the checksum file's GPG signature was not independently verified. ARM64 execution and genuine Ubuntu systemd remain unverified.

## Troubleshooting

```bash
sudo seedboxctl deluge status \
  --user delugeuser \
  --check
sudo seedboxctl deluge status \
  --user delugeuser \
  --json
sudo seedboxctl deluge logs \
  --user delugeuser \
  --source service \
  --lines 100
sudo seedboxctl deluge logs \
  --user delugeuser \
  --source service \
  --follow
sudo seedboxctl deluge logs --source installer
sudo seedboxctl deluge logs \
  --list \
  --source installer
/opt/deluge-2.2.0-lt-2.0.15/bin/deluged --version
python3 --version
```

Status is read-only and aggregates **both** services; “running” is not an authenticated application/transfer test. It retains the shared JSON `instances` contract and returns failure with `--check` if either service is stopped, failed or unverifiable. Service logs combine both journals; installer logs include `deluge.*` steps, including combined installs. `--source all` includes service and installer logs; there is no application-file source. See the [shared monitoring reference](../../docs/reference.md#status) for exit codes and log-source selection. Raw logs, paths, versions and JSON values are never translated; review sensitive data before sharing. The final command still uses host Python 3. Do not replace system Python, install old cross-distribution `.deb` files, run global `pip`, or bypass TLS/hash checks.
