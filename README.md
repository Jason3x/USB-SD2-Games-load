# USB & SD2 Games Monitor

A bash-based background service designed for retro-gaming handhelds and consoles. This script automatically detects and mounts external USB drives or secondary SD cards (SD2) as the primary ROM directory.

Special thanks to **@SjslTech** for their contribution to this project.

## 🚀 Main Features
The script is built around four core functions to ensure seamless operation:

*   **`run_monitor`**: The main loop that constantly watches for hardware connection at `/dev/sda1` (USB) or `/dev/mmcblk1p1` (SD2).
*   **`do_mount`**: Handles the mounting logic. It checks for a specific signature (presence of `Tools` or `themes` folders) before switching the ROM directory.
*   **`do_unmount`**: Safely reverts the system back to the internal storage when the external device is removed.
*   **`mount_internal_to_roms`**: Ensures the internal SD card games are always available as a fallback.

## 📂 Supported Formats
The script identifies and optimizes mount options (permissions, UID/GID) for the following file systems:
*   **FAT32 (vfat)**
*   **exFAT**
*   **NTFS**
*   **Ext4** (Standard Linux support)

## 🛠️ Requirements & Security
- **Security Check**: To prevent accidental mounting of non-gaming drives, the script **only** mounts devices containing a folder named either `/Tools` or `/themes`.
- **Systemd**: Automatically installs itself as a system service (`usb-games-monitor.service`) for persistent background monitoring.

## 🔧 Installation
 - **Copy all the ArkOS or dArkOS system folders** to your USB or SD2 drive. (from ArkOs system folder or run Folder Creation Script.bat in your USB or sd2) 
 - **Place the games** you want in the corresponding folders.
 - **Transfer USB Games.sh script** on roms/tools.
- **Run the script**
- **Insert** your USB or SD2

  Enjoy
