#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/mount-smb-script.log"
exec > >(tee -a "$LOGFILE") 2>&1

SMB_SERVER="10.10.250.20"
SMB_SHARE="SMB"
MOUNT_POINT="/mnt/share"
CRED_FILE="/etc/smb-credentials"
FSTAB="/etc/fstab"
FSTAB_BAK="/etc/fstab.bak.$(date +%F_%T)"
FSTAB_ENTRY="//${SMB_SERVER}/${SMB_SHARE} ${MOUNT_POINT} cifs credentials=${CRED_FILE},uid=110,gid=1000,file_mode=0755,dir_mode=0755,nofail 0 0"

echo "[INFO] Mount SMB Script started at $(date)"

# 1. Root check
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run this script as root or with sudo."
  exit 1
fi

# 2. Prompt for system username/group
read -p "Enter the local username to assign permissions to: " username
read -p "Enter the local group name to assign permissions to: " groupname

if ! id -u "$username" >/dev/null 2>&1; then
  echo "[ERROR] User '$username' does not exist."
  exit 1
fi
if ! getent group "$groupname" >/dev/null 2>&1; then
  echo "[ERROR] Group '$groupname' does not exist."
  exit 1
fi

# 3. Prompt for SMB credentials
read -p "Enter SMB username: " smb_username
read -s -p "Enter SMB password: " smb_password
echo

# 4. Network reachability check
if ! ping -c 1 -W 2 "$SMB_SERVER" &>/dev/null; then
  echo "[WARNING] SMB server $SMB_SERVER is not reachable. Proceeding anyway."
fi

# 5. Backup fstab
echo "[INFO] Backing up $FSTAB to $FSTAB_BAK"
cp "$FSTAB" "$FSTAB_BAK"

# 6. Check if mount point is already mounted
if mountpoint -q "$MOUNT_POINT"; then
  echo "[WARNING] $MOUNT_POINT is already mounted."
  read -p "Do you want to unmount and recreate the mount? (y/n): " remount_confirm
  if [[ "$remount_confirm" == "y" ]]; then
    echo "[INFO] Unmounting $MOUNT_POINT..."
    umount "$MOUNT_POINT" || { echo "[ERROR] Could not unmount $MOUNT_POINT"; exit 1; }
    # Remove old fstab entry
    sed -i "\|//${SMB_SERVER}/${SMB_SHARE} ${MOUNT_POINT} cifs|d" "$FSTAB"
    # Remove credentials file
    [ -f "$CRED_FILE" ] && rm -f "$CRED_FILE"
    # Remove mount directory
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  else
    echo "[INFO] Exiting without making changes."
    exit 0
  fi
fi

# 7. Confirm before proceeding
read -p "Proceed with these settings? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
  echo "[INFO] Script canceled by user. No changes were made."
  exit 0
fi

# 8. Install cifs-utils if needed
echo "[INFO] Checking for cifs-utils package..."
apt update
if ! dpkg -s cifs-utils >/dev/null 2>&1; then
  apt install -y cifs-utils
fi

# 9. Create mount point and set permissions
echo "[INFO] Creating mount point at $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
chown "$username:$groupname" "$MOUNT_POINT"
chmod 775 "$MOUNT_POINT"

# 10. Create SMB credentials file
echo "[INFO] Creating credentials file at $CRED_FILE"
{
  echo "username=$smb_username"
  echo "password=$smb_password"
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"

# 11. Remove old fstab entry (again, just to be safe)
sed -i "\|//${SMB_SERVER}/${SMB_SHARE} ${MOUNT_POINT} cifs|d" "$FSTAB"
sed -i "\|${MOUNT_POINT} |d" "$FSTAB"

# 12. Add new fstab entry (using static uid/gid per request)
echo "$FSTAB_ENTRY" >> "$FSTAB"
echo "[INFO] Added new fstab entry."

# 13. Mount the share
echo "[INFO] Mounting all filesystems from fstab..."
if ! mount -a; then
  echo "[ERROR] Mount failed. Rolling back changes."
  # Clean up (remove fstab entry, unmount, delete cred file, remove mount point)
  sed -i "\|//${SMB_SERVER}/${SMB_SHARE} ${MOUNT_POINT} cifs|d" "$FSTAB"
  umount "$MOUNT_POINT" 2>/dev/null || true
  rm -f "$CRED_FILE"
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  echo "[INFO] Reverted all changes. See $FSTAB_BAK for your original fstab."
  exit 1
fi

# 14. Verify mount
if mountpoint -q "$MOUNT_POINT"; then
  echo "[SUCCESS] SMB share mounted successfully at $MOUNT_POINT."
else
  echo "[ERROR] $MOUNT_POINT is not mounted. Please check configuration or logs."
  exit 1
fi

# 15. Show summary
echo "====================[SUMMARY]===================="
echo "SMB share ${SMB_SERVER}/${SMB_SHARE} mounted at $MOUNT_POINT"
echo "Local permissions: $username:$groupname"
echo "fstab backed up to: $FSTAB_BAK"
echo "Credentials file: $CRED_FILE (mode 600)"
echo "Logfile: $LOGFILE"
echo "================================================="

exit 0
