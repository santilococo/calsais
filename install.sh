#!/usr/bin/env bash

setDelimiters() {
    delimiters=("$@")
}

formatOptions() {
    options=()
    for item in "$@"; do
        options+=("${item}" "${delimiters[@]}")
    done
}

# TODO: Add support for MBR boot mode
checkUefi() {
    ls /sys/firmware/efi/efivars > /dev/null 2>&1
    if [ $? -ge 1 ]; then
        logAndExit "This scripts supports only UEFI boot mode." "checkUefi"
    fi
}

updateSystemClock() {
    timedatectl set-ntp true
}

logAndExit() {
    str="${1} Therefore, the installation process will stop, but you can continue where you left off by running:\n\nsh CocoASAIS"
    newlines=$(printf "$str" | grep -c $'\n')
    chars=$(echo "$str" | wc -c)
    height=$(echo "$chars" "$newlines" | awk '{
        x = (($1 - $2 + ($2 * 60)) / 60)
        printf "%d", (x == int(x)) ? x : int(x) + 1
    }')
    whiptail --msgbox "$str" $((5+height)) 60
    echo ${1} > CocoASAIS.log
    exit 1
}

exitIfCancel() {
    if [ $? -eq 1 ]; then
        logAndExit "$@"
    fi
}

partDisks() {
    whiptail --yesno "Do you want me to automatically partition and format a disk for you?" 0 0
    whipStatus=$?

    local IFS=$'\n'
    setDelimiters ""
    formatOptions $(lsblk -dpnlo NAME,SIZE -e 7,11)
    result=$(whiptail --title "Select the disk." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a disk." "partDisks"
    disk=$(echo $result | cut -d' ' -f1)

    if [ $whipStatus -eq 1 ]; then
        autoSelection=false
        calcHeightAndRun "whiptail --msgbox \"You will partition the disk yourself with gdisk and then, when finished, you will continue with the installation.\" HEIGHT 62 3>&1 1>&2 2>&3"
        # TODO: Let the user choose the program
        gdisk $disk
        parts=$(lsblk $disk -pnl | sed -n '2~1p' | wc -l)
        [ $parts -lt 2 ] && logAndExit "You must at least create boot and root partitions." "partDisks"

        # TODO: Ask for home partition
        formatOptions $(lsblk ${disk} -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p')
        result=$(whiptail --title "Select the boot partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the boot partition." "partDisks"
        bootPart=$(echo $result | cut -d' ' -f1)
        formatOptions $(lsblk ${disk} -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p' | awk '$0!~v' v="$bootPart")
        result=$(whiptail --title "Select the root partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the root partition." "partDisks"
        rootPart=$(echo $result | cut -d' ' -f1)

        parts=$(lsblk $disk -pnl | sed -n '2~1p' | awk '$0!~v' v="$bootPart|$rootPart" | wc -l)
        if [ $parts -gt 0 ]; then
            whiptail --yesno "Do you have a swap partition?" 0 0
            if [ $? -eq 0 ]; then
                formatOptions $(lsblk ${disk} -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p' | awk '$0!~v' v="$bootPart|$rootPart")
                result=$(whiptail --title "Select the swap partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
                exitIfCancel "You must select the swap partition." "partDisks"
                swapPart=$(echo $result | cut -d' ' -f1)
            else
                whiptail --yesno "Do you want to create a swapfile?" 0 0
                if [ $? -eq 0 ]; then
                    size=$(getSize "swapfile")
                    swapfile=/mnt/swapfile
                fi
            fi
        else
            whiptail --yesno "Do you want to create a swapfile?" 0 0
            if [ $? -eq 0 ]; then
                size=$(getSize "swapfile")
                swapfile=/mnt/swapfile
            fi
        fi
    else
        autoSelection=true
        bootPart=${disk}1
        rootPart=${disk}2

        whiptail --yesno "Do you want to create a swap space?" 0 0
        if [ $? -eq 0 ]; then
            result=$(whiptail --title "Select the swap space." --menu "" 0 0 0 "Partition" "" "Swapfile" "" 3>&1 1>&2 2>&3)
            exitIfCancel "You must select a swap space." "partDisks"
            size=$(getSize "${result:l}")
            if [ "$result" = "Partition" ]; then
                swapPart=${disk}2
                rootPart=${disk}3
            else
                swapfile=/mnt/swapfile
            fi
        fi

        autoPart
    fi

    formatPart
    mountPart
}

getSize() {
    sizeStr=$(whiptail --inputbox "Enter the size of the ${1} (in GB)." 0 0 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a size." "partDisks"
    size=$(echo "$sizeStr" | grep -Eo '[-]?[0-9]+([.,]?[0-9]+)?' | head -n1 | sed 's/,/./g' | awk '{ print int($1 * 1024) }')
    while [ $(echo $size | awk '{ print $1 <= 0 }') -eq 1 ]; do
        sizeStr=$(whiptail --inputbox "Size cannot be less than or equal to zero. Please enter a new size." 0 0 3>&1 1>&2 2>&3)
        exitIfCancel "You must enter a size." "partDisks"
        size=$(echo "$sizeStr" | grep -Eo '[-]?[0-9]+([.,]?[0-9]+)?' | head -n1 | sed 's/,/./g' | awk '{ print int($1 * 1024) }')
    done
    echo $size
}

createSwapfile() {
    dd if=/dev/zero of=$swapfile bs=1M count=${size} status=progress 2>&1 | debug
    chmod 600 $swapfile 2>&1 | debug
    mkswap $swapfile 2>&1 | debug
    swapon $swapfile 2>&1 | debug
}

autoPart() {
    parted -s $disk mklabel gpt 2>&1 | debug

    sgdisk $disk -n=1:0:+300M -t=1:ef00 2>&1 | debug
    if [ -n "$swapPart" ]; then
        sgdisk $disk -n=2:0:+${size}G -t=2:8200 2>&1 | debug
        sgdisk $disk -n=3:0:0 2>&1 | debug
    else
        sgdisk $disk -n=2:0:0 2>&1 | debug
    fi
}

# TODO: Let the user choose the file system (and add encryption support)
formatPart() {
    mkfs.fat -F 32 "$bootPart" 2>&1 | debug
    [ -n "$swapPart" ] && mkswap "$swapPart" 2>&1 | debug
    mkfs.ext4 "$rootPart" 2>&1 | debug
}

mountPart() {
    mount "$rootPart" /mnt 2>&1 | debug
    if [ $autoSelection = false ]; then
        result=$(whiptail --title "Select where to mount boot partition." --menu "" 0 0 0 "/boot/efi" "" "/boot" "" "==OTHER==" "" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select a path." "partDisks"
        bootPath=$(echo $result | sed 's/^\///g')
        if [ "$result" = "OTHER" ]; then
            local IFS=' '
            result=$(whiptail --inputbox "Enter the absolute path." 0 0 3>&1 1>&2 2>&3)
            exitIfCancel "You must enter a path." "partDisks"
            bootPath=$(echo $result | sed 's/^\///g')
            mkdir -p "/mnt/$bootPath"
            while [[ ! -d "/mnt/$bootPath" ]]; do
                result=$(whiptail --inputbox "Path isn't valid. Please try again" 0 0 3>&1 1>&2 2>&3)
                exitIfCancel "You must enter a path." "partDisks"
                bootPath=$(echo $result | sed 's/^\///g')
                mkdir -p "/mnt/$bootPath"
            done
        fi
        mount "$bootPart" "/mnt/$bootPath" 2>&1 | debug
    else
        mkdir -p /mnt/boot/efi 
        mount "$bootPart" /mnt/boot/efi 2>&1 | debug
    fi
    [ -n "$swapPart" ] && swapon "$swapPart" 2>&1 | debug
    [ -n "$swapfile" ] && createSwapfile
}

debug() {
    if [ $debugFlagToStdout = true ]; then
        tee
    elif [ $debugFlagToFile = true ]; then
        tee -a CocoASAIS.debug > /dev/null
    elif [ $debugFlag = true ]; then
        tee -a CocoASAIS.debug
    else
        tee > /dev/null
    fi
}

installPackage() {
    calcWidthAndRun "whiptail --infobox \"Installing '$1'.\" 7 WIDTH"
    case ${2} in
        A)  
            if [ $debugFlagToStdout = true ] || [ $debugFlag = true ]; then
                script -qec "pacstrap /mnt --needed ${1}" /dev/null 2>&1 | debug
            else
                pacstrap /mnt --needed ${1} 2>&1 | debug
            fi
            ;;
        B)
            runInChroot "pacman -Q ${1}" 2>&1 | debug
            [ $? -eq 0 ] && return
            if [ $debugFlagToStdout = true ] || [ $debugFlag = true ]; then
                runInChroot "script -qec \"pacman -S --needed --noconfirm ${1}\" /dev/null" 2>&1 | debug
            else
                runInChroot "pacman -S --needed --noconfirm ${1}" 2>&1 | debug
            fi
            ;;
        C)  
            runInChroot "sudo -u $username paru -Q ${1}" 2>&1 | debug
            [ $? -eq 0 ] && return
            if [ $debugFlagToStdout = true ] || [ $debugFlag = true ]; then
                runInChroot "script -qec \"sudo -u $username paru -S --needed --noconfirm --skipreview ${1}\" /dev/null" 2>&1 | debug
            else
                runInChroot "sudo -u $username paru -S --needed --noconfirm --skipreview ${1}" 2>&1 | debug
            fi
            ;;
        D)
            pkgName=$(echo ${1} | grep -oP '(?<=/).*?(?=.git)')
            runInChroot "sudo -u $username paru -Q ${pkgName}" 2>&1 | debug
            [ $? -eq 0 ] && return
            runInChroot "cd /tmp; sudo -u $username git clone https://github.com/${1}; cd ${pkgName}; sudo -u $username makepkg -si --noconfirm; cd ..; rm -rf ${pkgName}" 2>&1 | debug
            ;;
        ?)
            logAndExit "INSTALL must be A, B, C or D in packages.csv file." "${3}"
            ;;
    esac
    exitIfCancel "Package installation failed." "${3}"
}

checkForParu() {
    commOutput=$(runInChroot "command -v paru > /dev/null 2>&1 || echo 1")
    if [ "$commOutput" = "1" ]; then
        runInChroot "sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers"
        runInChroot "cd /tmp; sudo -u $username git clone https://aur.archlinux.org/paru-bin.git; cd paru-bin; sudo -u $username makepkg -si --noconfirm; cd ..; rm -rf paru-bin" 2>&1 | debug
    fi
}

getThePackages() {
    set -o pipefail
    if [ ! -f "packages.csv" ]; then
        curl -LO "https://raw.githubusercontent.com/santilococo/CocoASAIS/master/packages.csv" 2>&1 | debug
    fi
    local IFS=,
    while read -r NAME IMPORTANT INSTALL; do
        if [ "$IMPORTANT" = "${1}" ]; then
            installPackage "$NAME" "$INSTALL" "${2}" < /dev/null
        fi
    done < packages.csv
    set +o pipefail
}

installImportantPackages() {
    calcHeightAndRun "whiptail --msgbox \"We will continue with the installation of some important packages in the background. Please press OK and wait.\" HEIGHT 60 3>&1 1>&2 2>&3"
    checkForExpect
    getThePackages "Y" "installImportantPackages"
    runInChroot "systemctl enable NetworkManager; systemctl enable fstrim.timer" 2>&1 | debug
}

generateFstab() {
    genfstab -U /mnt >> /mnt/etc/fstab
}

setTimeZone() {
    whiptail --msgbox "Now, we will set the timezone." 0 0
    setDelimiters ""
    formatOptions $(ls -l /usr/share/zoneinfo/ | grep '^d' | awk '{printf $9" \n"}' | awk '!/posix/ && !/right/')
    region=$(whiptail --title "Region" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a region." "setTimeZone"
    formatOptions $(ls -l /usr/share/zoneinfo/${region} | grep -v '^d' | awk '{printf $9" \n"}')
    city=$(whiptail --title "City" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a city." "setTimeZone"

    ln -sf /mnt/usr/share/zoneinfo/${region}/${city} /mnt/etc/localtime
    runInChroot "hwclock --systohc"
}

setLocale() {
    # TODO: Let the user choose a locale
    sed 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -i /mnt/etc/locale.gen
    runInChroot "locale-gen" 2>&1 | debug
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
}

networkConf() {
    hostname=$(whiptail --inputbox "Enter the hostname." 0 0 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a hostname." "networkConf"
    echo "${hostname}" > /mnt/etc/hostname
    echo "
127.0.0.1   localhost
::1     localhost
127.0.1.1   ${hostname}.localdomain ${hostname}" >> /mnt/etc/hosts
    unset hostname
}

calcWidthAndRun() {
    width=$(echo "$@" | grep -oP '(?<=").*?(?=")' | wc -c)
    comm=$(echo "$@" | sed "s/WIDTH/$((width+8))/g")
    if [[ $comm != *"3>&1 1>&2 2>&3" ]]; then
        comm="${comm} 3>&1 1>&2 2>&3"
    fi
    commOutput=$(eval $comm)
    exitStatus=$?
    [ ! -z $commOutput ] && echo $commOutput
    return $exitStatus
}

calcHeightAndRun() {
    str=$(echo "$@" | grep -oP '(?<=").*?(?=")')
    newlines=$(printf '%s' "$str" | grep -c $'\n')
    chars=$(echo "$str" | wc -c)
    height=$(echo "$chars" "$newlines" | awk '{
        x = (($1 - $2 + ($2 * 60)) / 60)
        printf "%d", (x == int(x)) ? x : int(x) + 1
    }')
    comm=$(echo "$@" | sed "s/HEIGHT/$((5+height))/g")
    if [[ $comm != *"3>&1 1>&2 2>&3" ]]; then
        comm="${comm} 3>&1 1>&2 2>&3"
    fi
    commOutput=$(eval $comm)
    exitStatus=$?
    [ ! -z $commOutput ] && echo $commOutput
    return $exitStatus
}

askForPassword() {
    password=$(calcWidthAndRun "whiptail --passwordbox \"Now, enter the password for ${1}.\" 8 WIDTH 3>&1 1>&2 2>&3")
    exitIfCancel "You must enter a password." "${2}"
    passwordRep=$(calcWidthAndRun "whiptail --passwordbox \"Reenter password.\" 8 WIDTH 3>&1 1>&2 2>&3")
    exitIfCancel "You must enter a password." "${2}"
    while ! [ "$password" = "$passwordRep" ]; do
        password=$(calcWidthAndRun "whiptail --passwordbox \"Passwords do not match! Please enter the password again.\" 8 WIDTH 3>&1 1>&2 2>&3")
        exitIfCancel "You must enter a password." "${2}"
        passwordRep=$(calcWidthAndRun "whiptail --passwordbox \"Reenter password.\" 8 WIDTH 3>&1 1>&2 2>&3")
        exitIfCancel "You must enter a password." "${2}"
    done
    unset passwordRep
}

setRootPassword() {
    askForPassword "root" "setRootPassword"
    runInChroot "echo \"root:${password}\" | chpasswd" 2>&1 | debug
    unset password
}

updateMirrors() {
    whiptail --yesno "Would you like to update your mirrors by choosing your closest countries?" 0 0 || return
    runInChroot "cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup"
    runInChroot "curl -o /etc/pacman.d/mirrorlist.pacnew https://archlinux.org/mirrorlist/all/" 2>&1 | debug
    local IFS=$'\n'
    setDelimiters "" "OFF"
    formatOptions $(cat /mnt/etc/pacman.d/mirrorlist.pacnew | grep '^##' | cut -d' ' -f2- | sed -n '5~1p')
    countries=$(whiptail --title "Countries" --checklist "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select at least one country." "updateMirrors"
    countriesFmt=$(echo "$countries" | sed -r 's/" "/,/g')
    runInChroot "sudo reflector --country \"${countriesFmt//\"/}\" --protocol https --sort rate --save /etc/pacman.d/mirrorlist" 2>&1 | debug
}

grubSetUp() {
    # TODO: Prompt user for efi-directory
    runInChroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB; grub-mkconfig -o /boot/grub/grub.cfg" 2>&1 | debug
}

saveUsername() {
    echo $username > CocoASAIS.vars
}

loadUsername() {
    username=$(cat CocoASAIS.vars)
}

userSetUp() {
    username=$(whiptail --inputbox "Enter the new username." 0 0 3>&1 1>&2 2>&3) && saveUsername
    exitIfCancel "You must enter an username." "userSetUp"
    askForPassword "${username}" "userSetUp"
    runInChroot "useradd -m ${username};echo \"${username}:${password}\" | chpasswd; sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers; usermod -aG wheel ${username}"
    unset password
}

runInChroot() {
    cat << EOF > /mnt/cocoScript
${1}
EOF
    chmod 755 /mnt/cocoScript
    arch-chroot /mnt /cocoScript
    return $?
}

installOtherPackages() {
    calcHeightAndRun "whiptail --msgbox \"Now, we will install a few more packages (in the background). Press OK and wait (it may take some time).\" HEIGHT 60 3>&1 1>&2 2>&3"
    [ -z $username ] && loadUsername
    getThePackages "S" "installOtherPackages"
    checkForParu
    getThePackages "N" "installOtherPackages"
    runInChroot "sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers"
}

finishInstallation() {
    cp CocoASAIS /mnt/usr/bin/CocoASAIS
    echo "sh /usr/bin/CocoASAIS && logout" >> /mnt/home/slococo/.bashrc
    rm /mnt/cocoScript
    umount -R /mnt
    whiptail --yesno "Finally, the PC needs to restart, would you like to restart now?" 0 0
    if [ $? -eq 0 ]; then
        reboot
    else 
        clear
    fi
}

zshConfig() {
    # TODO: Choose between zsh-theme-powerlevel10k-git (AUR) and zsh-theme-powerlevel10k (community)
    mkdir -p $HOME/.cache/zsh
    touch $HOME/.cache/zsh/.histfile
}

getDotfiles() {
    zshConfig
    local lastFolder=$(pwd -P)
    cd $HOME/Documents
    git clone https://github.com/santilococo/CocoRice.git 2>&1 | debug
    cd CocoRice
    sh scripts/bootstrap.sh -w
    cd $lastFolder

    sudo rm -f ~/.bashrc /usr/bin/CocoASAIS
    chsh -s $(which zsh)
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
    installOtherPackages
    finishInstallation
)

runScript() {
    debugFlag=false; debugFlagToFile=false; debugFlagToStdout=false
    while getopts ':hdfs' flag; do
        case $flag in
            h)  printf 'usage: %s [command]\n\t-h\tPrint this help message.\n\t-d\tDebug to stdout.\n\t-d\tDebug to CocoASAIS.debug file.\n' "${0##*/}" && exit 0 ;;
            d)  debugFlag=true ;;
            f)  debugFlagToFile=true ;;
            s)  debugFlagToStdout=true ;;
            ?)  printf '%s: invalid option -''%s'\\n "${0##*/}" "$OPTARG" && exit 1 ;;
        esac
    done

    clear
    if [ -d "$HOME/Documents" ]; then
        whiptail --title "CocoASAIS" --msgbox "Now, we will finish the installation. Press OK and wait." 7 60
        getDotfiles
        whiptail --title "CocoASAIS" --msgbox "All done!" 0 0
        clear
        exit 0
    fi

    i=0; found=false
    if [ -f "CocoASAIS.log" ]; then
        lastStep=$(cat CocoASAIS.log)
        for item in "${steps[@]}"; do
            if [ "$item" = "$lastStep" ]; then
                found=true
                break
            fi
            ((i++))
        done
        if [ $found = false ]; then
            i=0
        fi
    fi

    if [ $i -gt 0 ]; then
        welcomeMsg="Welcome back to CocoASAIS!"
    else
        welcomeMsg="Welcome to CocoASAIS!"
    fi

    whiptail --title "CocoASAIS" --msgbox "${welcomeMsg}" 0 0

    while [ $i -le "${#steps[@]}" ]; do
        ${steps[$i]}
        ((i++))
    done
}

runScript "$@"
