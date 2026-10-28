# 详细参考

[主指南](../README.zh-CN.md) · [English](reference.md)

Dedicated-Seedbox V2.1.3 的命令选项、组件安装、调优数值、路径及恢复行为。日常操作请先阅读[主指南](../README.zh-CN.md)。

---

## 目录

- [支持环境](#supported-environments)
- [安装示例与旧版别名](#installation-examples)
- [CLI 概览](#cli-overview)
- [状态与监控](#status)
- [日志查看](#logs)
- [组件](#components)
  - [Deluge](#deluge)
  - [qBittorrent](#qbittorrent)
  - [主机调优](#主机调优)
  - [BBR 变体](#bbr-变体)
  - [Docker](#docker)
  - [Vertex](#vertex)
  - [autobrr](#autobrr)
  - [autoremove-torrents](#autoremove-torrents)
- [路径、日志和状态](#paths-logs-and-state)

---

<a id="supported-environments"></a>

## 支持环境

`seedboxctl --lang zh-CN` 会在变更前检测运行环境。

| 项目         | 支持情况                                                                       |
| ------------ | ------------------------------------------------------------------------------ |
| 操作系统     | Debian 11 或更新版本；Ubuntu 20.04 或更新版本。                                |
| 架构         | `amd64` / `x86_64` 以及 `arm64` / `aarch64`                                    |
| 初始化系统   | 主机/系统级服务需要 systemd。无 root 模式可回退到 `screen` 或 daemon 模式。    |
| 包管理器     | root/管理员安装需要基于 APT 的 Debian/Ubuntu 主机。                            |
| 无 root 安装 | 仅支持 qBittorrent。不运行 APT、不创建用户、不调优主机、不安装 Docker 或 BBR。 |

调优、Docker、Vertex 和 BBR 只应在你控制的主机或完整虚拟机上运行。

Deluge 需要 root 和 systemd。1.3.15 支持 Debian 11+/Ubuntu 20.04+；2.2.0 需要 Debian 12+/Ubuntu 22.04+。仅 amd64 经过执行验证。默认安装不包含 Deluge；旧版运行环境会显示已停止维护的安全提示。

---

<a id="installation-examples"></a>

## 安装示例

### 独享 Seedbox

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --lang zh-CN \
  --user jerry048 \
  --password-stdin \
  --cache 3072 \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --components qbittorrent,tuning,autobrr,vertex,autoremove-torrents \
  < /path/to/password.txt

seedboxctl --lang zh-CN version
```

### 共享 Seedbox

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --lang zh-CN \
  --rootless \
  --webui-username jerry048 \
  --password-stdin \
  --cache 3072 \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --service-mode auto \
  < /path/to/password.txt

~/.local/bin/seedboxctl --lang zh-CN version
```

独享示例以 root 运行；共享示例不要使用 root 或 sudo。请先创建私有密码文件并替换示例路径。

`--password`、`--password-file` 和 `--password-stdin` 互斥。`--password-stdin` 必须通过管道或文件重定向读取，不能直接从终端读取。无效组合会在安装开始前报错。

#### 旧版包装器别名

| 短选项           | 规范选项或含义                                                    |
| ---------------- | ----------------------------------------------------------------- |
| `-u USER`        | `--user USER`；旧版 rootless 用法中用于设置 WebUI 用户名          |
| `-p PASSWORD`    | `--password PASSWORD`；推荐密码文件或标准输入                     |
| `-c N`           | `--cache N`（MiB）                                                |
| `-q VERSION`     | `--qb-version VERSION`                                            |
| `-l VERSION`     | `--libtorrent-version VERSION`                                    |
| `-b`、`-v`、`-r` | 在 `--components` 中加入 autobrr、Vertex 或 autoremove-torrents   |
| `-3`、`-x`       | `--bbr-algo bbrv3`、`--bbr-algo bbrx`；默认使用经校验的随附安装器 |
| `-o`             | 交互式设置端口                                                    |
| `-T`             | `--no-tuning`                                                     |
| `-L LANG`        | `--lang LANG`                                                     |
| `-h`             | `--help`                                                          |

`Install.sh` 完成后使用 `seedboxctl`。示例统一使用规范长选项，旧别名仍受支持。

---

<a id="cli-overview"></a>

## CLI 概览

大写单词是参数占位符，`[...]` 表示可选，`{a|b}` 表示选一个值。语法摘要不是可直接执行的命令。每个命令都可在 `seedboxctl` 后指定全局 `--lang LANG`。

```text
seedboxctl --lang zh-CN install --profile {dedicated|shared} [OPTIONS]
seedboxctl --lang zh-CN qbittorrent {add-user|install-self|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl --lang zh-CN deluge {install|add-user|upgrade|uninstall|build-runtime|status|logs} [OPTIONS]
seedboxctl --lang zh-CN autobrr {install|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl --lang zh-CN autoremove-torrents {install|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl --lang zh-CN vertex {install|upgrade|uninstall|status|logs} [OPTIONS]
seedboxctl --lang zh-CN docker {install|uninstall|status|logs} [OPTIONS]
seedboxctl --lang zh-CN tuning {apply|uninstall|status|logs} [OPTIONS]
seedboxctl --lang zh-CN bbr {install|uninstall|status|logs} [OPTIONS]
seedboxctl --lang zh-CN status [--json] [--check]
seedboxctl --lang zh-CN logs COMPONENT [OPTIONS]
seedboxctl --lang zh-CN logs installer [--run RUN_ID] [--step STEP_ID] [OPTIONS]
seedboxctl --lang zh-CN list qbittorrent
seedboxctl --lang zh-CN version
```

组件专用参数：

```bash
seedboxctl --lang zh-CN help
seedboxctl --lang zh-CN qbittorrent help
seedboxctl --lang zh-CN deluge help
seedboxctl --lang zh-CN tuning help
seedboxctl --lang zh-CN bbr help
seedboxctl --lang zh-CN autobrr help
seedboxctl --lang zh-CN autoremove-torrents help
seedboxctl --lang zh-CN vertex help
seedboxctl --lang zh-CN docker help
```

---

<a id="status"></a>

## 状态与监控

`seedboxctl --lang zh-CN status` 读取安装器状态。

```bash
seedboxctl --lang zh-CN status
seedboxctl --lang zh-CN status \
  --json \
  --check
sudo seedboxctl --lang zh-CN qbittorrent status \
  --user jerry048 \
  --json
sudo seedboxctl --lang zh-CN autoremove-torrents status \
  --user jerry048 \
  --check
sudo seedboxctl --lang zh-CN vertex status \
  --vertex-name my-vertex \
  --json
```

JSON 变量（`{"instances":[...]}`，每条记录一个对象）：

| 变量               | 取值                                                                                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `component`        | `qbittorrent-instance`、`deluge-instance`、`autobrr`、`autoremove-torrents`、`vertex`、`docker-engine`、`docker-purge`、`tuning`、`bbr`                       |
| `id`               | 组件内的记录标识                                                                                                                                              |
| `user`             | Unix 账号                                                                                                                                                     |
| `webui_user`       | WebUI 登录名                                                                                                                                                  |
| `rootless`         | `0` 或 `1`                                                                                                                                                    |
| `service`          | 记录的单元或服务名                                                                                                                                            |
| `service_mode`     | `system`、`user`、`screen`、`daemon`                                                                                                                          |
| `web_port`         | 记录的 WebUI 端口                                                                                                                                             |
| `status`           | `active`、`inactive`、`unknown`                                                                                                                               |
| `kind`             | `service`、`process`、`timer`、`container`、`configuration`、`maintenance`                                                                                    |
| `runtime_state`    | `running`、`stopped`、`failed`、`missing`、`unknown`、`identity-mismatch`、`waiting`、`disabled`、`masked`、`paused`、`applied`、`selected`、`pending-reboot` |
| `enabled`          | 单元启用状态（`enabled`、`disabled`、`masked` 等）；Deluge 两个单元的启用状态不同时为 `mixed`                                                                 |
| `recorded_version` | 保存的应用版本                                                                                                                                                |
| `last_job_result`  | 最近的定时器/oneshot 结果                                                                                                                                     |
| `reason`           | 失败或观察详情                                                                                                                                                |
| `check_ok`         | `true` 或 `false`                                                                                                                                             |

`--json` 输出 JSON。`--check` 在预期未满足或无匹配记录时返回 `1`，否则 `0`，语法无效返回 `2`。`--user USER` 筛选 qBittorrent、Deluge、autobrr 和 autoremove-torrents；`--vertex-name NAME` 筛选 Vertex。`check_ok` 只反映预期是否满足，不代表应用健康。

<a id="logs"></a>

## 日志查看

`seedboxctl logs COMPONENT` 与 `seedboxctl COMPONENT logs` 等价，均为只读。

```bash
sudo seedboxctl --lang zh-CN logs qbittorrent \
  --user jerry048 \
  --lines 100
seedboxctl --lang zh-CN qbittorrent logs \
  --source application \
  --follow
sudo seedboxctl --lang zh-CN autoremove-torrents logs \
  --user jerry048 \
  --since '2026-10-22 12:00:00'
sudo seedboxctl --lang zh-CN vertex logs \
  --vertex-name my-vertex \
  --follow
seedboxctl --lang zh-CN logs installer
seedboxctl --lang zh-CN logs installer --list
seedboxctl --lang zh-CN logs --help
```

| 选项             | 取值                                                         |
| ---------------- | ------------------------------------------------------------ |
| `--source`       | `auto`（默认）、`service`、`application`、`installer`、`all` |
| `--lines N`      | 1–10000，默认每来源 200 行                                   |
| `--since TIME`   | journalctl/Docker 时间筛选；建议使用绝对时间戳               |
| `--follow`       | 持续跟踪一个来源                                             |
| `--list`         | 列出来源，或安装器运行/步骤                                  |
| `--run RUN_ID`   | 安装器运行名，不含 `.log`                                    |
| `--step STEP_ID` | 运行中的单个步骤，例如 `qb.upgrade.start`                    |

| 来源          | 读取内容                                                                                             |
| ------------- | ---------------------------------------------------------------------------------------------------- |
| `auto`        | qBittorrent 系统/用户 journal、daemon/screen 应用文件；其他组件使用服务/容器来源；BBR 使用安装器日志 |
| `service`     | 对应的 systemd journal；autoremove-torrents 含任务和定时器；Vertex 读取已验证容器的输出              |
| `application` | qBittorrent 应用文件（`[Application] FileLogger\Path`、`FileLogger\Enabled`）                        |
| `installer`   | 安装器运行/步骤日志                                                                                  |
| `all`         | 依次读取所有支持的来源                                                                               |

root 查看 qBittorrent、Deluge、autobrr 和 autoremove-torrents 时需指定 `--user USER`；普通用户默认使用当前账号。Vertex 使用 `--vertex-name NAME`。日志范围：root 为 `/var/log/seedbox`，其他账号为 `~/.local/state/seedbox/logs`；`SEEDBOX_LOG_BASE` 可覆盖。日志可能含敏感信息，分享前请检查。退出码：`0` 表示已读取，`1` 表示不可用、无匹配或部分失败，`2` 表示选项无效。

<a id="components"></a>

## 组件

### Deluge

```bash
sudo seedboxctl --lang zh-CN deluge add-user \
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

| 选项                                  | 说明                                                              |
| ------------------------------------- | ----------------------------------------------------------------- |
| `--user USER`                         | 实例所有者；不存在时自动创建。                                    |
| `--password-stdin`                    | 从标准输入读取 WebUI 密码。                                       |
| `--password-file FILE`                | 从文件读取 WebUI 密码。                                           |
| `--password PASSWORD`                 | 通过参数传入密码。安全性较低。                                    |
| `--deluge-version VERSION`            | `1.3.15`（默认）或 `2.2.0`。                                      |
| `--deluge-libtorrent-version VERSION` | 1.3.15 搭配 `1.1.14`；2.2.0 搭配 `1.2.20` 或 `2.0.15`（默认）。   |
| `--deluge-web-port PORT`              | WebUI 端口。默认 `8112`。                                         |
| `--deluge-rpc-port PORT`              | RPC 端口。默认 `58846`。                                          |
| `--deluge-incoming-port PORT`         | BT 端口。默认 `45000`。                                           |
| `--deluge-cache-mib N`                | libtorrent 1.x 的缓存大小（MiB），默认 `256`；2.0.15 拒绝该选项。 |
| `--jobs N`                            | 运行环境的编译任务数。默认 `2`。                                  |
| `--source-dir DIR`                    | 离线构建所用的已校验本地源码。                                    |

别名：`--web-port`、`--rpc-port`、`--incoming-port`、`--cache-mib`；仅在 Deluge 专用命令中可用 `--libtorrent-version`。

升级、状态、卸载：

```bash
sudo seedboxctl --lang zh-CN deluge upgrade --user delugeuser
sudo seedboxctl --lang zh-CN deluge status --user delugeuser --check
sudo seedboxctl --lang zh-CN deluge uninstall --user delugeuser
```

### qBittorrent

#### 静态安装

为 Linux 用户安装由 root 管理的实例，使用固定静态组合：

```bash
sudo seedboxctl --lang zh-CN qbittorrent add-user \
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

| 选项                                       | 说明                                                                                                                               |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `--user USER`                              | 拥有实例的 Linux 账号。                                                                                                            |
| `--password-stdin`                         | 从标准输入读取 WebUI 密码。推荐。                                                                                                  |
| `--password-file FILE`                     | 从文件读取 WebUI 密码。                                                                                                            |
| `--password PASSWORD`                      | 通过参数传入密码。方便但不够安全。                                                                                                 |
| `--source static`                          | 内置或下载的静态 `qbittorrent-nox`（Install.sh 默认）。                                                                            |
| `--qb-version VERSION`                     | 清单中的 qBittorrent 版本。                                                                                                        |
| `--libtorrent-version VERSION`             | 清单中的 libtorrent 版本。                                                                                                         |
| `--cache N`                                | 缓存大小，单位 MiB。默认 `3072`。                                                                                                  |
| `--web-port PORT`                          | WebUI 端口。默认 `8080`。别名：`--qb-web-port`、`--qb-port`。                                                                      |
| `--incoming-port PORT`                     | 入站 BT 端口。默认 `45000`。别名：`--qb-incoming-port`。                                                                           |
| `--webui-username NAME`                    | WebUI 用户名，可与 Unix 用户不同。                                                                                                 |
| `--service-mode MODE`                      | `system`、`user`、`screen`、`daemon`、`auto` 或 `prompt`。                                                                         |
| `--qb-tuning-profile PROFILE`              | `auto`、`legacy` 或 `1g-*`/`over1g-*` 配置档。                                                                                     |
| `--storage TYPE`、`--storage-path PATH`    | 存储覆盖：`auto`、`hdd`、`hdd-raid0`、`ssd`、`nvme`、`ceph`（也接受 `sata-ssd`）。路径仅用于识别调优所用的存储，不会迁移下载目录。 |
| `--interface IFACE`、`--link-speed-mbps N` | 网卡/带宽覆盖。也接受 `--netdev` 和 `--link-speed 2.5g`。                                                                          |
| `--allow-unverified-downloads`             | 允许跳过 SHA-256 校验。除非已审查来源，否则不要用于生产。                                                                          |

#### 其他安装来源

发行版软件包：

```bash
sudo seedboxctl --lang zh-CN qbittorrent add-user \
  --user jerry048 \
  --password-stdin \
  --source distro \
  --cache 3072 \
  --web-port 8080 \
  --incoming-port 45000 \
  < /path/to/password.txt
```

已有二进制：

```bash
seedboxctl --lang zh-CN qbittorrent add-user \
  --user jerry048 \
  --password-stdin \
  --source existing \
  --web-port 8080 \
  --incoming-port 45000 \
  < /path/to/password.txt
```

`add-user` 为 `--user USER` 指定的用户管理实例。`--source distro` 使用系统 `qbittorrent-nox` 包；`--source existing` 使用 `PATH`、`~/bin` 或 `~/.local/bin` 中的版本。两者都不使用静态清单。

#### 无 root

以当前用户身份安装，不使用 root 或 sudo：

```bash
seedboxctl --lang zh-CN qbittorrent install-self \
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

以上选项同样适用。省略 `--user`；`--service-mode` 默认 `auto`，也接受 `prompt`。

#### 调优档

用 `--qb-tuning-profile PROFILE` 覆盖自动选择。

| 配置档             | 异步 I/O 线程 | 发送缓冲区下限（MiB） | 发送缓冲区水位线（MiB） | 系数 | 请求上限（4.5.5+） |
| ------------------ | ------------: | --------------------: | ----------------------: | ---: | -----------------: |
| `1g-hdd`           |             4 |                     3 |                      10 | 150% |               2000 |
| `1g-hdd-raid0`     |             8 |                     3 |                      16 | 150% |               4000 |
| `1g-ssd`           |            12 |                     5 |                      20 | 200% |               4000 |
| `1g-nvme`          |            16 |                     5 |                      20 | 200% |               8000 |
| `1g-ceph`          |             8 |                     5 |                      20 | 200% |               4000 |
| `over1g-hdd`       |             4 |                     3 |                      16 | 250% |               4000 |
| `over1g-hdd-raid0` |             8 |                     3 |                      16 | 250% |               8000 |
| `over1g-ssd`       |            16 |                     5 |                      32 | 300% |              10000 |
| `over1g-nvme`      |            32 |                     5 |                      32 | 300% |              10000 |
| `over1g-ceph`      |            16 |                     5 |                      32 | 250% |              10000 |

版本相关设置：

| 适用条件                                         | 写入的设置                                                                                                       |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| libtorrent 2.x                                   | `Session\HashingThreadsCount`；NVMe/Ceph 配置档的 `Session\DiskIOType`。                                         |
| qBittorrent 4.4.5+                               | `Session\ConnectionSpeed=500`                                                                                    |
| qBittorrent 4.5.5+                               | `Session\DiskQueueSize` 和 `Session\RequestQueueSize`                                                            |
| qBittorrent 5.0.1+ 且 libtorrent 2.x Ceph 配置档 | `Session\DiskIOType=SimplePreadPwrite`；较旧的 libtorrent-2 版本使用 `Posix`，因为当时尚无 `SimplePreadPwrite`。 |

#### 配置保留

升级合并当前配置，而非用模板替换。

- 现有 WebUI 设置——端口、用户名、下载路径、限制、排队、认证/安全、自定义调优——优先于过期的安装器状态。
- 显式 CLI 参数覆盖单项设置。
- 已知新旧键名和值格式会迁移，包括 5.3 的 WebUI 分节变化。缺失默认值会补充。
- 除非用配置档或硬件选项重新调优受管字段，否则保留调优值。
- `--cache` 同时更新磁盘缓存和进程内存限制；省略时两者各自保留，包括自动或禁用缓存。

配置会在旧进程停止后重新读取，以保留退出时的写入。权限 `0600` 的 `qBittorrent.conf.pre-upgrade.*` 快照保留在配置旁，成功升级后也不删除。跨越 4.1 密码哈希边界需提供密码参数。旧目标无法实现所有新功能：未知键保留但可能被忽略，无法安全表达的转换——4.6 之前的启用代理、部分 HTTPS 证书格式变化、不支持的枚举——会报错，而非削弱设置。降级时保留快照。无 root 迁移需要 Python 3，包括 4.1 目标版本。

#### 升级静态版本

```bash
sudo seedboxctl --lang zh-CN qbittorrent upgrade \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  < /path/to/password.txt
```

升级、状态、卸载：

```bash
sudo seedboxctl --lang zh-CN qbittorrent upgrade --user jerry048
sudo seedboxctl --lang zh-CN qbittorrent status --user jerry048
sudo seedboxctl --lang zh-CN qbittorrent uninstall --user jerry048
```

### 主机调优

```bash
sudo seedboxctl --lang zh-CN tuning apply \
  --storage auto \
  --storage-path /path/to/storage \
  --interface auto \
  --link-speed-mbps 1000 \
  --txqueuelen 10000 \
  --initial-cwnd 25 \
  --disk-scheduler-all
```

| 选项                               | 说明                                                            |
| ---------------------------------- | --------------------------------------------------------------- |
| `--storage TYPE`                   | `auto`、`hdd`、`hdd-raid0`、`ssd`、`sata-ssd`、`nvme`、`ceph`。 |
| `--storage-path PATH`              | 用于识别存储的路径。                                            |
| `--interface IFACE`                | 要调优的网卡；别名 `--netdev`。                                 |
| `--link-speed-mbps N`              | 带宽覆盖值。                                                    |
| `--link-speed 1g\|10g\|25g\|2500m` | 带宽便捷写法。                                                  |
| `--txqueuelen N`                   | 网卡发送队列长度。                                              |
| `--initial-cwnd N`                 | 初始拥塞窗口（包数）。                                          |
| `--disk-scheduler-all`             | 对所有合格磁盘应用调度策略。                                    |
| `--no-sysctl`                      | 跳过 sysctl 设置。                                              |
| `--no-limits`                      | 跳过 ulimit。                                                   |
| `--no-cpu-tuning`                  | 跳过 CPU 策略。                                                 |
| `--no-read-ahead`                  | 跳过预读。                                                      |
| `--no-ring-buffer`                 | 跳过网卡环形缓冲区。                                            |
| `--no-rss`                         | 跳过接收端缩放。                                                |
| `--no-rps`                         | 跳过接收包分发。                                                |
| `--no-rfs`                         | 跳过接收流分发。                                                |
| `--no-xps`                         | 跳过发送包分发。                                                |
| `--no-initial-cwnd`                | 跳过初始 cwnd/initrwnd。                                        |
| `--no-disk-scheduler`              | 跳过调度器策略。                                                |
| `--no-net-queue-tuning`            | 跳过所有网卡队列调优。                                          |

受管 drop-in：

```text
/etc/sysctl.d/99-seedbox.conf
/etc/security/limits.d/99-seedbox.conf
/etc/default/seedbox-tuning
/usr/local/sbin/seedbox-runtime-tuning
/etc/systemd/system/seedbox-safe-tuning.service
```

检查或移除：

```bash
sudo seedboxctl --lang zh-CN tuning status
sudo seedboxctl --lang zh-CN tuning uninstall
```

### BBR 变体

##### 关于 BBR 变体的更多信息，请参见[这里](https://github.com/jerry048/Trove/blob/main/BBR-Install/BBR/README.md)

所有变体默认使用经 SHA-256 校验的随附安装器：`sudo seedboxctl --lang zh-CN bbr install --bbr-algo bbrx`。DKMS 变体支持 Debian 11–13 和 Ubuntu 20.04/22.04/24.04/26.04，需内核 5.4–7.1.x 及匹配的头文件。未配置 Ubuntu 20.04 的 BBRv3 软件包；其他系统的可用性取决于系统和架构。以下选项展示如何指定自定义安装器，需提供校验值或明确允许跳过校验。

Ubuntu 20.04 amd64 验证：五种 DKMS 变体均使用 GCC 9.4/DKMS 2.8.1，针对 `5.4.0-216-generic` 和 `5.15.0-139-generic` 完成编译与安装。两个内核均在 QEMU 中启动；每个模块均通过加载、拥塞控制算法切换、经 SHA-256 校验的 1 MiB 回环 TCP 传输、恢复 Cubic 及卸载检查。这些检查不涵盖 ARM64、Secure Boot 或长时间运行与性能测试。

卸载时先卸载内核模块，再移除 DKMS 文件；模块仍被占用时保留安装文件和状态。BBRv3 状态检查要求当前内核与记录的 `kernel_release` 一致，仅选中 `bbr` 算法不算通过。旧 BBRv3 记录需重新安装以记录目标内核。自定义 BBRv3 安装器须将目标内核版本标识写入传入的 `BBR_KERNEL_RESULT_FILE`；否则状态保持未验证。

```bash
sudo seedboxctl --lang zh-CN bbr install \
  --bbr-algo bbrx \
  --bbr-script-url 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBRInstall.sh' \
  --bbr-raw-base 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBR' \
  --bbr-script-sha256 SHA256 \
  --bbr-lang en \
  --force-runtime \
  --upgrade-system \
  --no-clear
```

| 选项                               | 说明                                                               |
| ---------------------------------- | ------------------------------------------------------------------ |
| `--bbr-algo ALGO`                  | `bbrv3`、`bbrx`、`bbrx_old`、`bbrw`、`bbr_brutal`、`bbrw_brutal`。 |
| `--bbr-script-url URL`             | 安装器 URL。                                                       |
| `--bbr-script-sha256 SHA256`       | 校验安装器。                                                       |
| `--bbr-raw-base URL`               | DKMS 源码的基础 URL。                                              |
| `--bbr-lang LANG`                  | 安装器语言：`en`、`zh-CN`、`zh-TW`。                               |
| `--allow-unverified-bbr-installer` | 审查后跳过安装器校验。                                             |
| `--force-runtime`                  | 允许容器/WSL。                                                     |
| `--upgrade-system`                 | 安装器支持时传递 `--upgrade-system`。                              |
| `--no-clear`                       | 安装器支持时传递 `--no-clear`。                                    |

检查或移除：

```bash
sudo seedboxctl --lang zh-CN bbr status
sudo seedboxctl --lang zh-CN bbr uninstall --bbr-algo bbrx
sudo seedboxctl --lang zh-CN bbr uninstall --bbr-algo bbrx_old
```

### Docker

```bash
sudo seedboxctl --lang zh-CN docker install \
  --docker-source official \
  --allow-docker-package-removal
```

| 选项                             | 说明                            |
| -------------------------------- | ------------------------------- |
| `--docker-source SOURCE`         | `official`（默认）或 `distro`。 |
| `--allow-docker-package-removal` | 同意移除冲突软件包。            |

```bash
sudo seedboxctl --lang zh-CN docker status
sudo seedboxctl --lang zh-CN docker uninstall
sudo seedboxctl --lang zh-CN docker uninstall \
  --purge \
  --yes
```

执行清理时，必须在任何停止、禁用或软件包变更**之前**传入 `--yes`。

### Vertex

```bash
sudo seedboxctl --lang zh-CN vertex install \
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

| 选项                             | 说明                                |
| -------------------------------- | ----------------------------------- |
| `--vertex-name NAME`             | 容器名。默认 `vertex`。             |
| `--vertex-port PORT`             | 发布的 WebUI 端口。默认 `3000`。    |
| `--vertex-data-dir DIR`          | 主机数据目录。默认 `/root/vertex`。 |
| `--vertex-image IMAGE`           | 镜像。默认 `lswl/vertex:stable`。   |
| `--timezone TZ`                  | 容器时区。默认 `Asia/Shanghai`。    |
| `--user WEBUI_USER`              | Vertex WebUI 用户名。               |
| `--password-stdin`               | 从标准输入读取 WebUI 密码。         |
| `--password-file FILE`           | 从文件读取 WebUI 密码。             |
| `--password PASSWORD`            | 通过参数传入密码。安全性较低。      |
| `--docker-source SOURCE`         | `official`（默认）或 `distro`。     |
| `--allow-docker-package-removal` | 同意移除冲突软件包。                |
| `--force`                        | 替换已有的受管实例。                |
| `--host-network`                 | 使用 Docker 主机网络，不发布端口。  |

默认值：

```text
image: lswl/vertex:stable
data:  /root/vertex
port:  3000
```

升级、状态、卸载：

```bash
sudo seedboxctl --lang zh-CN vertex upgrade
sudo seedboxctl --lang zh-CN vertex status
sudo seedboxctl --lang zh-CN vertex uninstall
sudo seedboxctl --lang zh-CN vertex uninstall \
  --purge \
  --yes
```

使用安装时的同一个 `--vertex-name`：

```bash
sudo seedboxctl --lang zh-CN vertex status --vertex-name my-vertex
sudo seedboxctl --lang zh-CN vertex upgrade --vertex-name my-vertex
sudo seedboxctl --lang zh-CN vertex uninstall --vertex-name my-vertex
```

### autobrr

```bash
sudo seedboxctl --lang zh-CN autobrr install \
  --user jerry048 \
  --autobrr-port 7474 \
  --autobrr-url 'https://github.com/autobrr/autobrr/releases/download/VERSION/autobrr_VERSION_linux_x86_64.tar.gz' \
  --autobrr-sha256 SHA256 \
  --allow-unverified-downloads \
  --force
```

| 选项                           | 说明                      |
| ------------------------------ | ------------------------- |
| `--user USER`                  | 服务账号。                |
| `--autobrr-port PORT`          | WebUI 端口。默认 `7474`。 |
| `--autobrr-url URL`            | 自定义发布包。            |
| `--autobrr-sha256 SHA256`      | 校验发布包。              |
| `--allow-unverified-downloads` | 审查后跳过校验。          |
| `--force`                      | 重新生成完整配置。        |

升级、状态、卸载：

```bash
sudo seedboxctl --lang zh-CN autobrr upgrade --user jerry048
sudo seedboxctl --lang zh-CN autobrr status --user jerry048
sudo seedboxctl --lang zh-CN autobrr uninstall --user jerry048
sudo seedboxctl --lang zh-CN autobrr uninstall \
  --user jerry048 \
  --purge \
  --yes
```

标准 GitHub Release 会解析并校验匹配的校验和文件。自定义 URL 需 `--autobrr-sha256`，或审查后显式 `--allow-unverified-downloads`。

### autoremove-torrents

```bash
sudo seedboxctl --lang zh-CN autoremove-torrents install \
  --user jerry048 \
  --enable-autoremove \
  --force
```

| 选项                  | 说明               |
| --------------------- | ------------------ |
| `--user USER`         | 服务账号。         |
| `--enable-autoremove` | 启用并启动定时器。 |
| `--force`             | 替换已有配置。     |

生成的配置是安全的初始模板。启用自动移除前请先编辑：

```bash
sudo -e /home/jerry048/.config/autoremove-torrents/config.yml
sudo systemctl enable --now seedbox-autoremove-torrents-jerry048.timer
```

升级、状态、卸载：

```bash
sudo seedboxctl --lang zh-CN autoremove-torrents upgrade --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents status --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents uninstall --user jerry048
sudo seedboxctl --lang zh-CN autoremove-torrents uninstall \
  --user jerry048 \
  --purge \
  --yes
```

---

<a id="paths-logs-and-state"></a>

## 路径、日志和状态

### Root/管理员模式

```text
/opt/seedbox/Dedicated-Seedbox/                  # 默认最小运行环境
/opt/seedbox/qbittorrent/                        # 静态 qBittorrent 二进制文件
/var/log/seedbox/                                # 操作日志
/var/log/seedbox/steps/                          # 每步命令日志
/var/log/seedbox/latest.log                      # 最新日志符号链接
/var/lib/seedbox/state/                          # 组件状态文件
/home/USER/.config/qBittorrent/qBittorrent.conf
/home/USER/qbittorrent/Downloads
/etc/systemd/system/seedbox-qbittorrent-USER.service
```

### 无 root 模式

```text
~/.local/share/seedbox/Dedicated-Seedbox/        # 默认最小运行环境
~/.local/share/seedbox/qbittorrent/              # 静态 qBittorrent 二进制文件
~/.local/state/seedbox/logs/                     # 操作日志
~/.local/state/seedbox/logs/steps/               # 每步命令日志
~/.local/state/seedbox/state/                    # 状态文件
~/.config/qBittorrent/qBittorrent.conf
~/.config/systemd/user/seedbox-qbittorrent.service
~/qbittorrent/Downloads
~/bin/qbittorrent-nox                            # 静态安装的便捷符号链接
~/.local/bin/seedbox-qbittorrent-restart         # 使用 screen/daemon 时的重启辅助脚本
```
