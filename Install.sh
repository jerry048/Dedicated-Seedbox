#!/bin/sh

clear

## Check Root Privilege
if [ $(id -u) -ne 0 ]; then 
    tput setaf 1; echo  "This script needs root permission to run" 
    exit 1 
fi

## Grabing information
username=$1
password=$2
cache=$3

Cache1=$(expr $cache \* 65536)
Cache2=$(expr $cache \* 1024)

## Check existence of input argument in a Bash shell script

if [ -z "$3" ]
  then
    tput setaf 1; echo "Please fill in all 3 arguments accordingly: <Username> <Password> <Cache Size(unit:GiB)>"
    exit
fi

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
curl -s -O https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/.seedbox_installation.sh && source .seedbox_installation.sh
Update
Decision qBittorrent
Decision autoremove-torrents




## Tweaking
clear
tput setaf 2; echo "Start Doing System Tweak"
curl -s -O https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/.tweaking.sh && source .tweaking.sh
CPU_Tweaking
NIC_Tweaking
Network_Other_Tweaking
Scheduler_Tweaking
file_open_limit_Tweaking
kernel_Tweaking
BBR_Prepare

## Configue Boot Script
clear
tput setaf 2; echo "Start Configuing Boot Script"
curl -s -O https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Miscellaneous/.boot-script.sh && source .boot-script.sh
boot_script
clear

## Clear
rm .seedbox_installation.sh
rm .tweaking.sh
rm .boot-script.sh

echo "Seedbox Installation Complete, Please Reboot and Run BBR Script"
