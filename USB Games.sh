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

# --- Remet SD1 en fonction ---
mount_internal_to_roms() {
    echo ">>> Restoring internal SD games to $ROM_PATH..."
    umount -l "$ROM_PATH" 2>/dev/null
    mkdir -p "$ROM_PATH"
    mount "$INTERNAL_DEV" "$ROM_PATH"
}

# --- Montage de l'USB/SD2 ---
do_mount() {
    local SOURCE_DEV=$1
    local FSTYPE=$(blkid -o value -s TYPE "$SOURCE_DEV")
    
    # Permissions
    local OPTS="rw"
    if [[ "$FSTYPE" =~ ^(vfat|exfat|ntfs)$ ]]; then
        OPTS="rw,uid=1000,gid=1000,umask=000"
    fi

    echo ">>> External storage detected: $SOURCE_DEV"

    # --- On verifie si prensence de tools ou themes avant de monter ---
    mkdir -p "$TMP_CHECK_MNT"
    umount -l "$TMP_CHECK_MNT" 2>/dev/null
    
    # Montage temporaire pour vérifier le contenu
    if mount -t "$FSTYPE" -o "$OPTS" "$SOURCE_DEV" "$TMP_CHECK_MNT"; then
        if [ -d "$TMP_CHECK_MNT/Tools" ] || [ -d "$TMP_CHECK_MNT/themes" ]; then
            echo ">>> Verification successful: 'Tools' or 'themes' found."
            umount -l "$TMP_CHECK_MNT"
        else
            echo ">>> Verification failed: Neither 'Tools' nor 'themes' folder found. Ignoring device."
            umount -l "$TMP_CHECK_MNT"
            return 1
        fi
    else
        echo ">>> Error: Could not perform temporary mount for verification."
        return 1
    fi

    # Libére /roms
    umount -l "$ROM_PATH" 2>/dev/null

    # Monte le stockage externe sur /roms
    if mount -t "$FSTYPE" -o "$OPTS" "$SOURCE_DEV" "$ROM_PATH"; then
        echo ">>> External Mount successful!"

        # Deplace roms/ de SD1 sur /tmp/sd1
        mkdir -p "$INTERNAL_MNT"
        umount -l "$INTERNAL_MNT" 2>/dev/null
        mount "$INTERNAL_DEV" "$INTERNAL_MNT" 2>/dev/null

        # Bind-mount des thèmes et tools de SD1 vers l'externe
        mount --bind "$INTERNAL_MNT/themes" "$ROM_PATH/themes" 2>/dev/null
        mount --bind "$INTERNAL_MNT/tools" "$ROM_PATH/tools" 2>/dev/null
        
        echo ">>> Internal themes/tools linked."
        echo ">>> Restarting EmulationStation..."
        systemctl restart emulationstation
        return 0
    fi
    return 1
}

# --- Démontage et retour à SD1 ---
do_unmount() {
    echo ">>> External device removed! Cleaning up..."

    # Démonte proprement les thèmes/tools et l'USB
    umount -l "$ROM_PATH/themes" 2>/dev/null
    umount -l "$ROM_PATH/tools" 2>/dev/null
    umount -l "$ROM_PATH" 2>/dev/null
    umount -l "$INTERNAL_MNT" 2>/dev/null

    # Remets les dossiers initial dans SD1
    mount_internal_to_roms

    echo ">>> Internal SD games are back in $ROM_PATH."
    echo ">>> Restarting EmulationStation..."
    systemctl restart emulationstation
}

# --- Surveillance ---
run_monitor() {
    local CURRENTLY_MOUNTED=""

    # Initialisation : si pas d'USB au boot, on est sur SD1
    if [ ! -b "$USB_DEV" ] && [ ! -b "$SD2_DEV" ]; then
        mount_internal_to_roms
    fi

    while true; do
        local DETECTED_DEV=""
        
        if [ -b "$USB_DEV" ]; then
            DETECTED_DEV="$USB_DEV"
        elif [ -b "$SD2_DEV" ]; then
            DETECTED_DEV="$SD2_DEV"
        fi

        # Si un périphérique est inséré et qu'on ne l'a pas encore traité
        if [ ! -z "$DETECTED_DEV" ] && [ -z "$CURRENTLY_MOUNTED" ]; then
            if do_mount "$DETECTED_DEV"; then
                CURRENTLY_MOUNTED="$DETECTED_DEV"
            else
                CURRENTLY_MOUNTED="IGNORED"
            fi

        # Si le périphérique a été retiré
        elif [ -z "$DETECTED_DEV" ] && [ ! -z "$CURRENTLY_MOUNTED" ]; then
            if [ "$CURRENTLY_MOUNTED" != "IGNORED" ]; then
                do_unmount
            fi
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
        echo "STATUS: Active and running in background."
    else
        echo "STATUS: Service stopped. Starting..."
        systemctl start $SERVICE_NAME
    fi
    echo "--------------------------------------------------"
    echo "Hardware watch: /dev/sda1 (USB) and /dev/mmcblk1p1 (SD2)"
    echo "Requirement: Folder 'Tools' or 'themes' must exist on USB."
    echo "=================================================="
    sleep 4
fi