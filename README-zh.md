# Seedbox Installation Script
### !!! 這些腳本僅可在新安裝的Debian 10/11上運行 
### !!! 緩存的單位由GiB更改為MiB。識用于有微調要求或者機器内存較緊張的用戶。 1GiB = 1024MiB
本腳本不保證能提高盒子性能，並且可能會導致您的服務器直接卡死。編寫此腳本的菜雞對編程一竅不通，並且可能在腳本里埋下了很多坑，請謹慎使用

魔改BBR會增加數據包的重傳率，做成帶寬浪費。在10Gbps網絡上，開銷大約是您真實上傳量的30％，而在1Gbps上大約是10％。

我沒有時間管理此腳本，有什麼問題請自己解決啦~
## 用法
### Install.sh
`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) <用戶名稱> <用戶密碼> <緩存大小(單位:MiB)>`

### Tuning.sh 假如你已經安裝了盒子環境 (有機會導致bug，請小心使用)

`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Tune.sh)`
## 功能
### Install.sh
###### 1. 安裝盒子環境
	BitTorrent 客戶端
		1.優化版qBittorrent
		2.優化版Deluge
	Autoremove-torrents
###### 2. 優化
	處理器優化
		1.Tuned
	網絡優化
		1.網卡優化
		2.ifconfig
		3.ip route
	内核參數
		1./proc/sys/kernel/
		2./proc/sys/fs/
		3./proc/sys/vm
		4./proc/sys/net/core
		5./proc/sys/net/ipv4/
	硬盤優化
		1.I/O Scheduler
		2.File Open Limit
	魔改 BBR
### Tuning.sh
###### 優化選擇:
	1. Deluge Libtorrent 優化 (只能用在Libtorrent 1.1.14 并且需要先安裝 ltconfig 插件)
	2. 系統優化
		處理器優化
		網絡優化
		内核數據
		硬盤優化
	3. 魔改 BBR 安裝
	4. 設置開機自動優化的脚本
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
