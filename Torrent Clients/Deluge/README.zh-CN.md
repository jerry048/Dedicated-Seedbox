# 在现代 Debian/Ubuntu 上安装 Deluge

[English](README.md)

可选的 `seedboxctl deluge` 组件支持以下原生私有运行环境：

| Deluge         | libtorrent           | 安装目录                      |
| -------------- | -------------------- | ----------------------------- |
| 1.3.15（默认） | 1.1.14               | `/opt/deluge-1.3.15`          |
| 2.2.0          | 1.2.20               | `/opt/deluge-2.2.0-lt-1.2.20` |
| 2.2.0          | 2.0.15（2.2.0 默认） | `/opt/deluge-2.2.0-lt-2.0.15` |

与 qBittorrent 共用生命周期管理、实例状态、进度、安装器日志和监控机制。不替换系统 Python、不安装旧发行版软件包、不注册全局库搜索路径，也不依赖 Docker。默认安装不包含 Deluge；不支持 rootless。

## 旧版本安全提示

Deluge 1.3.15、Python 2.7、OpenSSL 1.1.1 及兼容的 Python 依赖均已停止维护。固定版本可以让安装过程可复现，**不代表这些软件安全或仍受维护**。仅在确实需要 Deluge 1.3.15 的场景使用。BT 引擎仍会处理不可信的网络数据；私有运行环境和 systemd 限制无法消除其中的漏洞。

所有版本的 WebUI 和守护进程 RPC 均**仅监听 127.0.0.1**。请通过 SSH 隧道访问，不要直接公开这些端口，也不要关闭证书验证。出站 HTTPS 使用主机当前的 CA 证书集合；仅 1.3.15 运行环境使用旧版 TLS。

## 安装

要求：root 权限、正常运行 systemd 的主机，以及 Debian 12+ 或 Ubuntu 22.04+。构建目标为 amd64 和 arm64；目前仅对 amd64 进行了执行验证，ARM64 尚未验证。容器生命周期测试使用私有服务管理模拟器，另在 Debian 13 VPS 上验证了真实 systemd 和公共种子下载；未覆盖主机重启后的持久性、GTK 及长期做种。编译需要数 GiB 可用磁盘空间，并消耗较多内存和 CPU 时间；小内存主机请将 `--jobs` 降为 `1`。构建工具来自发行版的签名 APT 软件源，使用当前编译器。旧版源码和 wheel 的 SHA-256 固定在 `sources.lock` 中；现代版本的清单见下文。

可按[主指南快速开始](../../README.zh-CN.md#quick-start)，显式选择 `--components deluge`；或在完整本地副本中使用下方命令。不存在的 Unix 账号会自动创建；已有账号必须为非 root 用户，并持有真实主目录，也支持 `/home` 之外的自定义主目录。

先创建一个由自己持有、权限为 `600` 的私有密码文件，内容为非空、单行 UTF-8 密码。然后在仓库根目录执行：

```bash
sudo bash bin/seedboxctl --lang zh-CN deluge add-user \
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

另一组现代版本可用 `--deluge-libtorrent-version 1.2.20` 选择，支持 `--deluge-cache-mib 256`。libtorrent 2.x 会拒绝该缓存参数，并记录 `cache_mib=n/a`，不会把无效的旧版设置当成生效。旧版组合使用 `--deluge-version 1.3.15 --deluge-libtorrent-version 1.1.14`；省略两个版本参数仍选择此组合。旧版安装、运行环境构建和升级仍会显示安全提示，但无需额外确认参数。

密码不会出现在命令行参数中。WebUI 通过另行生成的随机 RPC 凭据连接守护进程（2.2.0 使用 `localclient`）。配置由实例所属用户创建，采用私有权限和 JSON 转义；密码可以包含 shell 特殊字符和非 ASCII 字符。

`install` 与 `add-user` 等价。安装器会拒绝已有活动设置、占用中的端口、来源不明的运行环境、不属于安装器的服务和服务 drop-in，不会静默覆盖其他安装。只有构建和配置完成后才会启用服务。就绪检查会实际登录 WebUI，并确认连接的守护进程报告所选版本。检查失败时停止并禁用两个服务，保留配置和受管状态以便排查或卸载。不能用 `--force` 绕过这些保护。

旧版的主要组件为 Python 2.7.18、OpenSSL 1.1.1w、Boost 1.69.0、libtorrent 1.1.14、Twisted 20.3.0、pyOpenSSL 21.0.0 和 Deluge 1.3.15。全部 Python 依赖和 ltConfig 0.3.1 均列在 `sources.lock` 中。不安装 GTK 桌面界面，也不使用附带的旧 `.deb` 软件包。

Deluge 2.2.0 编译独立的 **CPython 3.11.17** 和 **Boost 1.83.0**，Python/libtorrent 链接主机的 **OpenSSL 3**，使用 ltConfig **2.0.0**。`sources-2.2.0-common.lock` 与 `sources-2.2.0-{amd64,arm64}.lock` 固定源码及 Python wheel 的 SHA-256。为兼容上游的 `pkg_resources` 依赖，setuptools 固定为 80.9.0。经哈希锁定的 `deluge-2.2.0-crypto.patch` 将已被 pyOpenSSL 移除的 `X509Req` 调用替换为 `cryptography.x509` 证书生成接口，不降级 TLS 依赖。

两种现代 libtorrent 均使用与 qBittorrent 构建逐字节一致的对应补丁，来源为 `Patch/patches/libtorrent/{1.2.20,2.0.15}/patch`，由 `patches-2.2.0.lock` 锁定，应用时禁止模糊匹配。现代预设保留有效设置，不引入 libtorrent 1.1 的过时缓存选项：磁盘队列 **250 MiB**、tracker 管理上限 **1600**、监听队列 **3000**、全局连接上限 **500000**。libtorrent 1.2 的文件池为 **5000**，使用所选缓存；2.0 的文件池为 **100**，哈希线程为 **2**，AIO 线程为 **4**。升级保留已有自定义设置。

现代配置的 `hostlist.conf` 文件版本为 **3**，`web.conf` 为 **2**，其他活动 JSON 设置为 **1**。旧版仍使用 `hostlist.conf.1.2`，文件版本均为 **1**。

旧版组合编译 libtorrent 时会应用**与 qBittorrent 构建相同的 1.1.14 调优补丁**，从 `Patch/patches/libtorrent/1.1.14/patch` 原样复制到 `lib/components/deluge/libtorrent-1.1.14.patch`。`patches.lock` 固定其精确 SHA-256；应用时禁止模糊匹配，失败即中止。补丁和清单均参与运行环境指纹计算，并保留在安装目录中供核对来源；编译后还会检查默认值，区分已打补丁与上游原版库。

新建的旧版配置使用 50 个 ltConfig 设置，其中磁盘队列为 **250 MiB**（`262144000` 字节），tracker 管理上限为 **1600**。补丁中的监听队列为 **3000**、全局连接上限为 **500000**、校验内存回退值为 **128 MiB**、易失缓存回退值为 **128 块**。显式选择的缓存大小会覆盖补丁中的自动缓存回退值。升级不会静默重写已有设置。

### 访问

在自己的电脑上执行以下命令，将 `HOST` 替换为服务器地址：

```bash
ssh -N -L 8112:127.0.0.1:8112 USER@HOST
```

随后在本机打开 `http://127.0.0.1:8112`，输入密码文件中的密码。如 SSH 使用非默认端口，请加上 `ssh -p PORT`。

BT 端口默认为 TCP/UDP `45000`。按需在主机和服务商防火墙中放行选定的 BT 端口；安装器不修改防火墙。主机调优启用时，安装、升级和卸载会将受管 Deluge 的 WebUI、RPC、入站端口与 qBittorrent 端口一起刷新到保留列表，保留外部保留项，并保持 `net.ipv4.ip_local_port_range=1024 65535`。

### 组合安装

```bash
sudo seedboxctl --lang zh-CN install \
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

同时选择两个客户端时，通用 `--web-port`、`--incoming-port`、`--cache-mib`、`--libtorrent-version` 属于 qBittorrent；Deluge 请用 `--deluge-*` 参数，避免歧义。只选 Deluge 时，通用参数为别名；`--rpc-port` 是 `--deluge-rpc-port` 的别名。`--cache`/`-c` 仍为 qBittorrent 选项。组合安装共用 stdin 密码，不重复读取管道。每个实例都要选择不同端口；若组合安装仍使用两个客户端相同的默认入站端口，会在安装任一客户端前拒绝执行。

### 路径和服务

| 用途                         | 位置                                                                    |
| ---------------------------- | ----------------------------------------------------------------------- |
| 私有运行环境                 | 见上表中的版本专用目录                                                  |
| 已校验的下载缓存             | `/var/cache/seedbox-deluge-1.3.15` 或 `/var/cache/seedbox-deluge-2.2.0` |
| 用户配置和会话数据           | `~delugeuser/.config/deluge`                                            |
| 下载内容                     | `~delugeuser/deluge/download`                                           |
| 完成目录、种子目录、监视目录 | `~delugeuser/deluge/{completed,torrent,watch}`                          |
| root 持有的实例记录          | `/var/lib/seedbox/state/deluge.delugeuser.env`                          |
| 守护进程                     | `seedbox-deluged-delugeuser.service`                                    |
| WebUI                        | `seedbox-deluge-web-delugeuser.service`                                 |
| 安装器日志                   | `/var/log/seedbox`                                                      |

libtorrent 1.x 的 `--cache-mib` 会换算为 16 KiB 块数，并同步应用到核心配置和 ltConfig；libtorrent 2.x 不使用该缓存。服务由指定的非 root 用户运行，停止时由 systemd 正常终止进程，不使用 `killall`。

## 运行环境复用与迁移

可以先编译运行环境，再创建实例：

```bash
sudo seedboxctl --lang zh-CN deluge build-runtime \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  --jobs 2
```

对于完全一致且已构建完成的运行环境，安装器会检查后复用。运行环境标识包含源码清单、构建与检查脚本、主机发行版和架构；不要在不同发行版之间复制编译产物。构建失败时会保留构建目录和未完成的安装目录供检查。确认失败原因并停止相关服务后，请先将未完成的运行环境移到其他位置，再重试；安装器不会递归删除来源不明的运行目录。

旧的**未打补丁**运行环境指纹不同，不会被复用或覆盖。如需采用带补丁的旧版构建，请停止共用该运行环境的全部 Deluge 实例，保留旧运行环境与私有配置备份，将旧安装目录移到其他位置，再执行 `seedboxctl deluge build-runtime`，随后用 `upgrade` 更新各实例。这是需要明确操作的共用运行环境替换，不是自动在线升级；请保留旧版本以便手动恢复。

使用本地源码构建时，将旧版 `sources.lock` 或现代版本的 common 与主机架构两份清单中的全部文件放到同一目录，并指定 `--source-dir DIR`。编译前会复制到 root 私有工作目录中重新校验。缺少文件或校验不符都会中止，不提供绕过完整性校验的选项。APT 仍需能取得所需软件包。运行环境文件在 `lib/components/deluge/`，编排代码在 `lib/components/deluge.bash`，用户侧配置助手在 `lib/core/delugeconfig.py`；远程引导会随主运行环境一起获取这些文件。

已有配置和旧服务模板需要手动迁移。请先停止并备份旧安装，核对所属用户、凭据和下载路径，保留会话及种子数据。本安装器不会在 Deluge 主版本或 libtorrent ABI 之间自动转换，也不导入旧会话。请使用新 Unix 账号或制定手动迁移方案，不要只为绕过保护检查而删除旧配置。

<a id="upgrade-and-uninstall"></a>

## 升级与卸载

```bash
sudo seedboxctl --lang zh-CN deluge upgrade --user delugeuser
```

该操作保留**实例记录中的 Deluge/libtorrent 版本组合**，验证并复用运行环境、更新服务。旧版实例仍会显示安全提示，但无需额外确认参数。显式切换主版本或 ABI 会在停止服务前被拒绝。停止服务后，先将五个活动设置文件保存到私有 `.pre-upgrade-*` 快照，再重新读取并保留当前端口、下载路径、缓存、密码及 ltConfig 设置。无需重新输入密码；就绪检查验证本地 RPC 和 WebUI 可达性。停止后升级失败时，会尽可能恢复设置，并保持服务停止供检查；请保留快照并查看日志，再决定是否重启。跨发行版/ABI 更换运行环境需要手动处理，会影响共用该目录的所有实例。

卸载服务，同时保留运行环境、配置、种子/会话数据及下载内容：

```bash
sudo seedboxctl --lang zh-CN deluge uninstall --user delugeuser
```

确实需要删除活动配置时，加 `--purge --yes`。只删除 `core.conf`、`web.conf`、所选版本的主机列表（`hostlist.conf.1.2` 或 `hostlist.conf`）、`auth` 和 `ltconfig.conf`；下载、种子/会话元数据、插件、恢复快照及共用运行环境均保留。保留活动设置时不能重新安装；不要仅为了绕过迁移检查而删除设置。请使用受管的 `seedboxctl deluge` 命令；附带的 `.deb` 存档不参与安装。

## 验证范围

两组现代版本均在 amd64 `debian:12-slim`、`debian:13-slim`、`ubuntu:22.04` 和 `ubuntu:26.04` 上通过了全新原生构建及生命周期测试，包括全部补丁默认值、已有设置保留、传输与服务重启、恢复及保留数据的清理。容器中的服务管理为模拟环境。

Debian 13 amd64 验证涵盖真实的非 root systemd 服务、仅回环监听的 WebUI/RPC、journal、服务重启、保留版本组合的升级、两种 ABI 同时运行的隔离，以及公共 Debian ISO 下载。下载文件的 SHA-256 和 SHA-512 均与通过已验证 HTTPS 获取的官方校验值一致；未独立验证校验文件的 GPG 签名。ARM64 执行和真实 Ubuntu systemd 尚未验证。

## 排查问题

```bash
sudo seedboxctl --lang zh-CN deluge status \
  --user delugeuser \
  --check
sudo seedboxctl --lang zh-CN deluge status \
  --user delugeuser \
  --json
sudo seedboxctl --lang zh-CN deluge logs \
  --user delugeuser \
  --source service \
  --lines 100
sudo seedboxctl --lang zh-CN deluge logs \
  --user delugeuser \
  --source service \
  --follow
sudo seedboxctl --lang zh-CN deluge logs --source installer
sudo seedboxctl --lang zh-CN deluge logs \
  --list \
  --source installer
/opt/deluge-2.2.0-lt-2.0.15/bin/deluged --version
python3 --version
```

状态检查只读，汇总**两个**服务；“运行中”不代表认证或传输测试通过。JSON 沿用共用的 `instances` 格式；任一服务停止、失败或无法验证时，`--check` 返回失败。service 来源同时读取两份 journal；installer 来源包含 `deluge.*` 步骤，也能匹配组合安装。`--source all` 包含服务和安装器日志；没有应用文件来源。退出码及来源选择见[共用监控参考](../../docs/reference.zh-CN.md#status)。原始日志、路径、版本及 JSON 值不翻译；分享前请检查敏感信息。最后一条命令仍使用主机 Python 3。不要替换系统 Python、混装其他旧发行版的 `.deb`、运行全局 `pip`，或绕过 TLS/哈希校验。
