#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   exit 1
fi

# Prompt for domain information
read -rp "Enter your AD domain name (e.g., srv.world): " AD_DOMAIN
read -rp "Enter your AD realm (e.g., SRV.WORLD): " AD_REALM
read -rp "Enter AD admin user (e.g., Administrator): " AD_ADMIN
read -srp "Enter password for $AD_ADMIN: " AD_PASS
echo

echo "🔐 Leaving the domain..."
echo "$AD_PASS" | realm leave "$AD_REALM"
if [[ $? -ne 0 ]]; then
    echo "❌ Failed to leave the domain."
    exit 1
fi

echo "✅ Successfully left the domain."

echo "🧹 Cleaning up SSSD and related configurations..."

# Remove the SSSD configuration file
rm -f /etc/sssd/sssd.conf

# Remove related PAM settings (home directory creation)
sed -i '/pam_mkhomedir.so/d' /etc/pam.d/common-session

# Remove resolv.conf domain settings
cp /etc/resolv.conf.bak /etc/resolv.conf
echo "🧹 DNS settings reverted to previous state."

# Remove AD-related packages if desired
read -rp "Do you want to remove AD-related packages? (y/n): " REMOVE_PKGS
if [[ "$REMOVE_PKGS" =~ ^[Yy]$ ]]; then
    echo "🧹 Removing AD-related packages..."
    apt -y remove realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit
    echo "✅ AD-related packages removed."
fi

echo "🚀 The system has been unjoined from the AD domain."

