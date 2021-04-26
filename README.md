# This script is only intended to run on Debian 10

# Seedbox Installation Script
### Usage

`wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh && chmod +x Install.sh`

`bash Install.sh <Personal access tokens>
<username> <password> <Cache Size(unit:GiB)>`

#### BBR Script

`bash BBR.sh <Personal access tokens>`
	
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
