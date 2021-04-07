#!/bin/sh

clear

## Check Root Privilege
if [ $(id -u) -ne 0 ]; then 
    tput setaf 1; echo  "This script needs root permission to run" 
    exit 1 
fi


## Update Installed Packages & Installing Essential Packages
tput setaf 2; echo "Updating installed packages and install prerequisite"
tput setaf 7
echo "deb http://deb.debian.org/debian buster-backports main" | sudo tee -a /etc/apt/sources.list
apt-get -qqy update && apt-get -qqy upgrade
apt-get -qqy install sudo
apt-get -qqy install sysstat
cd $HOME
clear
tput setaf 1

## Update Kernel
tput setaf 2; echo "Updating Kernel"
tput setaf 7
apt-get -qqy install linux-image-5.9.0-0.bpo.5-amd64
tput setaf 1

## Grabing information
tokens=$1
username=$2
password=$3

## Creating User
pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
useradd -m -p "$pass" "$username"

## Define Decision
function Decision {
	while true; do
		tput setaf 2; read -p "Do you wish to install $1? (Y/N):" yn
		case $yn in
			[Yy]* ) tput setaf 2; echo "Installing $1"; $1; break;;
			[Nn]* ) tput setaf 2; echo "Skipping"; break;;
			* ) tput setaf 1; echo "Please answer yes or no.";;
		esac
	done
}


## Install Seedbox Environment
clear
tput setaf 2; echo "Start Installing Seedbox Environment"
curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/.seedbox_installation.sh
source .seedbox_installation.sh
Decision Deluge
Decision qBittorrent
Decision rTorrent
Decision autoremove-torrents
Decision Netdata



## Tweaking
clear
tput setaf 2; echo "Start Doing System Tweak"
curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/.tweaking.sh
source .tweaking.sh
CPU_Tweaking
NIC_Tweaking
Network_Other_Tweaking
fstab_Tweaking
Scheduler_Tweaking
file_open_limit_Tweaking
kernel_Tweaking


## Configue Boot Script
clear
tput setaf 2; echo "Start Configuing Boot Script"
curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/.boot-script.sh
source .boot-script.sh
boot_script
clear

## Clear
rm Install.sh
rm .seedbox_installation.sh
rm .tweaking.sh
rm .boot-script.sh

echo "Seedbox Installation Complete, Please Reboot and Run BBR Script"
