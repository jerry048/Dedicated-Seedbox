#!/bin/sh

tput sgr0; clear

## Load text color settings
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Miscellaneous/tput.sh)

## Check Root Privilege
if [ $(id -u) -ne 0 ]; then 
    warn_1; echo  "This script needs root permission to run"; normal_4
    exit 1 
fi


while true; do
    source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/tweaking.sh)
    normal_3; options=("Deluge Tuning" "Tweaked BBR Install" "System Tuning" "Configure Boot Script")
    select opt in "${options[@]}"
    do
        case $opt in
            "Deluge Tuning")
                need_input; read -p "Enter username of your Deluge: " username
                read -p "Cache Size (unit:GiB): " cache;
                Cache1=$(expr $cache \* 65536)
                Deluge_libtorrent; break
                ;;
            "Tweaked BBR Install")
                apt-get -qqy install sudo
                Tweaked_BBR; break
                normal_1; echo "Reboot for Tweaked BBR to take effect";
                ;;
            "System Tuning")
                CPU_Tweaking; NIC_Tweaking; Network_Other_Tweaking; Scheduler_Tweaking; kernel_Tweaking; break
                ;;
            "Configure Boot Script")
                source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Miscellaneous/boot-script.sh)
                boot_script; break
                ;;
            *) warn_1; echo "Please choose a valid action";;
        esac
    done
done
