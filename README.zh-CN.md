# Dedicated-Seedbox V2.1.1

[English](README.md) · [详细参考](docs/reference.zh-CN.md)

通过 `seedboxctl` 安装和管理 Debian/Ubuntu Seedbox。支持 Debian 11+、Ubuntu 20.04+，以及 amd64、ARM64 架构。独享主机需要 root 权限；共享/rootless 账号可在不使用 sudo 的情况下安装 qBittorrent。

1. [快速开始](#quick-start)
2. [升级与卸载](#upgrade-and-uninstall)
3. [故障排查](#troubleshooting)

<a id="quick-start"></a>

## 快速开始

先创建私有密码文件，再替换示例中的 `/path/to/password.txt` 和 `jerry048`。限制密码文件仅所有者可访问（`chmod 600 /path/to/password.txt`）。以 root 执行远程脚本前，请先审查其内容。

### 独享服务器或 VPS

在自己控制的主机/完整虚拟机上以 root 运行。安装 **qBittorrent 5.3.0 + libtorrent 2.1.2** 及系统调优：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --lang zh-CN \
  --user jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  --components qbittorrent,tuning \
  < /path/to/password.txt
```

### 共享/rootless 账号

以实际运行实例的 Unix 用户执行，**不要使用 root 或 sudo**。只安装 qBittorrent：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --lang zh-CN \
  --rootless \
  --webui-username jerry048 \
  --password-stdin \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2 \
  < /path/to/password.txt
```

使用安装器显示的 WebUI 地址，默认端口为 **8080**。请限制 WebUI 仅受信任网络可访问，在公开暴露前审查安全设置。安装后使用 `seedboxctl`；rootless 账号也可直接运行 `~/.local/bin/seedboxctl`。

已有安装请使用下方的**升级**命令，不要用全新安装覆盖现有配置。可选应用、自定义端口、存储选择及其他版本见[详细参考](docs/reference.zh-CN.md#components)。

### 可选 Deluge

Deluge **2.2.0** 支持带调优补丁的 libtorrent **1.2.20** 或 **2.0.15**。需要 Debian 12+/Ubuntu 22.04+、root 和 systemd。下方显式选择 Deluge，不安装 qBittorrent：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) --lang zh-CN \
  --components deluge \
  --user delugeuser \
  --password-stdin \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  < /path/to/password.txt
```

省略版本参数选择旧版 **1.3.15 / 1.1.14**，支持 Debian 11+/Ubuntu 20.04+，需要 root 和 systemd；会提示运行环境已停止维护，但不以此阻止安装。libtorrent 2.x 不接受磁盘缓存参数，详见[版本、安全提示及私有运行环境指南](Torrent%20Clients/Deluge/README.zh-CN.md)。

通过 `http://SERVER_IP:8112` 访问 WebUI，并将端口限制在可信来源；守护进程 RPC 仍仅监听回环地址。默认和 rootless 配置不包含 Deluge。组合安装及[升级、卸载命令](Torrent%20Clients/Deluge/README.zh-CN.md#upgrade-and-uninstall)见详细指南。

<a id="upgrade-and-uninstall"></a>

## 升级与卸载

升级前备份重要配置。普通 qBittorrent 升级会保留现有设置及兼容的凭据，并保存配置快照以便恢复。

### 升级 qBittorrent

静态版本安装：

```bash
sudo seedboxctl --lang zh-CN qbittorrent upgrade \
  --user jerry048 \
  --source static \
  --qb-version 5.3.0 \
  --libtorrent-version v2.1.2
```

发行版软件包安装：

```bash
sudo seedboxctl --lang zh-CN qbittorrent upgrade \
  --user jerry048 \
  --source distro
```

**Rootless 静态安装：** 使用上方静态升级命令，但省略 `sudo` 和 `--user jerry048`，只管理自己的实例。发行版软件包操作需要 root。发行版升级失败后可能需要手动恢复软件包及配置，依赖不能自动回滚。降级或从 qBittorrent 4.1 升级前，尤其需要阅读[qBittorrent 配置与升级说明](docs/reference.zh-CN.md#qbittorrent)。

### 卸载，保留配置和下载内容

```bash
sudo seedboxctl --lang zh-CN qbittorrent uninstall --user jerry048
```

### 删除 qBittorrent 配置，保留下载内容

仅当明确需要删除实例的 `qBittorrent.conf` 时使用：

```bash
sudo seedboxctl --lang zh-CN qbittorrent uninstall \
  --user jerry048 \
  --purge \
  --yes
```

下载内容、种子/会话元数据和恢复快照均会保留。Rootless 用户同样省略 `sudo` 和 `--user jerry048`。

其他组件的清理行为不同，Docker/Vertex 清理可能删除应用数据。在使用 `--purge --yes` 前，请先阅读[组件说明](docs/reference.zh-CN.md#components)。

<a id="troubleshooting"></a>

## 故障排查

先检查状态：

```bash
seedboxctl --lang zh-CN status
```

状态检查只读：报告受管服务、进程、容器、定时器及配置，不启动或修复任何组件。“运行中”不代表 WebUI 或种子传输正常。脚本可使用 `seedboxctl --lang zh-CN status --json --check`，详见[状态含义及退出码](docs/reference.zh-CN.md#status)。

root 管理的 qBittorrent 实例：

```bash
sudo seedboxctl --lang zh-CN qbittorrent logs --user jerry048
```

rootless 实例：

```bash
seedboxctl --lang zh-CN qbittorrent logs
```

Deluge 使用 `sudo seedboxctl --lang zh-CN deluge status --user delugeuser --check` 和 `sudo seedboxctl --lang zh-CN deluge logs --user delugeuser`。状态同时检查 daemon 和 WebUI 服务，服务日志同时读取两者的 journal；加 `--source installer` 可查看编译/安装日志。

- **找不到命令：** rootless 用户可直接运行 `~/.local/bin/seedboxctl`。
- **WebUI 无法访问：** 检查安装器显示的地址、服务状态、防火墙以及端口是否被其他进程占用。
- **安装/下载失败：** 查看失败步骤日志中的 APT 锁、DNS/网络故障、权限或校验和错误，不要仅为了继续安装而绕过完整性检查。
- **最近的安装失败：** `seedboxctl logs installer` 查看最近运行；`seedboxctl logs installer --list` 列出保留记录。组件日志来源及实时跟踪见[日志查看](docs/reference.zh-CN.md#logs)。
- **升级/恢复失败：** 保留错误中列出的备份及快照，不要反复重新安装或覆盖现有配置；按错误提示及[详细说明](docs/reference.zh-CN.md#qbittorrent)恢复。
- **安装界面与权限提示：** 安装器提示已本地化。普通用户实例遇到权限问题时，不应直接改用 sudo 重装。

求助时请提供失败命令及相关安装步骤或服务日志，分享前先检查并脱敏。完整的[日志与状态路径](docs/reference.zh-CN.md#paths-logs-and-state)位于详细参考中。

详细文档：[CLI 与别名](docs/reference.zh-CN.md#cli-overview) · [qBittorrent 选项](docs/reference.zh-CN.md#qbittorrent) · [系统调优](docs/reference.zh-CN.md#主机调优) · [可选组件](docs/reference.zh-CN.md#components)。
