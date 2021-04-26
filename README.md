# Seedbox Installation Script
## This script is only intended to run on Debian 10
### Usage

`wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh && chmod +x Install.sh`

`bash Install.sh <username> <password> <Cache Size(unit:GiB)>`

#### BBR Script

`bash BBR.sh`

### Credit
qBittorrent Install - https://github.com/userdocs/qbittorrent-nox-static

qBittorrent Password Set - https://github.com/KozakaiAya/libqbpasswd & https://amefs.net/archives/2027.html

autoremove-torrents - https://github.com/jerrymakesjelly/autoremove-torrents

BBR Install - https://github.com/KozakaiAya/TCP_BBR
	
### Functions
###### 1. Install Seedbox Environment
	BitTorrent Client
		1.qBittorrent
	Autoremove-torrents
###### 2. Tweaking
	CPU Optimization
		1.Tuned
	Network Optimization
		1.NIC Config
		2.ifconfig
		3.ip route
	sysctl values
		1./proc/sys/kernel/
		2./proc/sys/fs/
		3./proc/sys/vm
		4./proc/sys/net/core
		5./proc/sys/net/ipv4/
	Drive Optimization
		1.I/O Scheduler
		2.File Open Limit
	Optimizied BBR
