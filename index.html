#!/usr/bin/env bash

setDelimiters() {
    delimiters=("$@")
}

formatOptions() {
    options=()
    while read -r item; do
        options+=("${item}" "${delimiters[@]}")
    done < "$1"
}

# TODO: Add support for MBR boot mode
checkUefi() {
    ls /sys/firmware/efi/efivars > /dev/null 2>&1
    [ $? -ge 1 ] && printAndExit "This scripts supports only UEFI boot mode."
}

updateSystemClock() {
    timedatectl set-ntp true
}

printAndExit() {
    str="${1} Therefore, the installation process will stop, but you can continue where you left off by running:\n\nsh calsais"
    calcAndRun dialog --msgbox "\"\n${str}\"" HEIGHT 59
    exit 1
}

exitIfCancel() {
    [ $? -eq 1 ] && printAndExit "$@"
}

printWaitBox() {
    dialog --infobox "\nPlease wait..." 5 18
}

partDisks() {
    dialog --yesno "\nDo you want me to automatically partition and format a disk for you?" 8 59
    whipStatus=$?

    local IFS=$'\n'
    setDelimiters ""
    formatOptions <(lsblk -dpnlo NAME,SIZE -e 7,11)
    disks=$(lsblk -dpnl -e 7,11 | wc -l)
    result=$(dialog --menu "\nSelect the disk." 0 30 "$disks" "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a disk."
    disk=$(echo "$result" | cut -d' ' -f1)

    if [ $whipStatus -eq 1 ]; then
        autoSelection=false
        msg="\nYou will partition the disk yourself and then, when finished, you will continue with the installation."
        dialog --msgbox "$msg" 8 56
        partPrograms=("fdisk" "" "sfdisk" "" "cfdisk" "" "gdisk" "" "cgdisk" "" "sgdisk" "")
        partTool=$(dialog --menu "\nSelect the partitioning tool." 14 35 6 "${partPrograms[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select a partitioning tool."
        $partTool "$disk"
        parts=$(lsblk "$disk" -pnl | sed -n '2~1p' | wc -l)
        [ "$parts" -lt 2 ] && printAndExit "You must at least create boot and root partitions."

        # TODO: Ask for home partition
        formatOptions <(lsblk "${disk}" -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p')
        result=$(dialog --menu "\nSelect the boot partition." 0 30 "$parts" "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the boot partition."
        bootPart=$(echo "$result" | cut -d' ' -f1)
        formatOptions <(lsblk "${disk}" -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p' | awk '$0!~v' v="$bootPart")
        result=$(dialog --menu "\nSelect the root partition." 0 30 "$parts" "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the root partition."
        rootPart=$(echo "$result" | cut -d' ' -f1)

        remainingParts=$(lsblk "$disk" -pnl | sed -n '2~1p' | awk '$0!~v' v="$bootPart|$rootPart" | wc -l)
        if [ "$remainingParts" -gt 0 ]; then
            dialog --yesno "\nDo you have a swap partition?" 7 34
            if [ $? -eq 0 ]; then
                formatOptions <(lsblk "${disk}" -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p' | awk '$0!~v' v="$bootPart|$rootPart")
                result=$(dialog --menu "\nSelect the swap partition." 0 30 "$parts" "${options[@]}" 3>&1 1>&2 2>&3)
                exitIfCancel "You must select the swap partition."
                swapPart=$(echo "$result" | cut -d' ' -f1)
            else
                dialog --yesno "\nDo you want to create a swapfile?" 7 37
                if [ $? -eq 0 ]; then
                    size=$(getSize "swapfile")
                    swapfile=/mnt/swapfile
                fi
            fi
        else
            dialog --yesno "\nDo you want to create a swapfile?" 7 37
            if [ $? -eq 0 ]; then
                size=$(getSize "swapfile")
                swapfile=/mnt/swapfile
            fi
        fi
    else
        autoSelection=true
        bootPart=${disk}1
        rootPart=${disk}2

        dialog --yesno "\nDo you want to create a swap space?" 7 39
        if [ $? -eq 0 ]; then
            result=$(dialog --menu "\nSelect the swap space." 0 26 2 "Partition" "" "Swapfile" "" 3>&1 1>&2 2>&3)
            exitIfCancel "You must select a swap space."
            size=$(getSize "${result:l}")
            if [ "$result" = "Partition" ]; then
                swapPart=${disk}2
                rootPart=${disk}3
            else
                swapfile=/mnt/swapfile
            fi
        fi

        printWaitBox
        autoPart
    fi

    printWaitBox
    formatPart
    mountPart
}

getSize() {
    sizeStr=$(dialog --inputbox "\nEnter the size of the ${1} (in GB, for example 1.5GB)." 10 63 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a size."
    size=$(echo "$sizeStr" | grep -Eo '[-]?[0-9]+([.,]?[0-9]+)?' | head -n1 | sed 's/,/./g' | awk '{ print int($1 * 1024) }')
    while [ "$(echo "$size" | awk '{ print $1 <= 0 }')" -eq 1 ]; do
        msg="\nThe size must be a number and cannot be less than or equal to zero. Please enter a new size."
        sizeStr=$(dialog --inputbox "$msg" 11 63 3>&1 1>&2 2>&3)
        exitIfCancel "You must enter a size."
        size=$(echo "$sizeStr" | grep -Eo '[-]?[0-9]+([.,]?[0-9]+)?' | head -n1 | sed 's/,/./g' | awk '{ print int($1 * 1024) }')
    done
    echo "$size"
}

createSwapfile() {
    dd if=/dev/zero of=$swapfile bs=1M count="${size}" status=progress 2>&1 | debug
    chmod 600 $swapfile 2>&1 | debug
    mkswap $swapfile 2>&1 | debug
    swapon $swapfile 2>&1 | debug
}

autoPart() {
    parted -s "$disk" mklabel gpt 2>&1 | debug

    sgdisk "$disk" -n=1:0:+300M -t=1:ef00 2>&1 | debug
    if [ -n "$swapPart" ]; then
        sgdisk "$disk" -n=2:0:+"${size}"M -t=2:8200 2>&1 | debug
        sgdisk "$disk" -n=3:0:0 2>&1 | debug
    else
        sgdisk "$disk" -n=2:0:0 2>&1 | debug
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
        mountOptions=("/boot/efi" "" "/boot" "" "==OTHER==" "")
        result=$(dialog --menu "\nSelect where to mount the boot partition." 0 30 4 "${mountOptions[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select a path."
        bootPath=$(echo "$result" | sed 's/^\///g')
        if [ "$result" = "OTHER" ]; then
            local IFS=' '
            result=$(dialog --inputbox "\nEnter the absolute path." 10 35 3>&1 1>&2 2>&3)
            exitIfCancel "You must enter a path."
            bootPath=$(echo "$result" | sed 's/^\///g')
            mkdir -p "/mnt/$bootPath"
            while [[ ! -d "/mnt/$bootPath" ]]; do
                result=$(dialog --inputbox "\nPath isn't valid. Please try again." 10 40 3>&1 1>&2 2>&3)
                exitIfCancel "You must enter a path."
                bootPath=$(echo "$result" | sed 's/^\///g')
                mkdir -p "/mnt/$bootPath"
            done
        else
            mkdir -p "/mnt/$bootPath"
        fi
        mount "$bootPart" "/mnt/$bootPath" 2>&1 | debug
    else
        bootPath="boot/efi"
        mkdir -p /mnt/$bootPath
        mount "$bootPart" /mnt/$bootPath 2>&1 | debug
    fi
    printWaitBox
    [ -n "$swapPart" ] && swapon "$swapPart" 2>&1 | debug
    [ -n "$swapfile" ] && createSwapfile
    saveVar "bootPath" "/$bootPath"
}

debug() {
    if [ "$debugFlagToStdout" = true ]; then
        tee
    elif [ "$debugFlagToFile" = true ]; then
        tee -a calsais.log > /dev/null
    elif [ "$debugFlag" = true ]; then
        tee -a calsais.log
    else
        tee > /dev/null
    fi
}

installPackage() {
    calcAndRun dialog --infobox "\"\nInstalling '$1'.\"" 5 WIDTH
    case ${3} in
        A)
            if [ "$debugFlagToStdout" = true ] || [ "$debugFlag" = true ]; then
                script -qec "pacstrap /mnt --needed ${1}" /dev/null 2>&1 | debug
            else
                pacstrap /mnt --needed "${1}" 2>&1 | debug
            fi
            ;;
        B)
            flag=""
            if [ "$2" != "R" ]; then
                runInChroot "pacman -Q ${1}" 2>&1 | debug
                [ $? -eq 0 ] && return
                flag="--needed"
            fi
            if [ "$debugFlagToStdout" = true ] || [ "$debugFlag" = true ]; then
                runInChroot "script -qec \"pacman -S $flag --noconfirm ${1}\" /dev/null" 2>&1 | debug
            else
                runInChroot "pacman -S $flag --noconfirm ${1}" 2>&1 | debug
            fi
            ;;
        C)
            flag=""
            if [ "$2" != "R" ]; then
                runInChroot "sudo -u $username paru -Q ${1}" 2>&1 | debug
                [ $? -eq 0 ] && return
                flag="--needed"
            fi
            if [ "$debugFlagToStdout" = true ] || [ "$debugFlag" = true ]; then
                runInChroot "script -qec \"sudo -u $username paru -S $flag --noconfirm --skipreview ${1}\" /dev/null" 2>&1 | debug
            else
                runInChroot "sudo -u $username paru -S $flag --noconfirm --skipreview ${1}" 2>&1 | debug
            fi
            ;;
        ?)
            printAndExit "INSTALL must be A, B or C in packages.csv file."
            ;;
    esac
    exitIfCancel "Package installation failed."
}

checkForParu() {
    commOutput=$(runInChroot "command -v paru > /dev/null 2>&1 || echo 1")
    if [ "$commOutput" = "1" ]; then
        runInChroot "sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers"
        checkSudoers
        printWaitBox
        runInChroot "cd /tmp; sudo -u $username git clone https://aur.archlinux.org/paru-bin.git"
        runInChroot "cd /tmp/paru-bin; sudo -u $username makepkg -si --noconfirm; cd ..; rm -rf paru-bin" 2>&1 | debug
    fi
}

getThePackages() {
    set -o pipefail
    if [ ! -f "packages.csv" ]; then
        printWaitBox
        curl -LO "https://raw.githubusercontent.com/santilococo/calsais/master/packages.csv" 2>&1 | debug
    fi
    if [ "$IMPORTANT" = "N" ]; then
        dialog --msgbox "\nA menu will appear where you can deselect the packages you don't want to be installed." 8 59
        local IFS=$'\n'
        setDelimiters "" "ON"
        formatOptions <(grep "N" packages.csv | sed -n '2~1p' | cut -d',' -f1)
        msg="\nIf you don't want to install any packages, press Cancel."
        packages=$(dialog --separate-output --checklist "$msg" 28 46 19 "${options[@]}" 3>&1 1>&2 2>&3)
        tempFile=$(mktemp)
        for package in $packages; do
            grep "^$package," packages.csv >> "$tempFile"
        done
        header=$(head -n1 packages.csv)
        packages=$(sort <(sed -n '2~1p' packages.csv) <(cat "$tempFile") | uniq -d)
        printf '%s\n%s' "$header" "$packages" > packages.csv
    fi
    local IFS=,
    while read -r NAME IMPORTANT INSTALLER; do
        if [ "$IMPORTANT" = "${1}" ]; then
            installPackage "$NAME" "$IMPORTANT" "$INSTALLER" "${2}" < /dev/null
        fi
    done < packages.csv
    set +o pipefail
}

installImportantPackages() {
    msg="\nWe will continue with the installation of some important packages in the background. Please press OK and wait."
    dialog --msgbox "$msg" 8 60
    pacman -Sy --noconfirm archlinux-keyring 2>&1 | debug
    getThePackages "Y" "installImportantPackages"
    runInChroot "systemctl enable NetworkManager; systemctl enable fstrim.timer" 2>&1 | debug
}

generateFstab() {
    printWaitBox
    genfstab -U /mnt >> /mnt/etc/fstab
}

setTimeZone() {
    dialog --msgbox "\nNow, we will set the timezone." 7 34
    setDelimiters ""
    formatOptions <(find -H /usr/share/zoneinfo -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort | awk '!/posix/ && !/right/')
    region=$(dialog --menu "Select a region." 0 21 14 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a region."
    formatOptions <(find -H "/usr/share/zoneinfo/${region}" -maxdepth 1 -mindepth 1 -type f -printf '%f\n' | sort)
    city=$(dialog --menu "Select a city." 0 23 14 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a city."

    ln -sf "/mnt/usr/share/zoneinfo/${region}/${city}" /mnt/etc/localtime
    printWaitBox
    runInChroot "hwclock --systohc"
}

setLocale() {
    # TODO: Let the user choose a locale
    sed 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -i /mnt/etc/locale.gen
    printWaitBox
    runInChroot "locale-gen" 2>&1 | debug
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
}

networkConf() {
    hostname=$(dialog --inputbox "\nEnter the hostname." 9 28 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a hostname."
    echo "${hostname}" > /mnt/etc/hostname
    echo "
127.0.0.1   localhost
::1     localhost
127.0.1.1   ${hostname}.localdomain ${hostname}" >> /mnt/etc/hosts
    unset hostname
}

calcAndRun() {
    argc="$#"; i=1
    for item in "$@"; do
        [ $i -eq $((argc-2)) ] && str="$item"
        [ "$item" = "WIDTH" ] && { function="calcWidth"; dimName="width"; }
        [ "$item" = "HEIGHT" ] && { function="calcHeight"; dimName="height"; }
        ((i++))
    done
    dim=$($function "$str")
    comm="${*//${dimName^^}/$dim}"
    if [[ $comm != *"3>&1 1>&2 2>&3" ]]; then
        comm="${comm} 3>&1 1>&2 2>&3"
    fi
    commOutput=$(eval "$comm")
    exitStatus=$?
    [ -n "$commOutput" ] && echo "$commOutput"
    return $exitStatus
}

calcWidth() {
    str=$1; count=1; found=false; option=1
    for (( i = 0; i < ${#str}; i++ )); do
        if [ "${str:$i:1}" = "\\" ] && [ "${str:$((i+1)):1}" = "n" ]; then
            [ $count -ge $option ] && option=$count
            found=true
            count=-1
        fi
        ((count++))
    done
    [ $option -ge $count ] && count=option
    echo $((count+3))
}

calcHeight() {
    newlines=$(printf "$1" | grep -c $'\n')
    chars=$(echo "$1" | wc -c)
    height=$(echo "$chars" "$newlines" | awk '{
        x = (($1 - $2 + ($2 * 60)) / 60)
        printf "%d", (x == int(x)) ? x : int(x) + 1
    }')
    echo $((4+height))
}

askForPassword() {
    password=$(calcAndRun dialog --insecure --passwordbox "\"\nNow, enter the password for $1.\"" 10 WIDTH)
    exitIfCancel "You must enter a password."
    passwordRep=$(dialog --insecure --passwordbox "\nReenter password." 10 30 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a password."
    while ! [ "$password" = "$passwordRep" ]; do
        password=$(dialog --insecure --passwordbox "\nPasswords do not match! Please enter the password again." 10 60 3>&1 1>&2 2>&3)
        exitIfCancel "You must enter a password."
        passwordRep=$(dialog --insecure --passwordbox "\nReenter password." 10 30 3>&1 1>&2 2>&3)
        exitIfCancel "You must enter a password."
    done
    unset passwordRep
}

setRootPassword() {
    askForPassword "root" "setRootPassword"
    runInChroot "echo \"root:${password}\" | chpasswd" 2>&1 | debug
    unset password
}

updateMirrors() {
    msg="\nNow, we will update the mirror list by taking the most recently synchronized HTTPS mirrors sorted by download rate."
    dialog --msgbox "$msg" 9 59
    dialog --yesno "\nWould you like to choose your closest countries to narrow the search?" 8 55
    if [ $? -eq 0 ]; then
        printWaitBox
        systemctl stop reflector.service
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
        curl -o /etc/pacman.d/mirrorlist.pacnew https://archlinux.org/mirrorlist/all/ 2>&1 | debug
        local IFS=$'\n'
        setDelimiters "" "OFF"
        formatOptions <(grep '^##' /etc/pacman.d/mirrorlist.pacnew | cut -d' ' -f2- | sed -n '5~1p')
        countries=$(dialog --checklist "\nSelect your closest countries." 25 38 19 "${options[@]}" 3>&1 1>&2 2>&3)
        [ -z "$countries" ] && printAndExit "You must select at least one country."
        countriesFmt=$(echo "$countries" | sed -r 's/" "/,/g')
        printWaitBox
        reflector --country "${countriesFmt//\"/}" --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>&1 | debug
    else
        checkForSystemdUnit "mirrors update" "reflector.service" "oneshot"
    fi
}

grubSetUp() {
    printWaitBox
    [ -z $bootPath ] && tryLoadVar "bootPath"
    runInChroot "grub-install --target=x86_64-efi --efi-directory=${bootPath} --bootloader-id=GRUB"
    runInChroot "grub-mkconfig -o /boot/grub/grub.cfg" 2>&1 | debug
}

saveVar() {
    [ ! -f "calsais.vars" ] && touch calsais.vars
    if ! grep "$1" calsais.vars; then
        echo "$1=$2" >> calsais.vars
    else
        sed -i "s|$1=.*|$1=$2|" calsais.vars
    fi
}

loadVar() {
    var=$(grep "$1=" calsais.vars | cut -d= -f2)
    export "$1"="$var"
}

tryLoadVar() {
    loadVar "$1"
    if [ -z "${!1}" ]; then
        calcAndRun dialog --msgbox "\"\nCouldn't load '$1'. Try to run the script again.\"" 7 WIDTH
        rm -f calsais.vars
        exit 1
    fi
}

userSetUp() {
    username=$(dialog --inputbox "Enter the new username." 10 30 3>&1 1>&2 2>&3) && saveVar "username" "$username"
    exitIfCancel "You must enter an username."
    askForPassword "${username}" "userSetUp"
    runInChroot "useradd -m ${username};echo \"${username}:${password}\" | chpasswd; usermod -aG wheel ${username}"
    runInChroot "sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers"
    checkSudoers
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

checkSudoers() {
    runInChroot "visudo -c" 2>&1 | debug
    if [ $? -ne 0 ]; then
        dialog --msgbox "\nSudoers check failed. Try to run the script again." 7 54
        cp /etc/sudoers /mnt/etc/sudoers
        exit 1
    fi
}

installOtherPackages() {
    msg="\nNow, we will install a few more packages (in the background). Press OK and wait (it may take some time)."
    dialog --msgbox "$msg" 8 59
    [ -z "$username" ] && tryLoadVar "username"
    getThePackages "S" "installOtherPackages"
    checkForParu
    getThePackages "N" "installOtherPackages"
    getThePackages "R" "installOtherPackages"
    runInChroot "sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers"
    checkSudoers
}

finishInstallation() {
    cp calsais /mnt/usr/bin/calsais
    echo "sh /usr/bin/calsais && logout" >> /mnt/home/slococo/.bashrc
    rm -f /mnt/cocoScript
    umount -R /mnt
    dialog --yesno "\nFinally, the PC needs to restart, would you like to restart now?" 8 47
    if [ $? -eq 0 ]; then
        reboot
    else
        clear
    fi
}

getDotfiles() {
    lastFolder=$(pwd -P)
    cd "$HOME/Documents" || printAndExit "Couldn't cd into $HOME/Documents"
    git clone https://github.com/santilococo/cdotfis.git 2>&1 | debug
    cd cdotfis || printAndExit "Couldn't cd into ./cdotfis"
    sh sadedot/scripts/bootstrap.sh
    cd "$lastFolder" || printAndExit "Couldn't cd into $lastFolder"

    sudo rm -f ~/.bashrc /usr/bin/calsais
    mkdir -p "$HOME/.cache/zsh"
    touch "$HOME/.cache/zsh/.histfile"
    chsh -s "$(which zsh)"
}

checkForSystemdUnit() {
    trap 'systemctl stop ${2}; forceExit=true' INT
    if [ "${3}" = "oneshot" ]; then
        [ "$(systemctl show -p ActiveState --value "${2}")" = "inactive" ] && return
    else
        systemctl is-active --quiet "${2}" && return
    fi
    forceExit=false
    calcAndRun dialog --infobox "\"\nWaiting for the ${1} to finish. Please wait.\"" 5 WIDTH
    if [ "${3}" = "oneshot" ]; then
        while [ $forceExit = false ]; do
            result=$(systemctl show -p ActiveState --value "${2}")
            [ "$result" = "inactive" ] && break
            sleep 1
        done
    else
        systemctl is-active --quiet "${2}"
        while [ $? -ne 0 ] && [ $forceExit = false ]; do
            sleep 1
            systemctl is-active --quiet "${2}"
        done
    fi
    trap - INT
}

printStepIfDebug() {
    if [ "$debugFlagToFile" = true ] || [ "$debugFlag" = true ]; then
        printf '\n%s\n%s\n%s\n' "============================================================" "$step" \
        "============================================================" >> calsais.log
    fi
}

steps=(
    checkUefi
    updateSystemClock
    partDisks
    updateMirrors
    installImportantPackages
    generateFstab
    setTimeZone
    setLocale
    networkConf
    setRootPassword
    grubSetUp
    userSetUp
    installOtherPackages
    finishInstallation
)

usage() {
    cat << EOF
usage: ${0##*/} [command]
    -h      Print this help message.
    -d      Print log to stdout and calsais.log file.
    -f      Print log to calsais.log file.
    -s      Print log to stdout.
EOF
}

runScript() {
    debugFlag=false; debugFlagToFile=false; debugFlagToStdout=false
    while getopts ':hdfs' flag; do
        case $flag in
            h)  usage && exit 0 ;;
            d)  debugFlag=true ;;
            f)  debugFlagToFile=true ;;
            s)  debugFlagToStdout=true ;;
            ?)  printf '%s: invalid option -''%s'\\n "${0##*/}" "$OPTARG" && exit 1 ;;
        esac
    done

    clear
    if [ -d "$HOME/Documents" ]; then
        dialog --title "calsais" --msgbox "\nNow, we will finish the installation. Press OK and wait." 7 60
        getDotfiles
        dialog --title "calsais" --msgbox "\nAll done!" 7 15
        exit 0
    fi

    if [ ! -f "/etc/dialogrc" ]; then
        curl -LO "https://raw.githubusercontent.com/santilococo/calsais/master/.dialogrc" 2>&1 | debug
        mv .dialogrc /etc/dialogrc
    fi

    i=0; found=false
    loadVar "lastStep"
    if [ -n "$lastStep" ]; then
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
        welcomeMsg="Welcome back to calsais!"
    else
        systemctl stop reflector.service
        checkForSystemdUnit "systemd units" "graphical.target"
        systemctl --no-block start reflector.service
        welcomeMsg="Welcome to calsais!"
        echo "Please wait..."
        pacman -Sy --needed --noconfirm dialog
        clear
    fi

    calcAndRun dialog --title "calsais" --msgbox "\"\n${welcomeMsg}\"" 7 WIDTH

    while [ $i -lt "${#steps[@]}" ]; do
        step=${steps[$i]}
        printStepIfDebug
        saveVar "lastStep" "$step"
        $step
        ((i++))
    done
}

umountAndClean() {
    swapoff /mnt/swapfile
    rm /mnt/swapfile
    umount -R /mnt
    swapoff /dev/sda2
    parted -s /dev/sda mklabel gpt
}

runScript "$@"
