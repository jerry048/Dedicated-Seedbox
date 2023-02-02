#!/bin/sh

tput sgr0; clear

## Load text color settings
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Miscellaneous/tput.sh)

## Allow user to decide whether they would like to install a component or not
function Decision {
	while true; do
		need_input; read -p "Do you wish to install $1? (Y/N):" yn; normal_1
		case $yn in
			[Yy]* ) echo "Installing $1"; $1; break;;
			[Nn]* ) echo "Skipping"; break;;
			* ) warn_1; echo "Please answer yes or no."; normal_2;;
		esac
	done
}


## Check Root Privilege since this script requires root privilege
if [ $(id -u) -ne 0 ]; then 
    warn_1; echo  "This script needs root permission to run"; normal_4 
    exit 1 
fi


## Check Linux Distro since only Debian 10/11 is supported
distro_codename="$(source /etc/os-release && printf "%s" "${VERSION_CODENAME}")"
if [[ $distro_codename != buster ]] && [[ $distro_codename != bullseye ]] ; then
	warn_1; echo "Only Debian 10/11 is supported"; normal_4
	exit 1
fi


## Check Virtual Environment since part of the script might not work on virtual machine
systemd-detect-virt > /dev/null
if [ $? -eq 0 ]; then
	warn_1; echo "Virtualization is detected, part of the script might not run"; normal_4
fi


## Grabing the informations to be used for BitTorrent client setup
username=$1
password=$2
cache=$3

## Grabing the informations of the server to be used in determining certain Tweaking parameters

#Converting the cache size to Deluge's unit  (16KiB)
Cache_de=$(expr $cache \* 65536)
#Converting the cache to qBittorrent's unit (MiB)
Cache_qB=$(expr $cache \* 1024)


## Check existence of input argument in a Bash shell script

#Check if user fill in all the required variables
if [ -z "$3" ]
  then
    warn_1; echo "Please fill in all 3 arguments accordingly: <Username> <Password> <Cache Size(unit:GiB)>"; normal_4
    exit 1
fi

#Preventing user from filling in float number as it would make converting the cache size to deluge be difficult
re='^[0-9]+$'
if ! [[ $3 =~ $re ]] ; then
   warn_1; echo "Cache Size has to be an integer"; normal_4
   exit 1
fi


## Creating User to contain the soon to be installed clients
warn_2
pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
useradd -m -p "$pass" "$username"
normal_2


## Install Seedbox Environment
tput sgr0; clear
normal_1; echo "Start Installing Seedbox Environment"; warn_2
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/seedbox_installation.sh)
Update
Decision qBittorrent
Decision Deluge
Decision autoremove-torrents


## Tweaking
tput sgr0; clear
normal_1; echo "Start Doing System Tweak"; warn_2
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/tweaking.sh)
CPU_Tweaking
NIC_Tweaking
Network_Other_Tweaking
Scheduler_Tweaking
file_open_limit_Tweaking
kernel_Tweaking
Decision Tweaked_BBR

## Configue Boot Script
tput sgr0; clear
normal_1; echo "Start Configuing Boot Script"
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Miscellaneous/boot-script.sh)
boot_script
tput sgr0; clear

normal_1; echo "Seedbox Installation Complete"
publicip=$(curl https://ipinfo.io/ip)
[[ ! -z "$qbport" ]] && echo "qBittorrent $version is successfully installed, visit at $publicip:$qbport"
[[ ! -z "$deport" ]] && echo "Deluge $Deluge_Ver is successfully installed, visit at $publicip:$dewebport"
[[ ! -z "$bbrx" ]] && echo "Tweaked BBR is successfully installed, please reboot for it to take effect"
