# Seedbox Installation Script
### Usage
`export tokens=Your Personal access tokens`

`curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Script/main/Install.sh && chmod +x Install.sh && bash Install.sh`
### Functions
###### 1. Install Seedbox Environment
	BitTorrent Client
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
		1.Mounting Options
		2.I/O Scheduler
		3.File Open Limit
	Libtorrent Config
		1.Deluge
		2.qBittorrent - working
	Optimizied BBR
