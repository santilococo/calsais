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
        printAndExit "This scripts supports only UEFI boot mode."
    fi
}

updateSystemClock() {
    timedatectl set-ntp true
}

printAndExit() {
    str="${1} Therefore, the installation process will stop, but you can continue where you left off by running:\n\nsh calsais"
    calcHeightAndRun "whiptail --msgbox \"${str}\" HEIGHT 60"
    exit 1
}

exitIfCancel() {
    [ $? -eq 1 ] && printAndExit "$@"
}

printWaitBox() {
    whiptail --infobox "Please wait..." 7 19
}

partDisks() {
    whiptail --yesno "Do you want me to automatically partition and format a disk for you?" 0 0
    whipStatus=$?

    local IFS=$'\n'
    setDelimiters ""
    formatOptions $(lsblk -dpnlo NAME,SIZE -e 7,11)
    result=$(whiptail --title "Select the disk." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a disk."
    disk=$(echo "$result" | cut -d' ' -f1)

    if [ $whipStatus -eq 1 ]; then
        autoSelection=false
        calcHeightAndRun "whiptail --msgbox \"You will partition the disk yourself and then, when finished, you will continue with the installation.\" HEIGHT 58"
        partPrograms=("fdisk" "" "sfdisk" "" "cfdisk" "" "gdisk" "" "cgdisk" "" "sgdisk" "")
        partTool=$(whiptail --title "Select the partitioning tool." --menu "" 0 0 0 "${partPrograms[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select a partitioning tool."
        $partTool "$disk"
        parts=$(lsblk "$disk" -pnl | sed -n '2~1p' | wc -l)
        [ "$parts" -lt 2 ] && printAndExit "You must at least create boot and root partitions."

        # TODO: Ask for home partition
        formatOptions $(lsblk "${disk}" -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p')
        result=$(whiptail --title "Select the boot partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the boot partition."
        bootPart=$(echo "$result" | cut -d' ' -f1)
        formatOptions $(lsblk "${disk}" -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p' | awk '$0!~v' v="$bootPart")
        result=$(whiptail --title "Select the root partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select the root partition."
        rootPart=$(echo "$result" | cut -d' ' -f1)

        parts=$(lsblk "$disk" -pnl | sed -n '2~1p' | awk '$0!~v' v="$bootPart|$rootPart" | wc -l)
        if [ "$parts" -gt 0 ]; then
            whiptail --yesno "Do you have a swap partition?" 0 0
            if [ $? -eq 0 ]; then
                formatOptions $(lsblk "${disk}" -pnlo NAME,SIZE,MOUNTPOINTS | sed -n '2~1p' | awk '$0!~v' v="$bootPart|$rootPart")
                result=$(whiptail --title "Select the swap partition." --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
                exitIfCancel "You must select the swap partition."
                swapPart=$(echo "$result" | cut -d' ' -f1)
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
    sizeStr=$(whiptail --inputbox "Enter the size of the ${1} (in GB, for example 1.5GB)." 0 0 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a size."
    size=$(echo "$sizeStr" | grep -Eo '[-]?[0-9]+([.,]?[0-9]+)?' | head -n1 | sed 's/,/./g' | awk '{ print int($1 * 1024) }')
    while [ "$(echo "$size" | awk '{ print $1 <= 0 }')" -eq 1 ]; do
        sizeStr=$(whiptail --inputbox "The size must be a number and cannot be less than or equal to zero. Please enter a new size." 9 60 3>&1 1>&2 2>&3)
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
        result=$(whiptail --title "Select where to mount boot partition." --menu "" 0 0 0 "/boot/efi" "" "/boot" "" "==OTHER==" "" 3>&1 1>&2 2>&3)
        exitIfCancel "You must select a path."
        bootPath=$(echo "$result" | sed 's/^\///g')
        if [ "$result" = "OTHER" ]; then
            local IFS=' '
            result=$(whiptail --inputbox "Enter the absolute path." 0 0 3>&1 1>&2 2>&3)
            exitIfCancel "You must enter a path."
            bootPath=$(echo "$result" | sed 's/^\///g')
            mkdir -p "/mnt/$bootPath"
            while [[ ! -d "/mnt/$bootPath" ]]; do
                result=$(whiptail --inputbox "Path isn't valid. Please try again" 0 0 3>&1 1>&2 2>&3)
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
    calcWidthAndRun "whiptail --infobox \"Installing '$1'.\" 7 WIDTH"
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
        D)
            pkgName=$(echo "${1}" | grep -oP '(?<=/).*?(?=.git)')
            runInChroot "sudo -u $username paru -Q ${pkgName}" 2>&1 | debug
            [ $? -eq 0 ] && return
            runInChroot "cd /tmp; sudo -u $username git clone https://github.com/${1}; cd ${pkgName}; sudo -u $username makepkg -si --noconfirm; cd ..; rm -rf ${pkgName}" 2>&1 | debug
            ;;
        ?)
            printAndExit "INSTALL must be A, B, C or D in packages.csv file."
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
        runInChroot "cd /tmp; sudo -u $username git clone https://aur.archlinux.org/paru-bin.git; cd paru-bin; sudo -u $username makepkg -si --noconfirm; cd ..; rm -rf paru-bin" 2>&1 | debug
    fi
}

getThePackages() {
    set -o pipefail
    if [ ! -f "packages.csv" ]; then
        printWaitBox
        curl -LO "https://raw.githubusercontent.com/santilococo/calsais/master/packages.csv" 2>&1 | debug
    fi
    if [ "$IMPORTANT" = "N" ]; then
        calcHeightAndRun "whiptail --msgbox \"A menu will appear where you can deselect the packages you don't want to be installed.\" HEIGHT 60"
        local IFS=$'\n'
        setDelimiters "" "ON"
        formatOptions $(grep "N" packages.csv | sed -n '2~1p' | cut -d',' -f1)
        packages=$(whiptail --title "Packages" --separate-output --checklist "Press TAB to select Ok or Cancel. If you don't want to install any packages, press Cancel." 28 50 19 "${options[@]}" 3>&1 1>&2 2>&3)
        tempFile=$(mktemp)
        for package in $packages; do
            grep "^$package," packages.csv >> $tempFile
        done
        header=$(head -n1 packages.csv)
        printf '%s\n%s' "$(cat packages.csv | sed -n '2~1p')" "$(cat $tempFile)" | sort | uniq -d > packages.csv
        sed -i "1s/^/${header}\n/" packages.csv
        rm $tempFile
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
    calcHeightAndRun "whiptail --msgbox \"We will continue with the installation of some important packages in the background. Please press OK and wait.\" HEIGHT 60"
    pacman -Sy --noconfirm archlinux-keyring 2>&1 | debug
    getThePackages "Y" "installImportantPackages"
    runInChroot "systemctl enable NetworkManager; systemctl enable fstrim.timer" 2>&1 | debug
}

generateFstab() {
    printWaitBox
    genfstab -U /mnt >> /mnt/etc/fstab
}

setTimeZone() {
    whiptail --msgbox "Now, we will set the timezone." 0 0
    setDelimiters ""
    formatOptions $(ls -l /usr/share/zoneinfo/ | grep '^d' | awk '{printf $9" \n"}' | awk '!/posix/ && !/right/')
    region=$(whiptail --title "Region" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
    exitIfCancel "You must select a region."
    formatOptions $(ls -l "/usr/share/zoneinfo/${region}" | grep -v '^d' | awk '{printf $9" \n"}')
    city=$(whiptail --title "City" --menu "" 0 0 0 "${options[@]}" 3>&1 1>&2 2>&3)
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
    hostname=$(whiptail --inputbox "Enter the hostname." 0 0 3>&1 1>&2 2>&3)
    exitIfCancel "You must enter a hostname."
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
    commOutput=$(eval "$comm")
    exitStatus=$?
    [ -n "$commOutput" ] && echo "$commOutput"
    return $exitStatus
}

calcHeightAndRun() {
    str=$(echo "$@" | grep -oP '(?<=").*?(?=")')
    newlines=$(printf "$str" | grep -c $'\n')
    chars=$(echo "$str" | wc -c)
    height=$(echo "$chars" "$newlines" | awk '{
        x = (($1 - $2 + ($2 * 60)) / 60)
        printf "%d", (x == int(x)) ? x : int(x) + 1
    }')
    comm=$(echo "$@" | sed "s/HEIGHT/$((5+height))/g")
    if [[ $comm != *"3>&1 1>&2 2>&3" ]]; then
        comm="${comm} 3>&1 1>&2 2>&3"
    fi
    commOutput=$(eval "$comm")
    exitStatus=$?
    [ -n "$commOutput" ] && echo "$commOutput"
    return $exitStatus
}

askForPassword() {
    password=$(calcWidthAndRun "whiptail --passwordbox \"Now, enter the password for ${1}.\" 8 WIDTH")
    exitIfCancel "You must enter a password."
    passwordRep=$(calcWidthAndRun "whiptail --passwordbox \"Reenter password.\" 8 WIDTH")
    exitIfCancel "You must enter a password."
    while ! [ "$password" = "$passwordRep" ]; do
        password=$(calcWidthAndRun "whiptail --passwordbox \"Passwords do not match! Please enter the password again.\" 8 WIDTH")
        exitIfCancel "You must enter a password."
        passwordRep=$(calcWidthAndRun "whiptail --passwordbox \"Reenter password.\" 8 WIDTH")
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
    calcHeightAndRun "whiptail --msgbox \"Now, we will update the mirror list by taking the most recently synchronized HTTPS mirrors sorted by download rate.\" HEIGHT 65"
    whiptail --yesno "Would you like to choose your closest countries to narrow the search?" 0 0
    if [ $? -eq 0 ]; then
        printWaitBox
        systemctl stop reflector.service
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
        curl -o /etc/pacman.d/mirrorlist.pacnew https://archlinux.org/mirrorlist/all/ 2>&1 | debug
        local IFS=$'\n'
        setDelimiters "" "OFF"
        formatOptions $(grep '^##' /etc/pacman.d/mirrorlist.pacnew | cut -d' ' -f2- | sed -n '5~1p')
        countries=$(whiptail --title "Countries" --checklist "" 25 40 19 "${options[@]}" 3>&1 1>&2 2>&3)
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
    runInChroot "grub-install --target=x86_64-efi --efi-directory=${bootPath} --bootloader-id=GRUB; grub-mkconfig -o /boot/grub/grub.cfg" 2>&1 | debug
}

saveVar() {
    [ ! -f "calsais.vars" ] && touch calsais.vars
    if [ -z "$(grep "$1" calsais.vars)" ]; then
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
        calcWidthAndRun "whiptail --msgbox \"Couldn't load '$1'. Try to run the script again.\" 7 WIDTH"
        rm -f calsais.vars
        exit 1
    fi
}

userSetUp() {
    username=$(whiptail --inputbox "Enter the new username." 0 0 3>&1 1>&2 2>&3) && saveVar "username" "$username"
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
        calcWidthAndRun "whiptail --msgbox \"Sudoers check failed. Try to run the script again.\" 7 WIDTH"
        cp /etc/sudoers /mnt/etc/sudoers
        exit 1
    fi
}

installOtherPackages() {
    calcHeightAndRun "whiptail --msgbox \"Now, we will install a few more packages (in the background). Press OK and wait (it may take some time).\" HEIGHT 60"
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
    whiptail --yesno "Finally, the PC needs to restart, would you like to restart now?" 0 0
    if [ $? -eq 0 ]; then
        reboot
    else
        clear
    fi
}

getDotfiles() {
    local lastFolder=$(pwd -P)
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
    calcWidthAndRun "whiptail --infobox \"Waiting for the ${1} to finish. Please wait.\" 7 WIDTH"
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
        printf '\n%s' "============================================================" >> calsais.log
        printf '\n%s\n' "$step" >> calsais.log
        printf '%s\n' "============================================================" >> calsais.log
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

runScript() {
    debugFlag=false; debugFlagToFile=false; debugFlagToStdout=false
    while getopts ':hdfs' flag; do
        case $flag in
            h)  printf 'usage: %s [command]\n\t-h\tPrint this help message.\n\t-s\tDebug to stdout and to calsais.log file.\n\t-f\tDebug to calsais.log file.\t-s\tDebug to stdout.\n\n' "${0##*/}" && exit 0 ;;
            d)  debugFlag=true ;;
            f)  debugFlagToFile=true ;;
            s)  debugFlagToStdout=true ;;
            ?)  printf '%s: invalid option -''%s'\\n "${0##*/}" "$OPTARG" && exit 1 ;;
        esac
    done

    clear
    if [ -d "$HOME/Documents" ]; then
        whiptail --title "calsais" --msgbox "Now, we will finish the installation. Press OK and wait." 7 60
        getDotfiles
        whiptail --title "calsais" --msgbox "All done!" 0 0
        exit 0
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
    fi

    whiptail --title "calsais" --msgbox "${welcomeMsg}" 0 0

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
