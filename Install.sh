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
apt-get -qqy update
apt-get -qqy upgrade
apt-get -qqy install tuned > /dev/null
apt-get -qqy install dialog > /dev/null
apt-get -qqy install dkms > /dev/null
apt-get -qqy install screen > /dev/null
apt-get -qqy install linux-headers-$(uname -r) > /dev/null
cd $HOME
clear
tput setaf 1


## Grabing information
tokens=$1
username=$2
password=$3

## Creating User
useradd $username
mkdir -p /home/$username && chown -R $username /home/$username && sudo -u $username chmod +rwx /home/$username

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
sleep 5
curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/.seedbox_installation.sh
source .seedbox_installation.sh
Decision Deluge
Decision qBittorrent
Decision autoremove-torrents
Decision Netdata



## Tweaking
clear
tput setaf 2; echo "Start Doing System Tweak"
sleep 5
curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/.tweaking.sh
source .tweaking.sh
CPU_Tweaking
NIC_Tweaking
Network_Other_Tweaking
fstab_Tweaking
Scheduler_Tweaking
file_open_limit_Tweaking
kernel_Tweaking
BBR_Tweaking

## Configue Boot Script
clear
tput setaf 2; echo "Start Configuing Boot Script"
sleep 5
curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/.boot-script.sh
source .boot-script.sh
boot_script

## Clear
rm Install.sh
rm .seedbox_installation.sh
rm .tweaking.sh
rm .boot-script.sh

echo "Seedbox Installation Complete"
