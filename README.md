
# Status update
 
# Seedbox Installation Script
[中文Readme](https://github.com/jerry048/Dedicated-Seedbox/blob/main/README-zh.md)
## Usage
`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) -u <username> -p <password> -c <Cache Size(unit:MiB)> -q -l -b -v -r -3 -x -o`
#### Options
	1. -u: username 
	2. -p: password
	3. -c: Cache size for torrent client
	4. -q: qBittorrent versions
	5. -l: libtorrent versions
	6. -b: Install autobrr
	7. -v: Install vertex
	8. -r: Install autoremove-torrents
	9. -3: Enable BBR V3
	10.-x: Enable BBRx
	11. Customize ports
#### Example
`bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Install.sh) -u jerry048 -p 1LDw39VOgors -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -3`

##### Explanation
	1. username is jerry048
	2. password is 1LDw39VOgors 
	3. Cache size is 3GB
	4. Install qBittorrent 4.3.9 - libtorrent-v1.2.19
	5. Install autobrr
	6. Install vertex
	7. Install autoremove-torrents
	8. Enable BBR V3
## Supported Platform
	1. OS
		1. Debian 10+
		2. Ubuntu 20.04+
	
	2. CPU Architecture
		1. x86_64
		2. ARM64
## Functions
###### 1. Seedbox Environment
	1. qBittorrent
	2. autobrr
	3. vertex
	4. autoremove-torrents
###### 2. System Tunning
	CPU Optimization
	Network Optimization
	Kernel Values
	Drive Optimization
	BBRv3 or BBRx

### Fine Tunning Note
- The Cache size should be set to around 1/4 of the machine total available ram. In case you opt for qBittorrent 4.3.x, you need to take account into memory leakage and set it to 1/8. 

- aio_threads default setting is 4 and should be good for HDD. For SSD or even NVMe server, you might consider increase it to 8 or even 16. 
	- For qBittorrent 4.3.x - 4.6.x you can change it in the advance setting tab. 
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
