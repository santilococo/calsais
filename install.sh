#!/bin/sh

setDelimiters() {
    delimiters=("$@")
}

formatOptions() {
    options=()
    for item in "$@"; do
        options+=("${item}" "${delimiters[@]}")
    done
}

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
    local IFS=$'\n'
    setDelimiters ""
    formatOptions $(lsblk -d -p -n -l -o NAME,SIZE -e 7,11)
    
    result=$(whiptail --title "Select a disk" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    disk=${result%%\ *}
}

partDisks() {
    showDisks

    whiptail --yesno "Do you want me to automatically partition and format the disk for you?" 0 0
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
    whiptail --msgbox "Now we will set the timezone." 0 0
    setDelimiters ""
    formatOptions $(ls -l /usr/share/zoneinfo/ | grep '^d' | awk '{printf $9" \n"}' | awk '!/posix/ && !/right/')
	region=$(whiptail --title "Region" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    formatOptions $(ls -l /usr/share/zoneinfo/${region} | grep -v '^d' | awk '{printf $9" \n"}')
	city=$(whiptail --title "City" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)

    ln -sf /usr/share/zoneinfo/${region}/${city} /etc/localtime
    runInChroot "hwclock --systohc"
}

setLocale() {
    # TODO: Let the user choose a locale
    sed 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -i /etc/locale.gen
    runInChroot "locale-gen"
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
}

networkConf() {
    hostname=$(whiptail --inputbox "Enter the hostname." 0 0 3>&1 1>&2 2>&3)
    echo "${hostname}" > /etc/hostname
    echo "
127.0.0.1   localhost
::1     localhost
127.0.1.1   ${hostname}.localdomain ${hostname}" >> /etc/hosts
    unset hostname
}

setPassword() {
    askForPassword "root"
    runInChroot "echo "root:${password}" | chpasswd"
    unset password
}

updateMirrors() {
    runInChroot "cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup"
    local IFS=$'\n'
    setDelimiters "" "OFF"
    formatOptions $(cat /mnt/etc/pacman.d/mirrorlist | grep '^##' | cut -d' ' -f2- | sed -n '5~1p')
    countries=$(whiptail --title "Countries" --checklist "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    countriesFmt=$(echo "$countries" | sed -r 's/" "/,/g')
    runInChroot "sudo reflector --country "${countriesFmt//\"/}" --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
}

installPackage() {
    whiptail --infobox "Installing \`$1\` from the arch official repositories." 0 0
    pacstrap /mnt ${1}
}

installMorePackages() {
    # runInChroot "pacman -Sy --noconfirm grub efibootmgr networkmanager base-devel linux-headers xdg-user-dirs xdg-utils alsa-utils pipewire pipewire-alsa pipewire-pulse sudo nvidia-utils nvidia-settings"
    pacstrap /mnt grub efibootmgr networkmanager base-devel linux-headers xdg-user-dirs xdg-utils alsa-utils pipewire pipewire-alsa pipewire-pulse sudo nvidia-utils nvidia-settings
    runInChroot "systemctl enable NetworkManager; systemctl enable fstrim.timer"
}

grubSetUp() {
    runInChroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB; grub-mkconfig -o /boot/grub/grub.cfg"
}

askForPassword() {
    password=$(whiptail --inputbox "Enter the password for ${1}." 0 0 3>&1 1>&2 2>&3)
    passwordRep=$(whiptail --inputbox "Reenter password." 0 0 3>&1 1>&2 2>&3)
    while ! [ "$password" = "$passwordRep" ]; do
        password=$(whiptail --inputbox "Passwords do not match! Please enter the password again." 0 0 3>&1 1>&2 2>&3)
        passwordRep=$(whiptail --inputbox "Reenter password." 0 0 3>&1 1>&2 2>&3)
    done
    unset passwordRep
}

userSetUp() {
    username=$(whiptail --inputbox "Enter the new username." 0 0 3>&1 1>&2 2>&3)
    askForPassword "${username}"
    runInChroot "useradd -m ${username};echo "${username}:${password}" | chpasswd; sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers; usermod -aG wheel ${username}"
    unset username
    unset password
}

runInChroot() {
    cat << EOF > /mnt/cocoScript
${1}
EOF
    chmod 755 /mnt/cocoScript
    arch-chroot /mnt /cocoScript
    rm /mnt/cocoScript
}

finishInstallation() {
    umount -R /mnt
    whiptail --yesno "Finally, the PC needs to restart, would you like to do it?" 0 0
    if [ $? -eq 0 ]; then
        reboot
    fi
}

installLastPrograms() {
    sudo pacman -Sy --noconfirm xorg xorg-xinit ttf-fira-code dialog
    # TODO: Use csv to install all the programs
    sudo pacman -S zsh
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
    git clone https://aur.archlinux.org/paru.git; cd paru; makepkg -si --noconfirm; cd ..; rm -rf paru
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

# runScript