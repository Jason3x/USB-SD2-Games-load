#!/bin/bash

# --- Verification root ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

# --- Configuration ---
ROM_PATH="/roms"
INTERNAL_DEV="/dev/mmcblk0p3"
INTERNAL_MNT="/tmp/sd1"
USB_DEV="/dev/sda1"
SD2_DEV="/dev/mmcblk1p1"
TMP_CHECK_MNT="/tmp/usb_check"
FILES_LOG_NAME=".usb_added_files.log"
SERVICE_NAME="usb-games-monitor"
SCRIPT_PATH="$(readlink -f "$0")"

# --- Installation du service ---
if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    clear
    echo "=================================================="
    echo "      USB & SD2 GAMES By SjslTech & Jason             "
    echo "=================================================="
    sleep 2
    
    echo "Step 1: Creating the background service..."
    sleep 2
    cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=USB and SD2 Auto-Mount Service
After=multi-user.target

[Service]
Type=simple
ExecStart="$SCRIPT_PATH" --run
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    echo "Step 2: Enabling the service at boot..."
    sleep 2
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME.service
    systemctl start $SERVICE_NAME.service
    
    echo "--------------------------------------------------"
    echo "SUCCESS: The service is now installed and active!"
    echo "=================================================="
    sleep 3
    exit 0
fi

# --- Nettoyage ---
cleanup_internal_storage() {
    local TARGET_MNT=$1
    local LOG_FILE="$TARGET_MNT/$FILES_LOG_NAME"

    if [ -f "$LOG_FILE" ]; then
        echo ">>> Found persistent log. Cleaning up added files..."
        while read -r rel_path; do
            if [ -n "$rel_path" ]; then
                rm -f "$TARGET_MNT/$rel_path"
            fi
        done < "$LOG_FILE"
        rm -f "$LOG_FILE"
        find "$TARGET_MNT/themes" "$TARGET_MNT/tools" "$TARGET_MNT/Tools" -type d -empty -delete 2>/dev/null
        echo ">>> Cleanup complete."
    fi
}

# --- Remet SD1 en fonction ---
mount_internal_to_roms() {
    echo ">>> Restoring internal SD games to $ROM_PATH..."
    umount -l "$ROM_PATH" 2>/dev/null
    mkdir -p "$ROM_PATH"
    mount "$INTERNAL_DEV" "$ROM_PATH"
  
    cleanup_internal_storage "$ROM_PATH"
}

# --- Montage de l'USB/SD2 ---
do_mount() {
    local SOURCE_DEV=$1
    local FSTYPE=$(blkid -o value -s TYPE "$SOURCE_DEV")
    
    local OPTS="rw"
    if [[ "$FSTYPE" =~ ^(vfat|exfat|ntfs)$ ]]; then
        OPTS="rw,uid=1000,gid=1000,umask=000"
    fi

    mkdir -p "$TMP_CHECK_MNT"
    umount -l "$TMP_CHECK_MNT" 2>/dev/null
    
    if mount -t "$FSTYPE" -o "$OPTS" "$SOURCE_DEV" "$TMP_CHECK_MNT"; then
        if [ -d "$TMP_CHECK_MNT/Tools" ] || [ -d "$TMP_CHECK_MNT/tools" ] || [ -d "$TMP_CHECK_MNT/themes" ]; then
            umount -l "$TMP_CHECK_MNT"
        else
            umount -l "$TMP_CHECK_MNT"
            return 1
        fi
    else
        return 1
    fi

    umount -l "$ROM_PATH" 2>/dev/null

    if mount -t "$FSTYPE" -o "$OPTS" "$SOURCE_DEV" "$ROM_PATH"; then
        echo ">>> External Mount successful!"

        mkdir -p "$INTERNAL_MNT"
        umount -l "$INTERNAL_MNT" 2>/dev/null
        mount "$INTERNAL_DEV" "$INTERNAL_MNT" 2>/dev/null

        cleanup_internal_storage "$INTERNAL_MNT"

        local LOG_PATH="$INTERNAL_MNT/$FILES_LOG_NAME"
        echo "" > "$LOG_PATH"
        
        for dir in "themes" "tools" "Tools"; do
            if [ -d "$ROM_PATH/$dir" ]; then
                find "$ROM_PATH/$dir" -type f | while read -r src_file; do
                    rel_path="${src_file#$ROM_PATH/}"
                    if [ ! -f "$INTERNAL_MNT/$rel_path" ]; then
                        echo "$rel_path" >> "$LOG_PATH"
                    fi
                done
                cp -rn "$ROM_PATH/$dir" "$INTERNAL_MNT/" 2>/dev/null
            fi
        done

        mount --bind "$INTERNAL_MNT/themes" "$ROM_PATH/themes" 2>/dev/null
        mount --bind "$INTERNAL_MNT/tools" "$ROM_PATH/tools" 2>/dev/null
        mount --bind "$INTERNAL_MNT/Tools" "$ROM_PATH/Tools" 2>/dev/null
        
        systemctl restart emulationstation
        return 0
    fi
    return 1
}

# --- Démontage ---
do_unmount() {
    echo ">>> External device removed!"
    umount -l "$ROM_PATH/themes" 2>/dev/null
    umount -l "$ROM_PATH/tools" 2>/dev/null
    umount -l "$ROM_PATH/Tools" 2>/dev/null
    umount -l "$ROM_PATH" 2>/dev/null

    cleanup_internal_storage "$INTERNAL_MNT"

    umount -l "$INTERNAL_MNT" 2>/dev/null
    mount_internal_to_roms
    systemctl restart emulationstation
}

# --- Surveillance ---
run_monitor() {
    local CURRENTLY_MOUNTED=""
 
    mkdir -p "$INTERNAL_MNT"
    mount "$INTERNAL_DEV" "$INTERNAL_MNT" 2>/dev/null
    cleanup_internal_storage "$INTERNAL_MNT"
    umount -l "$INTERNAL_MNT" 2>/dev/null

    if [ ! -b "$USB_DEV" ] && [ ! -b "$SD2_DEV" ]; then
        mount_internal_to_roms
    fi

    while true; do
        local DETECTED_DEV=""
        if [ -b "$USB_DEV" ]; then DETECTED_DEV="$USB_DEV"
        elif [ -b "$SD2_DEV" ]; then DETECTED_DEV="$SD2_DEV"
        fi

        if [ ! -z "$DETECTED_DEV" ] && [ -z "$CURRENTLY_MOUNTED" ]; then
            if do_mount "$DETECTED_DEV"; then CURRENTLY_MOUNTED="$DETECTED_DEV"
            else CURRENTLY_MOUNTED="IGNORED"; fi
        elif [ -z "$DETECTED_DEV" ] && [ ! -z "$CURRENTLY_MOUNTED" ]; then
            if [ "$CURRENTLY_MOUNTED" != "IGNORED" ]; then do_unmount; fi
            CURRENTLY_MOUNTED=""
        fi
        sleep 5
    done
}

# --- Depart ---
if [ "$1" == "--run" ]; then
    run_monitor
else
    clear
    echo "=================================================="
    echo "         USB GAMES MONITOR STATUS                "
    echo "=================================================="
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo "STATUS: Active and running."
    else
        echo "STATUS: Stopped. Starting..."
        systemctl start $SERVICE_NAME
    fi
    echo "=================================================="
    sleep 4
fi