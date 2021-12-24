#!/bin/sh

checkUefi() {
    ls /sys/firmware/efi/efivars > /dev/null 2>&1
    if [ $? -ge 1 ]; then
        whiptail --msgbox "This scripts supports only UEFI boot mode." 0 0
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
    disk=${result%%\ *}
}

partDisks() {
    showDisks

    result=$(whiptail --yesno "Do you want me to automatically partition and format the disk for you?" 0 0 3>&1 1>&2 2>&3)
    if [ $? -eq 1 ]; then
        gdisk $disk
        # TODO: ask user for the partitions and do formatPart and mountPart.
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
    parted -s $disk mklabel gpt 2> /dev/null

	sgdisk $disk -n=1:0:+300M -t=1:ef00 > /dev/null
	sgdisk $disk -n=2:0:+1024M -t=2:8200 > /dev/null
	sgdisk $disk -n=3:0:0 > /dev/null
}

formatPart() {
    mkfs.fat -F 32 "$bootPart" > /dev/null 2>&1
    mkswap "$swapPart" > /dev/null 2>&1
    mkfs.ext4 "$rootPart" > /dev/null 2>&1
}

mountPart() {
    mount "$rootPart" /mnt > /dev/null
    mkdir -p /mnt/boot/efi 
    mount "$bootPart" /mnt/boot/efi > /dev/null
    swapon "$swapPart" > /dev/null
}

installPackages() {
    pacstrap /mnt base linux linux-firmware git neovim intel-ucode reflector
}

generateFstab() {
    genfstab -U /mnt > /mnt/etc/fstab
}

setTimeZone() {
    ln -sf /usr/share/zoneinfo/America/Buenos_Aires /etc/localtime
    runInChrootWithInput "hwclock --systohc"
}

setLocale() {
    sed 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -i /etc/locale.gen
    runInChrootWithInput "locale-gen"
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
}

networkConf() {
    echo "archLinux" > /etc/hostname
    echo "
127.0.0.1   localhost
::1     localhost
127.0.1.1   archLinux.localdomain archLinux" >> /etc/hosts
}

setPassword() {
    runInChrootWithInput "passwd"
}

updateMirrors() {
    runInChrootWithInput "cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup"
    runInChrootWithInput "sudo reflector --country Brazil,Chile,Colombia --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
}

installMorePackages() {
    runInChrootWithInput "pacman -Sy --noconfirm grub efibootmgr networkmanager network-manager-applet dialog reflector base-devel linux-headers xdg-user-dirs xdg-utils alsa-utils pipewire pipewire-alsa pipewire-pulse openssh reflector qemu qemu-arch-extra ttf-fira-code sudo nvidia-utils nvidia-settings xorg"
    runInChrootWithInput "systemctl enable NetworkManager; systemctl enable fstrim.timer"
}

grubSetUp() {
    runInChrootWithInput "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB; grub-mkconfig -o /boot/grub/grub.cfg"
}

userSetUp() {
    runInChrootWithInput "useradd -m slococo;passwd slococo; sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers; usermod -aG wheel slococo"
}

runInChroot() {
    arch-chroot /mnt bash -c '${1}'
}

runInChrootWithInput() {
    cat << EOF > /mnt/runme
${1}
EOF
    chmod 755 /mnt/runme
    arch-chroot /mnt /runme
    rm /mnt/runme
}

finishInstallation() {
    umount -R /mnt
    reboot
}

installLastPrograms() {
    sudo pacman -S xorg xorg-xinit
    # TODO: Use csv to install all the programs
    sudo pacman -S zsh
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
}

getDotfiles() {
    installLastPrograms
    local lastFolder=$(pwd -P)
    cd $HOME/Documents
    git clone https://github.com/santilococo/CocoRice.git
    cd CocoRice
    sh scripts/bootstrap.sh
    cd $lastFolder
}

runScript() {
    if [ -d "$HOME/Documents" ]; then
        getDotfiles
        exit 1
    fi

    whiptail --title "CocoASAIS" --msgbox "Welcome to CocoASAIS!" 0 0
    checkUefi
    updateSystemClock
    partDisks
    installPackages
    generateFstab
    setTimeZone
    setLocale
    networkConf
    setPassword
    updateMirrors
    installMorePackages
    grubSetUp
    userSetUp
    finishInstallation
}

runScript
