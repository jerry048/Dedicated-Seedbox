# 详细参考

[主指南](../README.zh-CN.md) · [English](reference.md)

Dedicated-Seedbox V2.1.0 的完整命令选项、组件安装、调优数值、文件位置与恢复行为。日常安装、升级、卸载和诊断请先阅读[主指南](../README.zh-CN.md)。

---

## 目录

- [支持环境](#supported-environments)
- [安装示例与旧版别名](#installation-examples)
- [CLI 概览](#cli-overview)
- [状态与监控](#status)
- [日志查看](#logs)
- [组件](#components)
- [路径、日志和状态](#paths-logs-and-state)
- [升级与卸载](#upgrade-and-uninstall)
- [故障排查](#troubleshooting)

---

<a id="supported-environments"></a>

## 支持环境

`seedboxctl --lang zh-CN` 会在执行变更前进行运行时检测。

| 项目         | 支持情况                                                                                   |
| ------------ | ------------------------------------------------------------------------------------------ |
| 操作系统     | Debian 11 或更新版本；Ubuntu 20.04 或更新版本。                                            |
| 架构         | `amd64` / `x86_64` 以及 `arm64` / `aarch64`                                                |
| 初始化系统   | 主机/系统级服务需要 systemd。无 root 模式可回退到 `screen` 或 daemon 模式。                |
| 包管理器     | root/管理员模式安装需要基于 APT 的 Debian/Ubuntu 主机。                                    |
| 无 root 安装 | 仅支持 qBittorrent。无 root 模式不会运行 APT、创建用户、调优主机、安装 Docker 或安装 BBR。 |

主机级组件（例如调优、Docker、Vertex 和 BBR）应只在你自己控制的主机或完整虚拟机上运行。
Deluge 额外要求 Debian 12+/Ubuntu 22.04+、root 和 systemd；仅 amd64 有执行验证。默认安装不包含 Deluge；选择旧版运行环境时仍会显示其已停止维护的安全提示。

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

独享示例需以 root 运行；共享/rootless 示例不要使用 root/sudo。请先创建私有密码文件，再替换示例中的路径。

#### 旧版包装器别名

| 短选项           | 规范选项或含义                                                  |
| ---------------- | --------------------------------------------------------------- |
| `-u USER`        | `--user USER`；旧版 rootless 用法设置 WebUI 用户名              |
| `-p PASSWORD`    | `--password PASSWORD`；推荐密码文件或标准输入                   |
| `-c N`           | `--cache N`（MiB）                                              |
| `-q VERSION`     | `--qb-version VERSION`                                          |
| `-l VERSION`     | `--libtorrent-version VERSION`                                  |
| `-b`、`-v`、`-r` | 在 `--components` 中加入 autobrr、Vertex 或 autoremove-torrents |
| `-3`、`-x`       | `--bbr-algo bbrv3`、`--bbr-algo bbrx`；仍需安装器信任选项       |
| `-o`             | 交互式设置端口                                                  |
| `-T`             | `--no-tuning`                                                   |
| `-L LANG`        | `--lang LANG`                                                   |
| `-h`             | `--help`                                                        |

`Install.sh` 完成后，用 `seedboxctl` 管理生命周期。以下示例统一使用规范长选项，旧别名仍受支持。

---

<a id="cli-overview"></a>

## CLI 概览

语法约定：大写单词是参数占位符，`[...]` 表示可选，`{a|b}` 表示选一个值。语法摘要不是可直接执行的 shell 命令。每个命令都可在 `seedboxctl` 后指定全局 `--lang LANG`。

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

使用内置帮助查看各组件的专用参数：

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

`seedboxctl status` 只读取当前 Unix 账号可见的安装器状态，不创建日志/状态目录、不 chmod 文件、不安装依赖、不启动服务、不读取应用凭据，也不连接外部主机。状态目录不存在表示没有受管安装，不会自动创建。root 默认查看系统状态，普通用户默认查看自己的状态；不扫描其他用户的私有安装，也不会自动切换用户访问其 systemd 会话。

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

所有组件的状态命令共用同一采集器，均支持 `--json` 与 `--check`。qBittorrent、Deluge、autobrr、autoremove-torrents 用 `--user USER` 筛选，Vertex 用 `--vertex-name NAME` 筛选。未筛选时 root 列出该组件所有记录，普通用户的用户组件查询默认仅当前账号。用户级 systemd 查询需以实例所有者执行；管理器不可访问应显示 `unknown`，不能断言服务已停止。

Deluge 同时检查记录中的 daemon 和 WebUI 单元，两者运行才有 `check_ok=true`。`service` 仍为 daemon 单元，`reason` 说明失败原因；两者启用状态不同时为 `mixed`。保存的组件名为 `deluge-instance`，JSON 字段及退出码沿用共用规则；不代表认证或应用健康检查通过。

| 组件                | 观察内容                                                                                                           |
| ------------------- | ------------------------------------------------------------------------------------------------------------------ |
| qBittorrent         | 确切的系统/用户服务；daemon/screen 模式匹配可执行文件路径及实际/有效 UID。仅端口监听不足以判定运行。               |
| autobrr             | 已记录的系统服务状态及运行结果。                                                                                   |
| autoremove-torrents | 定时器实际启用/活动状态及最近任务结果。定时器禁用且未记录任务失败可正常通过；任务之间 oneshot 服务空闲是正常现象。 |
| Docker              | `/var/run/docker.sock` 上的本机系统守护进程及系统服务状态，忽略远程 Docker context、主机及 TLS 覆盖值。            |
| Vertex              | 已保存的完整容器 ID、名称、`/vertex` 绑定挂载、运行状态及已有 Docker 健康检查；不自动认领旧版/不匹配的身份。       |
| 系统调优            | 已有默认配置/helper 及启动 oneshot 服务的最近结果。应用成功不等于常驻服务，也不代表逐项验证了所有内核实时值。      |
| BBR                 | 当前选择且已注册到内核的拥塞控制，允许内建模块。通用内核回退记录在安装完成前显示 `pending-reboot`。                |

端口、版本和 WebUI 用户名来自保存的状态，明确标为记录值，不重新询问应用。本地管理器查询限时四秒，另有一秒强制终止宽限；工具缺失、权限问题、超时或响应不完整显示为未验证，不当作健康。多个实例需要多次查询，并发安装/停止可能使报告变化。

全局 JSON 使用 `instances` 数组，包含字符串字段 `component`、`user`、`webui_user`、`rootless`、`service`、`service_mode`、`web_port`、`status`、`id`、`kind`、`runtime_state`、`enabled`、`recorded_version`、`last_job_result`、`reason`，以及布尔值 `check_ok`。其中 `status` 为 `active`、`inactive` 或 `unknown`。缺少的字符串元数据为空，无法确定的启用状态为 `unknown`。JSON 输出至 stdout，致命采集错误输出至 stderr。

组件 JSON 与全局状态统一使用 `instances`；读取旧版 qBittorrent 扁平对象的脚本需改读 `.instances[0]`。组件名使用状态中的值，例如 `qbittorrent-instance`、`docker-engine`；`id` 区分同一组件的记录。

`runtime_state` 提供更具体的运行、停止、失败、缺失、身份不符、等待、禁用、已应用、已选中或待重启状态。用 `check_ok` 判断组件预期是否满足，不要将所有非运行中的配置或定时器视为故障。它不保证认证、连接或传输性能。

| 退出码 | 普通报告                                                       | `--check`                                                        |
| ------ | -------------------------------------------------------------- | ---------------------------------------------------------------- |
| `0`    | 已生成报告，允许停止/缺失的实例或空列表。                      | 所选记录均满足各自预期；明确禁用的安全定时器可通过。             |
| `1`    | 无法安全读取/枚举状态目录。单个无效/不可读记录显示 `unknown`。 | 有未满足/无法验证的预期、待完成安装/重启、空选择或致命采集错误。 |
| `2`    | 命令、选项或筛选语法无效。                                     | 命令、选项或筛选语法无效。                                       |

`--check` 仅用于状态命令，绝不自动修复。先查看原因及相关日志，再决定如何处理。

<a id="logs"></a>

## 日志查看

`seedboxctl logs COMPONENT` 与 `seedboxctl COMPONENT logs` 等价，均只读，不初始化/chmod 状态或日志目录，不启动服务、不安装工具、不修复权限。root 查看 qBittorrent、autobrr、autoremove-torrents 运行日志需指定 `--user USER`；普通用户默认当前账号。多个 Vertex 实例需用 `--vertex-name NAME` 筛选。运行日志仅选择已有受管状态；安装失败或卸载后，即使没有状态记录，也能查看保留的安装器日志。

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

| 来源           | 选择规则                                                                                                                                                                                                                                                                      |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auto`（默认） | qBittorrent 系统/用户服务读取确切的服务 journal；daemon/screen 读取应用文件。qBittorrent journal 不可访问时说明原因并回退到应用文件，但不对带时间筛选的请求这样做。其他组件使用服务/容器来源，BBR 使用安装器日志。                                                            |
| `service`      | qBittorrent、autobrr、Docker、调优的确切服务 journal；autoremove-torrents 同时读取任务和定时器，包括历史执行。Vertex 从本机 Docker 读取已验证的保存容器 ID 的 stdout/stderr。BBR 没有独立守护进程日志。                                                                       |
| `application`  | qBittorrent 应用文件。默认使用受管 home/XDG 路径；尊重 `[Application] FileLogger\Path` 及禁用的 `FileLogger\Enabled`。无需 Python 即可解码支持的 QSettings 引号、反斜杠和十六进制转义；无法可靠解码或不安全的路径拒绝处理，不猜测。此前丢弃的 daemon/screen stdout 无法恢复。 |
| `installer`    | 最近匹配该组件的安装器运行，或指定运行/步骤；组合安装通过记录的组件步骤 ID 匹配。                                                                                                                                                                                             |
| `all`          | 依次查看所有支持的来源；请求的来源缺失/不可访问时视为部分失败，不做实时多源合流。                                                                                                                                                                                             |

`--lines N` 范围 1–10000，默认**每个来源** 200 行。`--since TIME` 将时间表达式传给 journalctl/Docker；二者相对时间语法不同，建议使用绝对时间戳。普通文件及 `--source all` 不接受该选项。`--list` 只列来源可用性；`--source installer --list` 列运行记录。可读空日志返回成功；journal 可访问不等于仍保存着指定单元的记录。查看器不会修改保留策略或开启应用日志。

`--follow` 持续跟踪一个来源，直到中断，不可与 `--list` 或 `--source all` 同用。文件跟踪固定在验证过的已打开描述符上，即使文件被重命名，也不会打开替换文件或跟随替换符号链接；轮转后重新执行命令以选择新文件。管理器发现及非跟踪查询有限时，明确请求的实时跟踪则不限时。Ctrl+C 清理查看器的子进程。文件读取依赖 Bash、coreutils、`/proc` 和 `timeout`；跟踪另需 `setsid`，缺失时只报错，不自动安装。

### 安装器运行与步骤

Deluge 支持 `logs --user USER`，选择与权限规则同 qBittorrent。`auto`/`service` 用一次查询同时读取 daemon 和 WebUI journal，也支持 `--follow`；`all` 再加安装器日志，没有应用文件来源。`deluge.*` 步骤 ID 可匹配编译、安装、升级及组合安装。

`seedboxctl logs installer` 查看调用账号日志范围内的最近运行。`--list` 输出运行 ID、操作、文件名中的时间及已记录失败步骤 ID；最近运行按文件修改时间选择。运行 ID 是**不带 `.log`** 的文件名。`seedboxctl logs installer --run RUN_ID` 查看指定运行，增加 `--list` 列出已记录完成/失败的步骤，或增加 `--step STEP_ID` 读取一个步骤。例如，将列表中的 ID 代入 `seedboxctl logs installer --run RUN_ID --step qb.upgrade.start`。步骤路径来自该运行的记录，不假定相近时间戳的目录属于同一运行。尚无结果/路径记录的正在执行步骤可能暂不可选；没有记录失败时，不凭空认定失败。

组件的 `--source installer` 和 `--source all` 是**按组件筛选，不按实例/用户筛选**：历史日志并未一致记录目标 Unix 用户。`--user` 仍筛选运行来源，但不缩小安装器记录范围。root 默认日志范围为 `/var/log/seedbox`，普通用户为 `~/.local/state/seedbox/logs`，可用 `SEEDBOX_LOG_BASE` 覆盖。有意创建的 `latest.log` 链接会检查是否指向日志目录内，不跟随无关/不安全链接。发现过程限八秒和 1024 个候选运行，摘要限制四 MiB；历史过多时用运行 ID 缩小范围。不可读/不安全运行会报告并跳过，不通过符号链接读取。

### 权限、输出及退出码

即使 root 调用，应用文件也以实例所有者权限读取。不安全路径、符号链接、FIFO 及其他非普通文件均拒绝，读取内容前检查文件身份。用户级 systemd journal 需由实例所有者查询，root 不自动切换其会话。Docker 固定使用 `/var/run/docker.sock`，忽略远程主机/context/TLS 覆盖值。访问 Vertex 日志前必须验证容器 ID、名称和数据挂载；验证过的停止/不健康容器仍可能有有用日志。

日志正文到 stdout，来源标签、失败提示和警告到 stderr。Docker 应用的 stdout/stderr 合并作为日志正文。不使用 pager，也不额外添加颜色。日志可能包含密码、令牌、私有路径或地址，分享前务必检查，**不保证自动脱敏**。来源标签独立于正文，因此管道只得到原始条目，不是带标签的报告。

退出 `0` 表示来源已读取（包括可访问的空日志）；`1` 表示不可访问、权限拒绝、超时、无匹配运行、实例选择不明确或明确多源请求部分失败；`2` 表示选项无效或组合不支持。中断跟踪可返回常规信号相关状态。不提供 JSON、bundle、远程日志或自动修复。

<a id="components"></a>

## 组件

### Deluge

可选 **1.3.15 / libtorrent 1.1.14**（默认），或 **2.2.0 / libtorrent 1.2.20、2.0.15**。使用 `--components deluge --deluge-version 2.2.0 --deluge-libtorrent-version 2.0.15`，也可在 `seedboxctl deluge add-user --user USER --password-stdin` 后指定相同版本参数。Deluge 2.2.0 默认搭配 libtorrent 2.0.15；1.3.15 会显示旧版安全提示，但无需额外确认参数。需要 root/systemd 和 Debian 12+/Ubuntu 22.04+。默认仅回环监听的 WebUI 为 `8112`、RPC 为 `58846`，BT TCP/UDP 端口为 `45000`。libtorrent 1.x 缓存默认 `256` MiB；2.x 拒绝显式缓存参数，记录 `cache_mib=n/a`。组合安装请用 `--deluge-*` 参数；通用客户端端口、缓存和 `--libtorrent-version` 属于 qBittorrent，入站端口必须显式区分。

[Deluge 指南](../Torrent%20Clients/Deluge/README.zh-CN.md)包含安全提示、SSH 访问、带补丁的原生构建、配置格式、迁移、保留版本组合与设置的 `upgrade`、仅清理配置的 `uninstall --purge --yes` 及双服务监控。运行环境在 `/opt/deluge-1.3.15` 或 `/opt/deluge-2.2.0-lt-{1.2.20,2.0.15}`；实例状态为 `/var/lib/seedbox/state/deluge.USER.env`，日志在 `/var/log/seedbox`。主版本或 ABI 切换会在停止服务前被拒绝，需要手动迁移或使用新 Unix 账号。普通卸载和清理均保留下载、会话元数据、插件、快照及共用运行环境。默认 qBittorrent 和 rootless 配置不包含 Deluge。

### qBittorrent

使用发行版软件包，为某个 Linux 用户安装由 root 管理的实例：

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

为当前用户安装无 root 实例：

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

常用 qBittorrent 选项：

`seedboxctl` 会拒绝未知选项、缺失参数值，以及当前命令/所选组件不支持的选项，而非静默忽略。旧选项别名仍受支持。

| 选项                                       | 说明                                                                                                                                                                                                |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--password-stdin`                         | 从标准输入读取 WebUI 密码。推荐使用。                                                                                                                                                               |
| `--password-file FILE`                     | 从文件读取 WebUI 密码。                                                                                                                                                                             |
| `--password PASSWORD`                      | 通过命令参数传入 WebUI 密码。使用方便，但安全性较低。                                                                                                                                               |
| `--cache N`                                | qBittorrent 缓存大小，单位为 MiB。默认值：`3072`。                                                                                                                                                  |
| `--qb-tuning-profile PROFILE`              | 配置档：`auto`、`legacy`、`1g-hdd`、`1g-hdd-raid0`、`1g-ssd`、`1g-nvme`、`1g-ceph`、`over1g-hdd`、`over1g-hdd-raid0`、`over1g-ssd`、`over1g-nvme` 或 `over1g-ceph`。旧 `10g-*` 名称仍作为别名接受。 |
| `--storage TYPE`、`--storage-path PATH`    | qBittorrent 与系统调优共享的存储检测覆盖值。类型：`auto`、`hdd`、`hdd-raid0`、`ssd`、`nvme`、`ceph`（也接受 `sata-ssd`）。路径只用于识别调优存储，不会迁移下载目录。                                |
| `--interface IFACE`、`--link-speed-mbps N` | 共享网卡/带宽覆盖值，也接受 `--netdev` 和 `--link-speed 2.5g`。提供商限速时请手动指定带宽。                                                                                                         |
| `--web-port PORT`                          | WebUI 端口。默认值：`8080`。别名：`--qb-web-port`、`--qb-port`。                                                                                                                                    |
| `--incoming-port PORT`                     | 入站 BitTorrent 端口。默认值：`45000`。别名：`--qb-incoming-port`。                                                                                                                                 |
| `--source distro`                          | 安装/使用操作系统提供的 `qbittorrent-nox` 软件包。仅限 root/管理员模式。                                                                                                                            |
| `--source static`                          | 使用内置或下载的静态 `qbittorrent-nox` 构建。                                                                                                                                                       |
| `--source existing`                        | 使用 `PATH`、`~/bin` 或 `~/.local/bin` 中已有的 `qbittorrent-nox`。                                                                                                                                 |
| `--qb-version VERSION`                     | 静态来源使用的 qBittorrent 版本。                                                                                                                                                                   |
| `--libtorrent-version VERSION`             | 静态来源使用的 libtorrent 版本。                                                                                                                                                                    |
| `--service-mode MODE`                      | `system`、`user`、`screen`、`daemon`、`auto` 或 `prompt`。                                                                                                                                          |
| `--webui-username NAME`                    | 单独设置 WebUI 用户名，不必与 Unix 用户名一致。                                                                                                                                                     |
| `--allow-unverified-downloads`             | 允许下载未经 SHA-256 校验的文件。除非你已经审查过构建产物来源，否则不建议在生产环境中使用。                                                                                                         |

列出可用的 qBittorrent 来源和静态 manifest 条目：

```bash
seedboxctl --lang zh-CN list qbittorrent
```

静态 qBittorrent 版本会从 `manifests/qbittorrent.tsv` 这份清单中选择。如果缺少 `--qb-version` 或 `--libtorrent-version`，或者提供的版本组合没有出现在当前架构对应的列表中，交互式安装会打印清单中的可选项并要求你选择其中一个。非交互式安装（例如 CI、cron 或无 TTY 会话）会打印有效选项后退出，方便你使用有效的清单版本组合重新运行。`--source distro` 和 `--source existing` 不使用这份清单，也不会显示版本选择菜单。

选择清单中的版本组合后，静态二进制文件会按以下顺序查找：

1. `Torrent Clients/qBittorrent/ARCH/` 下匹配的内置二进制文件。
2. `manifests/qbittorrent.tsv` 中的 URL。

两种来源都必须匹配清单中的确切版本组合及 SHA-256。没有推导 URL 或未验证的静态 qBittorrent 回退；`--allow-unverified-downloads` 不能绕过此要求。

#### qBittorrent 配置调优配置档

`--qb-tuning-profile auto` 是默认值。qBittorrent 与系统调优使用**相同且已确认的存储路径/类型、网卡和带宽**。每次安装/应用命令只选择一次，两组件复用结果。默认值优先级为**显式参数 → 已保存选择 → 自动检测**。有交互终端时始终提示确认，回车接受或输入覆盖值；无终端时自动使用这些默认值，不会读取管道中的密码作为确认输入。升级会恢复实例已保存的硬件选择，包括提供商带宽限制；已保存网卡不存在时，会警告并重新检测路由网卡。可用 `--storage auto`、`--interface auto`、`--link-speed auto` 分别重新检测。已保存的调优路径会保留，直到显式修改，不会自动跟随之后在 WebUI 中修改的下载目录。

**不高于 1000 Mbps** 使用 `1g-*`；**高于 1000 Mbps** 使用 `over1g-*`，包括 2.5G、5G、10G 及更高速链路。旧 `10g-*` 参数/已保存配置档仍作为别名兼容。显式 qBittorrent 配置档只覆盖其自动选档，不会改变共享系统调优设置；`legacy` 保留旧版 qBittorrent 启发式规则。

检测优先使用 IPv4/IPv6 路由选择的活动网卡，而非无关网卡中的最高速率。读取接口速率，必要时尝试 ethtool 和底层接口；未知速率会警告并回退至 1000 Mbps。物理端口速率无法反映提供商限速。存储检测按指定路径遍历分区/device-mapper/MD，LVM 使用内核设备名，ZFS 数据类型判断排除日志/缓存/备用/special 设备。远程/FUSE 存储使用 Ceph 兼容配置并警告，不代表其后端一定是 Ceph；未知存储警告并默认 HDD。复杂存储池、硬件 RAID、多下载挂载点仍需确认或显式覆盖。

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

对于 qBittorrent 4.5.5+，磁盘队列大小为系统总内存的四分之一，以 MiB 为单位向上取整到 2 的幂；**HDD/HDD RAID0 上限为 512 MiB**，**SSD/NVMe/Ceph 上限为 1024 MiB**。此上限按每个实例计算，依据总内存而非当前可用内存。`legacy` 不显式设置这些磁盘队列或请求上限。

额外设置只会在对应版本条件满足时写入：

| 适用条件                                             | 写入的设置                                                                                                                         |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| libtorrent 2.x                                       | `Session\HashingThreadsCount`；NVMe/Ceph 配置档使用 `Session\DiskIOType`。                                                         |
| qBittorrent 4.4.5+                                   | `Session\ConnectionSpeed=500`                                                                                                      |
| qBittorrent 4.5.5+                                   | `Session\DiskQueueSize` 和 `Session\RequestQueueSize`                                                                              |
| qBittorrent 5.0.1+ 且使用 libtorrent 2.x Ceph 配置档 | `Session\DiskIOType=SimplePreadPwrite`；较旧的 libtorrent-2 qBittorrent 版本会使用 `Posix`，因为当时还不存在 `SimplePreadPwrite`。 |

状态与日志：

```bash
sudo seedboxctl --lang zh-CN qbittorrent status --user jerry048
sudo seedboxctl --lang zh-CN qbittorrent status \
  --user jerry048 \
  --json
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

重复应用调优会保留 `/etc/default/seedbox-tuning` 中的硬件选择、窗口/队列值、调度范围及跳过选项，显式参数优先。`--no-sysctl` 和 `--no-limits` 也会保留到之后的应用，但不会删除此前生成的配置文件或撤销已有运行时设置。要重新启用此前跳过的设置，请先在 `/etc/default/seedbox-tuning` 中将相应 `SEEDBOX_ENABLE_*` 值改为 `1`，再重新应用。

网络处理与 qBittorrent 使用相同的 `1g` / `over1g` 分界：

| 设置                           | 不高于 1G | 高于 1G（包括 10G 及以上） |
| ------------------------------ | --------: | -------------------------: |
| `net.core.netdev_budget`       |      2000 |                       5000 |
| `net.core.netdev_budget_usecs` |      2000 |                       4000 |
| `net.core.netdev_max_backlog`  |     16384 |                      32768 |

`net.ipv4.tcp_mem` 分别使用系统总内存的 10% / 25% / 50%，按当前运行内核的页大小换算为页数，仅向上取整到完整页数，不按 2 的幂取整。这些是限制/压力阈值，并非预留内存。例如，16 GiB 内存、4 KiB 页大小对应 `419431 1048576 2097152`（约 1.6 / 4 / 8 GiB）。`net.ipv4.tcp_limit_output_bytes` 为 3276800 字节。

主机调优使用扩展后的 `net.ipv4.ip_local_port_range=1024 65535`。落在该范围内的受管 qBittorrent WebUI/入站端口与 Deluge WebUI/RPC/入站端口会合并到 `net.ipv4.ip_local_reserved_ports`，避免先被出站连接占用。已有保留项会保留；删除实例时只移除安装器自己添加的端口。主机调优启用时，两个客户端的安装、升级和卸载都会刷新保留项。普通用户无法修改主机 sysctl；普通用户端口变更后，需由管理员重新运行 `seedboxctl tuning apply`（会读取可访问的普通用户状态记录）来保留新端口。

脏页策略使用 `vm.dirty_background_ratio`：HDD 为 `5`，SSD/NVMe 为 `10`；所有存储类型的 `vm.dirty_ratio` 均为 `30`。内核脏页比例基于可用于脏页的内存，而非安装的总内存。回写/过期间隔取决于存储类型。

不高于 1G 的链路使用 RX 1024 / TX 2048 的网卡环形队列目标值，并受驱动上限约束。默认路由的 `initcwnd` 和 `initrwnd` 均默认为 25 个包；可用 `--initial-cwnd N` 同时覆盖两者。

CPU 调优在支持且可写的接口上设置 `performance` governor、`performance` 能效偏好、能效偏置 `0`（性能优先），以及 Intel P-state 的 `min_perf_pct=100`。缺失/不支持的接口（虚拟机中很常见）会非致命地跳过。这可能增加功耗和发热；无法改变宿主机调度，也不会对没有百分比控制接口的驱动强行锁定频率。可用 `seedboxctl tuning apply --no-cpu-tuning` 跳过 CPU 策略更改。启动服务会重新应用策略，已有电源管理服务可能与之冲突。

面向抢上传的磁盘预读起始值在**所有网卡速率**下保持一致：

| 存储                 |    预读 |
| -------------------- | ------: |
| HDD                  | 256 KiB |
| HDD RAID0            | 512 KiB |
| SATA SSD / 本地 NVMe | 128 KiB |
| 远程/FUSE / ZFS      |    不变 |

此设置会尽力应用，并在启动时重新应用到下载/调优路径直接使用的逻辑块设备（包括 MD/LVM），而非每个底层物理盘。分区使用父磁盘的控制接口，也会影响同盘其他分区。`--disk-scheduler-all` 不会扩大预读设置范围。可用 `seedboxctl tuning apply --no-read-ahead` 跳过。这些是面向抢上传的起始值，并非基准测试证明的最优值。已打补丁的 libtorrent 1.2.20 本身会执行最多 2 MiB、受分片边界限制的缓存预取，并通常对上传读取抑制 Linux 文件预读；此内核设置不能替代 libtorrent 缓存或发送缓冲区。

常用调优选项：

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
sudo seedboxctl --lang zh-CN bbr install \
  --bbr-algo bbrx \
  --bbr-script-sha256 SHA256
```

支持的算法：

```text
bbrv3
bbrx
bbrx_old
bbrw
bbr_brutal
bbrw_brutal
```

`bbrx_old` 保留旧版 BBRx 的算法行为，包括无法正常退出 STARTUP 的缺陷、10 位增益截断及原始 pacing 周期，同时加入现代内核兼容层。拥塞控制名称为 `bbrx_old`，模块为 `tcp_bbrx_old`，独立 DKMS 包为 `bbrx_old/0.1.0`，可与未修改的 `bbrx` 共存。旧参数 `-x` 仍选择 `bbrx`。

```bash
sudo seedboxctl --lang zh-CN bbr install \
  --bbr-algo bbrx_old \
  --bbr-raw-base 'file:///path/to/reviewed/Trove/BBR-Install/BBR'
sudo seedboxctl --lang zh-CN bbr uninstall --bbr-algo bbrx_old
```

`bbrx_old` 尚未发布时自动选用已验证的捆绑安装器，必须显式指定含此变体的本地/已发布 raw-base。如果同时覆盖安装器，它也必须支持 `bbrx_old`。远程来源应固定到已审查的提交。

固定并校验外部 BBR 安装脚本：

```bash
sudo seedboxctl --lang zh-CN bbr install \
  --bbr-algo bbrx \
  --bbr-script-url 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBRInstall.sh' \
  --bbr-raw-base 'https://raw.githubusercontent.com/jerry048/Trove/COMMIT/BBR-Install/BBR' \
  --bbr-script-sha256 SHA256
```

检查或移除由 BBR 管理的状态：

```bash
sudo seedboxctl --lang zh-CN bbr status
sudo seedboxctl --lang zh-CN bbr uninstall --bbr-algo bbrx
```

`bbrv3` 使用内核软件包路径，可能需要重启。对于基于 DKMS 的变体，如果本地缺少当前运行内核对应的头文件，并且无法通过 `apt install linux-headers-$(uname -r)` 安装，Seedbox 会自动安装发行版通用内核镜像和头文件，记录一个待处理的 BBR 状态，并要求你先重启进入通用内核，然后再重新运行 BBR 安装。DKMS/内核变更风险较高；请先在一次性 VPS 上测试。

运行环境检查及安装器验证在头文件/内核软件包修改前完成。容器/WSL 默认拒绝，只有明确 `--force-runtime` 才可覆盖。哈希占位符需替换为已审查脚本的 SHA-256；`--allow-unverified-bbr-installer` 是单独的显式授权，`--yes` 不代表同意。独立脚本工作父目录的路径链需属于 root 且可信；支持 root 所有、带 sticky 位的 `/tmp` 等父目录。

### Docker

安装 Docker：

```bash
sudo seedboxctl --lang zh-CN docker install --docker-source official
```

也可以使用发行版软件包：

```bash
sudo seedboxctl --lang zh-CN docker install --docker-source distro
```

Docker 状态会记录实际成功使用的安装来源。如果官方安装失败后成功回退到发行版软件包，会保存 `source=distro`，而非最初请求的 `official`。

状态与卸载：

```bash
sudo seedboxctl --lang zh-CN docker status
sudo seedboxctl --lang zh-CN docker uninstall
sudo seedboxctl --lang zh-CN docker uninstall \
  --purge \
  --yes
```

Docker 清理会在停止/禁用服务或修改软件包**之前**要求 `--yes`。通过 `/var/run/docker.sock` 查询本机系统守护进程的实际 `DockerRootDir`，忽略远程上下文和 `DOCKER_HOST`，不会猜测默认路径。查询失败时请启动守护进程后重试；私有的中断清理记录支持软件包移除后的重试。Python 3 会检查绝对路径、Docker 目录结构、符号链接父目录和挂载点，拒绝宽泛/共享/无法识别的路径或含挂载的目录树；请先停止容器并卸载其存储。独立 containerd 的软件包和数据（包括自定义目录）会保留，避免影响其他运行时。停止、软件包或删除失败时会返回错误并保留安装器状态。

### 生命周期安全与兼容性

- 新安装发现已有 qBittorrent 配置时需 `--force`；覆盖前保存私有 `.pre-install.TIME.*` 备份。升级保留现有设置。不会 chown/chmod 已有用户或下载目录；权限不够时请手动修复。拒绝符号链接配置及启动器路径。
- 静态二进制的 qBittorrent/libtorrent 组合及 SHA-256 必须与清单完全匹配，本地与远程来源同样验证；不会替换成其他 libtorrent。使用临时文件并原子替换。清除由实例用户执行，只删除 `qBittorrent.conf`；旧版 rootless 清除不会新增 Python 依赖。读取 crontab 失败时不提交替换内容。
- autobrr、autoremove-torrents 使用服务用户写入配置；强制覆盖先备份。定向清除检查目录和文件所有者，保留父目录及无关内容。
- BBR 远程或自定义本地安装器需 `--bbr-script-sha256` 或明确 `--allow-unverified-bbr-installer`。显式哈希不匹配直接失败，不回退。默认未验证下载的传输失败可使用内置哈希验证的捆绑安装器。该哈希只验证脚本，不认证 raw-base 源码和软件包校验表；需要可复现性时将两者固定到审阅过的提交。尚未发布的 `bbrx_old` 需显式本地/已发布 `--bbr-raw-base`，自动使用已验证的捆绑脚本（Ubuntu 22.04+ 或支持的 Debian）。仅接受 `.deb` 文件名，不接受校验表中的路径。DKMS/模块移除失败保留恢复状态。
- Docker 官方源迁移移除冲突软件包（含 containerd/runc）前必须显式 `--allow-docker-package-removal`；`--yes` 不代表此授权。迁移本身不删除数据，但软件包脚本及服务中断仍有风险；清除仍保留独立 containerd 数据和软件包。
- root 运行时目录、命令链接父目录及开机调优 helper 的路径链必须属于 root，且不可由组或其他用户写入。普通用户仍可安装到自身 HOME。特权清除固定已验证对象并拒绝不可信父目录，但不保证抵御其他特权写入者或并发挂载变化。

`Install.sh` 转发 `--force`、`--yes`、`--allow-docker-package-removal`。配置备份、Vertex 失败数据及旧容器保留供手动检查，不自动清理。

### Vertex

通过 Docker 安装 Vertex：

```bash
sudo seedboxctl --lang zh-CN vertex install \
  --vertex-port 3000 \
  --vertex-data-dir /root/vertex
```

所有 Vertex 写入（包括未提供凭据的安装）均需要 Python 3 执行文件系统安全检查。缺少时，在任何 Docker/镜像/数据操作之前询问是否安装；默认拒绝。无交互终端请先安装，或使用 `--yes` 同意；确认不会消费管道密码。

普通升级不自动修复缺失文件。`upgrade --repair-data --yes` 明确请求修复且必须创建数据快照。升级先停止旧容器，将数据复制到私有同级快照，禁用保留旧容器的自动重启，再启动新容器。快照失败恢复原运行状态；健康检查或状态写入失败，先恢复数据再启动旧容器。失败数据改名保留，不删除。快照/改名恢复要求数据树没有挂载点且有足够空间。成功后保留旧容器、状态备份及数据快照。`--no-data-snapshot` 放弃数据回滚；新容器失败后旧容器保持停止且禁用自动重启，需手动恢复。覆盖已管理安装需 `--force`，不会自动删除同名无关容器。健康检查只验证存活，不保证应用或数据库兼容性。

凭据更新只修改用户名和密码，保留私有 `setting.json.pre-credentials.*` 备份，并通过权限为 `0600` 的临时文件原子替换 JSON。现有设置无效、不可读、不是对象或为符号链接时会报错，不会改成空对象。只有成功更新后才删除自动生成的密码文件。普通升级不会重写凭据。

安装或升级时，必须收到本机 HTTP 响应，并再次确认已验证身份的容器仍在运行；仅看到 Docker 发布端口不代表应用已就绪。该检查使用原本必需的 Python 3，忽略代理设置且不跟随重定向，但不验证登录或数据库兼容性。只读的 `status --check` 仍仅检查管理器状态，不发送 HTTP 请求。

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
sudo seedboxctl --lang zh-CN vertex uninstall \
  --purge \
  --yes
```

使用自定义容器名时，请传入安装时使用的同一个 `--vertex-name`。状态只匹配准确名称，并显示该容器的日志，不会选中名称相似的其他容器：

```bash
sudo seedboxctl --lang zh-CN vertex status --vertex-name my-vertex
sudo seedboxctl --lang zh-CN vertex upgrade --vertex-name my-vertex
sudo seedboxctl --lang zh-CN vertex uninstall --vertex-name my-vertex
```

状态保存 Docker 容器完整 ID 及预期 `/vertex` 绑定挂载。生命周期操作拒绝过期 ID 或挂载不符的同名容器。旧状态缺少 `container_id` 时，需手动审查 `docker inspect NAME`，确认数据目录与私有状态一致后，在状态文件添加已核实的完整 ID；不要填写无关替代容器的 ID。初始化只使用唯一命名的自有容器，成功停止并移除后才合并数据；失败保留模板及容器供恢复。

Vertex 递归清理必须具有匹配的 `.seedbox-managed` 所有权标记。有 Python 3 时，会在初始化前标记新建/空的数据目录；不会自动认领已有内容的目录。旧版/未标记目录会保留，并在移除容器前拒绝清理；可先普通卸载，再人工检查和删除数据。拒绝宽泛路径、主目录根、符号链接路径和含挂载的目录树。`--yes` 和验证均在容器操作之前进行，移除容器或删除失败时保留状态以便重试。安全清理需要 Python 3，但不会隐式安装。

### autobrr

为某个用户安装 autobrr：

```bash
sudo seedboxctl --lang zh-CN autobrr install \
  --user jerry048 \
  --autobrr-port 7474
```

重新安装时，显式指定 `--autobrr-port` 只会更新根级 `port` 并重启 autobrr；不使用 `--force` 时保留其他设置。省略此选项则保留当前配置端口。含根级多行字符串的配置需要手动修改端口，以避免不安全的文本替换。`--force` 会有意重新生成完整配置。

状态、卸载：

```bash

sudo seedboxctl --lang zh-CN autobrr status --user jerry048
sudo seedboxctl --lang zh-CN autobrr uninstall --user jerry048
sudo seedboxctl --lang zh-CN autobrr uninstall \
  --user jerry048 \
  --purge \
  --yes
```

对于标准的 GitHub Release 产物，`seedboxctl --lang zh-CN` 会尝试解析并校验匹配的校验和文件。对于自定义 URL，请提供 `--autobrr-sha256`；或者在审查构建产物后，显式传入 `--allow-unverified-downloads`。

autobrr 清理只删除记录的 `config.toml` 及同目录默认的 `autobrr.db`、`autobrr.db-shm`、`autobrr.db-wal`，不会递归删除父目录。其他文件、备份及配置在外部的数据库均会保留，供人工检查。autoremove-torrents 同样只删除记录的 `config.yml`。两者都需要 Python 3 验证路径/文件类型，并在停止任何服务前要求 `--yes`；停止或删除失败时保留启动文件和状态。

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
sudo seedboxctl --lang zh-CN autoremove-torrents install \
  --user jerry048 \
  --enable-autoremove
```

重新安装会保留定时器启用状态。优先采用 systemd 实际状态，尊重手动 `systemctl enable`/`disable` 修改；无法查询单元/管理器时回退到安装器已保存状态。已启用但已停止的定时器不会仅因重新安装而启动；`--enable-autoremove` 才会显式启用并启动。首次安装仍默认禁用。已屏蔽的定时器需要先手动取消屏蔽，不会被静默覆盖。安装器会保存实际生效的启用状态，普通升级仍不改写定时器单元。

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
/opt/seedbox/Dedicated-Seedbox/                  # 默认的最小运行时
/opt/seedbox/qbittorrent/                        # 静态 qBittorrent 二进制文件
/var/log/seedbox/                                # 操作日志
/var/log/seedbox/steps/                          # 每一步命令的日志
/var/log/seedbox/latest.log                      # 最新日志的符号链接
/var/lib/seedbox/state/                          # 组件状态文件
/home/USER/.config/qBittorrent/qBittorrent.conf
/home/USER/qbittorrent/Downloads
/etc/systemd/system/seedbox-qbittorrent-USER.service
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

运行时替换只接受空目录，或只含清单所列文件/目录的已知最小运行时；拒绝混合仓库/共享目录、符号链接、宽泛路径、主目录根和挂载路径。允许旧版最小运行时缺少可选清单文件。临时和旧版备份使用唯一名称，不会删除已有的 `.old` 或 `.tmp.PID` 旁目录。旧版运行时保留为 `DESTINATION.previous.RANDOM`，供恢复或手动清理。目标路径不安全时直接中止，不回退到其他运行时。

内置和独立 BBR 安装器均将 `BBR_WORK_DIR` 视为新建私有 `bbr-install.*` 子目录的**父目录**，而非构建或删除目标。`BBR_CLEAN_WORK_DIR=1` 只会在路径、挂载和设备/inode 检查通过后删除本次子目录；`0` 保留它。`auto` 清理自动工作目录，保留显式指定父目录下的子目录。父目录原有内容不会被删除。

总体状态：

```bash
seedboxctl --lang zh-CN status
seedboxctl --lang zh-CN status --json
```

---

<a id="upgrade-and-uninstall"></a>

## 升级与卸载

### qBittorrent

升级基于发行版软件包的安装：

```bash
sudo seedboxctl --lang zh-CN qbittorrent upgrade \
  --user jerry048 \
  --source distro
```

省略 `--service-mode` 会保留已保存的启动方式；显式提供该选项（或 `--install-method`）会切换到该实例支持的方式。root 管理实例支持 `system`、`screen`、`daemon`；无 root 实例支持 `user`、`screen`、`daemon`、`auto`、`prompt`。切换时会禁用旧启动机制，启动或健康检查失败时会尝试回滚。

无 root 升级/卸载需要 `flock`。维护持有与 cron 重启脚本共享的排他锁，停止进程前移除受管 cron 项，并等待旧版正在运行的重启脚本退出。仅成功升级或安全回滚后恢复调度；失败时可能保留暂停状态，需手动恢复。配置恢复失败绝不启动旧实例。发行版升级会在停止并备份配置后更新 APT 索引并安装当前 `qbittorrent-nox` 候选版本。软件包及依赖不能自动回滚；升级失败保留快照和停止状态，需手动恢复软件包及配置。

**配置保留：** 升级会合并当前配置，而非用安装器模板替换。现有 WebUI 设置（包括端口、用户名、下载路径、限制、排队、认证/安全设置及自定义调优）优先于过期的安装器状态；显式命令参数只覆盖相应设置。会按目标版本迁移已知的新旧键名及值格式，包括 5.3 的 WebUI 分节变化，并补充缺失的安装器默认值。除非显式指定调优配置档或硬件选项，否则保留现有调优值。显式 `--cache` 会同时设置磁盘缓存和生成的进程内存限制；省略时保留这两个独立设置，包括磁盘缓存的自动/禁用值。

安装器会在旧进程停止后重新读取配置，以保留退出时写入的修改。配置旁会保留权限为 `0600` 的 `qBittorrent.conf.pre-upgrade.*` 快照，成功升级后也不删除。兼容的密码哈希会保留；跨越 4.1 密码哈希格式边界需要提供密码参数。旧版本无法实现所有新功能：未知键会保留，但目标版本可能忽略；无法安全表达的转换（例如将启用的代理配置降至 4.6 之前、部分 HTTPS 证书格式变化或不支持的枚举值）会报错，而非静默削弱设置。降级时请保留快照。无 root 配置迁移需要 Python 3，包括 4.1 目标版本。

daemon/screen 生命周期操作会在发送正常退出信号后，等待对应用户的旧进程完全退出，再改写配置、启动替代实例或清理配置。默认等待 30 秒；较慢存储可通过 `SEEDBOX_QB_STOP_TIMEOUT` 设置正整数秒数。超时会中止，不会强制杀死进程。回滚时若无法停止替代实例，也不会覆盖配置或重启旧实例。systemd 实例使用同步的 `systemctl stop`。

缺少的 `.local`、`.local/share`、`.local/share/qBittorrent` 和 `.cache` 目录由目标用户以私有权限创建。已有目录只检查访问权限，不 chown/chmod；不兼容的已有权限需手动修复。拒绝符号链接运行时目录。

升级静态安装：

```bash
sudo seedboxctl --lang zh-CN qbittorrent upgrade \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  < /path/to/password.txt
```

非破坏性卸载：

```bash
sudo seedboxctl --lang zh-CN qbittorrent uninstall --user jerry048
```

这会停止并移除启动文件，但会保留 qBittorrent 配置和下载内容。

清除 qBittorrent 配置，保留下载内容：

```bash
sudo seedboxctl --lang zh-CN qbittorrent uninstall \
  --user jerry048 \
  --purge \
  --yes
```

`--purge` 只删除实例状态中记录的 `qBittorrent.conf`，不使用写死的主目录路径。不会删除默认或自定义下载目录、配置父目录或配置旁的其他文件。恢复快照/备份以及种子/会话元数据会保留；不再需要时请手动删除。不安全的路径、符号链接及非普通文件会被拒绝。验证与确认均在停止/卸载前进行；配置删除失败时保留启动文件和实例状态，便于重试。

无 root 卸载：

```bash
seedboxctl --lang zh-CN qbittorrent uninstall
seedboxctl --lang zh-CN qbittorrent uninstall \
  --purge \
  --yes
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

只有在你明确想移除组件数据/配置时，才使用 `--purge --yes`。qBittorrent 只清除配置，始终保留下载内容；其他组件的清除行为不同。

---

<a id="troubleshooting"></a>

## 故障排查

### 安装界面的语言与进度

在 `seedboxctl` 后紧接 `--lang zh-CN`，或为 `Install.sh` 指定该选项，即可使用简体中文。安装器自己的提示、帮助、步骤状态、状态解释、日志查看器说明及恢复建议按完整含义翻译，不逐词替换。命令名、选项值、账号、路径、版本、状态记录键名、JSON 字段及值、安装日志中的结构标记保持原样。应用、软件包管理器及调试日志正文不改写、不翻译，便于保留证据和检索原始错误。随附的 BBR 安装器也支持 `--lang zh-CN`，原有英文及繁体中文模式仍可使用。

步骤的开始和结果各占一行，不使用按字节数补空格的列对齐方式，避免中文和窄终端错位。每个已尝试步骤都会显示耗时。有交互终端时，长步骤每五秒提示一次“仍在执行”；这只表示任务仍在运行，**不是完成百分比，也不承诺剩余时间**。重定向输出时不打印此类活动提示。设置 `SEEDBOX_PROGRESS=never` 可关闭活动提示；缺少 `setsid` 时也只跳过该显示功能，不影响安装。真正的步骤仍在主 shell 中执行，配置变量不会因显示进度而丢失。进度子进程不保留维护锁或密码输入描述符，步骤结束时会清理。

颜色会根据实际输出流自动启用，并遵循 `NO_COLOR`；不支持颜色时，文字标签仍能区分提示、完成、注意和错误。`SEEDBOX_COLOR=never` 关闭安装器颜色；终端具备颜色能力时，`always` 可显式强制启用。日志文件不额外写入颜色控制码，日志查看器也不会给 `[INFO]`、`[ERROR]` 结构标记补色。

已初始化安装日志的修改类命令，结束时统一显示本次操作结果，包括已尝试步骤的成功/失败数量、过程警告、待办事项及保留的日志路径。使用回退方案处理过的失败仍计入统计；不会虚构未执行步骤，也不会将“内核准备完成、等待重启”说成 BBR 模块已生效。结果摘要不会自动重启失败实例、修复权限，也不会改变原退出码。只读的状态、日志和帮助命令不创建日志，也不附加操作摘要。

### 遇到错误后先做什么

错误提示会分别给出可能原因、下一步安全操作，以及应查看的具体步骤/服务日志。普通用户 qBittorrent 实例遇到权限问题时，**继续使用实例所属账号**，先找出被拒绝访问的具体路径；自己无权修复时联系服务商或管理员，而不是直接改用 sudo 重跑整套安装。若当前已经是 root，应核对只读挂载、文件归属及相关服务的隔离策略，不要盲目使用 `chmod 777`、递归 `chown`，也不要整体关闭沙箱。

配置恢复失败时，先保持实例停止并保留快照。下一步是确认实际可执行文件/软件包版本，核对对应的保存配置；恢复兼容的程序与配置组合后，再按原启动方式启动。发行版软件包及依赖不能自动回滚。Vertex 恢复也应先核对新旧容器身份和数据快照状态，再决定是否启动或删除内容。“需要人工恢复”不代表可以直接覆盖重装或删除保留副本。

先从这里开始：

```bash
seedboxctl --lang zh-CN status
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

安装步骤失败时会检查日志中的常见错误模式，包括 APT 锁、DNS/网络故障、缺少命令、权限错误、端口被占用、校验和不匹配及 qBittorrent 密码哈希格式变化。这只是尽力提供的提示，不是完整健康检查。请查看报错中列出的步骤日志及受影响服务的日志；求助时提供失败命令和相关日志片段，并先脱敏。
