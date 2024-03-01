
# Seedbox Installation Script
## 用法
`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) -u <用戶名稱> -p <密碼> -c <緩存大小(單位:MiB)> -q -l -b -v -r -3 -x -o`
#### Options
	1. -u: 用戶名稱
	2. -p: 密碼
	3. -c: qBitorrent 的緩存大小
	4. -q: qBittorrent 版本
	5. -l: libtorrent 版本
	6. -b: 安裝autobrr
	7. -v: 安裝vertex
	8. -r: 安裝 autoremove-torrents
	9. -3: 啓動 BBR V3
	10.-x: 啓動 BBRx
	11.-o: 自定義端口
#### 範例
`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) -u jerry048 -p 1LDw39VOgors -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -3`

##### 解釋
	1. 用戶名稱 是 jerry048
	2. 密碼 是 1LDw39VOgors
	3. 緩存大 是 3GB
	4. 安裝 qBittorrent 4.3.9 - libtorrent-v1.2.19
	5. 安裝 autobrr
	6. 安裝 vertex
	7. 安裝 autoremove-torrents
	8. 啓動 BBR V3
## 支持平台
	1. 系統
		1. Debian 10+
		2. Ubuntu 20.04+
	
	2. CPU 架構
		1. x86_64
		2. ARM64

## 功能
###### 1. 盒子環境
	1.qBittorrent
	2.autobrr
	3.vertex
	4.autoremove-torrents
###### 2. 優化
	處理器優化
	網絡優化
	内核參數調配
	硬盤優化
	BBR V3 或 BBRx
### 進階優化備注
- 緩存大小應該設置在機器内存大小的 1/4 左右. 假如你使用的是qBittorrent 4.3.x, 你需要考慮到内存溢出的問題并且設置緩存大小在機器内存大小的 1/8. 

- 異步 I/O 綫程數的基礎設定是 4， 這設定對HDD比較友好. 假如你使用的是SSD甚至是NVMe的話, 你可以調整此參數到 8 甚至到 16. 
	- 在qBittorrent 4.3.x 的話，你可以在高級選項欄目中更改此項設定. 
	- 在qBittorrent 4.1.x 的話, 你可以在 /home/$username/.config/qBittorrent/qBittorrent.conf 裏的 [BitTorrent] 欄目下加入 `Session\AsyncIOThreadsCount=8`
		- 請在修改前關閉qBittorrent
	- 在Deluge 的話，你可以通過[ltconfig](https://github.com/ratanakvlun/deluge-ltconfig/releases/tag/v0.3.1)更改此項設定
		- aio_threads=8

- 在一些 I/O 較差的機器，send_buffer_low_watermark, send_buffer_watermark & send_buffer_watermark_factor 這三項設定應該調低
	- 在qBittorrent 4.3.x 的話，你可以在高級選項欄目中更改此項設定. 
	- 在qBittorrent 4.1.x 的話，你可以在 /home/$username/.config/qBittorrent/qBittorrent.conf 裏的 [BitTorrent] 欄目下加入`Session\SendBufferWatermark=5120`, `Session\SendBufferLowWatermark=1024`和 `ession\SendBufferWatermarkFactor=150`
		- 請在修改前關閉qBittorrent
	- 在Deluge 的話，你可以通過[ltconfig](https://github.com/ratanakvlun/deluge-ltconfig/releases/tag/v0.3.1)更改此項設定
		- send_buffer_low_watermark=1048576
		- send_buffer_watermark=5242880
		- send_buffer_watermark_factor=150

- 在一些 CPU 較差的機器，tick_internal 應該調高來節省CPU指令周期
	- qBittorrent 暫時還沒為修改這設定
	- 在Deluge 的話，你可以通過[ltconfig](https://github.com/ratanakvlun/deluge-ltconfig/releases/tag/v0.3.1)更改此項設定
		- tick_interval=250

- 在/etc/sysctl.conf 設置的 TCP 緩存大小對於一些低端機器來説可能會太大。 請根據情況更改.
	- 在 /etc/sysctl.conf 文檔中也能找到別的優化備注

- 文件系統的話, 本人强烈推薦使用 XFS 
### 嗚謝
qBittorrent 安裝 - https://github.com/userdocs/qbittorrent-nox-static

qBittorrent 密碼設置 - https://github.com/KozakaiAya/libqbpasswd & https://amefs.net/archives/2027.html

Deluge 密碼設置 - https://github.com/amefs/quickbox-lite

autoremove-torrents - https://github.com/jerrymakesjelly/autoremove-torrents

BBR 安裝 - https://github.com/KozakaiAya/TCP_BBR
