# 在 Debian/Ubuntu 上安装 Deluge

[English](README.md) · [主指南](../../README.zh-CN.md) · [完整选项](../../docs/reference.zh-CN.md#deluge)

Deluge 是可选组件，需要 **root 和 systemd**，不支持 rootless。使用独立运行环境，不替换系统 Python，也不依赖 Docker。

| Deluge         | libtorrent           | 最低系统要求             | 安装目录                      |
| -------------- | -------------------- | ------------------------ | ----------------------------- |
| 1.3.15（默认） | 1.1.14               | Debian 11 / Ubuntu 20.04 | `/opt/deluge-1.3.15`          |
| 2.2.0          | 1.2.20               | Debian 12 / Ubuntu 22.04 | `/opt/deluge-2.2.0-lt-1.2.20` |
| 2.2.0          | 2.0.15（2.2.0 默认） | Debian 12 / Ubuntu 22.04 | `/opt/deluge-2.2.0-lt-2.0.15` |

**旧版提示：** Deluge 1.3.15 及其 Python 2.7/OpenSSL 1.1.1 组件已停止维护，仅在确有需要时使用。私有安装和固定下载版本不代表软件安全或仍受维护。

## 安装

可使用[主指南快速开始](../../README.zh-CN.md#quick-start)中的 Deluge 示例；也可在完整仓库副本中执行：

```bash
sudo bash bin/seedboxctl --lang zh-CN deluge add-user \
  --user delugeuser \
  --password 'REPLACE_WITH_A_STRONG_PASSWORD' \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  --jobs 2
```

- 替换用户名和密码。不存在的 Unix 账号会自动创建；已有账号必须为非 root 用户，并持有自己的主目录。
- 命令行密码可能出现在 shell 历史记录和进程列表中。也可使用 `--password-file FILE`，文件须为私有、非空的单行 UTF-8 密码文件（`chmod 600 FILE`）。密码输入方式只能选一种；`--password-stdin` 需要管道或文件重定向。
- 编译需要数 GiB 磁盘空间及较多内存和 CPU 时间；小主机可用 `--jobs 1`。APT 软件源必须可用且通过签名验证；退役的 Debian 11 安全更新镜像可能需要改用 [Debian 存档](https://archive.debian.org/debian-security/)。
- Deluge 2.2.0 搭配 libtorrent 1.2.20 时，将 `--deluge-libtorrent-version` 改为 `1.2.20`，可设置 `--deluge-cache-mib 256`。libtorrent 2.x 不接受该缓存选项。
- 省略两个版本参数会选择 **1.3.15 / 1.1.14**，不是 2.2.0。

## 访问

打开 **`http://SERVER_IP:8112`**，输入 WebUI 密码。

| 服务         | 默认值                          | 选项                     |
| ------------ | ------------------------------- | ------------------------ |
| WebUI        | TCP `8112`，监听 `0.0.0.0`      | `--deluge-web-port`      |
| 守护进程 RPC | TCP `58846`，仅回环 `127.0.0.1` | `--deluge-rpc-port`      |
| BitTorrent   | TCP/UDP `45000`                 | `--deluge-incoming-port` |

安装器不会开放防火墙端口。请限制 WebUI 仅可信客户端可访问；在不可信网络上使用 HTTPS 反向代理或可信 VPN，并保持 TLS 验证开启。RPC 仅供本地使用，采用单独生成的凭据。

<a id="upgrade-and-uninstall"></a>

## 升级与卸载

```bash
sudo seedboxctl --lang zh-CN deluge upgrade --user delugeuser
sudo seedboxctl --lang zh-CN deluge upgrade --user delugeuser --deluge-version 2.2.0 --deluge-libtorrent-version 2.0.15
sudo seedboxctl --lang zh-CN deluge uninstall --user delugeuser
```

- **升级**默认保留当前版本组合，也可显式指定目标。支持 **1.3.15 → 2.2.0**，以及 2.2.0 内的 **1.2.20 ↔ 2.0.15** 切换。保留端口、路径、WebUI 密码及兼容的 ltConfig 设置，无需输入密码。
- 停止服务前会先构建目标运行环境。切换版本时创建完整配置目录的 `.pre-upgrade-*` 快照，包括种子/会话数据和插件；全部已保存种子加载后才算成功。失败时尽可能恢复配置、服务文件和状态，并保持服务停止供检查。不会删除下载文件和旧运行环境。
- **卸载**移除服务，保留配置、下载、种子/会话数据及共用运行环境。
- 仅在确实需要删除活动设置时加 **`--purge --yes`**：删除 `core.conf`、`web.conf`、`hostlist.conf.1.2` 或 `hostlist.conf`、`auth` 和 `ltconfig.conf`。下载、种子/会话元数据、插件和恢复快照仍会保留。

不支持自动降级至 **1.3.15**。切换版本前须禁用第三方插件。旧版的文件夹自动监视功能需通过 Deluge 2 的 AutoAdd 插件重新配置。升级前请备份重要数据。

## 路径和运行环境复用

| 用途                  | 位置                                                                           |
| --------------------- | ------------------------------------------------------------------------------ |
| 配置/会话             | `~delugeuser/.config/deluge`                                                   |
| 下载                  | `~delugeuser/deluge/download`                                                  |
| 完成/种子/监视目录    | `~delugeuser/deluge/{completed,torrent,watch}`                                 |
| 实例记录              | `/var/lib/seedbox/state/deluge.delugeuser.env`                                 |
| 守护进程 / WebUI 服务 | `seedbox-deluged-delugeuser.service` / `seedbox-deluge-web-delugeuser.service` |
| 安装器日志            | `/var/log/seedbox`                                                             |

匹配且构建完成的运行环境会在检查后复用。也可在创建实例前先构建：

```bash
sudo seedboxctl --lang zh-CN deluge build-runtime \
  --deluge-version 2.2.0 \
  --deluge-libtorrent-version 2.0.15 \
  --jobs 2
```

不要跨发行版复制编译产物。失败或不兼容的运行环境会保留，不会覆盖；请先排查原因、停止相关服务并备份运行环境及配置，再将旧目录移到其他位置后重建。更换运行环境会影响共用该目录的所有实例，之后需用 `upgrade` 更新各实例。

使用 `--source-dir DIR` 可提供所选运行环境清单中列出的精确本地源码文件；APT 依赖仍须可用。缺少文件或哈希不匹配会中止。构建源码清单及调优补丁位于 [`lib/components/deluge/`](../../lib/components/deluge/)。

## 排查问题

```bash
sudo seedboxctl --lang zh-CN deluge status --user delugeuser --check
sudo seedboxctl --lang zh-CN deluge logs --user delugeuser --source service --lines 100
sudo seedboxctl --lang zh-CN deluge logs --source installer
```

状态检查涵盖两个服务，不代表认证或传输测试通过。服务日志汇总两个 journal；加 `--follow` 可实时查看，使用 `--source installer --list` 可查找安装记录。JSON、退出码及日志选项见[监控参考](../../docs/reference.zh-CN.md#status)。分享日志前请检查敏感信息。
