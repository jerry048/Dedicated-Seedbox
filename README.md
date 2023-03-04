# Seedbox Installation Script
[中文Readme](https://github.com/jerry048/Dedicated-Seedbox/blob/main/README-zh.md)
### !!! The script will create a new user account to contain the BitTorrent clients using the provided password. Please use a strong password
### !!! The unit of Cache Size has been changed from GiB to MiB. This allow finer tunning and the script to be used in machine with less than 1GB of ram. 1GiB = 1024 MiB.
### !!! These scripts are only intended to run on freshly installed Debian 10/11

The Tweaked BBR would increase packet retransmission rate and waste your bandwidth. On 10Gbps network, the waste is around 30% of your acutal upload ammount and around 10% on a 1Gbps. Please use with caution if you are on a metered network. 

## Usage
### Install.sh
`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) <username> <password> <Cache Size(unit:MiB)>`

### Tune.sh if you have already installed clients (Likely to break something, becareful)

`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Tune.sh)`

## Functions
### Install.sh
###### 1. Install Seedbox Environment
	BitTorrent Client
		1.qBittorrent with tune
		2.Deluge with tune
	Autoremove-torrents with minimal config
###### 2. Tweaking
	CPU Optimization
		1.Tuned
	Network Optimization
		1.NIC Config
		2.ifconfig
		3.ip route
	Kenel Values
		1./proc/sys/kernel/
		2./proc/sys/fs/
		3./proc/sys/vm
		4./proc/sys/net/core
		5./proc/sys/net/ipv4/
	Drive Optimization
		1.I/O Scheduler
		2.File Open Limit
	Tweaked BBR
### Tune.sh
###### Tuning Options:
	1. Deluge Libtorrent tweaking (Only work on Libtorrent 1.1.14 with ltconfig plugins installed)
	2. System Tuning
		CPU Optimization
		Network Optimization
		Kernel parameters
		Drive Optimization
	3. Tweaked BBR Install
	4. Configuring Boot Script for certain tunings
### Fine Tunning Note
- The Cache size should be set to around 1/4 of the machine total available ram. In case you opt for qBittorrent 4.3.x, you need to take account into memory leakage and set it to 1/8. 

- aio_threads default setting is 4 and should be good for HDD. For SSD or even NVMe server, you might consider increase it to 8 or even 16. 
	- For qBittorrent 4.3.x - 4.5.x you can change it in the advance setting tab. 
	- For qBittorrent 4.1.x, you can set it in /home/$username/.config/qBittorrent/qBittorrent.conf by adding `Session\AsyncIOThreadsCount=8` under [BitTorrent] section
		- Please shut down qBittorrent before the editing
	- For Deluge, you can install [ltconfig](https://github.com/ratanakvlun/deluge-ltconfig/releases/tag/v0.3.1) and edit through the plugins
		- aio_threads=8

- send_buffer_low_watermark, send_buffer_watermark & send_buffer_watermark_factor can be set to a lower value if you are running on a machine with poor I/O.
	- For qBittorrent 4.3.x you can change it in the advance setting tab. 
	- For qBittorrent 4.1.x, you can set it in /home/$username/.config/qBittorrent/qBittorrent.conf by adding `Session\SendBufferWatermark=5120`,`Session\SendBufferLowWatermark=1024`and`Session\SendBufferWatermarkFactor=150` under [BitTorrent] section
		- Please shut down qBittorrent before the editing
	- For Deluge, you can install [ltconfig](https://github.com/ratanakvlun/deluge-ltconfig/releases/tag/v0.3.1) and edit through the plugins
		- send_buffer_low_watermark=1048576
		- send_buffer_watermark=5242880
		- send_buffer_watermark_factor=150

- tick_internal default setting is 100 which can be too high for some weaker CPU. Consider changing it to 250 or 500.
	- Sadly there is no way to change this setting in qBittorrent
	- For Deluge, you can install [ltconfig](https://github.com/ratanakvlun/deluge-ltconfig/releases/tag/v0.3.1) and edit through the plugins
		- tick_interval=250

- A little bit more fine tunning notes can also be found in /etc/sysctl.conf

- For file system, I highly recommend using XFS 

### Credit
qBittorrent Install - https://github.com/userdocs/qbittorrent-nox-static

qBittorrent Password Set - https://github.com/KozakaiAya/libqbpasswd & https://amefs.net/archives/2027.html

Deluge Password Set - https://github.com/amefs/quickbox-lite

autoremove-torrents - https://github.com/jerrymakesjelly/autoremove-torrents

BBR Install - https://github.com/KozakaiAya/TCP_BBR
