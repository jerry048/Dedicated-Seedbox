# Seedbox Installation Script
### !!! 這些腳本僅可在新安裝的Debian 10上運行 
本腳本不保證能提高盒子性能，並且可能會導致您的服務器直接卡死。編寫此腳本的菜雞對編程一竅不通，並且可能在腳本里埋下了很多坑。請謹慎使用

魔改的BBR會增加數據包的重傳速率，並浪費您的帶寬。在10Gbps網絡上，浪費大約是您真實上傳量的30％，而在1Gbps上大約浪費10％。如果您使用的是計量網絡，請謹慎使用。（甚至在不限流量的網絡上也請注意，因為這已經接近DDoS了）

我沒有時間管理此腳本，有什麼問題請自行調試
## 用法
### Install.sh
`wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh && chmod +x Install.sh`

`bash Install.sh <用戶名稱> <用戶密碼> <緩存大小(單位:GiB)>`

##### 在重啓后運行BBR脚本

`bash BBR.sh`

### Tuning.sh 假如你已經安裝了盒子環境 (有機會導致bug，請小心使用)

`wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Tune.sh && chmod +x Tune.sh`

`bash Tune.sh`
## 功能
### Install.sh
###### 1. 安裝盒子環境
	BitTorrent 客戶端
		1.優化版qBittorrent
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
	- 在qBittorrent 4.1.x 的話, 你可以在 /home/$username/.config/qBittorrent/qBittorrent.conf 裏的 [BitTorrent] 欄目下加入 Session\AsyncIOThreadsCount=8

- 在/etc/sysctl.conf 設置的 TCP 緩存大小對於一些低端機器來説可能會太大。 請根據情況更改.
	- 在 /etc/sysctl.conf 文檔中也能找到別的優化備注

- 文件系統的話, 本人强烈推薦使用 XFS 
### 嗚謝
qBittorrent 安裝 - https://github.com/userdocs/qbittorrent-nox-static

qBittorrent 密碼設置 - https://github.com/KozakaiAya/libqbpasswd & https://amefs.net/archives/2027.html

autoremove-torrents - https://github.com/jerrymakesjelly/autoremove-torrents

BBR 安裝 - https://github.com/KozakaiAya/TCP_BBR
