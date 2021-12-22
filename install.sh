#!/bin/sh

checkUefi() {
    ls /sys/firmware/efi/efivars > /dev/null 2>&1
    if [ $? -ge 1 ]; then
        echo "This scripts supports only UEFI boot mode."
        exit 1
    fi
}

updateSystemClock() {
    timedatectl set-ntp true
}

showDisks() {
    items=$(lsblk -d -p -n -l -o NAME,SIZE -e 7,11)
    options=()

    IFS_ORIG=$IFS
    IFS=$'\n'
    for item in ${items}; do  
        options+=("${item}" "")
    done
	IFS=$IFS_ORIG
    
    result=$(whiptail --title "Select a disk" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    disk=$result
}

partDisks() {
    showDisks

    result=$(whiptail --yesno "Do you want me to automatically partition and format the disk for you?" 0 0)
    if [ $result -eq 1 ]; then
        gdisk $disk
        return
    fi

    autoPart
    bootPart=${disk}1
    swapPart=${disk}2
    rootPart=${disk}3

    formatPart
    mountPart
}

autoPart() {
    # Create new GPT disklabel
    parted $disk mklabel gpt

	sgdisk $disk -n=1:0:+300M -t=1:ef00
	sgdisk $disk -n=2:0:+1024M -t=2:8200
	sgdisk $disk -n=3:0:0
}

formatPart() {
    mkfs.fat -F 32 "$bootPart"
    mkswap "$swapPart"
    mkfs.ext4 "$rootPart"
}

mountPart() {
    mount "$rootPart" /mnt
    mkdir -p /mnt/boot/efi
    mount "$bootPart" /mnt/boot/efi
    swapon "$swapPart" 
}

runScript() {
    whiptail --title "CocoASAIS" --msgbox "Welcome to CocoASAIS!" 0 0
    checkUefi
    updateSystemClock
    partDisks
}