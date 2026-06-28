libtorrent_Ver=1.1.14
Deluge_majver=1
Deluge_minver=1.3
Deluge_rev=1.3.15
dewebport=8112

function Deluge_download {
    normal_1; echo "Downloading Deluge"; normal_2
    if [[ "${Deluge_minver}" = "1.3" ]]; then
        while true; do
            result=$(wget -4 http://download.deluge-torrent.org/source/$Deluge_minver/deluge-$Deluge_rev.tar.xz 2>&1)
            if [[ ! $result =~ 404 ]]; then
                break
            fi
            sleep 2
        done
    fi
    tput sgr0; clear
}

function Deluge_install {
    normal_1; echo "Installing Deluge"; normal_2
    distro_codename="$(source /etc/os-release && printf "%s" "${VERSION_CODENAME}")"
    if [[ $distro_codename = buster ]]; then
        ## Installing Libtorrent
        apt-get -qqy install libboost-all-dev libboost-dev python python-twisted python-openssl python-setuptools intltool python-xdg python-chardet geoip-database python-notify python-pygame python-glade2 librsvg2-common xdg-utils python-mako 
        wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Torrent%20Clients/Deluge/libtorrent/buster_libtorrent-rasterbar_$libtorrent_Ver-amd64.deb
        dpkg -r libtorrent-rasterbar
        dpkg -i /root/buster_libtorrent-rasterbar_$libtorrent_Ver-amd64.deb && rm /root/buster_libtorrent-rasterbar_$libtorrent_Ver-amd64.deb
        ldconfig
        if [ ! $? -eq 0 ]; then
            warn_1; echo "Libtorrent install failed"; normal_4
            exit 1
        fi
        ## Installing Deluge
        test -e $HOME/deluge-$Deluge_rev && rm -r $HOME/deluge-$Deluge_rev
        tar xf deluge-$Deluge_rev.tar.xz && rm /root/deluge-$Deluge_rev.tar.xz && cd deluge-$Deluge_rev && wget --no-check-certificate https://pypi.python.org/packages/2.7/s/setuptools/setuptools-0.6c11-py2.7.egg
        python setup.py clean -a
        python setup.py build
        if [ ! $? -eq 0 ]; then
            warn_1; echo "Deluge build failed"; normal_4
            exit 1
        fi
        python setup.py install
        if [ ! $? -eq 0 ]; then
            warn_1; echo "Deluge install failed"; normal_4
            exit 1
        fi
        cd $HOME && rm -r deluge-$Deluge_rev
        ## Creating systemd services 
        cat << EOF > /etc/systemd/system/deluged@.service
[Unit]
Description=Deluge-Daemon
After=network-online.target

[Service]
Type=simple
UMask=002
User=$username
LimitNOFILE=infinity
ExecStart=/usr/local/bin/deluged -d
ExecStop=/usr/bin/killall -w -s 9 /usr/local/bin/deluged
Restart=on-failure
TimeoutStopSec=20
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        cat << EOF > /etc/systemd/system/deluge-web@.service
[Unit]
Description=Deluge-WebUI
After=network-online.target deluged.service
Wants=deluged.service

[Service]
Type=simple
User=$username
ExecStart=/usr/local/bin/deluge-web
ExecStop=/usr/bin/killall -w -s 9 /usr/local/bin/deluge-web
TimeoutStopSec=5
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    elif [[ $distro_codename = bullseye ]]; then
        apt-get -qqy install libboost-dev libboost-system-dev libboost-chrono-dev libboost-random-dev libssl-dev libgeoip-dev python2 python2-dev python-pkg-resources intltool librsvg2-common xdg-utils geoip-database
        curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py && python2 get-pip.py
        pip install Twisted service-identity mako chardet pyopenssl
        wget http://archive.ubuntu.com/ubuntu/pool/universe/p/pyxdg/python-xdg_0.26-1ubuntu1_all.deb
        dpkg -i python-xdg_0.26-1ubuntu1_all.deb
        wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Torrent%20Clients/Deluge/boost/boost-1-69-0_20220512-1_amd64.deb
        dpkg -i boost-1-69-0_20220512-1_amd64.deb
        wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Torrent%20Clients/Deluge/libtorrent/bullseye_libtorrent-rasterbar_$libtorrent_Ver-amd64.deb
        dpkg -r libtorrent-rasterbar
        dpkg -i /root/bullseye_libtorrent-rasterbar_$libtorrent_Ver-amd64.deb && rm /root/bullseye_libtorrent-rasterbar_$libtorrent_Ver-amd64.deb
        ldconfig
        if [ ! $? -eq 0 ]; then
            warn_1; echo "Libtorrent install failed"; normal_4
            exit 1
        fi
        ## Installing Deluge
        test -e $HOME/deluge-$Deluge_rev && rm -r $HOME/deluge-$Deluge_r
        tar xJvf deluge-$Deluge_rev.tar.xz && rm /root/deluge-$Deluge_rev.tar.xz && cd deluge-$Deluge_rev
        python2 setup.py build
        if [ ! $? -eq 0 ]; then
            warn_1; echo "Deluge build failed"; normal_4
            exit 1
        fi
        python2 setup.py install --install-layout=deb
        if [ ! $? -eq 0 ]; then
            warn_1; echo "Deluge install failed"; normal_4
            exit 1
        fi
        cd $HOME && rm -r deluge-$Deluge_rev
        ## Creating systemd services 
        cat << EOF > /etc/systemd/system/deluged@.service
[Unit]
Description=Deluge-Daemon
After=network-online.target

[Service]
Type=simple
UMask=002
User=$username
LimitNOFILE=infinity
ExecStart=/usr/bin/deluged -d
ExecStop=/usr/bin/killall -w -s 9 /usr/bin/deluged
Restart=on-failure
TimeoutStopSec=20
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        cat << EOF > /etc/systemd/system/deluge-web@.service
[Unit]
Description=Deluge-WebUI
After=network-online.target deluged.service
Wants=deluged.service

[Service]
Type=simple
User=$username
ExecStart=/usr/bin/deluge-web
ExecStop=/usr/bin/killall -w -s 9 /usr/bin/deluge-web
TimeoutStopSec=5
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    fi
    mkdir -p /home/$username/deluge/completed /home/$username/deluge/download /home/$username/deluge/torrent && chown -R $username /home/$username/deluge
    mkdir -p /home/$username/.config/deluge/plugins
    systemctl enable deluged@$username && systemctl start deluged@$username
    systemctl enable deluge-web@$username && systemctl start deluge-web@$username
}

function Deluge_config {
    systemctl stop deluged@$username && systemctl stop deluge-web@$username
    ## Setting up auth file
    echo "$username:$password:10" >> /home/$username/.config/deluge/auth

    ## Setting up Daemon config
    cat << EOF >/home/$username/.config/deluge/core.conf
{
  "file": 1, 
  "format": 1
}{
  "info_sent": 0.0, 
  "lsd": false, 
  "send_info": false, 
  "move_completed_path": "/home/$username/deluge/completed", 
  "enc_in_policy": 1, 
  "queue_new_to_top": false, 
  "ignore_limits_on_local_network": true, 
  "rate_limit_ip_overhead": true, 
  "daemon_port": 58846, 
  "natpmp": false, 
  "max_active_limit": -1, 
  "utpex": false, 
  "max_active_downloading": -1, 
  "max_active_seeding": -1, 
  "allow_remote": true, 
  "max_half_open_connections": -1, 
  "download_location": "/home/$username/deluge/download", 
  "compact_allocation": false, 
  "max_upload_speed": -1.0, 
  "cache_expiry": 300,
  "prioritize_first_last_pieces": false, 
  "auto_managed": true, 
  "enc_level": 2, 
  "max_connections_per_second": -1, 
  "dont_count_slow_torrents": true, 
  "random_outgoing_ports": true, 
  "max_upload_slots_per_torrent": -1, 
  "new_release_check": false, 
  "enc_out_policy": 1, 
  "outgoing_ports": [
    0, 
    0
  ], 
  "seed_time_limit": -1,
  "cache_size": $Cache_de, 
  "share_ratio_limit": -1.0, 
  "max_download_speed": -1.0, 
  "geoip_db_location": "/usr/share/GeoIP/GeoIP.dat", 
  "torrentfiles_location": "/home/$username/deluge/torrent", 
  "stop_seed_at_ratio": false, 
  "peer_tos": "0xB8", 
  "listen_interface": "", 
  "upnp": false, 
  "max_download_speed_per_torrent": -1, 
  "max_upload_slots_global": -1, 
  "enabled_plugins": [
    "ltConfig"
  ], 
  "random_port": true, 
  "autoadd_enable": true, 
  "max_connections_global": -1, 
  "enc_prefer_rc4": false, 
  "listen_ports": [
    6881, 
    6891
  ], 
  "dht": false, 
  "stop_seed_ratio": 2.0, 
  "seed_time_ratio_limit": -1.0, 
  "max_upload_speed_per_torrent": -1, 
  "copy_torrent_file": true, 
  "del_copy_torrent_file": false, 
  "move_completed": false, 
  "proxies": {
    "peer": {
      "username": "", 
      "password": "", 
      "type": 0, 
      "hostname": "", 
      "port": 8080
    }, 
    "web_seed": {
      "username": "", 
      "password": "", 
      "type": 0, 
      "hostname": "", 
      "port": 8080
    }, 
    "tracker": {
      "username": "", 
      "password": "", 
      "type": 0, 
      "hostname": "", 
      "port": 8080
    }, 
    "dht": {
      "username": "", 
      "password": "", 
      "type": 0, 
      "hostname": "", 
      "port": 8080
    }
  }, 
  "add_paused": false, 
  "max_connections_per_torrent": -1, 
  "remove_seed_at_ratio": false, 
  "autoadd_location": "/home/$username/deluge/watch/", 
  "plugins_location": "/home/$username/.config/deluge/plugins"
}
EOF

    ## Setting up WebUI config
    DWSALT=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Torrent%20Clients/Deluge/deluge.Userpass.py
    wget https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/Torrent%20Clients/Deluge/deluge.addHost.py
    DWP=$(python2 /root/deluge.Userpass.py $password $DWSALT)
	DUDID=$(python2 /root/deluge.addHost.py)
    cat << EOF >/home/$username/.config/deluge/web.conf
{
  "file": 1,
  "format": 1
}{
  "port": 8112,
  "enabled_plugins": [
    "ltConfig"
  ],
  "pwd_sha1": "$DWP",
  "theme": "gray",
  "show_sidebar": true,
  "sidebar_show_zero": false,
  "pkey": "ssl/daemon.pkey",
  "https": false,
  "sessions": {},
  "base": "/",
  "pwd_salt": "$DWSALT",
  "show_session_speed": true,
  "first_login": false,
  "cert": "ssl/daemon.cert",
  "session_timeout": 3600,
  "default_daemon": "$DUDID",
  "sidebar_multiple_filters": true
}
EOF
    rm /root/deluge.Userpass.py /root/deluge.addHost.py
    
    ## Setting up Hostlist
    cat << EOF > /home/$username/.config/deluge/hostlist.conf.1.2
{
  "file": 1,
  "format": 1
}{
  "hosts": [
    [
      "$DUDID",
      "127.0.0.1",
      58846,
      "$username",
      "$password"
    ]
  ]
}
EOF

    ## Setting up plugins
    cd /home/$username/.config/deluge/plugins
    wget https://github.com/ratanakvlun/deluge-ltconfig/releases/download/v0.3.1/ltConfig-0.3.1-py2.7.egg
    cd $HOME
    chown -R $username /home/$username/.config/deluge
    systemctl start deluged@$username && systemctl start deluge-web@$username
}


## Deluge

#Deluge Libtorrent Config
function Deluge_libtorrent {
    normal_1; echo "Configuring Deluge Libtorrent Settings"; warn_2
    systemctl stop deluged@$username
    cat << EOF >/home/$username/.config/deluge/ltconfig.conf
{
  "file": 1, 
  "format": 1
}{
  "apply_on_start": true, 
  "settings": {
    "default_cache_min_age": 10, 
    "connection_speed": 500, 
    "connections_limit": 500000, 
    "guided_read_cache": true, 
    "max_rejects": 100, 
    "inactivity_timeout": 120, 
    "active_seeds": -1, 
    "max_failcount": 20, 
    "allowed_fast_set_size": 0, 
    "max_allowed_in_request_queue": 10000, 
    "enable_incoming_utp": false, 
    "unchoke_slots_limit": -1, 
    "peer_timeout": 120, 
    "peer_connect_timeout": 30,
    "handshake_timeout": 30,
    "request_timeout": 5, 
    "allow_multiple_connections_per_ip": true, 
    "use_parole_mode": false, 
    "piece_timeout": 5, 
    "tick_interval": 100, 
    "active_limit": -1, 
    "connect_seed_every_n_download": 50, 
    "file_pool_size": 5000, 
    "cache_expiry": 300, 
    "seed_choking_algorithm": 1, 
    "max_out_request_queue": 10000, 
    "send_buffer_watermark": 10485760, 
    "send_buffer_watermark_factor": 200, 
    "active_tracker_limit": -1, 
    "send_buffer_low_watermark": 3145728, 
    "mixed_mode_algorithm": 0, 
    "max_queued_disk_bytes": 10485760, 
    "min_reconnect_time": 2,  
    "aio_threads": 4, 
    "write_cache_line_size": 256, 
    "torrent_connect_boost": 100, 
    "listen_queue_size": 3000, 
    "cache_buffer_chunk_size": 256, 
    "suggest_mode": 1, 
    "request_queue_time": 5, 
    "strict_end_game_mode": false, 
    "use_disk_cache_pool": true, 
    "predictive_piece_announce": 10, 
    "prefer_rc4": false, 
    "whole_pieces_threshold": 5, 
    "read_cache_line_size": 128, 
    "initial_picker_threshold": 10, 
    "enable_outgoing_utp": false, 
    "cache_size": $Cache_de, 
    "low_prio_disk": false
  }
}
EOF
    systemctl start deluged@$username
}