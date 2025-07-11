#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root. Please run with sudo."
   exit 1
fi

# --- Variables (Must match the join script's assumptions) ---
AD_REALM="" # We'll try to discover this if not provided
PAM_FILE="/etc/pam.d/common-session"
SSSD_CONF="/etc/sssd/sssd.conf"
RESOLV_CONF="/etc/resolv.conf"
RESOLV_CONF_BACKUP="/etc/resolv.conf.bak"
SMB_CONF="/etc/samba/smb.conf"
SMB_CONF_BACKUP="/etc/samba/smb.conf.bak"

# --- Functions ---

# Function to display error and exit
function exit_on_error() {
    echo "❌ Error: $1"
    exit 1
}

# --- Main Script ---

echo "Welcome to the Active Directory Domain UNJOIN Script for Ubuntu/Debian!"
echo "This script will attempt to revert changes made by the domain join script."
echo ""
echo "!!! WARNING: This will unjoin your system from the Active Directory domain."
echo "!!! WARNING: Active Directory users will no longer be able to log in."
echo "!!! WARNING: You must have local root access after this script runs."
read -rp "Do you wish to continue? (yes/no): " confirm
if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborting unjoin process."
    exit 0
fi

echo "---"

# Try to discover the realm if not explicitly set
if [[ -z "$AD_REALM" ]]; then
    echo "🔍 Attempting to discover current realm..."
    DISCOVERED_REALM=$(realm list --name-only 2>/dev/null)
    if [[ -n "$DISCOVERED_REALM" ]]; then
        AD_REALM="$DISCOVERED_REALM"
        echo "✅ Discovered realm: $AD_REALM"
    else
        read -rp "Could not automatically discover the domain. Please enter your AD realm (e.g., SRV.WORLD) to unjoin: " AD_REALM
        if [[ -z "$AD_REALM" ]]; then
            exit_on_error "AD Realm is required to unjoin the domain."
        fi
    fi
fi

if [[ -z "$AD_REALM" ]]; then
    exit_on_error "No AD Realm specified or discovered. Cannot proceed with unjoin."
fi

echo "🔐 Attempting to unjoin domain '$AD_REALM'..."
if ! realm leave -v "$AD_REALM"; then
    # It's possible the machine is already unjoined or there's a connectivity issue.
    # We'll allow it to proceed to cleanup steps if unjoin fails, but warn.
    echo "⚠️ Warning: Failed to unjoin the domain using 'realm leave'. This might mean the system was already unjoined, or there's a connectivity issue to the DC. Proceeding with local cleanup."
fi
echo "✅ Attempted domain unjoin (check previous messages for success)."
echo "---"

echo "🗑️ Removing SSSD related files and configurations..."

# Stop SSSD service
echo "Stopping SSSD service..."
systemctl stop sssd || echo "⚠️ Warning: SSSD service not running or failed to stop."

# Remove SSSD cache
echo "Clearing SSSD cache..."
rm -rf /var/lib/sss/db/* /var/lib/sss/pubconf/* /var/lib/sss/pipes/* 2>/dev/null
rm -rf /var/log/sssd/* 2>/dev/null

# Delete sssd.conf (realm leave usually removes it, but as a safeguard)
if [[ -f "$SSSD_CONF" ]]; then
    echo "Deleting $SSSD_CONF..."
    rm "$SSSD_CONF"
fi

# Remove pam_mkhomedir.so from common-session
echo "Reverting pam_mkhomedir.so in $PAM_FILE..."
if grep -q "pam_mkhomedir.so" "$PAM_FILE"; then
    sed -i '/session\s\+optional\s\+pam_mkhomedir.so/d' "$PAM_FILE"
    echo "✅ Removed pam_mkhomedir.so line."
else
    echo "ℹ️ pam_mkhomedir.so line not found or already removed from $PAM_FILE."
fi
echo "---"

echo "🌐 Reverting DNS configuration..."
if [[ -f "$RESOLV_CONF_BACKUP" ]]; then
    echo "Restoring $RESOLV_CONF from backup..."
    if ! cp "$RESOLV_CONF_BACKUP" "$RESOLV_CONF"; then
        echo "❌ Failed to restore $RESOLV_CONF from backup. Manual intervention may be required."
    else
        echo "✅ $RESOLV_CONF restored."
    fi
else
    echo "ℹ️ No $RESOLV_CONF_BACKUP found. Manual DNS configuration may be needed."
    echo "Consider setting nameserver to a public DNS like 8.8.8.8 or your router's IP."
    echo "Example: echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
fi
echo "---"

echo "🌐 Reverting Samba client configuration..."
if [[ -f "$SMB_CONF_BACKUP" ]]; then
    echo "Restoring $SMB_CONF from backup..."
    if ! cp "$SMB_CONF_BACKUP" "$SMB_CONF"; then
        echo "❌ Failed to restore $SMB_CONF from backup. Manual intervention may be required."
    else
        echo "✅ $SMB_CONF restored."
    fi
else
    echo "ℹ️ No $SMB_CONF_BACKUP found. Samba configuration remains as is."
fi

# Restart smbd/nmbd if they are running (for samba client config)
echo "🔄 Checking and restarting Samba services (if active)..."
if systemctl is-active --quiet smbd; then
    echo "  - Restarting smbd..."
    sudo systemctl restart smbd
fi
if systemctl is-active --quiet nmbd; then
    echo "  - Restarting nmbd..."
    sudo systemctl restart nmbd
fi
echo "✅ Samba services (if active) checked/restarted."
echo "---"

echo "🧹 Cleaning up packages (optional)..."
read -rp "Do you want to remove realmd, sssd and kio-fuse packages? (yes/no): " remove_pkgs
if [[ "$remove_pkgs" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Removing realmd, sssd, and kio-fuse..."
    if ! apt -y purge realmd sssd sssd-tools libnss-sss libpam-sss adcli kio-fuse; then
        echo "⚠️ Warning: Failed to purge some packages. You may need to remove them manually."
    else
        echo "✅ Packages removed."
    fi
    echo "Running apt autoremove..."
    apt -y autoremove
    echo "✅ Autoremove complete."
else
    echo "Skipping package removal."
fi
echo "---"

echo "🎉 Unjoin and reversion process complete!"
echo "Your system has been unjoined from the Active Directory domain."
echo "You will no longer be able to log in with AD user accounts."
echo ""
echo "Important:"
echo "1. Reboot your system for all changes to fully take effect."
echo "2. Ensure you can log in with a local user account after reboot."
echo "3. If you removed packages, you might need to manually clean up any remaining configuration files in /etc/sssd/ or /etc/realmd/ if they exist."
echo ""

exit 0