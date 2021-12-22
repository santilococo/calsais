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

installPackages() {
    pacstrap /mnt base linux linux-firmware git neovim intel-ucode
}

generateFstab() {
    genfstab -U /mnt >> /mnt/etc/fstab
}

setTimeZone() {
    ln -sf /usr/share/zoneinfo/America/Buenos_Aires /etc/localtime
    hwclock --systohc
}

setLocale() {
    sed 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -i /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
}

networkConf() {
    echo "archLinux" > /etc/hostname
    echo "\n127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\tarchLinux.localdomain archLinux" >> /etc/hosts
}

setPassword() {
    echo root:password | chpasswd
}

installMorePackages() {
    pacman -S grub efibootmgr networkmanager network-manager-applet dialog reflector base-devel linux-headers xdg-user-dirs xdg-utils alsa-utils pipewire pipewire-alsa pipewire-pulse openssh reflector qemu qemu-arch-extra ttf-fira-code
    pacman -S --noconfirm nvidia nvidia-utils nvidia-settings

    systemctl enable NetworkManager
    systemctl enable fstrim.timer
}

grubSetUp() {
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
}

userSetUp() {
    useradd -m slococo
    echo slococo:password | chpasswd

    # echo "slococo ALL=(ALL) ALL" >> /etc/sudoers.d/slococo
    # Uncomment wheel line:
    EDITOR=nvim visudo

    usermod -aG wheel slococo
}

runScript() {
    whiptail --title "CocoASAIS" --msgbox "Welcome to CocoASAIS!" 0 0
    checkUefi
    updateSystemClock
    partDisks
    installPackages
    generateFstab
    arch-chroot /mnt
    setTimeZone
    setLocale
    networkConf
    setPassword
    installMorePackages
    grubSetUp
    userSetUp
    exit
    umount -R /mnt
    # reboot
}