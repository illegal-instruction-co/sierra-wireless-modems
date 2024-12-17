#!/bin/bash
# shellcheck disable=SC2059
#
#.USAGE
# To start, run:
# sudo bash autoflash-7455.sh

#.NOTES
# License: The Unlicense / CCZero / Public Domain
# Author: Daniel Wood / https://github.com/danielewood

# Simplified by: machinetherapist - illegal-instruction

##################
### Pre-Checks ###
##################

if [ "$EUID" -ne 0 ] then
    echo "[ERROR]"
    echo "Please run with sudo"
    exit
fi

if [[ $(lsb_release -r | awk '{print ($2 >= "20.04")}') -eq 0 ]]; then
    echo "[ERROR]"
    echo "Please run on Ubuntu 20.04 (Focal Fossa) or later"
    lsb_release -a
    exit
fi

#################
### Functions ###
#################

# If no options are set, use defaults of -Mgcdfs
if [[ -z $get_modem_settings_trigger && -z $clear_modem_firmware_trigger \
    && -z $flash_modem_firmware_trigger \
    && -z $set_modem_settings_trigger && -z $set_swi_setusbcomp_trigger ]]; then
        all_functions_trigger=1
fi

if [[ all_functions_trigger -eq 1 ]]; then
  get_modem_settings_trigger=1
  clear_modem_firmware_trigger=1
  flash_modem_firmware_trigger=1
  set_modem_settings_trigger=1
  set_swi_setusbcomp_trigger=1
fi

function set_options() {
    # See if QMI desired, otherwise default to MBIM
    if [[ ${AT_USBCOMP^^} =~ ^QMI$|^6$ ]]; then
        echo 'Setting QMI Mode for Modem'
        echo 'Interface bitmask: 0000010D (diag,nmea,modem,rmnet0)'
        AT_USBCOMP="1,1,0000010D"
        swi_usbcomp='6'
    else
        echo 'Setting MBIM Mode for Modem'
        echo 'Interface bitmask: 0000100D (diag,nmea,modem,mbim)'
        AT_USBCOMP="1,1,0000100D"
        swi_usbcomp='8'
    fi

    # Check for ALL/00 bands and set correct SELRAT/BAND, otherwise default to LTE
    if [[ ${AT_SELRAT^^} =~ ^ALL$|^0$|^00$ ]]; then
        AT_SELRAT='00'
        AT_BAND='00'
    else
        AT_SELRAT='06'
        AT_BAND='09'
    fi

    # Check if valid FASTENUMEN mode, otherwise default to 2
    if [[ ! $AT_FASTENUMEN =~ ^[0-3]$ ]]; then
        AT_FASTENUMEN=2
    fi

    #FASTENUMEN_MODES="0 = Disable fast enumeration [Default]
    #1 = Enable fast enumeration for cold boot and disable for warm boot
    #2 = Enable fast enumeration for warm boot and disable for cold boot
    #3 = Enable fast enumeration for warm and cold boot"
    #echo '"FASTENUMEN"—Enable/disable fast enumeration for warm/cold boot.'
    #echo -n 'Set mode: ' && echo "$FASTENUMEN_MODES" | grep -E "^$AT_FASTENUMEN"

    # Check desired USB interface mode, otherwise default to 0 (USB 2.0)
    if [[ ${AT_USBSPEED^^} =~ SUPER|USB3|1 ]]; then
        AT_USBSPEED=1
    else
        AT_USBSPEED=0
    fi
}

function get_modem_deviceid() {
    max_attempts=10
    deviceid=''
    while [ -z $deviceid ]
    do
        max_attempts=$((max_attempts-1))
        if [ $max_attempts -eq 0 ]; then
            echo "[ERROR]"
            echo "Could not find modem device ID, exiting..."
            exit
        fi
        echo 'Waiting for modem to reboot...'
        sleep 3
        deviceid=$(lsusb | grep -i -E '1199:9071|1199:9079|413C:81B6' | awk '{print $6}')
    done
    sleep 3
    ttyUSB=$(dmesg | grep '.3: Qualcomm USB modem converter detected' -A1 | grep -Eo 'ttyUSB[0-9]$' | tail -1)
    devpath=$(find /dev -maxdepth 1 -regex '/dev/cdc-wdm[0-9]' -o -regex '/dev/qcqmi[0-9]')
}

function get_modem_deviceid_safe() {
    deviceid=''
    while [ -z $deviceid ]
    do
        echo 'Waiting for modem to reboot...'
        sleep 3
        deviceid=$(lsusb | grep -i -E '1199:9071|1199:9079|413C:81B6' | awk '{print $6}')
    done
    sleep 3
    ttyUSB=$(dmesg | grep '.3: Qualcomm USB modem converter detected' -A1 | grep -Eo 'ttyUSB[0-9]$' | tail -1)
    devpath=$(find /dev -maxdepth 1 -regex '/dev/cdc-wdm[0-9]' -o -regex '/dev/qcqmi[0-9]')
}

function get_modem_bootloader_deviceid() {
    max_attempts=100
    deviceid=''
    while [ -z $deviceid ]
    do
        max_attempts=$((max_attempts-1))
        if [ $max_attempts -eq 0 ]; then
            echo "[ERROR]"
            echo "Device could not switch to bootloader mode, exiting..."
            exit
        fi
        echo 'Waiting for modem in boothold mode...'
        sleep 2
        deviceid=$(lsusb | grep -i -E '1199:9070|1199:9078|413C:81B5' | awk '{print $6}')
    done
    echo "Found $deviceid"
}

function reset_modem {
    get_modem_deviceid

    # Reset Modem
    echo 'Reseting modem...'
    ./swi_setusbcomp.pl --usbreset --device="$devpath" &>/dev/null
}

function get_modem_settings() {
    # cat the serial port to monitor output and commands. cat will exit when AT!RESET kicks off.
    sudo cat /dev/"$ttyUSB" 2>&1 | tee -a modem.log &  

    # Display current modem settings
    echo 'Current modem settings:'
    echo 'send AT
send ATE1
sleep 1
send ATI
sleep 1
send AT!ENTERCND=\"A710\"
sleep 1
send AT!IMPREF?
sleep 1
send AT!GOBIIMPREF?
sleep 1
send AT!USBSPEED?
sleep 1
send AT!USBSPEED=?
sleep 1
send AT!USBCOMP?
sleep 1
send AT!USBCOMP=?
sleep 1
send AT!USBVID?
sleep 1
send AT!USBPID?
sleep 1
send AT!USBPRODUCT?
sleep 1
send AT!PRIID?
sleep 1
send AT!SELRAT?
sleep 1
send AT!BAND?
sleep 1
send AT!BAND=?
sleep 1
send AT!PCINFO?
sleep 1
send AT!PCOFFEN?
sleep 1
send AT!CUSTOM?
sleep 1
send AT!IMAGE?
sleep 1
! pkill cat
sleep 1
! pkill minicom
' > script.txt
    sudo minicom -b 115200 -D /dev/"$ttyUSB" -S script.txt &>/dev/null
}

function clear_modem_firmware() {
    # cat the serial port to monitor output and commands. cat will exit when AT!RESET kicks off.
    sudo cat /dev/"$ttyUSB" 2>&1 | tee -a modem.log &  
    # Clear Previous PRI/FW Entries
    echo 'send AT
send AT!IMAGE=0
sleep 1
send AT!IMAGE?
sleep 1
! pkill cat
sleep 1
! pkill minicom
' > script.txt
    sudo minicom -b 115200 -D /dev/"$ttyUSB" -S script.txt &>/dev/null
}

function flash_modem_firmware() {
    # Kill cat processes used for monitoring status, if it hasnt already exited
    sudo pkill -9 cat &>/dev/null

    echo "Flashing $SWI9X30C_CWE onto Generic Sierra Modem..."
    sleep 5
    qmi-firmware-update --reset -d "$deviceid"
    get_modem_bootloader_deviceid
    qmi-firmware-update --update-download -d "$deviceid" "$SWI9X30C_CWE" "$SWI9X30C_NVU"
    rc=$?
    if [[ $rc != 0 ]]
    then
        echo "[ERROR]"
        echo "Firmware Update failed, exiting..."
        exit $rc
    fi
}

function set_modem_settings() {
    dmesg -c
    sleep 3
    demsg
    max_attempts=100
    while [ ! -e /dev/"$ttyUSB" ]
    do
        max_attempts=$((max_attempts-1))
        if [ $max_attempts -eq 0 ]; then
            echo "[ERROR]"
            echo "Could not find modem serial port for settings, exiting..."
            exit
        fi
        echo 'Waiting for modem to reboot...'
        get_modem_deviceid_safe
        sleep 3
    done

    # cat the serial port to monitor output and commands. cat will exit when AT!RESET kicks off.
    sudo cat /dev/"$ttyUSB" 2>&1 | tee -a modem.log &  

    # Set Generic Sierra Wireless VIDs/PIDs
    cat <<EOF > script.txt
send AT
sleep 1
send ATE1
sleep 1
send ATI
sleep 1
send AT!ENTERCND=\"A710\"
sleep 1
send AT!IMPREF=\"GENERIC\"
sleep 1
send AT!GOBIIMPREF=\"GENERIC\"
sleep 1
send AT!USBCOMP=$AT_USBCOMP
sleep 1
send AT!USBVID=1199
sleep 1
send AT!USBPID=9071,9070
sleep 1
send AT!USBPRODUCT=\"EM7455\"
sleep 1
send AT!PRIID=\"$AT_PRIID_PN\",\"$AT_PRIID_REV\",\"Generic-Laptop\"
sleep 1
send AT!SELRAT=$AT_SELRAT
sleep 1
send AT!BAND=$AT_BAND
sleep 1
send AT!CUSTOM=\"FASTENUMEN\",$AT_FASTENUMEN
sleep 1
send AT!PCOFFEN=2
sleep 1
send AT!PCOFFEN?
sleep 1
send AT!USBSPEED=$AT_USBSPEED
sleep 1
send AT!USBSPEED?
sleep 1
send AT!USBSPEED=?
sleep 1
send AT!CUSTOM?
sleep 1
send AT!IMAGE?
sleep 1
send AT!PCINFO?
sleep 1
send AT!RESET
! pkill minicom
EOF
    sudo minicom -b 115200 -D /dev/"$ttyUSB" -S script.txt &>/dev/null
}

function script_prechecks() {
    echo 'Searching for EM7455/MC7455 USB modems...'
    modemcount=$(lsusb | grep -c -i -E '1199:9071|1199:9079|413C:81B6')
    max_attempts=10
    while [ $modemcount -eq 0 ]
    do
        max_attempts=$((max_attempts-1))

        if [ $max_attempts -eq 0 ]; then
            echo "[ERROR]"
            echo "Could not find any EM7455/MC7455 USB modems, exiting..."
            exit
        fi

        echo "Could not find any EM7455/MC7455 USB modems"
        echo 'Unplug and reinsert the EM7455/MC7455 USB connector...'
        modemcount=$(lsusb | grep -c -i -E '1199:9071|1199:9079|413C:81B6')
        sleep 3
    done

    echo "Found EM7455/MC7455: 
    $(lsusb | grep -i -E '1199:9071|1199:9079|413C:81B6')
    "

    if [ "$modemcount" -gt 1 ] then 
        echo "[ERROR]"
        echo "Found more than one EM7455/MC7455, remove the one you dont want to flash and try again."
        exit
    fi

    # Stop modem manager to prevent AT command spam and allow firmware-update
    echo 'Stoping modem manager to prevent AT command spam and allow firmware-update, this may take a minute...'
    systemctl stop ModemManager &>/dev/null
    systemctl disable ModemManager &>/dev/null

    # Use cpan to install/compile all dependencies needed by swi_setusbcomp.pl
    yes | cpan install UUID::Tiny IPC::Shareable JSON

    # Install Modem Mode Switcher
    if [ ! -f swi_setusbcomp.pl ]; then
        wget https://git.mork.no/wwan.git/plain/scripts/swi_setusbcomp.pl
    fi
    chmod +x ./swi_setusbcomp.pl

    reset_modem
}

function set_swi_setusbcomp() {
    # Modem Mode Switch to usbcomp=8 (DM   NMEA  AT    MBIM)
    echo "Running Modem Mode Switch to usbcomp=$swi_usbcomp"
    ./swi_setusbcomp.pl --usbcomp=$swi_usbcomp --device="$devpath"
    reset_modem


    # cat the serial port to monitor output and commands.
    sudo cat /dev/"$ttyUSB" 2>&1 | tee -a modem.log &  

    # Set Generic Sierra Wireless VIDs/PIDs
    cat <<EOF > script.txt
send AT
sleep 1
send AT!ENTERCND=\"A710\"
sleep 1
send AT!USBCOMP=$AT_USBCOMP
sleep 1
send AT!RESET
! pkill cat
sleep 1
! pkill minicom
EOF
    sudo minicom -b 115200 -D /dev/"$ttyUSB" -S script.txt &>/dev/null

   get_modem_deviceid
}

function script_cleanup() {
    # Restart ModemManager
    systemctl enable ModemManager &>/dev/null
    systemctl start ModemManager &>/dev/null

    echo "Done!"

    # Kill cat processes used for monitoring status, if it hasnt already exited
    sudo pkill -9 cat &>/dev/null

    rm -f script.txt modem.log serial.log
}

########################
### Script Execution ###
########################

if [[ $quiet_trigger ]]; then
    script_prechecks &>/dev/null
else
    script_prechecks
fi

set_options

devpath=$(find /dev -maxdepth 1 -regex '/dev/cdc-wdm[0-9]' -o -regex '/dev/qcqmi[0-9]')

if [[ $set_swi_setusbcomp_trigger ]]; then
    set_swi_setusbcomp
fi

get_modem_deviceid

[[ $get_modem_settings_trigger ]] && get_modem_settings

if [[ $clear_modem_firmware_trigger ]]; then
  clear_modem_firmware
  get_modem_deviceid
fi

SWI9X30C_CWE="./flash/firmware/SWI9X30C.cwe"
SWI9X30C_NVU="./flash/firmware/SWI9X30C.nvu"

AT_PRIID_STRING=$(strings "$SWI9X30C_NVU" | grep '^9999999_.*_SWI9X30C_' | sort -u | head -1)
AT_PRIID_PN="$(echo "$AT_PRIID_STRING" | awk -F'_' '{print $2}')"
AT_PRIID_REV="$(echo "$AT_PRIID_STRING" | grep -Eo '[0-9]{3}\.[0-9]{3}')"

[[ $flash_modem_firmware_trigger ]] && flash_modem_firmware
[[ $set_modem_settings_trigger ]] && set_modem_settings

script_cleanup

# Done
