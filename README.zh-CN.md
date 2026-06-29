# Dedicated-Seedbox V2.0.0

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-blue)](#supported-environments)
[![Mode](https://img.shields.io/badge/modes-dedicated%20%7C%20shared%20%7C%20rootless-informational)](#profiles)

英文版：[README.md](README.md)

`Dedicated-Seedbox` 是用于构建和管理 Debian/Ubuntu Seedbox 安装的统一后端。它提供了一个统一的 CLI 工具 `seedboxctl --lang zh-CN`，可用于管理 qBittorrent 实例、主机调优、BBR 变体、Docker/Vertex、autobrr、autoremove-torrents、状态报告、日志和诊断等功能。

这个项目主要面向两类使用场景：

<a id="profiles"></a>
- **独享服务器或 VPS 主机**：你拥有 root 权限，可以管理用户、systemd 服务、APT 软件包、内核/网络调优、Docker 和 BBR。
- **共享或无 root 的 Seedbox 账号**：你只能控制自己的 Unix 账号，希望在不使用 `sudo` 的情况下运行 qBittorrent。

---

## 目录

- [功能特性](#features)
- [支持环境](#supported-environments)
- [快速开始](#quick-start)
- [CLI 概览](#cli-overview)
- [组件](#components)
- [路径、日志和状态](#paths-logs-and-state)
- [升级与卸载](#upgrade-and-uninstall)
- [故障排查](#troubleshooting)

---

<a id="supported-environments"></a>
## 支持环境

`seedboxctl --lang zh-CN` 会在执行变更前进行运行时检测。

| 项目 | 支持情况 |
| --- | --- |
| 操作系统 | Debian 11 或更新版本；Ubuntu 20.04 或更新版本。 |
| 架构 | `amd64` / `x86_64` 以及 `arm64` / `aarch64` |
| 初始化系统 | 主机/系统级服务需要 systemd。无 root 模式可回退到 `screen` 或 daemon 模式。 |
| 包管理器 | root/管理员模式安装需要基于 APT 的 Debian/Ubuntu 主机。 |
| 无 root 安装 | 仅支持 qBittorrent。无 root 模式不会运行 APT、创建用户、调优主机、安装 Docker 或安装 BBR。 |

主机级组件（例如调优、Docker、Vertex 和 BBR）应只在你自己控制的主机或完整虚拟机上运行。

---

<a id="quick-start"></a>
## 快速开始

### 独享 Seedbox

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --lang zh-CN\
  -u jerry048 \
  -p 'change-this-password' \
  -c 3072 \
  -q 5.2.2 -l v2.0.13 \
  -b -v -r \
  -x

seedboxctl --lang zh-CN version
```
### 共享 Seedbox
```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --rootless --lang zh-CN\
  -u jerry048 \
  -p 'change-this-password' \
  -c 3072 \
  -q 5.2.2 -l v2.0.13 \
  --service-mode auto

~/.local/bin/seedboxctl --lang zh-CN version
```
#### 选项
	1. -u：Linux 用户名；rootless 模式下作为 WebUI 用户名
	2. -p：密码
	3. -c：qBittorrent 缓存大小，单位 MiB
	4. -q：qBittorrent 版本，例如 5.2.2
	5. -l：libtorrent 版本，例如 v1.2.20
	6. -b：安装 autobrr（需要 root）
	7. -v：安装 Vertex（需要 root）
	8. -r：安装 autoremove-torrents（需要 root）
	9. -3：安装 BBRv3（需要 root）
	10.-x：安装 BBRx（需要 root）
	11.-o：自定义端口
	12.-T：跳过系统调优
	13.--storage-path 路径：系统调优使用该路径背后的存储；默认使用 qBittorrent 下载目录
	14.--disk-scheduler-all：对所有合格物理盘应用调度器策略，而不是只处理下载路径背后的磁盘
	15.-L：设置安装界面语言
	16.-h：显示帮助

##### `Install.sh` 运行完成后，可以通过 `seedboxctl --lang zh-CN` 调用脚本

---

<a id="cli-overview"></a>
## CLI 概览

```bash
seedboxctl --lang zh-CN install --profile dedicated|shared [options]
seedboxctl --lang zh-CN qbittorrent add-user|install-self|upgrade|uninstall|status|logs [options]
seedboxctl --lang zh-CN autobrr install|upgrade|uninstall|status [options]
seedboxctl --lang zh-CN autoremove-torrents install|upgrade|uninstall|status [options]
seedboxctl --lang zh-CN vertex install|upgrade|uninstall|status [options]
seedboxctl --lang zh-CN docker install|uninstall|status [options]
seedboxctl --lang zh-CN tuning apply|uninstall|status [options]
seedboxctl --lang zh-CN bbr install|uninstall|status [options]
seedboxctl --lang zh-CN status [--json]
seedboxctl --lang zh-CN logs qbittorrent --user USER
seedboxctl --lang zh-CN doctor [--bundle]
seedboxctl --lang zh-CN list qbittorrent
seedboxctl --lang zh-CN version
```

使用内置帮助查看各组件的专用参数：

```bash
seedboxctl --lang zh-CN help
seedboxctl --lang zh-CN qbittorrent help
seedboxctl --lang zh-CN tuning help
seedboxctl --lang zh-CN bbr help
seedboxctl --lang zh-CN autobrr help
seedboxctl --lang zh-CN autoremove-torrents help
seedboxctl --lang zh-CN vertex help
seedboxctl --lang zh-CN docker help
```

---

<a id="components"></a>
## 组件

### qBittorrent

使用发行版软件包，为某个 Linux 用户安装由 root 管理的实例：

```bash
printf '%s' 'change-this-password' | sudo seedboxctl --lang zh-CN qbittorrent add-user \
  --user jerry048 \
  --password-stdin \
  --source distro \
  --cache 3072 \
  --web-port 8080 \
  --incoming-port 45000
```

为当前用户安装无 root 实例：

```bash
printf '%s' 'change-this-password' | seedboxctl --lang zh-CN qbittorrent install-self \
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

常用 qBittorrent 选项：

| 选项 | 说明 |
| --- | --- |
| `--password-stdin` | 从标准输入读取 WebUI 密码。推荐使用。 |
| `--password-file FILE` | 从文件读取 WebUI 密码。 |
| `--password PASSWORD` | 通过命令参数传入 WebUI 密码。使用方便，但安全性较低。 |
| `--cache MIB` | qBittorrent 缓存大小，单位为 MiB。默认值：`3072`。 |
| `--qb-tuning-profile PROFILE` | 配置调优配置档：`auto`、`legacy`、`1g-hdd`、`1g-hdd-raid0`、`1g-ssd`、`1g-nvme`、`1g-ceph`、`10g-hdd`、`10g-hdd-raid0`、`10g-ssd`、`10g-nvme` 或 `10g-ceph`。 |
| `--web-port PORT` | WebUI 端口。默认值：`8080`。别名：`--qb-web-port`、`--qb-port`。 |
| `--incoming-port PORT` | 入站 BitTorrent 端口。默认值：`45000`。别名：`--qb-incoming-port`。 |
| `--source distro` | 安装/使用操作系统提供的 `qbittorrent-nox` 软件包。仅限 root/管理员模式。 |
| `--source static` | 使用内置或下载的静态 `qbittorrent-nox` 构建。 |
| `--source existing` | 使用 `PATH`、`~/bin` 或 `~/.local/bin` 中已有的 `qbittorrent-nox`。 |
| `--qb-version VERSION` | 静态来源使用的 qBittorrent 版本。 |
| `--libtorrent-version VERSION` | 静态来源使用的 libtorrent 版本。 |
| `--service-mode MODE` | `system`、`user`、`screen`、`daemon`、`auto` 或 `prompt`。 |
| `--webui-username NAME` | 单独设置 WebUI 用户名，不必与 Unix 用户名一致。 |
| `--allow-unverified-downloads` | 允许下载未经 SHA-256 校验的文件。除非你已经审查过构建产物来源，否则不建议在生产环境中使用。 |

列出可用的 qBittorrent 来源和静态 manifest 条目：

```bash
seedboxctl --lang zh-CN list qbittorrent
```

静态 qBittorrent 版本会从 `manifests/qbittorrent.tsv` 这份清单中选择。如果缺少 `--qb-version` 或 `--libtorrent-version`，或者提供的版本组合没有出现在当前架构对应的列表中，交互式安装会打印清单中的可选项并要求你选择其中一个。非交互式安装（例如 CI、cron 或无 TTY 会话）会打印有效选项后退出，方便你使用有效的清单版本组合重新运行。`--source distro` 和 `--source existing` 不使用这份清单，也不会显示版本选择菜单。

选择清单中的版本组合后，静态二进制文件会按以下顺序查找：

1. `Torrent Clients/qBittorrent/<arch>/` 下匹配的内置二进制文件。
2. `manifests/qbittorrent.tsv` 中的 URL。
3. 根据所选 qBittorrent/libtorrent 版本和架构生成的默认 GitHub Raw URL。

下载的静态二进制文件需要 SHA-256 校验和，除非显式传入 `--allow-unverified-downloads`。

#### qBittorrent 配置调优配置档

`--qb-tuning-profile auto` 是默认值。它会检测最高速的非回环网卡，以及下载路径所在的后端存储，然后映射到下表中的某个配置档。使用 `--qb-tuning-profile legacy` 可保留旧版自动启发式规则，也可以显式指定某个配置档：

| 配置档 | 异步 I/O 线程 | 发送缓冲区下限 | 发送缓冲区水位线 | 系数 |
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

额外设置只会在对应版本条件满足时写入：

| 适用条件 | 写入的设置 |
| --- | --- |
| libtorrent 2.x | `Session\HashingThreadsCount`；NVMe/Ceph 配置档使用 `Session\DiskIOType`。 |
| qBittorrent 4.4.5+ | `Session\ConnectionSpeed=500` |
| qBittorrent 4.5.5+ | `Session\DiskQueueSize` 和 `Session\RequestQueueSize`|
| qBittorrent 5.0.1+ 且使用 libtorrent 2.x Ceph 配置档 | `Session\DiskIOType=SimplePreadPwrite`；较旧的 libtorrent-2 qBittorrent 版本会使用 `Posix`，因为当时还不存在 `SimplePreadPwrite`。 |

状态与日志：

```bash
sudo seedboxctl --lang zh-CN qbittorrent status --user jerry048
sudo seedboxctl --lang zh-CN qbittorrent status --user jerry048 --json
sudo seedboxctl --lang zh-CN qbittorrent logs --user jerry048
sudo journalctl -u seedbox-qbittorrent-jerry048.service -n 200 --no-pager
```

无 root 状态与日志：

```bash
seedboxctl --lang zh-CN qbittorrent status
seedboxctl --lang zh-CN qbittorrent logs
systemctl --user status seedbox-qbittorrent.service --no-pager
journalctl --user -u seedbox-qbittorrent.service -n 200 --no-pager
```

### 主机调优

应用自适应 Seedbox 调优：

```bash
sudo seedboxctl --lang zh-CN tuning apply
```

常用调优选项：

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

调优会写入受管理的 drop-in 配置，而不是直接修改大范围的系统文件：

```text
/etc/sysctl.d/99-seedbox.conf
/etc/security/limits.d/99-seedbox.conf
/etc/default/seedbox-tuning
/usr/local/sbin/seedbox-runtime-tuning
/etc/systemd/system/seedbox-safe-tuning.service
```

检查或移除调优：

```bash
sudo seedboxctl --lang zh-CN tuning status
sudo seedboxctl --lang zh-CN tuning uninstall
```

卸载后可能需要重启，才能完全恢复运行时内核/网络参数。

### BBR 变体

##### 关于 BBR 变体的更多信息，请参见[这里](https://github.com/jerry048/Trove/blob/main/BBR-Install/BBR/README.md)

安装一种 BBR 算法：

```bash
sudo seedboxctl --lang zh-CN bbr install --bbr-algo bbrx
```

支持的算法：

```text
bbrv3
bbrx
bbrw
bbr_brutal
bbrw_brutal
```

固定并校验外部 BBR 安装脚本：

```bash
sudo seedboxctl --lang zh-CN bbr install \
  --bbr-algo bbrx \
  --bbr-script-url 'https://raw.githubusercontent.com/jerry048/Trove/<commit>/BBR-Install/BBRInstall.sh' \
  --bbr-raw-base 'https://raw.githubusercontent.com/jerry048/Trove/<commit>/BBR-Install/BBR' \
  --bbr-script-sha256 '<sha256>'
```

检查或移除由 BBR 管理的状态：

```bash
sudo seedboxctl --lang zh-CN bbr status
sudo seedboxctl --lang zh-CN bbr uninstall --bbr-algo bbrx
```

`bbrv3` 使用内核软件包路径，可能需要重启。对于基于 DKMS 的变体，如果本地缺少当前运行内核对应的头文件，并且无法通过 `apt install linux-headers-$(uname -r)` 安装，Seedbox 会自动安装发行版通用内核镜像和头文件，记录一个待处理的 BBR 状态，并要求你先重启进入通用内核，然后再重新运行 BBR 安装。DKMS/内核变更风险较高；请先在一次性 VPS 上测试。

### Docker

安装 Docker：

```bash
sudo seedboxctl --lang zh-CN docker install --docker-source official
```

也可以使用发行版软件包：

```bash
sudo seedboxctl --lang zh-CN docker install --docker-source distro
```

状态与卸载：

```bash
sudo seedboxctl --lang zh-CN docker status
sudo seedboxctl --lang zh-CN docker uninstall
sudo seedboxctl --lang zh-CN docker uninstall --purge --yes
```

### Vertex

通过 Docker 安装 Vertex：

```bash
sudo seedboxctl --lang zh-CN vertex install \
  --vertex-port 3000 \
  --vertex-data-dir /root/vertex
```

默认值：

```text
image: lswl/vertex:stable
data:  /root/vertex
port:  3000
```

只有在你明确需要 Docker 主机网络模式时，才使用 host networking：

```bash
sudo seedboxctl --lang zh-CN vertex install --host-network
```

状态、卸载：

```bash

sudo seedboxctl --lang zh-CN vertex status
sudo seedboxctl --lang zh-CN vertex uninstall
sudo seedboxctl --lang zh-CN vertex uninstall --purge --yes
```

### autobrr

为某个用户安装 autobrr：

```bash
sudo seedboxctl --lang zh-CN autobrr install \
  --user jerry048 \
  --autobrr-port 7474
```

状态、卸载：

```bash

sudo seedboxctl --lang zh-CN autobrr status --user jerry048
sudo seedboxctl --lang zh-CN autobrr uninstall --user jerry048
sudo seedboxctl --lang zh-CN autobrr uninstall --user jerry048 --purge --yes
```

对于标准的 GitHub Release 产物，`seedboxctl --lang zh-CN` 会尝试解析并校验匹配的校验和文件。对于自定义 URL，请提供 `--autobrr-sha256`；或者在审查构建产物后，显式传入 `--allow-unverified-downloads`。

### autoremove-torrents

使用 `pipx` 安装到目标用户的家目录下：

```bash
sudo seedboxctl --lang zh-CN autoremove-torrents install --user jerry048
```

生成的配置是一个安全的起步模板。在启用自动移除前，请先编辑它：

```bash
sudo -e /home/jerry048/.config/autoremove-torrents/config.yml
sudo systemctl enable --now seedbox-autoremove-torrents-jerry048.timer
```

立即安装并启用定时器：

```bash
sudo seedboxctl --lang zh-CN autoremove-torrents install --user jerry048 --enable-autoremove
```

升级、状态、卸载：

```bash
sudo seedboxctl --lang zh-CN autoremove-torrents upgrade --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents status --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents uninstall --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents uninstall --user jerry048 --purge --yes
```

---

<a id="paths-logs-and-state"></a>
## 路径、日志和状态

### Root/管理员模式

```text
/opt/seedbox/Dedicated-Seedbox/                  # 默认的最小运行时
/opt/seedbox/qbittorrent/                        # 静态 qBittorrent 二进制文件
/var/log/seedbox/                                # 操作日志
/var/log/seedbox/steps/                          # 每一步命令的日志
/var/log/seedbox/latest.log                      # 最新日志的符号链接
/var/lib/seedbox/state/                          # 组件状态文件
/home/<user>/.config/qBittorrent/qBittorrent.conf
/home/<user>/qbittorrent/Downloads
/etc/systemd/system/seedbox-qbittorrent-<user>.service
```

### 无 root 模式

```text
~/.local/share/seedbox/Dedicated-Seedbox/        # 默认的最小运行时
~/.local/share/seedbox/qbittorrent/              # 静态 qBittorrent 二进制文件
~/.local/state/seedbox/logs/                     # 操作日志
~/.local/state/seedbox/logs/steps/               # 每一步命令的日志
~/.local/state/seedbox/state/                    # 状态文件
~/.config/qBittorrent/qBittorrent.conf
~/.config/systemd/user/seedbox-qbittorrent.service
~/qbittorrent/Downloads
~/bin/qbittorrent-nox                            # 静态安装的便捷符号链接
~/.local/bin/seedbox-qbittorrent-restart         # 使用 screen/daemon 时的重启辅助脚本
```

总体状态：

```bash
seedboxctl --lang zh-CN status
seedboxctl --lang zh-CN status --json
```

诊断摘要：

```bash
seedboxctl --lang zh-CN doctor
seedboxctl --lang zh-CN doctor --bundle
```

---

<a id="upgrade-and-uninstall"></a>
## 升级与卸载

### qBittorrent

升级基于发行版软件包的安装：

```bash
sudo seedboxctl --lang zh-CN qbittorrent upgrade --user jerry048 --source distro
```

升级静态安装：

```bash
printf '%s' 'change-this-password' | sudo seedboxctl --lang zh-CN qbittorrent upgrade \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.2.2 \
  --libtorrent-version v2.0.13
```

非破坏性卸载：

```bash
sudo seedboxctl --lang zh-CN qbittorrent uninstall --user jerry048
```

这会停止并移除启动文件，但会保留 qBittorrent 配置和下载内容。

清除 qBittorrent 配置/数据：

```bash
sudo seedboxctl --lang zh-CN qbittorrent uninstall --user jerry048 --purge --yes
```

无 root 卸载：

```bash
seedboxctl --lang zh-CN qbittorrent uninstall
seedboxctl --lang zh-CN qbittorrent uninstall --purge --yes
```

### 可选组件

```bash
sudo seedboxctl --lang zh-CN autobrr upgrade --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents upgrade --user jerry048
sudo seedboxctl --lang zh-CN vertex upgrade

sudo seedboxctl --lang zh-CN autobrr uninstall --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents uninstall --user jerry048
sudo seedboxctl --lang zh-CN vertex uninstall
sudo seedboxctl --lang zh-CN docker uninstall
sudo seedboxctl --lang zh-CN tuning uninstall
sudo seedboxctl --lang zh-CN bbr uninstall --bbr-algo bbrx
```

只有在你明确想移除组件数据/配置时，才使用 `--purge --yes`。

---

<a id="troubleshooting"></a>
## 故障排查

先从这里开始：

```bash
seedboxctl --lang zh-CN doctor
seedboxctl --lang zh-CN status
```

创建诊断包：

```bash
seedboxctl --lang zh-CN doctor --bundle
```

Root/管理员日志：

```text
/var/log/seedbox/latest.log
/var/log/seedbox/steps/
/var/lib/seedbox/state/
```

无 root 日志：

```text
~/.local/state/seedbox/logs/latest.log
~/.local/state/seedbox/logs/steps/
~/.local/state/seedbox/state/
```

qBittorrent 系统服务：

```bash
sudo systemctl status seedbox-qbittorrent-jerry048.service --no-pager
sudo journalctl -u seedbox-qbittorrent-jerry048.service -n 200 --no-pager
```

qBittorrent 无 root 用户服务：

```bash
systemctl --user status seedbox-qbittorrent.service --no-pager
journalctl --user -u seedbox-qbittorrent.service -n 200 --no-pager
```

qBittorrent 的 screen 回退方式：

```bash
screen -ls
screen -r seedbox-qbittorrent
```

`doctor` 和步骤日志常见能够发现的问题包括：APT 锁、DNS 故障、下载失败、缺少命令、权限错误、端口被占用、校验和不匹配，以及升级/降级过程中 qBittorrent 密码哈希系列发生变化。
