#!/bin/bash
#
# Create SD card #2
# for configuring freshly flashed OpenIPC firmware
# on a Wyze Cam V3 camera
#
# 2023 Paul Philippov, paul@themactep.com
#

show_help_and_exit() {
    echo "Usage: $0 -d <SD card device>"
    if [ "$EUID" -eq 0 ]; then
        echo -n "Detected devices: "
        fdisk -x | grep -B1 'SD/MMC' | head -1 | awk '{print $2}' | sed 's/://'
    fi
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    show_help_and_exit
fi

# command line arguments
while getopts d: flag; do
    case ${flag} in
        d) card_device=${OPTARG} ;;
    esac
done

[ -z "$card_device" ] && show_help_and_exit

echo "Please select your camera model"
select ret in "AtomCam 2" "Hualai HL-CAM04" "Wyze Cam V3" "Wyze Doorbell"; do
    case $ret in
        "AtomCam 2"|"Wyze Cam V3"|"Wyze Doorbell")
            camdev="wyze-v3"
            break
            ;;
        "Hualai HL-CAM04")
            camdev="hl-cam04"
            sensor_modline="ingenic/sensor_sc3335_t31.ko: ingenic/tx-isp-t31.ko"
            break
            ;;
        *)
            echo "Please select one of the available options."
    esac
done

echo "Please select your wireless module"
select ret in "AltoBeam" "Realtek"; do
    case $ret in
        AltoBeam)
            wlandev="atbm603x-t31-wyze-v3"
            wlanmod="hal_apollo/atbm603x_wifi_sdio.ko"
            wlan_modline="extra/hal_apollo/atbm603x_wifi_sdio.ko: kernel/net/wireless/cfg80211.ko"
            break
            ;;
        Realtek)
            wlandev="rtl8189ftv-t31-wyze-v3"
            wlanmod="8189fs.ko"
            wlan_modline="extra/8189fs.ko: kernel/net/wireless/cfg80211.ko"
            break
            ;;
        *)
            echo "Please select one of the available options."
    esac
done

echo

while [ -z "$wlanssid" ]; do
    read -p "Enter Wireless network SSID: " wlanssid
done

while [ -z "$wlanpass" ]; do
    read -p "Enter Wireless network password: " wlanpass
done

echo

if [ ! -e "$card_device" ]; then
    echo "Device $card_device not found."
    exit 2
fi

while mount | grep $card_device > /dev/null; do
    umount $(mount | grep $card_device | awk '{print $1}')
done

read -p "All existing information on the card will be lost! Proceed? [Y/N]: " ret
if [ "$ret" != "Y" ]; then
    echo "Aborting!"
    exit 99
fi

echo "Creating a 64MB FAT32 partition on the SD card."
parted -s ${card_device} mklabel msdos mkpart primary fat32 1MB 64MB && \
    sleep 3 && \
    mkfs.vfat ${card_device}1 > /dev/null
if [ $? -ne 0 ]; then
    echo "Cannot create a partition."
    exit 3
fi

sdmount=$(mktemp -d)

echo "Mounting the partition to ${sdmount}."
if ! mkdir -p $sdmount; then
    echo "Cannot create ${sdmount}."
    exit 4
fi

if ! mount ${card_device}1 $sdmount; then
    echo "Cannot mount ${card_device}1 to ${sdmount}."
    exit 5
fi

echo "Copying files."
cp -r $(dirname $0)/files ${sdmount}/
mkdir -p $(dirname ${sdmount}/files/lib/modules/3.10.14__isvp_swan_1.0__/extra/${wlanmod})
cp $(dirname $0)/extra/${wlanmod} ${sdmount}/files/lib/modules/3.10.14__isvp_swan_1.0__/extra/${wlanmod}

echo "Creating installation script."
echo "#!/bin/sh

fw_setenv wlandev \"${wlandev}\"
fw_setenv wlanssid \"${wlanssid}\"
fw_setenv wlanpass \"${wlanpass}\"

cp -rv \$(dirname \$0)/files/* /
[ -n \"$sensor_modline\" ] && echo \"${sensor_modline}\" | tee -a /lib/modules/3.10.14__isvp_swan_1.0__/modules.dep
[ -n \"$wlan_modline\" ] && echo \"${wlan_modline}\" | tee -a /lib/modules/3.10.14__isvp_swan_1.0__/modules.dep

echo \"
Configuration is done.

Please remove the SD card from the SD card slot of the camera
then restart the camera by disconnecting the USB power supply
and UART adapter, and reconnecting power back after 5 seconds.
\"
" > ${sdmount}/install.sh

echo "Unmounting the SD partition."
sync
umount $sdmount
eject $card_device

echo "
Card #2 created successfully.
The card is unmounted. You can safely remove it from the slot.

To install extra scripts, the wireless driver and perform basic
configuration, place the card into the camera and execute the
/mnt/mmcblk0p1/install.sh script.
"

exit 0
