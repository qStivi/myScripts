#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/mount-smb-script.log"
exec > >(tee -a "$LOGFILE") 2>&1

# === Configuration ===
SMB_SERVER="10.10.250.20"
SMB_SHARE="SMB"
MOUNT_POINT="/mnt/share"
CRED_FILE="/etc/smb-credentials"
FSTAB="/etc/fstab"
FSTAB_BAK="/etc/fstab.bak.$(date +%F_%T)"
MEDIA_GROUP="media"
MEDIA_GID="1000"     # Change if needed for your environment!

echo "[INFO] Mount SMB Script started at $(date)"

# --- 1. Root check ---
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run this script as root or with sudo."
  exit 1
fi

# --- 2. Ensure media group exists with correct GID ---
if getent group "$MEDIA_GROUP" >/dev/null; then
  existing_gid=$(getent group "$MEDIA_GROUP" | cut -d: -f3)
  if [[ "$existing_gid" != "$MEDIA_GID" ]]; then
    echo "[WARNING] Group '$MEDIA_GROUP' exists but with GID $existing_gid (expected $MEDIA_GID)."
    read -p "Do you want to update '$MEDIA_GROUP' to GID $MEDIA_GID? (y/n): " fix_gid
    if [[ "$fix_gid" == "y" ]]; then
      groupmod -g "$MEDIA_GID" "$MEDIA_GROUP"
      echo "[INFO] Updated group '$MEDIA_GROUP' to GID $MEDIA_GID."
    else
      echo "[ERROR] Please resolve GID mismatch before proceeding."
      exit 1
    fi
  fi
else
  echo "[INFO] Creating group '$MEDIA_GROUP' with GID $MEDIA_GID."
  groupadd -g "$MEDIA_GID" "$MEDIA_GROUP"
fi

# --- 3. Prompt for service user and ensure membership in media group ---
read -p "Enter the local service username to assign group access (e.g. radarr/readarr/sonarr): " username
if ! id -u "$username" >/dev/null 2>&1; then
  echo "[ERROR] User '$username' does not exist."
  exit 1
fi

if id -nG "$username" | grep -qw "$MEDIA_GROUP"; then
  echo "[INFO] User '$username' is already in group '$MEDIA_GROUP'."
else
  usermod -aG "$MEDIA_GROUP" "$username"
  echo "[INFO] Added '$username' to group '$MEDIA_GROUP'."
fi

# --- 4. Prompt for SMB credentials ---
read -p "Enter SMB username: " smb_username
read -s -p "Enter SMB password: " smb_password
echo

# --- 5. Network check ---
if ! ping -c 1 -W 2 "$SMB_SERVER" &>/dev/null; then
  echo "[WARNING] SMB server $SMB_SERVER is not reachable. Proceeding anyway."
fi

# --- 6. Confirm settings ---
echo "====================[REVIEW]===================="
echo "Will mount: //${SMB_SERVER}/${SMB_SHARE} -> $MOUNT_POINT"
echo "SMB credentials: $smb_username / (hidden)"
echo "Local group for access: $MEDIA_GROUP (GID: $MEDIA_GID)"
echo "Local service user: $username"
echo "All files will appear owned by root:$MEDIA_GROUP, permissions 0775."
echo "Any user in the '$MEDIA_GROUP' group will have access."
echo "================================================"
read -p "Proceed with these settings? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
  echo "[INFO] Script canceled by user. No changes were made."
  exit 0
fi

# --- 7. Ensure cifs-utils is installed ---
echo "[INFO] Checking for cifs-utils package..."
apt update
if ! dpkg -s cifs-utils >/dev/null 2>&1; then
  apt install -y cifs-utils
fi

# --- 8. Mount point setup ---
echo "[INFO] Creating mount point at $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
chown root:"$MEDIA_GROUP" "$MOUNT_POINT"
chmod 775 "$MOUNT_POINT"

# --- 9. Credentials file ---
echo "[INFO] Creating credentials file at $CRED_FILE"
{
  echo "username=$smb_username"
  echo "password=$smb_password"
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"

# --- 10. Remove old fstab entries ---
sed -i "\|//${SMB_SERVER}/${SMB_SHARE} ${MOUNT_POINT} cifs|d" "$FSTAB"
sed -i "\|${MOUNT_POINT} |d" "$FSTAB"

# --- 11. Add new fstab entry ---
FSTAB_ENTRY="//${SMB_SERVER}/${SMB_SHARE} ${MOUNT_POINT} cifs credentials=${CRED_FILE},uid=0,gid=$MEDIA_GID,file_mode=0775,dir_mode=0775,nofail 0 0"
echo "$FSTAB_ENTRY" >> "$FSTAB"
echo "[INFO] Added new fstab entry."

# --- 12. Handle existing mount ---
if mountpoint -q "$MOUNT_POINT"; then
  echo "[WARNING] $MOUNT_POINT is already mounted."
  read -p "Do you want to unmount and remount? (y/n): " remount_confirm
  if [[ "$remount_confirm" == "y" ]]; then
    umount "$MOUNT_POINT" || { echo "[ERROR] Could not unmount $MOUNT_POINT"; exit 1; }
    echo "[INFO] Unmounted. Remounting..."
  else
    echo "[INFO] Skipping remount."
  fi
fi

# --- 13. Mount the share ---
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

# --- 14. Verify mount ---
if mountpoint -q "$MOUNT_POINT"; then
  echo "[SUCCESS] SMB share mounted successfully at $MOUNT_POINT."
else
  echo "[ERROR] $MOUNT_POINT is not mounted. Please check configuration or logs."
  exit 1
fi

# --- 15. Show summary and reminders ---
echo "====================[SUMMARY]===================="
echo "SMB share ${SMB_SERVER}/${SMB_SHARE} mounted at $MOUNT_POINT"
echo "Access granted to all users in the '$MEDIA_GROUP' group (GID: $MEDIA_GID)."
echo "Service user '$username' is now a member of '$MEDIA_GROUP'."
echo "Files will appear as root:$MEDIA_GROUP and have 0775 permissions."
echo "fstab backed up to: $FSTAB_BAK"
echo "Credentials file: $CRED_FILE (mode 600)"
echo "Logfile: $LOGFILE"
echo "================================================="

echo "[REMINDER] For correct multi-service and multi-container access, ensure the 'media' group exists with the SAME GID ($MEDIA_GID) on ALL containers and the SMB server."

exit 0
