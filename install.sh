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

logStep() {
    echo ${1} > CocoASAIS.log
}

checkUefi() {
    ls /sys/firmware/efi/efivars > /dev/null 2>&1
    if [ $? -ge 1 ]; then
        whiptail --msgbox "This scripts supports only UEFI boot mode." 0 0
        logStep "checkUefi"
        exit 1
    fi
}

updateSystemClock() {
    timedatectl set-ntp true
}

exitIfCancel() {
    if [ $? -eq 1 ]; then
        whiptail --msgbox "${1} Therefore, the installation process will stop, but you can continue where you left off by running:\n\nsh CocoASAIS" 0 0
        echo "${2}" > CocoASAIS.log
        exit 1
    fi
}

partDisks() {
    local IFS=$'\n'
    setDelimiters ""
    formatOptions $(lsblk -dpnlo NAME,SIZE -e 7,11)
    
    result=$(whiptail --title "Select a disk." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a disk." "partDisks"
    disk=$(echo $result | cut -d' ' -f1)

    # TODO: Add swapfile as an alternative to swap partition
    whiptail --yesno "Do you want me to automatically partition and format the disk for you?" 0 0
    if [ $? -eq 1 ]; then
        whiptail --msgbox "You will partition the disk yourself with gdisk and then, when finished, you will continue with the installation." 0 0
        gdisk $disk
        # TODO: Ask for home partition
        formatOptions $(lsblk ${disk} -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p')
        result=$(whiptail --title "Select the boot partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the boot partition." "partDisks"
        bootPart=$(echo $result | cut -d' ' -f1)
        result=$(whiptail --title "Select the root partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the root partition." "partDisks"
        rootPart=$(echo $result | cut -d' ' -f1)
        whiptail --yesno "Do you have a swap partition?" 0 0
        if [ $? -eq 0 ]; then
            result=$(whiptail --title "Select the swap partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
            exitIfCancel "You must select the swap partition." "partDisks"
            swapPart=$(echo $result | cut -d' ' -f1)
        fi
    else
        autoPart
        bootPart=${disk}1
        swapPart=${disk}2
        rootPart=${disk}3
    fi

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
    # TODO: Ask where to mount the bootPart
    mount "$bootPart" /mnt/boot/efi > /dev/null
    swapon "$swapPart" > /dev/null
}

installPackage() {
    case ${2} in
        Y)
            if [ -z $username ]; then
                whiptail --msgbox "Important packages cannot be installed with paru." 0 0
                logStep "${3}"
                exit 1
            fi
            runInChroot "sudo -u $username paru -S ${1} > /dev/null 2>&1"
            ;;
        N)
            pacstrap /mnt --needed ${1} > /dev/null 2>&1
            ;;
        ?)
            whiptail --msgbox "AUR must be Y or N in packages.csv file." 0 0
            logStep "${3}"
            exit 1
            ;;
    esac
    exitIfCancel "You must have an active internet connection" "${3}"
}

getThePackages() {
    if [ ! -f "packages.csv" ]; then
        curl -LO "https://raw.githubusercontent.com/santilococo/CocoASAIS/master/packages.csv" > /dev/null 2>&1
    fi
    commOutput=$(runInChroot "command -v paru &> /dev/null || echo 1")
    if [ "$commOutput" = "1" ] && [ "${1}" = "N" ]; then
        if [ -z $username ]; then
            username=$(whiptail --inputbox "Enter the username of the newly created user." 0 0 3>&1 1>&2 2>&3)
        fi
        # runInChroot "sed -i 's/%wheel ALL=(ALL) ALL/# %wheel ALL=(ALL) ALL/' -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers"
        runInChroot "sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers"
        runInChroot "cd /tmp; sudo -u $username git clone https://aur.archlinux.org/paru-bin.git; cd paru; sudo -u $username makepkg -si --noconfirm; cd ..; rm -rf paru"
        runInChroot "sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers"
        # runInChroot "sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' -e 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers"
    fi
    local IFS=,
    while read -r NAME IMPORTANT AUR; do
        if [ "$IMPORTANT" = "${1}" ]; then
            installPackage "$NAME" "$AUR" "${2}"
        fi
	done < packages.csv
}

installImportantPackages() {
    whiptail --msgbox "We will start by installing some important packages in the background. Please wait." 0 0
    getThePackages "Y" "installImportantPackages"
    runInChroot "systemctl enable NetworkManager; systemctl enable fstrim.timer"
}

generateFstab() {
    genfstab -U /mnt > /mnt/etc/fstab
}

setTimeZone() {
    whiptail --msgbox "Now we will set the timezone." 0 0
    setDelimiters ""
    formatOptions $(ls -l /usr/share/zoneinfo/ | grep '^d' | awk '{printf $9" \n"}' | awk '!/posix/ && !/right/')
    region=$(whiptail --title "Region" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a region." "setTimeZone"
    formatOptions $(ls -l /usr/share/zoneinfo/${region} | grep -v '^d' | awk '{printf $9" \n"}')
    city=$(whiptail --title "City" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a city." "setTimeZone"

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
    exitIfCancel "You must enter a hostname." "networkConf"
    echo "${hostname}" > /etc/hostname
    echo "
127.0.0.1   localhost
::1     localhost
127.0.1.1   ${hostname}.localdomain ${hostname}" >> /etc/hosts
    unset hostname
}

askForPassword() {
    password=$(whiptail --passwordbox "Enter the password for ${1}." 8 40 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a password." "${2}"
    passwordRep=$(whiptail --passwordbox "Reenter password." 8 30 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a password." "${2}"
    while ! [ "$password" = "$passwordRep" ]; do
        password=$(whiptail --passwordbox "Passwords do not match! Please enter the password again." 8 65 3>&1 1>&2 2>&3)
        exitIfCancel "You must enter a password." "${2}"
        passwordRep=$(whiptail --passwordbox "Reenter password." 8 30 3>&1 1>&2 2>&3)
        exitIfCancel "You must enter a password." "${2}"
    done
    unset passwordRep
}

setRootPassword() {
    askForPassword "root" "setRootPassword"
    runInChroot "echo "root:${password}" | chpasswd"
    unset password
}

updateMirrors() {
    whiptail --yesno "Would you like to update your mirrors by choosing your closest countries?" 0 0 || return
    runInChroot "cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup"
    local IFS=$'\n'
    setDelimiters "" "OFF"
    formatOptions $(cat /mnt/etc/pacman.d/mirrorlist.pacnew | grep '^##' | cut -d' ' -f2- | sed -n '5~1p')
    countries=$(whiptail --title "Countries" --checklist "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select at least one country." "updateMirrors"
    countriesFmt=$(echo "$countries" | sed -r 's/" "/,/g')
    runInChroot "sudo reflector --country "${countriesFmt//\"/}" --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
}

grubSetUp() {
    # TODO: Prompt user for efi-directory
    runInChroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB; grub-mkconfig -o /boot/grub/grub.cfg" > /dev/null 2>&1
}

userSetUp() {
    username=$(whiptail --inputbox "Enter the new username." 0 0 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter an username." "userSetUp"
    askForPassword "${username}" "userSetUp"
    runInChroot "useradd -m ${username};echo "${username}:${password}" | chpasswd; sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers; usermod -aG wheel ${username}"
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

installNotImportantPackages() {
    whiptail --msgbox "Now, we will install some more packages (in the background). This may take long, please wait." 0 0
    getThePackages "N" "installNotImportantPackages"
}

finishInstallation() {
    umount -R /mnt
    whiptail --yesno "Finally, the PC needs to restart, would you like to do it?" 0 0
    if [ $? -eq 0 ]; then
        reboot
    else 
        clear
    fi
}

installLastPrograms() {
    sudo pacman -Sy
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
}

getDotfiles() {
    installLastPrograms
    local lastFolder=$(pwd -P)
    cd $HOME/Documents
    git clone https://github.com/santilococo/CocoRice.git
    cd CocoRice
    sh scripts/bootstrap.sh -w
    cd $lastFolder
}

steps=(
    checkUefi
    updateSystemClock
    partDisks
    installImportantPackages
    generateFstab
    setTimeZone
    setLocale
    networkConf
    setRootPassword
    updateMirrors
    grubSetUp
    userSetUp
    installNotImportantPackages
    finishInstallation
)

runScript() {
    if [ -d "$HOME/Documents" ]; then
        getDotfiles
        whiptail --title "CocoASAIS" --msgbox "All done!" 0 0
        exit 0
    fi

    i=0; found=false
    if [ -f "CocoASAIS.log" ]; then
        lastStep=$(cat CocoASAIS.log)
        for item in "${steps[@]}"; do
            if [ $item = "$lastStep" ]; then
                found=true
                break
            fi
            ((i++))
        done
        if [ $found = false ]; then
            i=0
        fi
    fi

    whiptail --title "CocoASAIS" --msgbox "Welcome to CocoASAIS!" 0 0

    while [ $i -le "${#steps[@]}" ]; do
        ${steps[$i]}
        ((i++))
    done
}

runScript
