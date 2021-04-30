#!/bin/sh

clear

## Check Root Privilege
if [ $(id -u) -ne 0 ]; then 
    tput setaf 1; echo  "This script needs root permission to run" 
    exit 1 
fi

# Read Source
curl -s -O https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/.tweaking.sh && source .tweaking.sh
curl -s -O https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/Miscellaneous/.boot-script.sh && source .boot-script.sh

while true; do
    tput setaf 2; echo "Time to go brr"
    options=("Deluge Tuning" "System Tuning" "BBR Preparation" "BBR Install" "Configure Boot Script")
    select opt in "${options[@]}"
    do
        case $opt in
            "Deluge Tuning")
                read -p "Enter username of your Deluge: " username
                read -p "Cache Size (unit:GiB): " cache
                Cache1=$(expr $cache \* 65536)
                Deluge_libtorrent; break
                ;;
            "System Tuning")
                CPU_Tweaking; NIC_Tweaking; Network_Other_Tweaking; Scheduler_Tweaking; echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control = bbrx" >> /etc/sysctl.conf; kernel_Tweaking; break
                ;;
            "BBR Preparation")
                BBR_Prepare; break
                ;;
            "BBR Install")
                BBR_Tweaking; break
                ;;
            "Configure Boot Script")
                boot_script; break
                ;;
            *) tput setaf 1; echo "Please choose a valid action";;
        esac
    done
done


## Clear
rm .tweaking.sh
rm .boot-script.sh
